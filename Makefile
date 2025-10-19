# Makefile for Elata Protocol
# Provides convenient commands for development

.PHONY: help install build test test-v clean fmt fmt-check coverage gas-report setup-hooks security-check

help: ## Show this help message
	@echo "Elata Protocol - Development Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies and setup hooks
	@echo "📦 Installing Foundry dependencies..."
	forge install
	@echo "🔧 Setting up Git hooks..."
	bash scripts/setup-hooks.sh
	@echo "✅ Installation complete!"

build: ## Build contracts
	@echo "🔨 Building contracts..."
	forge build

test: ## Run tests
	@echo "🧪 Running tests..."
	forge test

test-v: ## Run tests with verbose output
	@echo "🧪 Running tests (verbose)..."
	forge test -vv

test-vvv: ## Run tests with very verbose output
	@echo "🧪 Running tests (very verbose)..."
	forge test -vvv

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	forge clean
	rm -rf cache out broadcast

fmt: ## Format code
	@echo "📝 Formatting code..."
	forge fmt

fmt-check: ## Check code formatting
	@echo "📝 Checking code formatting..."
	forge fmt --check

coverage: ## Generate test coverage report (may fail due to complex contracts)
	@echo "📊 Generating coverage report..."
	@echo "⚠️  Note: Coverage may fail due to 'stack too deep' in AppDeploymentLib"
	@forge coverage --ir-minimum --report lcov || echo "❌ Coverage failed (known issue with complex contracts)"
	@if [ -f lcov.info ]; then echo "✅ Coverage report generated: lcov.info"; fi

gas-report: ## Generate gas usage report
	@echo "⛽ Generating gas report..."
	forge test --gas-report

snapshot: ## Generate gas snapshot
	@echo "📸 Generating gas snapshot..."
	forge snapshot

setup-hooks: ## Setup Git hooks
	@bash scripts/setup-hooks.sh

security-check: ## Run security checks
	@echo "🔒 Running security checks..."
	@bash scripts/security-check.sh

deploy-local: ## Deploy to local Anvil
	@echo "🚀 Deploying to local Anvil..."
	bash scripts/dev-setup.sh

stop-local: ## Stop local Anvil
	@echo "🛑 Stopping local Anvil..."
	bash scripts/dev-stop.sh

restart-local: ## Restart local Anvil
	@echo "🔄 Restarting local Anvil..."
	bash scripts/dev-restart.sh

ci: fmt-check build test ## Run CI checks locally
	@echo "✅ All CI checks passed!"
	@echo "ℹ️  Note: Some contracts (AppModuleFactory) exceed EIP-170 limit but are acceptable for L2 deployment"

pre-push: fmt-check build test gas-report ## Run all pre-push checks
	@echo "✅ Ready to push!"

all: clean install build test ## Full clean build and test

