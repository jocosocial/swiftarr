**EXTENSION**

# `GDImage`
```swift
extension GDImage
```

## Methods
### `init(url:)`

```swift
public convenience init?(url: URL)
```

### `write(to:quality:allowOverwrite:)`

```swift
public func write(to url: URL, quality: Int = 100, allowOverwrite: Bool = false) -> Bool
```

### `init(data:as:)`

```swift
public convenience init(data: Data, as format: ImportableFormat = .any) throws
```

Initializes a new `Image` instance from given image data in specified raster format.
If `DefaultImportableRasterFormat` is omitted, all supported raster formats will be evaluated.

- Parameters:
  - data: The image data
  - rasterFormat: The raster format of image data (e.g. png, webp, ...). Defaults to `.any`
- Throws: `GDError` if `data` in `rasterFormat` could not be converted

#### Parameters

| Name | Description |
| ---- | ----------- |
| data | The image data |
| rasterFormat | The raster format of image data (e.g. png, webp, …). Defaults to `.any` |

### `export(as:)`

```swift
public func export(as format: ExportableFormat = .png) throws -> Data
```

Exports the image as `Data` object in specified raster format.

- Parameter format: The raster format of the returning image data (e.g. as jpg, png, ...). Defaults to `.png`
- Returns: The image data
- Throws: `GDError` if the export of `self` in specified raster format failed.

#### Parameters

| Name | Description |
| ---- | ----------- |
| format | The raster format of the returning image data (e.g. as jpg, png, …). Defaults to `.png` |