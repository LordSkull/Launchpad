#!/bin/sh
set -eu

cd /app

# Rails refuses to start if a stale PID survived an unclean container stop.
rm -f tmp/pids/server.pid

mkdir -p user_data/songs storage

DB_FILE="/app/storage/development.sqlite3"

if [ ! -f "$DB_FILE" ]; then
  echo "[Launchpad] Initializing SQLite database..."
  bundle _2.4.22_ exec rake db:setup
fi

echo "[Launchpad] Starting on http://localhost:3000"
exec "$@"
