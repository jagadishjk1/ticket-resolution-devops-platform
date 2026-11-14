# Infrastructure Automation and Observability for an AI-Based IT Ticket Resolution Platform

**A DevOps and Cloud Engineering project**
Submitted in partial fulfilment of the requirements for the degree of Master of Computer Applications (MCA)

| | |
|---|---|
| Student | *[Your name]* |
| Roll / Registration no. | *[number]* |
| Guide | *[name, designation]* |
| University / Institute | *[name]* |
| Academic year | *[year]* |

---

## Declaration of contribution

The application deployed in this project (an AI-based IT-ticket resolution service using
Retrieval-Augmented Generation) was developed by **kishoredhondhu** and is used here,
unmodified, under the MIT licence
(https://github.com/kishoredhondhu/ai-ticket-resolution-system, commit `049f3ef`).
It serves as the workload. The work submitted by the student is the **design and
implementation of the infrastructure automation, container orchestration, observability
platform, CI/CD pipelines and documentation** described in this report.

*[Add acknowledgement and certificate pages per university format.]*

---

## Abstract

Modern applications fail less often because of their code than because of how they are
built, deployed and watched. This project designs and implements a complete delivery and
operations platform for an AI-driven IT-ticket resolution service. The platform provisions
cloud infrastructure on AWS with **Terraform**, runs the application as a replicated
service on a **Docker Swarm** cluster with health-gated rolling updates and automatic
rollback, and provides **observability** through Prometheus, Grafana, Loki and Alertmanager
without modifying the application. A **GitHub Actions** pipeline automates linting,
testing, container image builds, vulnerability scanning, deployment and smoke testing.
The result is a reproducible environment that can be created, updated and destroyed with
a few commands, with measurable service health and alerting.

**Keywords:** DevOps, Infrastructure as Code, Terraform, Docker Swarm, Observability, Prometheus, Grafana, Loki, CI/CD, AWS.

---

## 1. Introduction

### 1.1 Background
IT help desks handle large volumes of repetitive tickets. The chosen application suggests
resolutions by retrieving similar past tickets (TF-IDF similarity) and optionally refining
the answer with a language model. Running such a service reliably requires repeatable
infrastructure, safe releases and visibility into behaviour.

### 1.2 Problem statement
The application is deployed manually on a single platform-as-a-service host. There is no
infrastructure definition, no automated pipeline, no multi-node redundancy, no monitoring
of availability or quality, and no log aggregation or alerting.

### 1.3 Objectives
1. Define all infrastructure as code so environments are reproducible and reviewable.
2. Containerise the application and run it replicated on an orchestrated cluster.
3. Achieve zero-downtime releases with automatic rollback.
4. Provide metrics, logs, dashboards and alerts for the application and the cluster.
5. Automate build, test, security scanning and deployment.
6. Document architecture, operation and recovery.

### 1.4 Scope
In scope: AWS infrastructure, Swarm orchestration, observability, CI/CD, documentation.
Out of scope: changes to the application's business logic or machine-learning approach.

---

## 2. Technology overview and justification

| Area | Choice | Reason |
|---|---|---|
| IaC | Terraform | Declarative, plan/apply workflow, state, large AWS provider |
| Cloud | AWS (EC2, VPC, ASG, IAM, SSM) | Widely used; all components have free-tier-friendly small sizes |
| Orchestration | Docker Swarm | Built into Docker; rolling updates, secrets, configs, service discovery with low operational overhead for a single stateless service |
| Metrics | Prometheus + exporters | De-facto standard; pull model with DNS service discovery fits Swarm |
| Logs | Loki + Promtail | Label-based, lightweight, integrates with Grafana |
| Dashboards | Grafana | Provisioned from files (dashboards as code) |
| Alerting | Prometheus rules + Alertmanager | Grouping, inhibition and routing |
| CI/CD | GitHub Actions | Integrated with source and GHCR; OIDC to AWS |
| Security scanning | Trivy, Hadolint, ShellCheck, TFLint | Shift-left checks on images, Dockerfile, scripts, IaC |

---

## 3. System analysis

### 3.1 Existing system
Single-node PaaS deployment; no redundancy, no health history, no alerting, manual releases.

### 3.2 Proposed system
A three-node (1 manager + 2 workers) Swarm on AWS, created by Terraform, running two app
replicas spread across nodes with a complete monitoring stack and an automated pipeline.

### 3.3 Requirements

**Functional:** provision and destroy infrastructure with one command; deploy new versions
without downtime; observe availability, latency, quality and resource use; alert on failure;
roll back on a bad release.

**Non-functional:** reproducibility, security (least privilege, no secrets in code),
cost awareness (small instances, destroy when idle), maintainability (everything in Git),
recoverability (documented procedures).

---

## 4. System design

*(Insert the diagrams from `docs/ARCHITECTURE.md`: system context, network/infrastructure, observability data flow, CI/CD flow.)*

### 4.1 Infrastructure design
A VPC (10.20.0.0/16) with two public subnets in separate availability zones. One security group
allows Swarm traffic only between members, HTTP from the internet, and administration
ports (SSH, Grafana, Prometheus, Alertmanager) only from the operator's CIDR. IAM roles give
the manager write access and workers read-only access to the SSM parameters holding the
join token. Workers belong to an Auto Scaling Group for self-healing.

### 4.2 Cluster bootstrap
Nodes configure themselves through EC2 user-data: the manager initialises the swarm and
publishes the join token to SSM Parameter Store; workers poll the parameter and join. No manual
SSH steps are needed to form the cluster.

### 4.3 Application deployment design
Multi-stage image build; non-root runtime; health check; two replicas spread across nodes;
`start-first` rolling updates with a 30-second monitor window and automatic rollback;
resource limits; secrets mounted as files and exported by the entrypoint.

### 4.4 Observability design
The application exposes JSON metrics, not Prometheus format. Rather than modifying it, a
JSON exporter converts `/api/metrics` and `/api/metrics/realtime`, and a Blackbox exporter
probes `/health`. Prometheus discovers replicas through Swarm DNS (`tasks.app`), so each
replica is monitored individually. node-exporter and cAdvisor (global services) cover hosts
and containers; Promtail ships logs to Loki. Grafana datasources and the dashboard are
provisioned from files; alert rules cover availability, application quality and capacity.

### 4.5 CI/CD design
Pull requests run static checks, tests, an image build, a vulnerability scan and a container
smoke test. Merges to `main` publish the image to GHCR and trigger a gated deployment that
authenticates to AWS through OIDC, opens SSH for the runner's IP only for the duration of the
job, deploys the stack, runs smoke tests and closes access.

---

## 5. Implementation

| Module | Files | Summary |
|---|---|---|
| Network & security | `terraform/network.tf`, `security.tf` | VPC, subnets, routing, security group with `for_each` rules; validation forbids `0.0.0.0/0` for admin ports |
| Identity | `terraform/iam.tf` | Separate manager/worker roles, SSM parameters |
| Compute | `terraform/compute.tf`, `templates/` | Manager instance + Elastic IP, launch template and ASG, bootstrap scripts |
| State | `terraform/bootstrap-state/` | S3 bucket for remote state with versioning and encryption |
| Image | `docker/Dockerfile`, `entrypoint.sh` | Multi-stage build, non-root, health check |
| Stack | `docker-stack.yml` | 10 services, 2 overlay networks, 4 volumes, 2 secrets, 10 configs |
| Observability | `observability/**` | Prometheus, rules, Alertmanager, Blackbox, JSON exporter, Loki, Promtail, Grafana provisioning and dashboard |
| Automation | `scripts/`, `Makefile` | Deploy with config hashing and convergence wait, local Swarm, smoke test, load generator, offline validator |
| Pipelines | `.github/workflows/` | `ci.yml`, `deploy.yml`, `terraform.yml` |

*[Add short code excerpts with explanations: the config-hash trick, the `tasks.app` relabelling, the SSM join flow, the `start-first` update policy.]*

---

## 6. Testing and validation

### 6.1 Test strategy

| Level | What | How |
|---|---|---|
| Static | YAML/JSON/shell syntax, stack↔Prometheus consistency | `scripts/validate.sh` |
| Lint / security | Dockerfile, shell, Terraform, IaC misconfiguration, image CVEs | Hadolint, ShellCheck, TFLint, Trivy in CI |
| Unit | Upstream frontend tests | Vitest in CI |
| Integration | Image starts, `/health` 200, resolution endpoint, SPA served, metrics endpoints | `scripts/smoke-test.sh` |
| Infrastructure | `terraform validate`, `terraform plan`, real apply | Workflow and manual |
| Resilience | Replica failure, node failure, bad release | Experiments below |

### 6.2 Resilience experiments (record your results)

| # | Experiment | Expected result | Observed *(fill in)* |
|---|---|---|---|
| 1 | `docker service scale ticket_app=0` | `AppDown` fires after ~2 min; recovers when scaled back | |
| 2 | Kill one app container | Swarm restarts it; availability stays UP via second replica | |
| 3 | Terminate a worker EC2 instance | ASG replaces it; it joins swarm; tasks rescheduled | |
| 4 | Deploy a new image tag under load | No failed requests (start-first rolling update) | |
| 5 | Deploy a deliberately broken image | Health checks fail; automatic rollback | |
| 6 | Fill dashboards with `load-test.sh` | Query rate, latency, confidence panels populate | |

### 6.3 Results *(fill in from your run)*

- Time from `terraform apply` to a healthy cluster: *[ ] minutes*
- Time for a rolling update: *[ ] seconds*; failed requests during update: *[ ]*
- Time to detect an outage (alert fired): *[ ]*
- Pipeline duration end to end: *[ ] minutes*

*[Insert screenshots: terraform apply, node list, stack services, Grafana, Prometheus targets/alerts, GitHub Actions run, AWS console.]*

---

## 7. Security considerations

Least-privilege IAM; no long-lived cloud keys in CI (OIDC); secrets in Swarm secrets and SSM;
admin ports restricted by CIDR with a Terraform guard; IMDSv2 enforced; encrypted volumes;
non-root containers; pinned third-party image versions; automated vulnerability scanning.
Residual risks (documented): plain HTTP, single manager, public subnets, permissive CORS in the
upstream application.

---

## 8. Cost analysis

Approximate running cost for the default sizing is a few US dollars per day (see
`docs/DEPLOYMENT.md` §2.6). The environment is designed to be destroyed after use;
`terraform destroy` removes every billable resource it created.

---

## 9. Challenges and lessons learned

- **Metrics format mismatch:** the app exposes JSON; solved with exporters instead of code changes.
- **Per-replica state:** in-memory metrics behind a load balancer give inconsistent values; solved by scraping each replica via Swarm DNS.
- **Immutable Swarm configs:** solved by content-hashed config names.
- **Boot ordering of nodes:** solved with SSM polling instead of fixed delays.
- **CI access to a restricted SSH port:** solved with just-in-time security-group rules.
- *[Add your own genuine experiences from the build and deployment.]*

---

## 10. Conclusion

The project turns a manually deployed application into a reproducible, observable and
continuously delivered service. Infrastructure, configuration, dashboards and alerts are all
version-controlled; releases are health-gated and reversible; failures are detected and
visible within minutes.

## 11. Future scope

1. Three Swarm managers across availability zones; private subnets with NAT/VPC endpoints.
2. TLS termination with an ALB and ACM or Traefik with Let's Encrypt; WAF.
3. Instrument the application natively (`/metrics`, histograms) and define SLOs with burn-rate alerts.
4. Remote storage for metrics and logs (Thanos/Mimir, Loki on S3); EBS snapshots.
5. Migrate to Amazon EKS using the same image, health endpoints and dashboards.
6. Policy-as-code (OPA/Conftest, Checkov) and drift detection in CI.
7. Autoscaling of replicas based on Prometheus metrics.

## References

1. Terraform documentation, HashiCorp. https://developer.hashicorp.com/terraform
2. Docker Swarm mode documentation. https://docs.docker.com/engine/swarm/
3. Prometheus documentation. https://prometheus.io/docs/
4. Grafana and Loki documentation. https://grafana.com/docs/
5. GitHub Actions: OpenID Connect with AWS. https://docs.github.com/actions
6. Beyer, B. et al., *Site Reliability Engineering*, O'Reilly, 2016.
7. Kim, G. et al., *The DevOps Handbook*, IT Revolution, 2016.
8. kishoredhondhu, *AI Ticket Resolution System* (MIT). https://github.com/kishoredhondhu/ai-ticket-resolution-system

## Appendices

A. Repository structure · B. Terraform variables and outputs · C. Alert rule catalogue (`docs/OBSERVABILITY.md`) · D. Runbook (`docs/RUNBOOK.md`) · E. Command log of the deployment *[add]*
