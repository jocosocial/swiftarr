#!/bin/bash

swift doc generate --minimum-access-level private -n App Sources/App/Controllers Sources/App/Enumerations -o swiftdocTest 
sed -i '' 's/<doc:\(.*\)>/[[\1]]/g' swiftDocTest/*.md
