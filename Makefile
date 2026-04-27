.PHONY: help dev dev-down dev-status \
       prod-plan prod-apply prod-down prod-destroy prod-bootstrap prod-status \
       prod-scale-down prod-scale-up \
       argocd-password validate lint build-all

TOFU := tofu -chdir=terraform
KIND_CLUSTER := spezi-study-platform
BRANCH ?=

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Local development (KIND)
# ---------------------------------------------------------------------------

dev: ## Create KIND cluster and bootstrap ArgoCD + apps
	@kind get clusters 2>/dev/null | grep -q '^$(KIND_CLUSTER)$$' || kind create cluster --name $(KIND_CLUSTER) --config tools/kind-config.yaml
	python3 tools/setup.py $(if $(BRANCH),--branch $(BRANCH))

dev-status: ## Show ArgoCD Application sync status
	kubectl get applications -n argocd

dev-down: ## Delete KIND cluster
	kind delete cluster --name $(KIND_CLUSTER)

# ---------------------------------------------------------------------------
# Production (OpenTofu + GKE)
# ---------------------------------------------------------------------------

prod-plan: ## Preview infrastructure changes
	$(TOFU) plan

prod-apply: ## Apply infrastructure changes
	$(TOFU) apply

prod-down: ## Destroy GKE cluster only (keeps IP, VPC, IAM, secrets)
	$(TOFU) destroy \
		-target=google_container_node_pool.primary \
		-target=google_container_cluster.primary

prod-destroy: ## Tear down all cloud infrastructure
	@echo "This will destroy ALL cloud infrastructure (VPC, IP, IAM, secrets, cluster)."
	@printf "Type 'destroy' to confirm: " && read ans && [ "$$ans" = "destroy" ] || (echo "Aborted."; exit 1)
	$(TOFU) destroy

prod-bootstrap: ## Bootstrap ArgoCD on prod GKE cluster
	python3 tools/setup.py --env prod

prod-status: ## Show ArgoCD Application sync status (prod context)
	kubectl get applications -n argocd

prod-scale-down: ## Scale GKE node pool to 0
	gcloud container clusters resize $$($(TOFU) output -raw cluster_name) \
		--node-pool $$($(TOFU) output -raw cluster_name)-pool \
		--num-nodes 0 \
		--zone $$($(TOFU) output -raw cluster_zone) \
		--project $$($(TOFU) output -raw project_id) \
		--quiet

prod-scale-up: ## Scale GKE node pool to 1
	gcloud container clusters resize $$($(TOFU) output -raw cluster_name) \
		--node-pool $$($(TOFU) output -raw cluster_name)-pool \
		--num-nodes 1 \
		--zone $$($(TOFU) output -raw cluster_zone) \
		--project $$($(TOFU) output -raw project_id) \
		--quiet

# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------

argocd-password: ## Print ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

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
	@for overlay in infrastructure/dev infrastructure/prod apps/dev apps/prod bootstrap/dev bootstrap/prod argocd-apps/dev argocd-apps/prod; do \
		echo "Validating $$overlay..."; \
		kubectl kustomize $$overlay | kubeconform -strict -summary -output text; \
	done

build-all: ## Render all overlays to stdout (useful for diffing)
	@for overlay in infrastructure/dev infrastructure/prod apps/dev apps/prod bootstrap/dev bootstrap/prod argocd-apps/dev argocd-apps/prod; do \
		echo "---"; \
		echo "# $$overlay"; \
		kubectl kustomize $$overlay; \
	done
