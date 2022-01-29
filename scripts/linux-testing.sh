#!/bin/bash

# simple control for running the test suite in a linux environment
# (api + postgres + redis)
#
# up: build swiftarr, create postgres and redis test containers if necessary, then start
# start: start any stopped container services
# stop: stop any running container services
# remove: remove stopped containers (to fully reset)
# build: build any dependent images
# logs: get logs

if [ $# -lt 1 ]; then
    echo "Usage: $0 COMMAND"
    echo "Valid commands are 'up', 'start', 'stop', 'remove'."
    exit
fi

COMPOSE_PROJECT_NAME="swiftarr_testing"
COMPOSE_FILE="scripts/docker-compose-linux-testing.yml"
COMPOSE="docker-compose -p ${COMPOSE_PROJECT_NAME} -f ${COMPOSE_FILE}"

case "$1" in
    up)     echo "starting linux-testing"
            ${COMPOSE} up --abort-on-container-exit
            ;;
    start)  echo "starting swiftarr test containers"
            ${COMPOSE} start
            ;;
    stop)   echo "stopping swiftarr test containers"
            ${COMPOSE} stop
            ;;
    build)   echo "build swiftarr test container images"
            ${COMPOSE} build
            ;;
    logs)   echo "gets logs from this stack"
            ${COMPOSE} logs
            ;;
    remove) echo "removing test containers"
            ${COMPOSE} rm
            ;;
    *)      echo "parameter '$1' not understood (must be 'up' 'start' 'stop' or 'remove'"
            ;;
esac
