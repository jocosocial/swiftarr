#!/usr/bin/env bash

# Setup any prereqs needed for the init sequence that
# will seed the database.

# Bail if something goes wrong and print out what we're doing.
set -ex

# Some packages install interactively, specifically looking at tzdata. This disables
# the prompting and accepts a default. For the tzdata case, this becomes UTC.
# https://linuxhint.com/debian_frontend_noninteractive/
export DEBIAN_FRONTEND=noninteractive

# Basic prereqs.
# libicu tends to rev pretty aggressively with different base images!
apt-get -qq update
apt-get install -y \
  curl libatomic1 libicu66 libxml2 gnupg2 \
  libcurl4 libz-dev libbsd0 tzdata libgd3

# Postgres client. Make sure to keep the repo in sync with whatever base image you're using.
curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add
echo 'deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main' > /etc/apt/sources.list.d/pgdg.list
apt-get -qq update
apt-get install -y postgresql-client-14

# Wait tool. This will guarantee the database is available before allowing the container to proceed.
# Hopefully this is not a bad idea.
WAIT_VERSION=2.9.0
curl -sL -o /wait "https://github.com/ufoscout/docker-compose-wait/releases/download/${WAIT_VERSION}/wait"
chmod +x /wait

# Cleanup & Lockdown
apt-get clean
rm -r /var/lib/apt/lists/*
