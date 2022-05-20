## Using Prometheus with Swiftarr

### General

Prometheus is a server metrics platform that can pull metrics data from servers, store it locally, and 
display tables and graphs of collected metrics data. It's designed for projects much larger than Swiftarr; 
with support for collating data from multiple servers, federating instances of the stored metrics data,
customizable alerts, and a bunch of third party integations. 

I chose Prometheus because Vapor already uses SwiftMetrics (see DefaultResponder.swift) and has built-in support
for several metrics objects, importantly "http_request_duration_seconds", "http_requests_total", and "http_request_errors_total"

Redis also has built-in support for delivering metrics. Sadly, the fluent postgres driver does not.

Anyway, Swiftarr delivers metrics to the prometheus process via an endpoint in ClientController, at "/api/v3/client/metrics".
Prometheus polls this endpoint while running. Prometheus currently uses basic auth to access the endpoint.

### swiftarr.yml

This file contains the setup parameters to use with prometheus in order to get metrics on Swiftarr. 
Launch the prometheus server process with:

`prometheus --config.file="swiftarr.yml"`

### Metrics Browser

Once the prometheus process is up and running, it'll poll the metrics endpoint every few seconds and store the data.
You can then see a bunch of time-series data at http://localhost:9090/metrics 

Prometheus is really designed for collecting metrics on a bunch of servers and allowing sysadmins to set alerts of 
various sorts. But, it'll work for our purposes and wasn't too difficult to set up.
