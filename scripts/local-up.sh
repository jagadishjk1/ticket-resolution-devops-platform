#!/usr/bin/env bash
# Run the whole platform on this machine as a single-node Swarm.
# Same stack file and configs as production, so what you test is what you ship.
#
#   ./scripts/local-up.sh            # build image, deploy, smoke test
#   APP_PORT=9000 ./scripts/local-up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${APP_IMAGE:-ticket-resolution:local}"
export APP_PORT="${APP_PORT:-8080}"
export APP_REPLICAS="${APP_REPLICAS:-2}"
export RESOLVE_IMAGE=never        # image only exists in the local daemon

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }

if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
  echo "[local] initialising single-node swarm"
  docker swarm init >/dev/null || {
    echo "docker swarm init failed. On a host with several IPs run: docker swarm init --advertise-addr <ip>" >&2
    exit 1
  }
fi

echo "[local] building $IMAGE"
docker build -f docker/Dockerfile -t "$IMAGE" .

APP_IMAGE="$IMAGE" ./scripts/deploy.sh

echo "[local] smoke test"
./scripts/smoke-test.sh "http://localhost:${APP_PORT}"

cat <<EOF

  App          http://localhost:${APP_PORT}
  API docs     http://localhost:${APP_PORT}/docs
  Grafana      http://localhost:3000     (admin / password printed above)
  Prometheus   http://localhost:9090
  Alertmanager http://localhost:9093

  Generate traffic for the dashboards:  ./scripts/load-test.sh http://localhost:${APP_PORT} 100
  Tear down:                            ./scripts/local-down.sh
EOF
