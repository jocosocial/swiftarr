#!/bin/bash

# Currently only generating docs for the Service API parts of the code.
swift doc generate --minimum-access-level private -n App Sources/App/Controllers Sources/App/Enumerations -o swiftdocs --base-url "https://github.com/challfry/swiftarr/wiki"
# Swift doc inserts zero-width-space Unicode chars that mess up [[MediaWikiLinks]]. Remove them, then convert <doc:Links> to [[Links]].
perl -C -i -p -e 's/\x{200B}//g; s/<doc:([^<]*)>/[[$1]]/g' swiftDocs/*.md
mv swiftDocs/Home.md swiftDocs/Types.md
