#!/bin/bash

# Exit script on error
set -e

# Define variables
DB_NAME="swiftarr"
DB_USER="swiftarr"
DB_PASSWORD="password"
POSTGRES_CONFIG="/opt/homebrew/var/postgresql@14/postgresql.conf"

echo "Configuring PostgreSQL 14 database..."

# Install PostgreSQL 14 if not already installed
if ! brew list | grep -q postgresql@14; then
  echo "Installing PostgreSQL 14..."
  brew install postgresql@14
else
  echo "PostgreSQL 14 is already installed."
fi

# Configure PostgreSQL to listen on TCP port 5432
echo "Configuring PostgreSQL to listen on TCP port 5432..."
if grep -q "^#listen_addresses = 'localhost'" "$POSTGRES_CONFIG"; then
  sed -i '' "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$POSTGRES_CONFIG"
else
  echo "listen_addresses = '*'" >> "$POSTGRES_CONFIG"
fi

# Start PostgreSQL service
echo "Starting PostgreSQL service..."
brew services start postgresql@14

# Ensure `psql` uses the correct version of PostgreSQL
export PATH="/usr/local/opt/postgresql@14/bin:$PATH"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Create the database
echo "Creating database '${DB_NAME}'..."
createdb "$DB_NAME" || echo "Database '${DB_NAME}' already exists."

# Create the user
echo "Creating user '${DB_USER}'..."
psql postgres -c "DO \$\$ 
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
   END IF;
END
\$\$;"

# Grant privileges to the user
echo "Granting privileges to user '${DB_USER}'..."
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# Verify the configuration
echo "Verifying configuration..."
psql "$DB_NAME" -U "$DB_USER" -c "\dt" || echo "User '${DB_USER}' is unable to access the database. Check your settings."

echo "PostgreSQL database '${DB_NAME}' configured successfully with user '${DB_USER}'."
