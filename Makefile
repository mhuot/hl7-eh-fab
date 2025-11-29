# HL7-EH-FAB Makefile
# Simple commands for common operations

.PHONY: help validate infra deploy test clean logs status

RESOURCE_GROUP ?= hl7-demo-rg
LOCATION ?= centralus
IMAGE_TAG ?= v1

help: ## Show this help
	@echo "HL7-EH-FAB Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make infra                    # Deploy infrastructure"
	@echo "  make deploy                   # Deploy HL7 listener to AKS"
	@echo "  make test IP=1.2.3.4          # Send test messages"

validate: ## Check prerequisites
	@./scripts/validate-prereqs.sh

infra: ## Deploy Azure infrastructure (Bicep)
	@if [ ! -f infra/main.parameters.local.json ]; then \
		echo "Error: infra/main.parameters.local.json not found."; \
		echo "Create it by running: cp infra/main.parameters.json infra/main.parameters.local.json"; \
		echo "Then edit it with your SSH key and email."; \
		exit 1; \
	fi
	az deployment sub create \
		--template-file infra/main.bicep \
		--location $(LOCATION) \
		--parameters infra/main.parameters.local.json \
		--name hl7Deployment

deploy: ## Deploy HL7 listener to AKS
	./deploy.sh $(RESOURCE_GROUP) $(IMAGE_TAG)

test: ## Send test HL7 messages (usage: make test IP=<external-ip> [COUNT=100])
ifndef IP
	$(error IP is required. Usage: make test IP=<external-ip> [COUNT=100])
endif
	python3 src/hl7-listener/send_test_hl7.py --host $(IP) --port 2575 --count $(or $(COUNT),10)

logs: ## View HL7 listener logs
	kubectl logs -n hl7 -l app=hl7-listener -f --tail=100

status: ## Check deployment status
	@echo "=== Pods ===" 
	@kubectl get pods -n hl7
	@echo ""
	@echo "=== Service ==="
	@kubectl get service -n hl7
	@echo ""
	@echo "=== Deployment ==="
	@kubectl get deployment -n hl7

clean: ## Delete all resources
	@echo "This will delete resource group $(RESOURCE_GROUP) and all resources!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	az group delete --name $(RESOURCE_GROUP) --yes --no-wait
	@echo "Deletion started. Resources will be removed in the background."

restart: ## Restart HL7 listener pods
	kubectl rollout restart deployment/hl7-listener -n hl7
	kubectl rollout status deployment/hl7-listener -n hl7

scale: ## Scale HL7 listener (usage: make scale REPLICAS=3)
	kubectl scale deployment/hl7-listener -n hl7 --replicas=$(REPLICAS)
