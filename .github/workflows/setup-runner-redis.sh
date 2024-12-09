#!/bin/bash

# Exit script on error
set -e

# Define variables
REDIS_VERSION="redis@6.2"
REDIS_CONFIG="/opt/homebrew/etc/redis.conf"
REDIS_PASSWORD="password"

echo "Configuring Redis 6.2..."

# Install Redis 6.2 if not already installed
if ! brew list | grep -q "$REDIS_VERSION"; then
  echo "Installing Redis 6.2..."
  brew install "$REDIS_VERSION"
else
  echo "Redis 6.2 is already installed."
fi

# Link Redis to the default `redis` command (optional)
if ! brew list | grep -q "^redis$"; then
  echo "Linking $REDIS_VERSION to default Redis command..."
  brew link --overwrite "$REDIS_VERSION"
fi

# Ensure Redis is stopped before configuration
echo "Stopping Redis service if running..."
brew services stop "$REDIS_VERSION" || true

# Update Redis configuration to require a password
echo "Configuring Redis to require a password..."
if grep -q "^# requirepass" "$REDIS_CONFIG"; then
  sed -i '' "s/^# requirepass.*/requirepass $REDIS_PASSWORD/" "$REDIS_CONFIG"
else
  echo "requirepass $REDIS_PASSWORD" >> "$REDIS_CONFIG"
fi

# Start Redis service
echo "Starting Redis service..."
brew services start "$REDIS_VERSION"

# Test Redis connection with password
echo "Testing Redis setup..."
if redis-cli -a "$REDIS_PASSWORD" PING | grep -q "PONG"; then
  echo "Redis is configured successfully and is requiring a password."
else
  echo "Failed to authenticate with Redis. Check the configuration."
  exit 1
fi

echo "Redis 6.2 setup is complete. Password: $REDIS_PASSWORD"
