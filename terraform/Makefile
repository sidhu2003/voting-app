# Convenience wrapper so you type the same three commands every time.
#
# Usage:
#   make plan DIR=live/dev/00-network
#   make apply DIR=live/dev/00-network
#
# Automating your own repetitive commands is literally the job description.
# When this Makefile stops being enough, that is your signal to write the Python
# wrapper the JD asks for.

DIR ?= live/dev/00-network

.PHONY: help fmt init validate lint plan apply destroy check clean

help:
	@echo "Targets: fmt init validate lint plan apply destroy check"
	@echo "Set DIR=<layer path>   (current: $(DIR))"

fmt:
	terraform fmt -recursive .

init:
	terraform -chdir=$(DIR) init

validate:
	terraform -chdir=$(DIR) validate

lint:
	@command -v tflint >/dev/null 2>&1 || { echo "tflint not installed: brew install tflint"; exit 1; }
	tflint --chdir=$(DIR) --config=$(CURDIR)/.tflint.hcl

# Always write the plan to a file, then apply THAT file.
# Applying a saved plan guarantees you apply exactly what you reviewed. Running a
# bare `terraform apply` re-plans, and the world may have changed since you looked.
# This is the habit that separates a careful engineer from a lucky one.
plan:
	terraform -chdir=$(DIR) plan -out=tfplan

apply:
	terraform -chdir=$(DIR) apply tfplan

destroy:
	terraform -chdir=$(DIR) destroy

# Run before every commit.
check: fmt validate lint

clean:
	find . -name tfplan -delete
