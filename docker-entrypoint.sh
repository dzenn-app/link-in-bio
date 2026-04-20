#!/bin/sh
set -e

echo ">>> Running Prisma db push..."
./node_modules/.bin/prisma db push --skip-generate

echo ">>> Starting application..."
exec "$@"
