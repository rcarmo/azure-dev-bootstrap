# Set environment variables
export COMPUTE_GROUP?=dev-compute
export STORAGE_GROUP?=dev-storage
export LOCATION?=westeurope
export COMPUTE_SKU=Standard_B8ms
export COMPUTE_INSTANCE?=devbox
export COMPUTE_DISK_SIZE?=128
export COMPUTE_PRIORITY?=Regular # or Spot
export COMPUTE_ARCHITECTURE?=x86_64 # or aarch64
# want fast disks for this one
export COMPUTE_STORAGE?=Premium_LRS
export COMPUTE_FQDN=$(COMPUTE_GROUP)-$(COMPUTE_INSTANCE).$(LOCATION).cloudapp.azure.com
export COMPUTE_ADMIN_USERNAME?=me
export TIMESTAMP=`date "+%Y-%m-%d-%H-%M-%S"`
export FILE_SHARES=data
export STORAGE_ACCOUNT_NAME?=shared0$(shell echo $(COMPUTE_FQDN)|md5sum|base64|tr '[:upper:]' '[:lower:]'|cut -c -16)
export SHARE_NAME?=data
export COMPUTE_SSH_PORT?=22
# This will set both your management and ingress NSGs to your public IP address 
# - since using "*" in an NSG may be disabled by policy
export APPLY_ORIGIN_NSG?=true
export SHELL=/bin/bash

# Permanent local overrides
-include .env

SSH_KEY_FILES:=$(COMPUTE_ADMIN_USERNAME).pem $(COMPUTE_ADMIN_USERNAME).pub
SSH_KEY:=$(COMPUTE_ADMIN_USERNAME).pem

# Do not output warnings, do not validate or add remote host keys (useful when doing successive deployments or going through the load balancer)
SSH_TO_INSTANCE:=ssh -p $(COMPUTE_SSH_PORT) -q -A -i keys/$(SSH_KEY) $(COMPUTE_ADMIN_USERNAME)@$(COMPUTE_FQDN) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

.PHONY: deploy-storage deploy-compute redeploy destroy-compute destroy-storage destroy-environment
.DEFAULT_GOAL := help

list-resources: ## View all resource groups in current subscription
	az group list --output table

list-images: ## List all Ubuntu images
	az vm image list --all --publisher Canonical --output table

list-locations: ## List all Azure locations
	az account list-locations --output table

list-sizes: ## List all VM sizes in the current location
	az vm list-sizes --location=$(LOCATION) --output table

keys: ## Generate an SSH key for initial access
	mkdir keys
	ssh-keygen -b 2048 -t rsa -f keys/$(COMPUTE_ADMIN_USERNAME) -q -N ""
	mv keys/$(COMPUTE_ADMIN_USERNAME) keys/$(COMPUTE_ADMIN_USERNAME).pem
	chmod 0600 keys/*

params: ## Generate the Azure Resource Template parameter files
	$(eval STORAGE_ACCOUNT_KEY := $(shell az storage account keys list \
		--resource-group $(STORAGE_GROUP) \
	    	--account-name $(STORAGE_ACCOUNT_NAME) \
		--query "[0].value" \
		--output tsv | tr -d '"'))
	@mkdir parameters 2> /dev/null; STORAGE_ACCOUNT_KEY=$(STORAGE_ACCOUNT_KEY) python3 genparams.py > parameters/compute.json

clean: ## Remove the parameters directory
	rm -rf parameters

deploy-storage: ## Deploy the storage account and create file shares
	-az group create --name $(STORAGE_GROUP) --location $(LOCATION) --output table 
	-az storage account create \
		--name $(STORAGE_ACCOUNT_NAME) \
		--resource-group $(STORAGE_GROUP) \
		--location $(LOCATION) \
		--https-only \
		--allow-blob-public-access false \
		--output table
	$(foreach SHARE_NAME, $(FILE_SHARES), \
		az storage share create --account-name $(STORAGE_ACCOUNT_NAME) --name $(SHARE_NAME) --output tsv;)

deploy-compute: ## Deploy the compute instance
	-az group create --name $(COMPUTE_GROUP) --location $(LOCATION) --output table 
	az group deployment create \
		--template-file templates/compute.json \
		--parameters @parameters/compute.json \
		--resource-group $(COMPUTE_GROUP) \
		--name cli-$(LOCATION) \
		--output table \
		--no-wait

redeploy: ## Destroy and redeploy the compute instance (storage is left intact)
	-make destroy-compute
	make params
	while [[ $$(az group list | grep Deleting) =~ "Deleting" ]]; do sleep 15; done
	make deploy-compute

destroy-environment: ## Destroy both compute and storage resource groups
	make destroy-compute
	make destroy-storage

destroy-compute: ## Destroy the compute resource group and instance
	az group delete \
		--name $(COMPUTE_GROUP) \
		--no-wait

destroy-storage: ## Destroy the storage resource group and storage account
	az group delete \
		--name $(STORAGE_GROUP) \
		--no-wait

ssh: ## SSH to the instance using the public IP address and our SSH key
	-cat keys/$(COMPUTE_ADMIN_USERNAME).pem | ssh-add -k -
	$(SSH_TO_INSTANCE) \
	-L 3390:localhost:3389

tail-cloud-init: ## Tail cloud-init logs as it runs
	-cat keys/$(COMPUTE_ADMIN_USERNAME).pem | ssh-add -k -
	$(SSH_TO_MASTER) \
	sudo tail -f /var/log/cloud-init*

view-deployment: ## View deployment details (as table)
	az deployment operation group list \
		--resource-group $(COMPUTE_GROUP) \
		--name cli-$(LOCATION) \
		--query "[].{OperationID:operationId,Name:properties.targetResource.resourceName,Type:properties.targetResource.resourceType,State:properties.provisioningState,Status:properties.statusCode}" \
		--output table

watch-deployment: ## Watch deployment (2s interval)
	watch az resource list \
		--resource-group $(COMPUTE_GROUP) \
		--output table

list-endpoints: ## List DNS endpoints
	az network public-ip list \
		--resource-group $(COMPUTE_GROUP) \
		--query '[].{dnsSettings:dnsSettings.fqdn}' \
		--output table

get-vm-details: ## Show details of the VM (JSON format)
	@az vm list \
	--resource-group $(COMPUTE_GROUP) \
	--show-details \
	--output json

help: ## This help
	@grep -hE '^[A-Za-z0-9_ \-]*?:.*##.*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'