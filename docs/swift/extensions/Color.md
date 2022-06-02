**EXTENSION**

# `Color`
```swift
extension Color
```

## Properties
### `red`

```swift
public static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
```

### `green`

```swift
public static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
```

### `blue`

```swift
public static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
```

### `black`

```swift
public static let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
```

### `white`

```swift
public static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
```

## Methods
### `init(hex:leadingAlpha:)`

```swift
public init(hex string: String, leadingAlpha: Bool = false) throws
```

Initializes a new `Color` instance of given hexadecimal color string.

Given string will be stripped from a single leading "#", if applicable.
Resulting string must met any of the following criteria:

- Is a string with 8-characters and therefore a fully fledged hexadecimal
  color representation **including** an alpha component. Given value will remain
  untouched before conversion. Example: `ffeebbaa`
- Is a string with 6-characters and therefore a fully fledged hexadecimal color
  representation **excluding** an alpha component. Given RGB color components will
  remain untouched and an alpha component of `0xff` (opaque) will be extended before
  conversion. Example: `ffeebb` -> `ffeebbff`
- Is a string with 4-characters and therefore a shortened hexadecimal color
  representation **including** an alpha component. Each single character will be
  doubled before conversion. Example: `feba` -> `ffeebbaa`
- Is a string with 3-characters and therefore a shortened hexadecimal color
  representation **excluding** an alpha component. Given RGB color character will
  be doubled and an alpha of component of `0xff` (opaque) will be extended before
  conversion. Example: `feb` -> `ffeebbff`

- Parameters:
  - string: The hexadecimal color string.
  - leadingAlpha: Indicate whether given string should be treated as ARGB (`true`) or RGBA (`false`)
- Throws: `.invalidColor` if given string does not match any of the above mentioned criteria or is not a valid hex color.

#### Parameters

| Name | Description |
| ---- | ----------- |
| string | The hexadecimal color string. |
| leadingAlpha | Indicate whether given string should be treated as ARGB (`true`) or RGBA (`false`) |

### `init(hex:leadingAlpha:)`

```swift
public init(hex color: Int, leadingAlpha: Bool = false)
```

Initializes a new `Color` instance of given hexadecimal color values.

- Parameters:
  - color: The hexadecimal color value, incl. red, green, blue and alpha
  - leadingAlpha: Indicate whether given code should be treated as ARGB (`true`) or RGBA (`false`)

#### Parameters

| Name | Description |
| ---- | ----------- |
| color | The hexadecimal color value, incl. red, green, blue and alpha |
| leadingAlpha | Indicate whether given code should be treated as ARGB (`true`) or RGBA (`false`) |