#!/usr/bin/env bash
# Deploy (or update) the stack on the Swarm that DOCKER_HOST / the local daemon points at.
#
#   APP_IMAGE=ghcr.io/me/ticket-resolution:sha-abc1234 \
#   DOCKER_HOST=ssh://ubuntu@<manager-ip> ./scripts/deploy.sh
#
# Environment:
#   APP_IMAGE               (required) image to run
#   STACK_NAME              stack name                       (default: ticket)
#   APP_REPLICAS            app replicas                     (default: 2)
#   APP_PORT                published HTTP port              (default: 80)
#   RESOLVE_IMAGE           always|changed|never             (default: always; "never" for local images)
#   GRAFANA_ADMIN_PASSWORD  initial Grafana admin password   (default: random, printed once)
#   HUGGINGFACE_API_TOKEN   optional token for AI refinement (default: none)
#   WAIT_TIMEOUT            seconds to wait for convergence  (default: 300)
set -euo pipefail

cd "$(dirname "$0")/.."

: "${APP_IMAGE:?Set APP_IMAGE, e.g. ghcr.io/<owner>/ticket-resolution:<tag>}"
STACK_NAME="${STACK_NAME:-ticket}"
APP_REPLICAS="${APP_REPLICAS:-2}"
APP_PORT="${APP_PORT:-80}"
RESOLVE_IMAGE="${RESOLVE_IMAGE:-always}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

log() { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker CLI not found"

# --- sha256 portable across Linux / macOS
if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd() { sha256sum; }
else
  hash_cmd() { shasum -a 256; }
fi

# --- must be talking to a swarm manager
state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
[ "$state" = "active" ] || die "Docker is not in swarm mode (state='$state'). Check DOCKER_HOST or run: docker swarm init"
[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" = "true" ] || die "This node is not a swarm manager"

# --- config version: changes whenever any file under ./observability changes
CONFIG_VERSION="$(find observability -type f | LC_ALL=C sort | xargs -I{} sh -c 'cat "{}"; echo "{}"' | hash_cmd | cut -c1-10)"
export APP_IMAGE APP_REPLICAS APP_PORT CONFIG_VERSION
log "stack=$STACK_NAME image=$APP_IMAGE replicas=$APP_REPLICAS port=$APP_PORT config=$CONFIG_VERSION"

# --- secrets (created once; Swarm secrets are immutable)
if ! docker secret inspect grafana_admin_password >/dev/null 2>&1; then
  gf_pw="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-24)}"
  printf '%s' "$gf_pw" | docker secret create grafana_admin_password - >/dev/null
  log "created secret grafana_admin_password"
  printf '\n  Grafana login: admin / %s   (shown once, store it safely)\n\n' "$gf_pw"
fi

if ! docker secret inspect huggingface_api_token >/dev/null 2>&1; then
  printf '%s' "${HUGGINGFACE_API_TOKEN:-none}" | docker secret create huggingface_api_token - >/dev/null
  log "created secret huggingface_api_token (value: $([ -n "${HUGGINGFACE_API_TOKEN:-}" ] && echo provided || echo placeholder))"
fi

# --- deploy
log "deploying stack..."
docker stack deploy \
  --compose-file docker-stack.yml \
  --with-registry-auth \
  --resolve-image "$RESOLVE_IMAGE" \
  --prune \
  "$STACK_NAME"

# --- wait until every service reports desired/desired replicas
log "waiting up to ${WAIT_TIMEOUT}s for services to converge..."
deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
while :; do
  pending="$(docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME" --format '{{.Name}} {{.Replicas}}' \
    | awk '{split($2,a,"/"); if (a[1] != a[2]) print $1" "$2}')"
  [ -z "$pending" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '%s\n' "$pending" >&2
    docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME" >&2
    die "timed out. Inspect with: docker service ps --no-trunc ${STACK_NAME}_app"
  fi
  sleep 5
done

log "all services converged"
docker service ls --filter "label=com.docker.stack.namespace=$STACK_NAME"
