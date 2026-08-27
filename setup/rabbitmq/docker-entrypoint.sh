#!/bin/sh
set -eu

rabbitmq_user=${RABBITMQ_DEFAULT_USER:-dev}
if [ "$rabbitmq_user" = guest ]; then
  echo "RABBITMQ_DEFAULT_USER must not be guest" >&2
  exit 64
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
