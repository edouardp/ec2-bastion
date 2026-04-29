# --- Environment configs (loaded from config/*.yaml) ---
LOAD_CONFIG = uv run scripts/load_config.py

$(foreach v,$(shell $(LOAD_CONFIG) config/prod.yaml),$(eval PROD_$(v)))
$(foreach v,$(shell $(LOAD_CONFIG) config/staging.yaml),$(eval STAGING_$(v)))

# Staging VPC/subnets: fall back to CloudFormation outputs when blank
STAGING_VPC_ID     := $(or $(STAGING_VPC_ID),$(shell aws cloudformation describe-stacks --stack-name staging-vpc --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text 2>/dev/null))
STAGING_SUBNET_IDS := $(or $(STAGING_SUBNET_IDS),$(shell aws cloudformation describe-stacks --stack-name staging-vpc --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' --output text 2>/dev/null))

CHOOSER      = uv run scripts/chooser.py --title
ENVS_JSON    = scripts/environments.json
ENVS_BOTH    = scripts/environments-with-both.json

# Helper: choose env then dispatch to <target>-prod / <target>-staging.
# $(1) = prompt, $(2) = target prefix, $(3) = json file
define choose_and_dispatch
	@ENV=$$($(CHOOSER) $(1) $(3) 3>&1 1>&2) || exit 1; \
	case "$$ENV" in \
		both) $(MAKE) $(2)-prod && $(MAKE) $(2)-staging ;; \
		prod) $(MAKE) $(2)-prod ;; \
		staging) $(MAKE) $(2)-staging ;; \
	esac
endef

.PHONY: database-tunnel database-tunnel-prod database-tunnel-staging
.PHONY: ssh ssm
.PHONY: all help deploy deploy-prod deploy-staging
.PHONY: start-ec2 start-ec2-prod start-ec2-staging
.PHONY: stop-ec2 stop-ec2-prod stop-ec2-staging
.PHONY: ensure-ec2 ensure-ec2-prod ensure-ec2-staging
.PHONY: ssm-prod ssm-staging ssh-prod ssh-staging
.PHONY: test-ssm test-ssm-prod test-ssm-staging
.PHONY: test-ssh test-ssh-prod test-ssh-staging test
.PHONY: status status-prod status-staging
.PHONY: teardown teardown-prod teardown-staging
.PHONY: lint clean

all: help

