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

# To accurately load the right compose file but not require the user to be in
# specific directories in the repo, we use Git voodoo to cd to the right place for
# this script. Then regardless if the compose fails we'll go back to where their
# shell started.
GIT_ROOT=$(git rev-parse --show-toplevel)

pushd $GIT_ROOT
COMPOSE_PROJECT_NAME="swiftarr_instance"
COMPOSE_FILE="scripts/docker-compose-instance.yml"
docker-compose -p ${COMPOSE_PROJECT_NAME} -f ${COMPOSE_FILE} "$@"
popd  # not really required for subshells, but good practice anyway
