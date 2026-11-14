#!/bin/sh
# Container entrypoint.
# The upstream app only reads HUGGINGFACE_API_TOKEN from the environment, so a
# Docker/Swarm secret mounted as a file is exported here before starting it.
set -eu

SECRET_FILE="${HUGGINGFACE_API_TOKEN_FILE:-/run/secrets/huggingface_api_token}"

if [ -z "${HUGGINGFACE_API_TOKEN:-}" ] && [ -r "$SECRET_FILE" ]; then
  token="$(tr -d '\r\n' < "$SECRET_FILE")"
  # "none" is the placeholder that scripts/deploy.sh stores when no token is configured.
  if [ -n "$token" ] && [ "$token" != "none" ]; then
    HUGGINGFACE_API_TOKEN="$token"
    export HUGGINGFACE_API_TOKEN
  fi
fi

exec "$@"
