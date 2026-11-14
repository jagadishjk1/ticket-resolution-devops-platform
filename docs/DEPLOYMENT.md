# Deployment guide

## 0. Prerequisites

| Need | For | Notes |
|---|---|---|
| Docker 24+ | local run, image build | Swarm mode is part of Docker Engine / Docker Desktop. |
| `jq`, `curl`, `openssl`, bash ≥ 4.3 | scripts | macOS: `brew install bash jq`. |
| Terraform ≥ 1.6 (≥ 1.10 for S3 native locking) | AWS | `brew install terraform` or HashiCorp apt repo. |
| AWS account + CLI credentials | AWS | An IAM user/role able to create VPC, EC2, IAM roles, SSM, EIP, Auto Scaling. |
| SSH key pair | AWS | `ssh-keygen -t ed25519` (public key path goes in `terraform.tfvars`). |
| GitHub repository | CI/CD | Needed for GHCR images and Actions. |

First, run the offline checks:

```bash
make validate      # or: bash scripts/validate.sh
```

## 1. Local deployment (recommended first step)

```bash
./scripts/local-up.sh
```

What it does: initialises a single-node Swarm if needed → builds `ticket-resolution:local`
→ runs `scripts/deploy.sh` (creates secrets, renders the config version, deploys the
stack, waits for convergence) → smoke-tests the app.

| URL | What |
|---|---|
| http://localhost:8080 | Application (SPA) |
| http://localhost:8080/docs | FastAPI Swagger UI |
| http://localhost:3000 | Grafana (user `admin`, password printed once during deploy) |
| http://localhost:9090 | Prometheus (Status → Targets) |
| http://localhost:9093 | Alertmanager |

Generate data for the dashboards: `./scripts/load-test.sh http://localhost:8080 200`.

Docker Desktop note: cAdvisor mounts host paths (`/var/lib/docker`, `/sys`). If it fails to
start on your Docker Desktop version, the rest of the stack still works; container
panels will be empty. On a Linux VM or the AWS deployment it runs normally.

## 2. AWS deployment

### 2.1 (Optional but recommended) remote state

```bash
cd terraform/bootstrap-state
terraform init
terraform apply -var bucket_name=ticket-swarm-tfstate-<your-account-id>
cd ..
cp backend.tf.example backend.tf     # put the bucket name in
```

### 2.2 Provision the infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
#   admin_cidrs = ["<your-public-ip>/32"]       (curl -s https://checkip.amazonaws.com)
terraform init
terraform plan
terraform apply
```

Outputs include `manager_public_ip`, `app_url`, `grafana_url`, `ssh_command`, `docker_host`.
Allow ~3–5 minutes for the nodes to install Docker and form the Swarm, then verify:

```bash
ssh ubuntu@<manager_ip> 'docker node ls'        # expect 1 manager + N workers, all Ready
ssh ubuntu@<manager_ip> 'tail -n 20 /var/log/swarm-bootstrap.log'
```

### 2.2b Optional: friendly DNS names with Route53

If you have an existing **public** hosted zone, set in `terraform.tfvars`:

```hcl
hosted_zone_name = "longsea.online"
app_subdomain    = "ticket"
```

Terraform then creates A records pointing at the manager's Elastic IP:

| Name | Use |
|---|---|
| `ticket.longsea.online` | Application |
| `grafana.ticket.longsea.online` | Grafana (port 3000) |
| `prometheus.ticket.longsea.online` | Prometheus (port 9090) |
| `alerts.ticket.longsea.online` | Alertmanager (port 9093) |

Notes:
- The zone is only looked up; Terraform never creates or changes it. `terraform destroy` removes just the four records.
- The zone must be public and the domain's registrar nameservers must point to it (`dig NS <domain> +short`).
- If a record with the same name already exists, `apply` fails instead of overwriting it.
- `admin_cidrs` is still required: the firewall allow-list is by IP, not by name.
- Needed IAM permissions: `route53:ListHostedZonesByName`, `route53:GetHostedZone`, `route53:ListResourceRecordSets`, `route53:ChangeResourceRecordSets`, `route53:GetChange`.
- Still plain HTTP. HTTPS (reverse proxy + Let's Encrypt) is listed under future scope.

### 2.3 Get an image

Either let CI build it (push the repo to GitHub, see §3) or build and push your own:

```bash
docker build -f docker/Dockerfile -t ghcr.io/<owner>/ticket-resolution:v1 .
echo $GITHUB_TOKEN | docker login ghcr.io -u <owner> --password-stdin
docker push ghcr.io/<owner>/ticket-resolution:v1
```

Make the GHCR package **public** (Package settings → Change visibility), or provide a
pull token (`GHCR_PULL_TOKEN` secret in CI, or `docker login` on the manager).

### 2.4 Deploy and verify

```bash
cd ..
APP_IMAGE=ghcr.io/<owner>/ticket-resolution:v1 make deploy
make cloud-smoke
```

`make deploy` talks to the cluster through `DOCKER_HOST=ssh://ubuntu@<manager-ip>`, so
the workstation's IP must be in `admin_cidrs`.

