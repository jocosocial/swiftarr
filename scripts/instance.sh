#!/bin/bash

# simple control for instance environment databases
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
    up)     echo "creating instance database services"
            docker-compose -f scripts/docker-compose-instance.yml up
            ;;
    start)  echo "starting instance database services"
            docker-compose -f scripts/docker-compose-instance.yml start
            ;;
    stop)   echo "stopping instance database services"
            docker-compose -f scripts/docker-compose-instance.yml stop
            ;;
    remove) echo "removing instance database containers"
            docker-compose -f scripts/docker-compose-instance.yml rm
            ;;
    *)      echo "parameter '$1' not understood (must be 'up' 'start' 'stop' or 'remove'"
            ;;
esac

