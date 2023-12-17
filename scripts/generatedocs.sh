#!/usr/bin/env bash
set -e

# Currently only generating docs for the Service API parts of the code.
#swift doc generate --minimum-access-level private -n App Sources/swiftarr/Controllers Sources/swiftarr/Enumerations -o swiftdocs --base-url "https://github.com/challfry/swiftarr/wiki"
# Swift doc inserts zero-width-space Unicode chars that mess up [[MediaWikiLinks]]. Remove them, then convert <doc:Links> to [[Links]].
#perl -C -i -p -e 's/\x{200B}//g; s/<doc:([^<]*)>/[[$1]]/g' swiftDocs/*.md
#mv swiftDocs/Home.md swiftDocs/Types.md

USE_CACHE=false
OUTPUT_DIR=./docs/Output
SOURCEFILE=/tmp/doc.json

while [ -n "$1" ]; do
	case "$1" in
		-c) USE_CACHE=true ;;
    -o) OUTPUT_DIR=${2} ;;
    -s) SOURCEFILE=${2} ;;
	esac
	shift
done

# Sometimes we just want to rebuild the Jazzy skeleton, not the entire set
# of source code documentations.
if [ "${USE_CACHE}" = true ]; then
	echo "Using cached Sourcekitten file at ${SOURCEFILE}"
else
	echo "Generating new Sourcekitten file at ${SOURCEFILE}"
	sourcekitten doc --spm > "${SOURCEFILE}"
fi

echo "Generating Jazzy docs to ${OUTPUT_DIR}"
jazzy --clean --sourcekitten-sourcefile "${SOURCEFILE}" -o "${OUTPUT_DIR}"

echo "Done"
