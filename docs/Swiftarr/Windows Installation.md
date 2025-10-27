Windows Installation
====================

WARNING: Docs for natively building Swiftarr on Windows are not available due to third party dependencies (`libjpeg` and `gdlib`). Use VS Code with Windows Subsystem for Linux (WSL) and do the [Linux Installation](./Linux%20Installation.md) instead.

This assumes you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) set up and functioning on your workstation. You should be able to run `docker ps` within your WSL machine.

If you see an error such as:
```shell
scripts/instance.sh up -d postgres redis
-bash: scripts/instance.sh: cannot execute: required file not found
```

Run from the native filesystem rather than the WSL mount. You may need to move your project directory.