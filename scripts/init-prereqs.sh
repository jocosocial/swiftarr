#!/usr/bin/env bash

# Setup any prereqs needed for the init container that
# will seed the database.

# Bail if something goes wrong.
set -e

# Basic prereqs
# Annoyingly the Makefile from the Toolbox requires sudo.
apt-get -qq update
apt-get install -y sudo curl libgd-dev

# Postgres client
curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add
echo 'deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main' > /etc/apt/sources.list.d/pgdg.list
apt-get -qq update
apt-get install -y postgresql-client-14

# Cleanup
apt-get clean
rm -r /var/lib/apt/lists/*
