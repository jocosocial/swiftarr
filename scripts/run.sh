#!/usr/bin/env bash

# Launch script for running an instance of Swiftarr in its container environment.

echo "Swiftarr start."

echo "Waiting for dependencies..."
/wait

if [ "${AUTO_MIGRATE}" = true ]; then
  echo "Testing for database existence..."
  # To avoid doubling up on environment variables, we're gonna consume
  # the ones passed to the app and reset the psql env vars to match.
  export PGHOST=${DATABASE_HOSTNAME} PGUSER=${DATABASE_USER} PGPASSWORD=${DATABASE_PASSWORD} PGDATABASE=${DATABASE_DB}
  psql -P pager=off -c "SELECT * FROM public.user LIMIT 1;" > /dev/null

  if [ $? != 0 ]; then
    echo "Database not initialized. Running migration..."
    # Papa Bless - https://theswiftdev.com/server-side-swift-projects-inside-docker-using-vapor-4/
    /app/Run migrate --yes --env "${ENVIRONMENT}"
  else
    echo "Database already initialized."
  fi
else
  echo "Automatic database migration was disabled."
fi

exec /app/Run serve --env "${ENVIRONMENT}" --hostname ${SWIFTARR_IP} --port ${SWIFTARR_PORT}
