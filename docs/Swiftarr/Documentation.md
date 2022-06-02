Documentation
=============

This documentation is built using [Jazzy](https://github.com/realm/jazzy/).

Swift Code Docs
---------------

### Update the Code Docs
```
scripts/generatedocs.sh
```

Note: for Linux hosts I got strange errors reading files part way through the generation
process. I needed to increase the limit of open files using `ulimit -n 4000`. 4000 was a
random number I picked, but it was much higher than the 1024 default the system had.

Human Docs
----------
SoonTM
