#!/usr/bin/env bash

curl -f "http://localhost:${SWIFTARR_PORT}/api/v3/client/health" || exit 1