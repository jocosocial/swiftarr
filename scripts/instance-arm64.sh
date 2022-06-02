#!/bin/bash

# simple control for instance environment databases
# (just postgres and redis docker containers running on standard ports)
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

COMPOSE_PROJECT_NAME="swiftarr_instance"
COMPOSE_FILE="scripts/docker-compose-arm64.yml"
docker-compose -p ${COMPOSE_PROJECT_NAME} -f ${COMPOSE_FILE} "$@"
