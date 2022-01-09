#!/usr/bin/env bash

echo "Swiftarr start."

echo "Waiting for dependencies..."
/wait

if [ "${AUTO_MIGRATE}" = true ]; then
  echo "Testing for database existence..."
  # To avoid doubling up on environment variables, we're gonna consume
  # the ones passed to the app and reset the psql env vars to match.
  export PGHOST=${DATABASE_HOSTNAME} PGUSER=${DATABASE_USER} PGPASSWORD=${DATABASE_PASSWORD} PGDATABASE=${DATABASE_DB}
  psql -P pager=off -c "SELECT * FROM users LIMIT 1;" > /dev/null

  if [ $? != 0 ]; then
    echo "Database not initialized. Running migration..."
    /app/Run migrate --yes --env "${ENVIRONMENT}"
  else
    echo "Database already initialized."
  fi
else
  echo "Automatic database migration was disabled."
fi

/app/Run serve --env "${ENVIRONMENT}" --hostname 0.0.0.0 --port 8081