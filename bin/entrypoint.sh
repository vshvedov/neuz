#!/usr/bin/env bash
set -euo pipefail

NEUZ_DATA_DIR="${NEUZ_DATA_DIR:-/app/data}"
mkdir -p "$NEUZ_DATA_DIR"
chmod 700 "$NEUZ_DATA_DIR"

cd /app
echo "[neuz.entrypoint] Running database migrations..."
bundle exec rake db:migrate

if [ ! -f "$NEUZ_DATA_DIR/.first_boot_announced" ] && [ -f "$NEUZ_DATA_DIR/first_boot_key.txt" ]; then
  echo
  echo "[neuz.entrypoint] First boot detected. To finish setup, run:"
  echo
  echo "    docker compose exec neuz bin/neuz setup"
  echo
  echo "(That command prints the API key and the two Claude prompts.)"
  echo
fi

echo "[neuz.entrypoint] Starting Puma on port ${PORT:-9292}..."
exec bundle exec puma -C /app/config/puma.rb
