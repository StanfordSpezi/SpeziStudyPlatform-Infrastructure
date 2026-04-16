.PHONY: help dev dev-status clean validate lint build-all

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Local development
# ---------------------------------------------------------------------------

dev: ## Set up local dev environment in KIND
	python3 tools/setup.py

dev-status: ## Show ArgoCD Application sync status
	kubectl get applications -n argocd

dev-recreate: ## Recreate KIND cluster from scratch
	kind delete cluster --name spezi-study-platform && kind create cluster --config tools/kind-config.yaml

clean: ## Delete the local KIND cluster
	kind delete cluster --name spezi-study-platform

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate: ## Validate all Kustomize overlays build cleanly
	@echo "Building infrastructure/dev..."
	@kubectl kustomize infrastructure/dev > /dev/null
	@echo "Building infrastructure/prod..."
	@kubectl kustomize infrastructure/prod > /dev/null
	@echo "Building apps/dev..."
	@kubectl kustomize apps/dev > /dev/null
	@echo "Building apps/prod..."
	@kubectl kustomize apps/prod > /dev/null
	@echo "Building bootstrap/dev..."
	@kubectl kustomize bootstrap/dev > /dev/null
	@echo "Building bootstrap/prod..."
	@kubectl kustomize bootstrap/prod > /dev/null
	@echo "Building argocd-apps/dev..."
	@kubectl kustomize argocd-apps/dev > /dev/null
	@echo "Building argocd-apps/prod..."
	@kubectl kustomize argocd-apps/prod > /dev/null
	@echo "All overlays build successfully."

lint: ## Run kubeconform schema validation on all overlays
	@for overlay in infrastructure/dev infrastructure/prod apps/dev apps/prod bootstrap/dev bootstrap/prod; do \
		echo "Validating $$overlay..."; \
		kubectl kustomize $$overlay | kubeconform -strict -summary -output text; \
	done

build-all: ## Render all overlays to stdout (useful for diffing)
	@for overlay in infrastructure/dev infrastructure/prod apps/dev apps/prod bootstrap/dev bootstrap/prod argocd-apps/dev argocd-apps/prod; do \
		echo "---"; \
		echo "# $$overlay"; \
		kubectl kustomize $$overlay; \
	done
