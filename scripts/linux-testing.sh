#!/bin/bash

# simple control for running the test suite in a linux environment
# (api + postgres + redis)
#
# up: build swiftarr, create postgres and redis test containers if necessary, then start
# start: start any stopped container services
# stop: stop any running container services
# remove: remove stopped containers (to fully reset)

if [ $# -lt 1 ]; then
    echo "Usage: $0 COMMAND"
    echo "Valid commands are 'up', 'start', 'stop', 'remove'."
    exit
fi

case "$1" in
    up)     echo "starting linux-testing"
            docker-compose -f scripts/docker-compose-linux-testing.yml up --abort-on-container-exit
            ;;
    start)  echo "starting swiftarr test containers"
            docker-compose -f scripts/docker-compose-linux-testing.yml start
            ;;
    stop)   echo "stopping swiftarr test containers"
            docker-compose -f scripts/docker-compose-linux-testing.yml stop
            ;;
    remove) echo "removing test containers"
            docker-compose -f scripts/docker-compose-linux-testing.yml rm
            ;;
    *)      echo "parameter '$1' not understood (must be 'up' 'start' 'stop' or 'remove'"
            ;;
esac
