# Operations runbook

All commands run against the manager: SSH in, or use
`export DOCKER_HOST=ssh://ubuntu@<manager-ip>` from an allow-listed IP. The stack is named `ticket`
(services are `ticket_<name>`).

## 1. Daily checks

```bash
docker node ls                                   # all nodes Ready/Active
docker stack services ticket                     # REPLICAS column x/x everywhere
docker service ps ticket_app --no-trunc          # recent task history, failures
```

Grafana home dashboard: availability UP, 2 healthy replicas, 0 firing alerts.

## 2. Deploy, roll back, scale

| Task | Command |
|---|---|
| Deploy new version | CI does it on merge; manual: `APP_IMAGE=ghcr.io/<o>/ticket-resolution:<tag> ./scripts/deploy.sh` |
| Roll back | Run the **Deploy to Swarm** workflow with an older `image_tag`, or `docker service rollback ticket_app` |
| Scale app | `APP_REPLICAS=4 APP_IMAGE=<current-image> ./scripts/deploy.sh` (keeps the file as source of truth). Quick test: `docker service scale ticket_app=4` |
| Add worker capacity | Change `worker_count` in Terraform and apply; new nodes join automatically |
| Change an alert/dashboard | Edit under `observability/`, redeploy; the new config hash rolls the service |

If a rollout fails its health checks, Swarm rolls back by itself (`failure_action: rollback`).

## 3. Incident playbook

| Symptom / alert | Likely cause | Check | Fix |
|---|---|---|---|
| `AppDown` | All replicas unhealthy or crashing | `docker service ps ticket_app --no-trunc`, `docker service logs ticket_app --tail 100` | Fix cause; if a bad release, roll back |
| App tasks restart loop, logs show failed RAG init | Knowledge base file missing/incompatible | logs for "Failed to initialize RAG engine" | Rebuild image; the app can rebuild from `Sample-Data.xlsx` |
| `/health` 503 for > 1 min after start | KB still loading or failed | logs; `start_period` is 40 s | Wait, then see above |
| `AppReplicasDegraded` | A node is down or tasks rescheduling | `docker node ls`, ASG activity in console | Replace/restore node; ASG self-heals workers |
| `NodeDiskLow` | Images, logs or TSDB growing | `docker system df`, `df -h` | `docker system prune -af` on that node; reduce retention; enlarge volume |
| Node shows `Down` after the ASG replaced it | Stale swarm membership | `docker node ls` | `docker node rm <id>` for the Down node |
| Prometheus target down | Service restarting or overlay DNS issue | Prometheus → Targets error text | Check service; `docker service ps` for that service |
| Grafana empty panels | No traffic yet, or datasource unreachable | Explore → run the query directly | Run `scripts/load-test.sh`; check Prometheus is up |
| `AppLowConfidence` | Questions not covered by knowledge base | Compare categories in app stats | Rebuild KB (`POST /api/reload-knowledge-base` after updating data) |

## 4. Manager failure

The manager holds Swarm state (Raft), Prometheus/Loki/Grafana data and Docker secrets.
With a single manager, losing it means rebuilding:

1. `terraform apply` (recreates the instance if it was destroyed; refresh/untaint as needed).
2. Existing workers are orphaned; terminate them so the ASG recreates them and they join the new swarm.
3. Redeploy: `./scripts/deploy.sh` (secrets are recreated; Grafana gets a new password; metrics history is lost).

Mitigations: three managers (see ARCHITECTURE.md §6), EBS snapshots (AWS Backup / DLM) of the
manager volume, and Thanos/S3 for metrics.

## 5. Secrets and credentials

| Item | Procedure |
|---|---|
| Rotate Hugging Face token | Swarm secrets are immutable: `docker stack rm ticket`, `docker secret rm huggingface_api_token`, set `HUGGINGFACE_API_TOKEN`, redeploy |
| Reset Grafana admin password | `docker exec -it $(docker ps -q -f name=ticket_grafana) grafana cli admin reset-admin-password '<new>'` |
| Rotate Swarm join token | `docker swarm join-token --rotate worker`, then re-run the manager's SSM `put-parameter` (see `manager.sh.tftpl`) |
| Replace SSH key | New public key in `terraform.tfvars`; note the key pair resource is replaced but running instances keep the old authorised key until recreated; use SSM Session Manager meanwhile |

## 6. Backups

| Data | Approach |
|---|---|
| Infrastructure | Terraform state in versioned S3 |
| Config | Everything under `observability/` is in Git |
| Metrics/logs | Optional: snapshot the manager's EBS volume; Docker volumes live under `/var/lib/docker/volumes/ticket_*` |
| Application data | None: the knowledge base is in the image |

## 7. Likely first-run issues

| Issue | Resolution |
|---|---|
| `docker build` fails in the frontend stage with TypeScript errors | The build runs `tsc -b` (upstream). Build with `--build-arg FRONTEND_BUILD_CMD="npx vite build"` and note it in your report; ideally fix the types upstream. |
| `docker stack deploy` says config/secret not found | Run via `scripts/deploy.sh`; it creates secrets and exports `CONFIG_VERSION` |
| Port 80 / 3000 / 9090 already in use locally | `APP_PORT=9000 ./scripts/local-up.sh`; stop whatever else uses 3000/9090 |
| cAdvisor does not start on Docker Desktop | Expected on some versions; container panels stay empty, everything else works |
| Loki exits with a config error | Pinned to 2.9.8 syntax; if you bump the image, review the Loki changelog (3.x changes `compactor`/storage keys) |
| Terraform: key file not found | Set `public_key_path` to an existing `.pub` file |
| Workers never join | `ssh` to a worker: `tail /var/log/swarm-bootstrap.log`; usual causes are no outbound internet or SG rules missing |
| `terraform validate` complains about a provider argument | Provider is pinned to `~> 5.60`; run `terraform init -upgrade`, and if a newer major changed an argument, adjust accordingly |
