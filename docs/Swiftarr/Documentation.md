Documentation
=============

This documentation is built using [Jazzy](https://github.com/realm/jazzy/). A hosted copy is available at [https://docs.twitarr.com](https://docs.twitarr.com) which is automatically generated with every commit.

Generating Documentation
------------------------
This requires [Jazzy](https://github.com/realm/jazzy/) and [Sourcekitten](https://github.com/jpsim/SourceKitten) to be installed. A helper script exists to simplify generating the HTML-based documentation from the source code on your local machine.

```
scripts/generatedocs.sh
```

Note: Linux hosts can see strange errors reading files part way through the generation
process. This likely means you need to increase the limit of open files using `ulimit -n 4000`. This number was
randomly selected to be much higher than the 1024 default the system had. You can run `ulimit -n` to see the current limit. Consult your distribution documentation to make this change permanent.

Swift Code Docs
---------------
Comments within the source code get automatically translated and linked.

Human Docs
----------
Any custom documentation outside of the source code can be added to the repo under `docs/Swiftarr` as a Markdown file (`*.md`). These will automatically be rendered by Jazzy.

To add documentation to a category in `.jazzy.yaml` such as Overview, Operations, etc create a corresponding Markdown file under `docs/Swiftarr/Sections`.