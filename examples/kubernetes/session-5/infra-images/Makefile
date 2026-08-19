SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help create build push list destroy all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

create: ## Create the ECR repositories (idempotent)
	@bash scripts/create-ecr.sh

build: ## Build + push both images to ECR (multi-arch: amd64/arm64)
	@bash scripts/build-push.sh

push: build ## Alias for 'build' (build already pushes)

list: ## List the images currently sitting in each ECR repository
	@bash scripts/list-ecr.sh

destroy: ## Delete all images, then delete the ECR repositories
	@bash scripts/destroy-ecr.sh

all: create build ## create + build in one shot
