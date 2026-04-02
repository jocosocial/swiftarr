# Image Format Safety: Magic Byte Validation + Modern Format Support

Addresses [#52](https://github.com/jocosocial/swiftarr/issues/52) (HEIC uploads cause server segfault) and [#535](https://github.com/jocosocial/swiftarr/issues/535) (JXL/AVIF image support).

## Problem

The image upload pipeline in `ImageHandler.loadImageFromData()` tries every GD parser in sequence (JPEG → PNG → GIF → WebP → TIFF → BMP → WBMP) with no format pre-check. When a user uploads a format GD doesn't support (HEIC, AVIF, JXL), GD attempts to parse it as each known format, hits memory corruption, and segfaults — crashing the server.

All known clients (web, Tricordarr, TheKraken) convert HEIC→JPEG before uploading, so this is an edge case from direct API calls. But a single malformed upload should never crash the server.

## Solution

Two new components inserted before GD processing:

1. **Magic byte detection** — identify the actual image format from file header bytes
2. **CLI-based conversion** — convert non-GD formats (HEIC, AVIF, JXL) to JPEG via system tools before handing to GD

## Architecture

### ImageFormatDetector

New file: `Sources/swiftarr/Image/ImageFormatDetector.swift`

Pure function. Reads the first ~12 bytes, returns the detected format.

```swift
enum DetectedImageFormat {
    // GD-supported formats
    case jpeg, png, gif, webp, tiff, bmp
    // Convertible via CLI tools
    case heic, avif, jxl
    // Not recognized
    case unknown
}

struct ImageFormatDetector {
    static func detect(_ data: Data) -> DetectedImageFormat
}
```

Magic byte signatures:

| Format | Signature |
|--------|-----------|
| JPEG | `FF D8 FF` |
| PNG | `89 50 4E 47` |
| GIF | `47 49 46 38` |
| WebP | `52 49 46 46` at 0 + `57 45 42 50` at 8 |
| TIFF | `49 49 2A 00` (LE) or `4D 4D 00 2A` (BE) |
| BMP | `42 4D` |
| HEIC/HEIF | `ftyp` at offset 4, brand: `heic`, `heix`, `mif1`, `msf1` |
| AVIF | `ftyp` at offset 4, brand: `avif`, `avis` |
| JXL | `FF 0A` (codestream) or `00 00 00 0C 4A 58 4C 20` (container) |

No dependencies — bytes in, enum out.

### ImageFormatConverter

New file: `Sources/swiftarr/Image/ImageFormatConverter.swift`

Converts non-GD formats to JPEG by shelling out to CLI tools.

```swift
struct ImageFormatConverter {
    static func convertToJPEG(_ data: Data, from format: DetectedImageFormat) throws -> Data
}
```

Flow:
1. Write input to a UUID-named temp file in `/tmp/swiftarr-convert/`
2. Run the appropriate converter:
   - HEIC/AVIF → `heif-convert input.heic output.jpg -q 95`
   - JXL → `djxl input.jxl output.jpg`
3. Read output JPEG back as `Data`
4. Clean up both temp files in a `defer` block

Design decisions:
- **JPEG quality 95** for intermediate output. GD re-encodes at quality 90 on final export, so two rounds of JPEG compression. Keeping the intermediate high preserves quality.
- **30-second timeout** on subprocess. Safety valve for malformed files that could hang the converter.
- **UUID filenames** to avoid collisions from concurrent uploads.
- **Descriptive error** if converter binary is missing: "Server does not support [format] conversion. Please upload JPEG, PNG, GIF, or WebP."

### Pipeline Integration

Modified file: `Sources/swiftarr/Protocols/ImageHandler.swift`

Changes to `loadImageFromData()`:

```
Before: try each GD parser blindly → crash on unsupported formats
After:  detect format → route to GD or converter → clear error on unknown
```

1. Call `ImageFormatDetector.detect(data)` 
2. GD-supported format → pass directly to the correct GD parser (no more guessing through all 7)
3. Convertible format → `ImageFormatConverter.convertToJPEG(data, from:)`, then load JPEG via GD
4. Unknown → fall back to trying TGA and WBMP via GD (obscure formats without reliable magic bytes), then throw `GDError.invalidImage` with supported formats listed if neither works

The return type and behavior of `loadImageFromData()` stays the same: `(GDImage, ImportableFormat, Int32)`. Everything downstream is untouched.

`regenerateThumbnail()` also calls `loadImageFromData()`, so it gets the fix automatically.

### Dockerfile Changes

Modified file: `scripts/init-prereqs.sh`

Add converter packages to the existing `apt-get install`:

```bash
apt-get install -y \
  curl libatomic1 libicu74 libxml2 gnupg2 \
  libcurl4 libz-dev libbsd0 tzdata libgd3 \
  libheif-examples libjxl-tools
```

Runtime image only. Builder image doesn't need them.

## Testing

### Unit: ImageFormatDetector
- Known magic bytes for each format → correct detection
- Truncated data (< 12 bytes) → `.unknown`, no crash
- Random garbage → `.unknown`
- JPEG data regardless of file extension → `.jpeg`

### Unit: ImageFormatConverter
- Convert small HEIC/AVIF/JXL test file → output starts with `FF D8 FF` (valid JPEG)
- Missing converter binary → descriptive error message
- Subprocess timeout → doesn't hang
- Temp file cleanup → no files left after conversion

### Integration: Upload Pipeline
- Upload HEIC via API → 200, image stored as JPEG
- Upload valid JPEG → still works (regression check)
- Upload random bytes → 400 with descriptive error
- Upload zero-byte file → handled gracefully

Test fixtures: small sample files (~few KB) for each format in `Tests/AppTests/Resources/`.

Conversion integration tests need `heif-convert` and `djxl` installed. On macOS: `brew install libheif jpeg-xl`. Tests that need missing tools use `try XCTSkipUnless` to skip gracefully.

## Scope

**In scope:**
- Magic byte validation for all uploads
- HEIC, AVIF, JXL → JPEG conversion via CLI tools
- Descriptive errors for unknown formats
- Dockerfile runtime dependency additions

**Out of scope:**
- AVIF/JXL output support (GD doesn't support it)
- Changes to `ImportableFormat` or `ExportableFormat` enums
- Changes to `configure.swift`'s `gdSupportsFileType` check
- Client-side changes
- TGA/WBMP detection (obscure formats, keep existing GD try-all behavior as fallback)
