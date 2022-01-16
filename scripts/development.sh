#!/bin/bash

# simple control for development environment databases
# (just postgres and redis docker containers running on standard ports
# and their *-test counterparts running on +1 ports for testing)
#
# Any arguments to docker-compose can be provided as arguments to this script.
# For example:
#   * scripts/development.sh up -d
#   * scripts/development.sh down
#   * scripts/development.sh restart postgres
#
# This does break backwards compatibility since "remove" is not a docker-compose
# verb (rm is the equivalent under the hood). While extended parameters could be
# provided in the form of "${@:2}" (all params except the first one, thanks StackOverflow)
# this requires any new verbs to be supported by this wrapper which feels overly
# complex.

COMPOSE_PROJECT_NAME="swiftarr"
COMPOSE_FILE="scripts/docker-compose-development.yml"
docker-compose -p ${COMPOSE_PROJECT_NAME} -f ${COMPOSE_FILE} "$@"
