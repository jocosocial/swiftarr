# Client Conventions

## Photostream

The Photostream is meant to be a snapshot of what is happening on the boat right now. The server does not  
currently check when an uploaded photo was taken, so clients are responsible for keeping old photos out. This is to reduce round-trip time over congested wifi.

### Capture Time

* A client may only upload a photo if its EXIF capture date shows it was taken up to **2 hours** prior to the current time.
* Clients are responsible for enforcing this check.
* Photos may be taken in the client's own camera or attached from another camera app or photo library. This lets
photographers share a photo right away from a paired camera.
* If the client cannot determine the capture date before upload, it must tell the user the upload is not allowed.
* Send the capture date as `createdAt` in `PhotostreamUploadData`.

### Server Enforcement

The server may start enforcing the capture-time check in the future. Clients must not rely on the server
accepting photos that fail it.
