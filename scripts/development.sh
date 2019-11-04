#!/bin/bash

# simple control for development environment databases
# (just postgres and redis docker containers running on standard ports)
#
# up: create postgres and redis containers if necessary, then start
# start: start any stopped database container services
# stop: stop any running database container services
# remove: remove stopped containers (to reset databases)

if [ $# -lt 1 ]; then
    echo "Usage: $0 COMMAND"
    echo "Valid commands are 'up', 'start', 'stop', 'remove'."
    exit
fi

case "$1" in
    up)     echo "creating dev database services"
            docker-compose -f scripts/docker-compose-development.yml up
            ;;
    start)  echo "starting dev database services"
            docker-compose -f scripts/docker-compose-development.yml start
            ;;
    stop)   echo "stopping dev database services"
            docker-compose -f scripts/docker-compose-development.yml stop
            ;;
    remove) echo "removing dev database containers"
            docker-compose -f scripts/docker-compose-development.yml rm
            ;;
    *)      echo "parameter '$1' not understood (must be 'up' 'start' 'stop' or 'remove'"
            ;;
esac

