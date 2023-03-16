#!/usr/bin/env bash

# Currently only generating docs for the Service API parts of the code.
#swift doc generate --minimum-access-level private -n App Sources/App/Controllers Sources/App/Enumerations -o swiftdocs --base-url "https://github.com/challfry/swiftarr/wiki"
# Swift doc inserts zero-width-space Unicode chars that mess up [[MediaWikiLinks]]. Remove them, then convert <doc:Links> to [[Links]].
#perl -C -i -p -e 's/\x{200B}//g; s/<doc:([^<]*)>/[[$1]]/g' swiftDocs/*.md
#mv swiftDocs/Home.md swiftDocs/Types.md

USE_CACHE=false

while [ -n "$1" ]; do
	case "$1" in
		-c) USE_CACHE=true ;;
	esac
	shift
done

# Can't use jazzy --clean because it blows away the entire directory including
# the docs that we wrote.
find ./docs -name "*.html" -delete

# Sometimes we just want to rebuild the Jazzy skeleton, not the entire set
# of source code documentations.
if [ "${USE_CACHE}" = true ]; then
	echo "Using cached Sourcekitten doc.json"
else
	echo "Generating new Sourcekitten doc.json"
	sourcekitten doc --spm > /tmp/doc.json
fi

echo "Generating Jazzy docs"
jazzy --sourcekitten-sourcefile /tmp/doc.json

echo "Done"
