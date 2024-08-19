Swiftarr Client Config
======================

Sometimes it can be useful for client applications to have seed data provided by the server. At this time, Tricordarr is the only app looking to implement this feature.

The convention is to put a JSON file in this directory matching the client name in `SwiftarrClientApp` defined in `AppFeatures.swift`. The filename should be entirely lower-case. The file can contain any valid JSON. The file can then be accessed by any HTTP client at `/public/clients/${filename}.json`.

These files can be dynamically edited on the Swiftarr server and do not require version controlling. Any defaults here are provided to enhance developer testing.