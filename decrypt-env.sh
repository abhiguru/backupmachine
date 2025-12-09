#!/bin/bash
# Decrypt .env file from backup
# Usage: ./decrypt-env.sh /backup/secrets/.env.20251209_030001.gpg

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <encrypted_file.gpg>"
    exit 1
fi

ENCRYPTED_FILE="$1"
PASSPHRASE_FILE="$HOME/.secrets/gpg_passphrase"

if [ ! -f "$ENCRYPTED_FILE" ]; then
    echo "Error: Encrypted file not found: $ENCRYPTED_FILE"
    exit 1
fi

if [ ! -f "$PASSPHRASE_FILE" ]; then
    echo "Error: Passphrase file not found: $PASSPHRASE_FILE"
    exit 1
fi

# Decrypt to stdout
gpg --decrypt --quiet --batch --passphrase-file "$PASSPHRASE_FILE" "$ENCRYPTED_FILE"
