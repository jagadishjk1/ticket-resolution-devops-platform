.DEFAULT_GOAL := help
SHELL := /bin/bash

IMAGE      ?= ticket-resolution:local
TF_DIR     := terraform
MANAGER_IP ?= $(shell cd $(TF_DIR) && terraform output -raw manager_public_ip 2>/dev/null)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

##@ Local (single-node Swarm)
.PHONY: build local-up local-down smoke load
build: ## Build the application image
	docker build -f docker/Dockerfile -t $(IMAGE) .

local-up: ## Build, deploy and smoke-test everything locally
	./scripts/local-up.sh

local-down: ## Remove the local stack (use ARGS=--purge to wipe data)
	./scripts/local-down.sh $(ARGS)

smoke: ## Smoke test (URL=http://localhost:8080)
	./scripts/smoke-test.sh $(or $(URL),http://localhost:8080)

load: ## Generate traffic for dashboards (URL=..., N=100)
	./scripts/load-test.sh $(or $(URL),http://localhost:8080) $(or $(N),100)

##@ Quality
.PHONY: validate
validate: ## Offline static validation
	./scripts/validate.sh

##@ Infrastructure (AWS)
.PHONY: tf-init tf-plan tf-apply tf-destroy
tf-init: ## terraform init
	cd $(TF_DIR) && terraform init

tf-plan: ## terraform plan
	cd $(TF_DIR) && terraform plan

tf-apply: ## terraform apply
	cd $(TF_DIR) && terraform apply

tf-destroy: ## terraform destroy (removes ALL cloud resources)
	cd $(TF_DIR) && terraform destroy

##@ Deploy to the cloud cluster
.PHONY: deploy cloud-smoke
deploy: ## Deploy to the cluster (APP_IMAGE=ghcr.io/<owner>/ticket-resolution:<tag>)
	@test -n "$(MANAGER_IP)" || (echo "No manager IP: run terraform apply first or pass MANAGER_IP=" && exit 1)
	DOCKER_HOST=ssh://ubuntu@$(MANAGER_IP) ./scripts/deploy.sh

cloud-smoke: ## Smoke test the cloud deployment
	./scripts/smoke-test.sh http://$(MANAGER_IP) http://$(MANAGER_IP):9090
