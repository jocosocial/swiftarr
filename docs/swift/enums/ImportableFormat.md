**ENUM**

# `ImportableFormat`

```swift
public enum ImportableFormat: ImportableFormatter
```

Enum definition of built-in importable image raster formats

- bmp: https://en.wikipedia.org/wiki/BMP_file_format
- gif: https://en.wikipedia.org/wiki/gif
- jpg: https://en.wikipedia.org/wiki/jpeg
- png: https://en.wikipedia.org/wiki/Portable_Network_Graphics
- tiff: https://en.wikipedia.org/wiki/tiff
- tga: https://en.wikipedia.org/wiki/Truevision_TGA
- wbmp: https://en.wikipedia.org/wiki/wbmp
- webp: https://en.wikipedia.org/wiki/webp
- any: Evaluates all of the above mentioned formats on import

## Cases
### `bmp`

```swift
case bmp
```

### `gif`

```swift
case gif
```

### `jpg`

```swift
case jpg
```

### `png`

```swift
case png
```

### `tiff`

```swift
case tiff
```

### `tga`

```swift
case tga
```

### `wbmp`

```swift
case wbmp
```

### `webp`

```swift
case webp
```

### `any`

```swift
case any
```

## Methods
### `imagePtr(of:)`

```swift
public func imagePtr(of data: Data) throws -> gdImagePtr
```

Creates a `gdImagePtr` from given image data.

- Parameter data: The image data of which an image should be instantiated.
- Returns: The `gdImagePtr` of the instantiated image.
- Throws: `GDError` if import failed.

#### Parameters

| Name | Description |
| ---- | ----------- |
| data | The image data of which an image should be instantiated. |