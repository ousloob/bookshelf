SHELL := /bin/sh
include .env

# ==============================================================================	
# Define dependencies

KIND 				:= kindest/node:v1.32.0
GRAFANA				:= grafana/grafana:12.0.0
LOKI				:= grafana/loki:3.5.0
PROMTAIL			:= grafana/promtail:3.5.0
PROMETHEUS			:= prom/prometheus:v3.3.1
POSTGRES 			:= postgres:17.4

KIND_CLUSTER 		:= bookshelf-cluster
NAMESPACE       	:= bookshelf-system
INVENTORY_APP			:= inventory
BASE_IMAGE_NAME		:= localhost/loobyte
INVENTORY_VERSION		:= v0.3.0
INVENTORY_IMAGE 		:= $(BASE_IMAGE_NAME)/$(INVENTORY_APP):$(INVENTORY_VERSION)
GOOSE_APP			:= goose
GOOSE_VERSION		:= v0.1.0
GOOSE_IMAGE			:= $(BASE_IMAGE_NAME)/$(GOOSE_APP):$(GOOSE_VERSION)

# ==============================================================================
# Install dependencies

.PHONY: dev-gotooling

dev-gotooling:
	go install github.com/divan/expvarmon@latest
	go install github.com/rakyll/hey@latest
	go install honnef.co/go/tools/cmd/staticcheck@latest
	go install golang.org/x/vuln/cmd/govulncheck@latest
	go install golang.org/x/tools/cmd/goimports@latest

# ==============================================================================	
# Module support

.PHONY: tidy

tidy:
	go get -u all
	go mod tidy
	go mod vendor

# ==============================================================================
# Code quality check

.PHONY: test lint vulncheck check

# Run all checks
check: test lint vulncheck

test:
	go test -count=1 ./...

lint:
	CGO_ENABLED=0 go vet ./...
	staticcheck -checks=all ./...

vulncheck:
	govulncheck ./...

# ==============================================================================
# Running locally

.PHONY: run run-help curl-live curl-ready

run:
	go run api/services/inventory/main.go

help:
	go run api/services/inventory/main.go --help

curl-live:
	curl -il -X GET http://localhost:8080/liveness

curl-ready:
	curl -il -X GET http://localhost:8080/readiness

# ==============================================================================
# Building containers

.PHONY: build build-goose dev-docker

build:
	docker build \
		-f zarf/docker/Dockerfile.inventory \
		-t $(INVENTORY_IMAGE) \
		--build-arg BUILD_REF=$(INVENTORY_VERSION) \
		--build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
		.

build-goose:
	docker build \
		-f zarf/docker/Dockerfile.goose \
		-t $(GOOSE_IMAGE) \
		.

dev-docker:
	docker pull $(KIND) & \
	docker pull $(GRAFANA) & \
	docker pull $(LOKI) & \
	docker pull $(PROMTAIL) & \
	docker pull $(PROMETHEUS) & \
	docker pull $(POSTGRES) & \
	wait;

# ==============================================================================
# Running from with k8s/kind

.PHONY: update-images dev-up dev-down dev-status dev-status-all

update-images:
	@( cd zarf/k8s/dev/grafana && kustomize edit set image grafana=$(GRAFANA) )
	@( cd zarf/k8s/dev/loki && kustomize edit set image loki=$(LOKI) )
	@( cd zarf/k8s/dev/promtail && kustomize edit set image promtail=$(PROMTAIL) )
	@( cd zarf/k8s/dev/prometheus && kustomize edit set image prometheus=$(PROMETHEUS) )
	@( cd zarf/k8s/dev/database && kustomize edit set image postgres=$(POSTGRES) )
	@( cd zarf/k8s/dev/migrations && kustomize edit set image goose-image=$(GOOSE_IMAGE) )
	@( cd zarf/k8s/dev/inventory && kustomize edit set image inventory-image=$(INVENTORY_IMAGE) )

dev-up: update-images
	kind create cluster \
		--image $(KIND) \
		--name $(KIND_CLUSTER) \
		--config zarf/k8s/dev/kind-config.yaml

	kubectl wait --timeout=120s --namespace=local-path-storage \
	--for=condition=Available deployment/local-path-provisioner

	kubectl apply -f zarf/k8s/base/inventory/namespace.yaml

	kind load docker-image $(GRAFANA) --name $(KIND_CLUSTER) & \
	kind load docker-image $(LOKI) --name $(KIND_CLUSTER) & \
	kind load docker-image $(PROMTAIL) --name $(KIND_CLUSTER) & \
	kind load docker-image $(PROMETHEUS) --name $(KIND_CLUSTER) & \
	kind load docker-image $(POSTGRES) --name $(KIND_CLUSTER) & \
	wait;

