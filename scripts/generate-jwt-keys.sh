#!/bin/bash
# Script to generate RSA keys for JWT signing in OpenID Connect

# Default directory
CURRENT_DIR=$(pwd)
GIT_ROOT=$(git rev-parse --show-toplevel)
cd $GIT_ROOT
KEY_DIR="./scripts/jwt-keys"

# Handle command-line arguments
while getopts ":d:" opt; do
  case $opt in
    d) KEY_DIR="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
        exit 1
    ;;
  esac
done

# Create directory if it doesn't exist
if [ ! -d "$KEY_DIR" ]; then
  echo "Creating directory $KEY_DIR..."
  mkdir -p "$KEY_DIR"
fi

# Generate private key
PRIVATE_KEY_PATH="$KEY_DIR/private.pem"
echo "Generating RSA private key to $PRIVATE_KEY_PATH..."
openssl genrsa -out "$PRIVATE_KEY_PATH" 2048

# Generate public key
PUBLIC_KEY_PATH="$KEY_DIR/public.pem"
echo "Extracting public key to $PUBLIC_KEY_PATH..."
openssl rsa -in "$PRIVATE_KEY_PATH" -pubout -out "$PUBLIC_KEY_PATH"

# Set permissions
chmod 600 "$PRIVATE_KEY_PATH"
chmod 644 "$PUBLIC_KEY_PATH"

echo "Keys generated successfully."
echo ""
echo "To use the keys with Swiftarr, set the following environment variables:"
echo "SWIFTARR_JWT_PRIVATE_KEY=$PRIVATE_KEY_PATH"
echo "SWIFTARR_JWT_PUBLIC_KEY=$PUBLIC_KEY_PATH"
echo "SWIFTARR_JWT_KID=swiftarr-key-1  # Or any other key ID you prefer"
echo ""
echo "For security, ensure that the private key is only readable by the application user."
cd $CURRENT_DIR
