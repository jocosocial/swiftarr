**STRUCT**

# `ImageUploadData`

```swift
public struct ImageUploadData: Content
```

Used to upload an image file or refer to an already-uploaded image. Either `filename` or `image` should always be set. 
If both are set, `filename` is ignored and `image` is processed and saved with a new name. A more Swift-y way to do this
would be an Enum with associated values, except Codable support becomes a pain and makes it difficult to understand 
what the equivalent JSON struct will look like.

Required by: `POST /api/v3/user/image`
Incorporated into `PostContentData`, which is in turn required by several routes.

See `UserController.imageHandler(_:data)`.