Optional Hugging Face token (better AI refinement, higher rate limits), set before the
**first** deploy: `export HUGGINGFACE_API_TOKEN=hf_xxx`. Secrets are immutable; see the
runbook to rotate.

### 2.5 Tear down (stops all charges)

```bash
terraform -chdir=terraform destroy
```

### 2.6 Cost (approximate; check the AWS pricing calculator for your region)

| Item | Typical |
|---|---|
| 1 × t3.medium + 2 × t3.small (ap-south-1) | ≈ US$2–3 per day while running |
| ~70 GB gp3 storage | ≈ US$6 per month |
| Public IPv4 addresses (3) | ≈ US$0.015/hour in total |

Destroy the environment between work sessions. For a submission demo, deploy → capture
screenshots → destroy.

## 3. CI/CD setup (GitHub)

Push this project to its own GitHub repository (the `app/` folder included; keep its LICENSE).

### 3.1 AWS side: OIDC roles (no long-lived keys)

Create an IAM OIDC provider for `token.actions.githubusercontent.com` and two roles
trusting your repository:

| Role | Used by | Permissions |
|---|---|---|
| `github-terraform` | `terraform.yml` | Manage the resources in `terraform/` and read/write the state bucket. Start broad while learning, then tighten. |
| `github-deploy` | `deploy.yml` | Only `ec2:AuthorizeSecurityGroupIngress` and `ec2:RevokeSecurityGroupIngress` on the cluster's security group. |

Trust policy condition: `token.actions.githubusercontent.com:sub` = `repo:<owner>/<repo>:*`
(restrict to `ref:refs/heads/main` / the environment for production).

### 3.2 Repository variables and secrets

| Name | Type | Value |
|---|---|---|
| `AWS_REGION` | variable | e.g. `ap-south-1` |
| `AWS_TERRAFORM_ROLE_ARN` | variable | role for Terraform workflow |
| `AWS_DEPLOY_ROLE_ARN` | variable | role for deploy workflow |
| `TF_STATE_BUCKET` | variable | state bucket name |
| `TF_ADMIN_CIDRS` | variable | JSON list, e.g. `["203.0.113.10/32"]` |
| `SWARM_MANAGER_IP` | variable | `terraform output manager_public_ip` |
| `SWARM_SECURITY_GROUP_ID` | variable | the cluster security group id (`aws ec2 describe-security-groups` or console) |
| `SWARM_SSH_PRIVATE_KEY` | secret | private key matching the public key given to Terraform |
| `SWARM_SSH_PUBLIC_KEY` | secret | the public key text (used by the Terraform workflow) |
| `HUGGINGFACE_API_TOKEN` | secret, optional | for AI refinement |
| `GHCR_PULL_TOKEN` | secret, optional | only if the image is private |

Create GitHub **environments** `production` and `infrastructure` and add required
reviewers for a manual approval gate.

### 3.3 Pipeline behaviour

| Event | Result |
|---|---|
| Pull request | Static checks, tests, image build + scan + smoke test (no push), Terraform plan if `terraform/` changed |
| Merge to `main` | Above + push image `sha-<7>` and `latest` → deploy job (after approval, if configured) |
| Manual `Deploy to Swarm` with `image_tag` | Deploy/rollback to any tag |
| Manual `Terraform` with action | plan / apply / destroy (apply and destroy need approval) |

## 4. Evidence to capture for your submission

Take these while the environment is running (they feed straight into the project report):

1. `terraform apply` output and the AWS console (VPC, EC2, ASG, security group).
2. `docker node ls` and `docker stack services ticket`.
3. The application UI returning a suggested resolution.
4. Grafana dashboard with traffic (after `load-test.sh`), including the logs panel.
5. Prometheus → Status → Targets (all UP) and the Alerts page.
6. A triggered alert: `docker service scale ticket_app=0`, wait ~2 min, show `AppDown` firing, scale back.
7. A rolling update (deploy a new tag while `watch docker service ps ticket_app` runs) and an intentional bad deploy rolling back automatically.
8. Self-healing: terminate a worker EC2 instance; the ASG replaces it and it rejoins the swarm.
9. GitHub Actions run: green pipeline with all stages.
