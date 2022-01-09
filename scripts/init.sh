#!/usr/bin/env bash

echo "Swiftarr init start."

echo "Testing for database existence..."
psql -P pager=off -c "SELECT * FROM users LIMIT 1;" > /dev/null

if [ $? != 0 ]; then
  echo "Database not initialized. Running migration..."
  vapor run migrate --auto-migrate
else
  echo "Database already initialized."
fi

echo "Swiftarr init finish."