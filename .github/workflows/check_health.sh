#!/usr/bin/env bash
set -e

while getopts e: flag
do
    case "${flag}" in
        e) environment=${OPTARG};;
        *) continue;;
    esac
done
shift $(($OPTIND - 1))

if [ -z "${environment}" ]; then
  echo "Must specify an environment (development/production) with '-e' as the first parameter."
  exit 1
else
  echo "Testing health in \"${environment}\" mode."
fi

envfile="./Sources/swiftarr/seeds/Private Swiftarr Config/${environment}.env"
echo "Using env file at ${envfile}"

set -a
source "${envfile}"
set +a

# Odds are SWIFTARR_IP is 0.0.0.0 which magically becomes localhost
endpoint="http://${SWIFTARR_IP}:${SWIFTARR_PORT}/api/v3/client/health"
echo "Checking endpoint ${endpoint}"

curl -f "${endpoint}"