**CLASS**

# `GDImage`

```swift
public class GDImage
```

## Properties
### `size`

```swift
public var size: Size
```

### `transparent`

```swift
public var transparent: Bool = false
```

## Methods
### `init(width:height:type:)`

```swift
public init?(width: Int, height: Int, type: ImageType = .truecolor)
```

### `init(gdImage:)`

```swift
public init(gdImage: gdImagePtr)
```

### `resizedTo(width:height:applySmoothing:)`

```swift
public func resizedTo(width: Int, height: Int, applySmoothing: Bool = true) -> GDImage?
```

### `resizedTo(width:applySmoothing:)`

```swift
public func resizedTo(width: Int, applySmoothing: Bool = true) -> GDImage?
```

### `resizedTo(height:applySmoothing:)`

```swift
public func resizedTo(height: Int, applySmoothing: Bool = true) -> GDImage?
```

### `cropped(to:)`

```swift
public func cropped(to rect: Rectangle) -> GDImage?
```

### `applyInterpolation(enabled:currentSize:newSize:)`

```swift
public func applyInterpolation(enabled: Bool, currentSize: Size, newSize: Size)
```

### `renderText(_:from:fontList:color:size:angle:)`

```swift
public func renderText(
	_ text: String, from: Point, fontList: [String], color: Color, size: Double, angle: Angle = .zero
) -> (upperLeft: Point, upperRight: Point, lowerRight: Point, lowerLeft: Point)
```

Renders an UTF-8 string onto the image.

The text will be rendered from the specified basepoint:

 let basepoint = Point(x: 20, y: 200)
 image.renderText(
	 "SwiftGD",
	 from: basepoint,
	 fontList: ["SFCompact"],
	 color: .red,
	 size: 100,
	 angle: .degrees(90)
 )

- Parameters:
  - text: The string to render.
  - from: The basepoint (roughly the lower left corner) of the first
 letter.
  - fontList: A list of font filenames to look for. The first match
 will be used.
  - color: The font color.
  - size: The height of the font in typographical points (pt).
  - angle: The angle to rotate the rendered text from the basepoint
 perspective. Positive angles rotate clockwise.
- Returns: The rendered text bounding box. You can use this output to
  render the text off-image first, and then render it again, on the
  image, with the bounding box information (e.g., to center-align the
  text).

#### Parameters

| Name | Description |
| ---- | ----------- |
| text | The string to render. |
| from | The basepoint (roughly the lower left corner) of the first letter. |
| fontList | A list of font filenames to look for. The first match will be used. |
| color | The font color. |
| size | The height of the font in typographical points (pt). |
| angle | The angle to rotate the rendered text from the basepoint perspective. Positive angles rotate clockwise. |

### `fill(from:color:)`

```swift
public func fill(from: Point, color: Color)
```

### `drawLine(from:to:color:)`

```swift
public func drawLine(from: Point, to: Point, color: Color)
```

### `set(pixel:to:)`

```swift
public func set(pixel: Point, to color: Color)
```

### `get(pixel:)`

```swift
public func get(pixel: Point) -> Color
```

### `strokeEllipse(center:size:color:)`

```swift
public func strokeEllipse(center: Point, size: Size, color: Color)
```

### `fillEllipse(center:size:color:)`

```swift
public func fillEllipse(center: Point, size: Size, color: Color)
```

### `strokeRectangle(topLeft:bottomRight:color:)`

```swift
public func strokeRectangle(topLeft: Point, bottomRight: Point, color: Color)
```

### `fillRectangle(topLeft:bottomRight:color:)`

```swift
public func fillRectangle(topLeft: Point, bottomRight: Point, color: Color)
```

### `flip(_:)`

```swift
public func flip(_ mode: FlipMode)
```

### `pixelate(blockSize:)`

```swift
public func pixelate(blockSize: Int)
```

### `blur(radius:)`

```swift
public func blur(radius: Int)
```

### `colorize(using:)`

```swift
public func colorize(using color: Color)
```

### `desaturate()`

```swift
public func desaturate()
```

### `reduceColors(max:shouldDither:)`

```swift
public func reduceColors(max numberOfColors: Int, shouldDither: Bool = true) throws
```

Reduces `Image` to an indexed palette of colors from larger color spaces.
Index `Image`s only make sense with 2 or more colors, and will `throw` nonsense values
- Parameter numberOfColors: maximum number of colors
- Parameter shouldDither: true will apply GD’s internal dithering algorithm

#### Parameters

| Name | Description |
| ---- | ----------- |
| numberOfColors | maximum number of colors |
| shouldDither | true will apply GD’s internal dithering algorithm |

### `deinit`

```swift
deinit
```
