**CLASS**

# `DecoderProxy`

```swift
final public class DecoderProxy<OutputType>: Decodable where OutputType: Decodable
```

## Properties
### `result`

```swift
public var result: OutputType
```

## Methods
### `init(from:)`

```swift
public init(from decoder: Decoder) throws
```

#### Parameters

| Name | Description |
| ---- | ----------- |
| decoder | The decoder to read data from. |