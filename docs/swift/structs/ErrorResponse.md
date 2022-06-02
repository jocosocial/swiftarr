**STRUCT**

# `ErrorResponse`

```swift
public struct ErrorResponse: Codable, Error
```

 All errors returned in HTTP responses use this structure.
 
 Some server errors (such as 404s) may not have any payload in the response body, but for any HTTP error response that has a payload, the 
 payload will have this strcture.
 
`error` is always true, `reason` concatenates all errors into a single string, and `fieldErrors` breaks errors up by field name
 of the request's body content, if available. Only content validation errors actaully use `fieldErrors`.
 Field-specific validation errors are keyed by the path to the field that caused the error. Validation errors that aren't specific to an input field
 (e.g. an error indicating that one of two fields may be empty, but not both) are all concatenated and placed into a `general` key in `fieldErrors`.
 This means that all field errors are both in `error` (concatenated into a single string), and also in `fieldErrors` (split into fields). 
 
 - Note: If the request body has validation errors, the error response should list all validation errors at once. However, other errors that may prevent a successful
 action will not be included. For instance, a user might try creating a Forum with empty fields. The error response will indicate that both Title and Text fields need values.
 After fixing those issues, the user could still get an error becuase they are quarantined and not authorized to create posts.
