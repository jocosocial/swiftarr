**ENUM**

# `ExportableFormat`

```swift
public enum ExportableFormat: ExportableFormatter
```

Enum definition of built-in exportable image raster formats

- bmp: https://en.wikipedia.org/wiki/BMP_file_format
- gif: https://en.wikipedia.org/wiki/gif
- jpg: https://en.wikipedia.org/wiki/jpeg
- png: https://en.wikipedia.org/wiki/Portable_Network_Graphics
- tiff: https://en.wikipedia.org/wiki/tiff
- wbmp: https://en.wikipedia.org/wiki/wbmp
- webp: https://en.wikipedia.org/wiki/webp
- any: Evaluates all of the above mentioned formats on export

## Cases
### `bmp(compression:)`

```swift
case bmp(compression: Bool)
```

### `gif`

```swift
case gif
```

### `jpg(quality:)`

```swift
case jpg(quality: Int32)
```

### `png`

```swift
case png
```

### `tiff`

```swift
case tiff
```

### `wbmp(index:)`

```swift
case wbmp(index: Int32)
```

### `webp`

```swift
case webp
```

## Methods
### `data(of:)`

```swift
public func data(of imagePtr: gdImagePtr) throws -> Data
```

Creates a data representation of given `gdImagePtr`.

- Parameter imagePtr: The `gdImagePtr` of which a data representation should be instantiated.
- Returns: The (raw) `Data` of the image
- Throws: `GDError` if export failed.

#### Parameters

| Name | Description |
| ---- | ----------- |
| imagePtr | The `gdImagePtr` of which a data representation should be instantiated. |