dev-down:
	kind delete cluster --name $(KIND_CLUSTER)

dev-status:
	watch -n 2 kubectl get pods -o wide --all-namespaces

dev-status-all:
	kubectl get nodes -o wide
	kubectl get svc -o wide
	kubectl get pods -o wide --watch --all-namespaces

# ------------------------------------------------------------------------------

.PHONY: dev-load dev-apply dev-restart dev-restart-db dev-secrets

dev-load:
	kind load docker-image $(INVENTORY_IMAGE) --name $(KIND_CLUSTER)
	kind load docker-image $(GOOSE_IMAGE) --name $(KIND_CLUSTER)

dev-apply:
	kustomize build zarf/k8s/dev/grafana | kubectl apply -f -
	kustomize build zarf/k8s/dev/loki | kubectl apply -f -
	kustomize build zarf/k8s/dev/promtail | kubectl apply -f -
	kustomize build zarf/k8s/dev/prometheus | kubectl apply -f -

	kustomize build zarf/k8s/dev/database | kubectl apply -f -
	kubectl rollout status --namespace=$(NAMESPACE) --watch --timeout=120s sts/database

	kubectl delete job --ignore-not-found=true -n $(NAMESPACE) $(GOOSE_APP)
	kustomize build zarf/k8s/dev/migrations | kubectl apply -f -
	kubectl wait --namespace=$(NAMESPACE) --for=condition=complete --timeout=120s job/$(GOOSE_APP)

	kustomize build zarf/k8s/dev/inventory | kubectl apply -f -
	kubectl wait pods --namespace=$(NAMESPACE) --selector app=$(INVENTORY_APP) --timeout=120s --for=condition=Ready

dev-restart:
	kubectl rollout restart deployment $(INVENTORY_APP) --namespace=$(NAMESPACE)

dev-restart-db:
	kubectl rollout restart statefulset database --namespace=$(NAMESPACE)

dev-secrets:
	@kubectl create secret generic postgres-creds \
		-n $(NAMESPACE) \
		--from-literal=POSTGRES_HOST=$(POSTGRES_HOST) \
		--from-literal=POSTGRES_DB=$(POSTGRES_DB) \
		--from-literal=POSTGRES_USER=$(POSTGRES_USER) \
		--from-literal=POSTGRES_PASSWORD=$(POSTGRES_PASSWORD) \
		--from-literal=POSTGRES_SSLMODE=$(POSTGRES_SSLMODE)
	
	@kubectl create secret generic jwt-keys \
		-n $(NAMESPACE) \
		--from-file=$(KEYS_DIR)

# ------------------------------------------------------------------------------

.PHONY: dev-run dev-update dev-update-apply

dev-run: build build-goose dev-up dev-secrets dev-load dev-apply

dev-update: build build-goose dev-load dev-restart

dev-update-apply: build build-goose dev-load dev-apply

# ------------------------------------------------------------------------------

.PHONY: dev-logs dev-logs-db dev-logs-goose dev-logs-grafana dev-logs-loki dev-logs-promtail

dev-logs:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(INVENTORY_APP) --all-containers=true -f --tail=100

dev-logs-db:
	kubectl logs --namespace=$(NAMESPACE) -l app=database --all-containers=true -f --tail=100

dev-logs-goose:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(GOOSE_APP) --all-containers=true -f --tail=100

dev-logs-grafana:
	kubectl logs --namespace=$(NAMESPACE) -l app=grafana --all-containers=true -f --tail=100

dev-logs-loki:
	kubectl logs --namespace=$(NAMESPACE) -l app=loki --all-containers=true -f --tail=100

dev-logs-promtail:
	kubectl logs --namespace=$(NAMESPACE) -l app=promtail --all-containers=true -f --tail=100

# ------------------------------------------------------------------------------

.PHONY: dev-describe-node dev-describe-deployment dev-describe-inventory dev-describe-db dev-describe-goose dev-describe-grafana

dev-describe-node:
	kubectl describe node

dev-describe-deployment:
	kubectl describe deployment --namespace=$(NAMESPACE) $(INVENTORY_APP)

dev-describe-inventory:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=$(INVENTORY_APP)

dev-describe-db:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=database

dev-describe-goose:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=$(GOOSE_APP)

dev-describe-grafana:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=grafana

# ==============================================================================
# Metrics and Tracing

.PHONY: metrics

metrics:
	expvarmon -ports="localhost:8081" -vars="build,requests,goroutines,errors,panics,mem:memstats.HeapAlloc,mem:memstats.HeapSys,mem:memstats.Sys"

# ==============================================================================
