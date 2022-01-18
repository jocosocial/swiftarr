#!/bin/bash

# Defaults
stackname="swiftarr"
environment="production"
filename="./scripts/docker-compose-stack.yml"

function usage () {
  echo "Usage:"
  echo "-e: environment name (default: ${environment})"
  echo "-n: stack name (default: ${stackname})"
  echo "-f: compose file path (default: ${filename})"
  echo "-h: help"
  echo ""
  echo "Any remaining arguments are dumped into docker-compose."
  echo ""
  exit 0
}

# https://www.baeldung.com/linux/use-command-line-arguments-in-bash-script
# Make sure these don't overlap with raw docker-compose options, or if they do
# it is somewhat known.
while getopts e:n:f:h: flag
do
    case "${flag}" in
        e) environment=${OPTARG};;
        n) stackname=${OPTARG};;
        f) filename=${OPTARG};;
        h) usage;;
        *) continue;;
    esac
done
# https://stackoverflow.com/questions/9472871/parse-arguments-after-getopts
shift $(($OPTIND - 1))

if [ -z "${environment}" ]; then
  echo "Must specify an environment (development/production) with '-e' as the first parameter."
  exit 1
else
  echo "Managing stack \"${stackname}\" in \"${environment}\" mode."
  echo "Arguments for docker-compose are: \"${@}\""
  echo "Using compose file at ${filename}."
fi

envfile="./Sources/Run/Private Swiftarr Config/${environment}.env"
echo "Using env file at ${envfile}"

docker-compose --project-name "${stackname}" --env-file "${envfile}" --file "${filename}" "${@}"
