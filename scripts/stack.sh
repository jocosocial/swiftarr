#!/bin/bash

# Defaults
environment="production"
stackname="swiftarr"
filename="./scripts/docker-compose-stack.yml"

# https://www.baeldung.com/linux/use-command-line-arguments-in-bash-script
# Make sure these don't overlap with raw docker-compose options, or if they do
# it is somewhat known.
while getopts e:n:f: flag
do
    case "${flag}" in
        e) environment=${OPTARG};;
        n) stackname=${OPTARG};;
        f) filename=${OPTARG};;
        *) continue;;
    esac
done
# https://stackoverflow.com/questions/9472871/parse-arguments-after-getopts
shift $(($OPTIND - 1))

if [ -z "${environment}" ]; then
  echo "Must specify an environment (development/production) with '-e' as the first parameter."
  exit 1
else
  echo "Managing stack in ${environment} mode."
  echo "Arguments for docker-compose are: \"${@}\""
  echo "Using compose file at ${filename}."
fi

envfile="./Sources/Run/Private Swiftarr Config/${environment}.env"
echo "Using env file at ${envfile}"

docker-compose --project-name "${stackname}" --env-file "${envfile}" --file "${filename}" "${@}"