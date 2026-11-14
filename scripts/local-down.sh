#!/usr/bin/env bash
# Remove the local stack.
#   ./scripts/local-down.sh             # remove services only (data kept)
#   ./scripts/local-down.sh --purge     # also remove volumes and secrets
#   ./scripts/local-down.sh --leave     # additionally leave swarm mode
set -euo pipefail

STACK_NAME="${STACK_NAME:-ticket}"
purge=0; leave=0
for a in "$@"; do
  case "$a" in
    --purge) purge=1 ;;
    --leave) purge=1; leave=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

docker stack rm "$STACK_NAME"

if [ "$purge" -eq 1 ]; then
  echo "[local] waiting for containers to stop..."
  while [ -n "$(docker ps -q --filter "label=com.docker.stack.namespace=$STACK_NAME")" ]; do sleep 2; done
  sleep 5   # let the network release the volumes
  for v in prometheus_data alertmanager_data loki_data grafana_data; do
    docker volume rm "${STACK_NAME}_${v}" >/dev/null 2>&1 || true
  done
  docker secret rm grafana_admin_password huggingface_api_token >/dev/null 2>&1 || true
fi

if [ "$leave" -eq 1 ]; then
  docker swarm leave --force
fi
echo "[local] done"