help: ## Show this help message
	@echo ""
	@echo "  \033[1mCommands\033[0m"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -v -E -- '-(staging|prod):' | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  \033[1mEnvironment-specific Commands\033[0m"
	@grep -E '^[a-zA-Z0-9_-]+-(staging|prod):.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'

# --- Deploy ---
define deploy_stack
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo "ERROR: AWS credentials not valid. Run 'aws sso login' and retry." >&2; exit 1; } && \
	BASTION_SG=$$(./scripts/resolve-bastion-source-sg.sh $(4)) && \
	aws cloudformation deploy \
		--template-file cloudformation/ssm-on-demand-instance.yaml \
		--stack-name $(1) \
		--parameter-overrides VpcId=$(2) SubnetIds=$(3) Environment=$(4) NotificationTopicArn=$(5) BastionSourceSecurityGroupId="$$BASTION_SG" \
		--capabilities CAPABILITY_IAM \
		--tags Project=on-demand-ec2 Environment=$(4) Owner=$(6)
endef

deploy: ## Deploy (choose environment)
	$(call choose_and_dispatch,"Deploy which environment?",deploy,$(ENVS_BOTH))

deploy-prod: ## Deploy prod stack
	$(call deploy_stack,$(PROD_STACK_NAME),$(PROD_VPC_ID),$(PROD_SUBNET_IDS),$(PROD_ENVIRONMENT),$(PROD_SNS_TOPIC),$(PROD_OWNER))

deploy-staging: ## Deploy staging stack
	$(call deploy_stack,$(STAGING_STACK_NAME),$(STAGING_VPC_ID),$(STAGING_SUBNET_IDS),$(STAGING_ENVIRONMENT),$(STAGING_SNS_TOPIC),$(STAGING_OWNER))

# --- Start / Stop ---
start-ec2: ## Start instance (choose environment)
	$(call choose_and_dispatch,"Start which environment?",start-ec2,$(ENVS_BOTH))

start-ec2-prod: ## Start prod instance
	@STACK_NAME=$(PROD_STACK_NAME) $(MAKE) _start-ec2

start-ec2-staging: ## Start staging instance
	@STACK_NAME=$(STAGING_STACK_NAME) $(MAKE) _start-ec2

_start-ec2:
	@START_FN=$$(aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query "Stacks[0].Outputs[?OutputKey=='StartFunctionArn'].OutputValue" \
		--output text) && \
	echo "Invoking $$START_FN..." && \
	aws lambda invoke --function-name "$$START_FN" /dev/stdout && echo

stop-ec2: ## Stop instance (choose environment)
	$(call choose_and_dispatch,"Stop which environment?",stop-ec2,$(ENVS_BOTH))

stop-ec2-prod: ## Stop prod instance
	@STACK_NAME=$(PROD_STACK_NAME) $(MAKE) _stop-ec2

stop-ec2-staging: ## Stop staging instance
	@STACK_NAME=$(STAGING_STACK_NAME) $(MAKE) _stop-ec2

_stop-ec2:
	@ASG_NAME=$$(aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
		--output text) && \
	aws autoscaling set-desired-capacity \
		--auto-scaling-group-name "$$ASG_NAME" --desired-capacity 0 && \
	echo "Scaled $$ASG_NAME to 0"

# --- Connect ---
ensure-ec2: ## Start and wait until ready (choose environment)
	$(call choose_and_dispatch,"Ensure which environment?",ensure-ec2,$(ENVS_JSON))

ensure-ec2-prod: ## Start prod and wait until ready
	STACK_NAME=$(PROD_STACK_NAME) ./scripts/ensure-ec2-running.sh

ensure-ec2-staging: ## Start staging and wait until ready
	STACK_NAME=$(STAGING_STACK_NAME) ./scripts/ensure-ec2-running.sh

ssh: ## SSH shell (choose environment)
	@ENV=$$($(CHOOSER) "SSH to which environment?" $(ENVS_JSON) 3>&1 1>&2) || exit 1; \
	if [ "$$ENV" = "prod" ]; then STACK_NAME=$(PROD_STACK_NAME); else STACK_NAME=$(STAGING_STACK_NAME); fi; \
	STACK_NAME=$$STACK_NAME ./scripts/interactive-ssh-session.sh

ssm: ## SSM shell (choose environment)
	@ENV=$$($(CHOOSER) "SSM to which environment?" $(ENVS_JSON) 3>&1 1>&2) || exit 1; \
	if [ "$$ENV" = "prod" ]; then STACK_NAME=$(PROD_STACK_NAME); else STACK_NAME=$(STAGING_STACK_NAME); fi; \
	STACK_NAME=$$STACK_NAME ./scripts/interactive-ssm-session.sh

ssm-prod: ## SSM shell to prod
	STACK_NAME=$(PROD_STACK_NAME) ./scripts/interactive-ssm-session.sh

ssm-staging: ## SSM shell to staging
	STACK_NAME=$(STAGING_STACK_NAME) ./scripts/interactive-ssm-session.sh

ssh-prod: ## SSH shell to prod
	STACK_NAME=$(PROD_STACK_NAME) ./scripts/interactive-ssh-session.sh

ssh-staging: ## SSH shell to staging
	STACK_NAME=$(STAGING_STACK_NAME) ./scripts/interactive-ssh-session.sh

# --- Test ---
test-ssm: ## Run command via SSM (choose environment)
	$(call choose_and_dispatch,"Test SSM on which environment?",test-ssm,$(ENVS_BOTH))

test-ssm-prod: ## Run command via SSM on prod (CMD="...")
	STACK_NAME=$(PROD_STACK_NAME) ./scripts/test-ssm-run-command.sh "$(or $(CMD),uname -a)"

test-ssm-staging: ## Run command via SSM on staging (CMD="...")
	STACK_NAME=$(STAGING_STACK_NAME) ./scripts/test-ssm-run-command.sh "$(or $(CMD),uname -a)"

test-ssh: ## Run command via SSH (choose environment)
	$(call choose_and_dispatch,"Test SSH on which environment?",test-ssh,$(ENVS_BOTH))

test-ssh-prod: ## Run command via SSH on prod (CMD="...")
	STACK_NAME=$(PROD_STACK_NAME) ./scripts/test-ssh-run-command.sh "$(or $(CMD),uname -a)"

test-ssh-staging: ## Run command via SSH on staging (CMD="...")
	STACK_NAME=$(STAGING_STACK_NAME) ./scripts/test-ssh-run-command.sh "$(or $(CMD),uname -a)"

test: test-ssm-prod test-ssh-prod ## Run SSM and SSH tests on prod

# --- Status ---
status: ## Show status (choose environment)
	$(call choose_and_dispatch,"Status for which environment?",status,$(ENVS_BOTH))

status-prod: ## Show prod status
	@echo "===== PROD ====="
	@STACK_NAME=$(PROD_STACK_NAME) ./scripts/status.sh

status-staging: ## Show staging status
	@echo "===== STAGING ====="
	@STACK_NAME=$(STAGING_STACK_NAME) ./scripts/status.sh

# --- Database Tunnel ---
database-tunnel: ## Port-forward to Aurora via bastion (choose environment)
	@ENV=$$($(CHOOSER) "Tunnel to which database?" $(ENVS_JSON) 3>&1 1>&2) || exit 1; \
	$(MAKE) database-tunnel-$$ENV

database-tunnel-prod: ## Port-forward to prod Aurora (localhost:5432)
	STACK_NAME=$(PROD_STACK_NAME) ENVIRONMENT=prod ./scripts/database-tunnel.sh

database-tunnel-staging: ## Port-forward to staging Aurora (localhost:5432)
	STACK_NAME=$(STAGING_STACK_NAME) ENVIRONMENT=staging ./scripts/database-tunnel.sh

# --- Lint / Clean ---
lint: ## Run cfn-lint, shellcheck, checkmake, rumdl
	./scripts/lint.sh

# --- Teardown ---
teardown: ## Teardown stack (choose environment)
	$(call choose_and_dispatch,"Teardown which environment?",teardown,$(ENVS_BOTH))

teardown-prod: ## Delete prod stack
	@STACK_NAME=$(PROD_STACK_NAME) $(MAKE) _teardown

teardown-staging: ## Delete staging stack
	@STACK_NAME=$(STAGING_STACK_NAME) $(MAKE) _teardown

_teardown:
	@aws cloudformation delete-stack --stack-name $(STACK_NAME) && \
	echo "Stack $(STACK_NAME) deletion initiated."

clean: ## Remove generated files
	rm -rf __pycache__ __marimo__ .rumdl_cache

.DEFAULT_GOAL := help
