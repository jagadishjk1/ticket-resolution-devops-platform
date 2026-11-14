# Attribution and scope of work

## Third-party application (not part of this project's authorship)

The directory `app/` contains an **unmodified snapshot** of:

- **Project:** AI Ticket Resolution System & RAG Service
- **Author:** kishoredhondhu
- **Source:** https://github.com/kishoredhondhu/ai-ticket-resolution-system
- **Snapshot commit:** `049f3ef47b54bc5ec6d243c894896c79049175fe`
- **Licence:** MIT (see [`app/LICENSE`](app/LICENSE)). The licence and copyright notice are retained as required.

It is used purely as the **workload** that the infrastructure deploys and monitors.

## This project's own work

Everything outside `app/`:

- Terraform infrastructure (`terraform/`)
- Container image build (`docker/`)
- Docker Swarm stack and rollout strategy (`docker-stack.yml`)
- Observability platform: metrics, logs, dashboards and alert rules (`observability/`)
- CI/CD pipelines (`.github/workflows/`)
- Automation scripts and Makefile (`scripts/`, `Makefile`)
- All documentation under `docs/`

## For the submission

State this split clearly in the report and viva: the application belongs to its author;
the contribution being assessed is the DevOps and cloud engineering around it. It is also
good practice to inform the application's author that it is being used this way.
