# Food Safety Governance System Makefile
# 简化构建、测试、部署等操作

-include .env

.PHONY: all test clean deploy help install build fmt lint

# 默认私钥（仅用于本地测试）
DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 帮助信息
help:
	@echo "Food Safety Governance System - 食品安全治理系统"
	@echo ""
	@echo "Available commands:"
	@echo "  make install     - 安装依赖"
	@echo "  make build       - 编译合约"
	@echo "  make test        - 运行测试"
	@echo "  make test-unit   - 运行单元测试"
	@echo "  make test-flow   - 运行流程测试"
	@echo "  make deploy      - 部署到指定网络"
	@echo "  make deploy-local - 部署到本地网络"
	@echo "  make anvil       - 启动本地节点"
	@echo "  make clean       - 清理构建文件"
	@echo "  make fmt         - 格式化代码"
	@echo "  make lint        - 代码检查"
	@echo "  make coverage    - 生成测试覆盖率报告"
	@echo ""
	@echo "Environment variables:"
	@echo "  PRIVATE_KEY      - 部署者私钥"
	@echo "  RPC_URL          - RPC端点URL"
	@echo "  ETHERSCAN_API_KEY - Etherscan API密钥"

# 安装依赖
install:
	@echo "Installing dependencies..."
	forge install

# 更新依赖
update:
	@echo "Updating dependencies..."
	forge update

# 编译合约
build:
	@echo "Building contracts..."
	forge build

# 清理构建文件
clean:
	@echo "Cleaning build files..."
	forge clean

# 代码格式化
fmt:
	@echo "Formatting code..."
	forge fmt

# 代码检查
lint:
	@echo "Running linter..."
	forge fmt --check

# 运行所有测试
test:
	@echo "Running all tests..."
	forge test -vvv

# 运行单元测试
test-unit:
	@echo "Running unit tests..."
	forge test --match-path "test/unit/*" -vvv

# 运行流程测试
test-flow:
	@echo "Running flow tests..."
	forge test --match-path "test/integration/*" -vvv

# 运行特定测试
test-specific:
	@echo "Running specific test..."
	forge test --match-test $(TEST) -vvv

# 生成测试覆盖率报告
coverage:
	@echo "Generating coverage report..."
	forge coverage --report lcov
	@echo "Coverage report generated in lcov.info"

# 启动本地Anvil节点
anvil:
	@echo "Starting local Anvil node..."
	anvil --host 0.0.0.0 --port 8545 --chain-id 31337

# 网络配置
NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# 根据网络参数设置部署配置
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network goerli,$(ARGS)),--network goerli)
	NETWORK_ARGS := --rpc-url $(GOERLI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network mainnet,$(ARGS)),--network mainnet)
	NETWORK_ARGS := --rpc-url $(MAINNET_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# 部署系统
deploy:
	@echo "Deploying Food Safety Governance System..."
	@forge script script/DeployFoodSafetyGovernance.s.sol:DeployFoodSafetyGovernance $(NETWORK_ARGS)

# 部署到本地网络
deploy-local:
	@echo "Deploying to local network..."
	@forge script script/DeployFoodSafetyGovernance.s.sol:DeployFoodSafetyGovernance --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# 仅部署主合约（测试用）
deploy-governance-only:
	@echo "Deploying Governance contract only..."
	@forge script script/DeployFoodSafetyGovernance.s.sol:DeployFoodSafetyGovernance --sig "deployGovernanceOnly()" $(NETWORK_ARGS)

# 部署并注册验证者
deploy-with-validators:
	@echo "Deploying with initial validators..."
	@forge script script/DeployFoodSafetyGovernance.s.sol:DeployFoodSafetyGovernance --sig "deployWithValidators()" $(NETWORK_ARGS)

# 验证合约（在部署后使用）
verify:
	@echo "Verifying contracts on Etherscan..."
	@echo "Please run this manually with the deployed contract addresses"

# 生成快照
snapshot:
	@echo "Generating gas snapshot..."
	forge snapshot

# 开发者工具
dev-setup:
	@echo "Setting up development environment..."
	@make install
	@make build
	@echo "Development environment ready!"

# 运行完整的CI流程
ci:
	@echo "Running CI pipeline..."
	@make lint
	@make build
	@make test
	@make coverage
	@echo "CI pipeline completed successfully!"

# 快速本地测试
quick-test:
	@echo "Running quick local test..."
	@make build
	@make test-unit
	@echo "Quick test completed!"

# 创建新的测试文件模板
new-test:
	@echo "Creating new test file template..."
	@test -n "$(NAME)" || (echo "Usage: make new-test NAME=TestName" && exit 1)
	@cp test/unit/FoodSafetyGovernanceTest.t.sol test/unit/$(NAME).t.sol
	@sed -i 's/FoodSafetyGovernanceTest/$(NAME)/g' test/unit/$(NAME).t.sol
	@echo "Test file created: test/unit/$(NAME).t.sol"

# 监视文件变化并自动测试（需要安装 entr）
watch-test:
	@echo "Watching for file changes... (Ctrl+C to stop)"
	@find src test -name "*.sol" | entr -c make test-unit

# 估算部署成本
estimate-deploy:
	@echo "Estimating deployment gas costs..."
	@forge script script/DeployFoodSafetyGovernance.s.sol:DeployFoodSafetyGovernance --rpc-url http://localhost:8545

# 安全检查（需要安装 slither）
security-check:
	@echo "Running security analysis..."
	@command -v slither >/dev/null 2>&1 || (echo "Please install slither: pip install slither-analyzer" && exit 1)
	@slither .

# 文档生成
docs:
	@echo "Generating documentation..."
	@forge doc

# 初始化新项目
init:
	@echo "Initializing Food Safety Governance project..."
	@forge init --template https://github.com/foundry-rs/forge-template
	@echo "Project initialized!"

# 环境检查
check-env:
	@echo "Checking environment..."
	@test -n "$(PRIVATE_KEY)" || echo "Warning: PRIVATE_KEY not set"
	@test -n "$(RPC_URL)" || echo "Warning: RPC_URL not set"
	@test -n "$(ETHERSCAN_API_KEY)" || echo "Warning: ETHERSCAN_API_KEY not set"
	@forge --version
	@echo "Environment check completed!"

# 清理所有生成的文件
clean-all:
	@echo "Cleaning all generated files..."
	@make clean
	@rm -rf cache/
	@rm -rf out/
	@rm -rf broadcast/
	@rm -f lcov.info
	@echo "All files cleaned!"

# 显示合约大小
contract-size:
	@echo "Contract sizes:"
	@forge build --sizes

# 优化合约
optimize:
	@echo "Optimizing contracts..."
	@forge build --optimize --optimizer-runs 200

# 获取项目统计信息
stats:
	@echo "Project Statistics:"
	@echo "Contract files: $$(find src -name "*.sol" | wc -l)"
	@echo "Test files: $$(find test -name "*.sol" | wc -l)"
	@echo "Total lines of code: $$(find src -name "*.sol" -exec cat {} \; | wc -l)"
	@echo "Total lines of tests: $$(find test -name "*.sol" -exec cat {} \; | wc -l)"

# 默认目标
all: clean install build test

# 检查依赖是否存在
check-deps:
	@command -v forge >/dev/null 2>&1 || (echo "Please install Foundry: https://getfoundry.sh/" && exit 1)
	@echo "All dependencies are installed!"

# 快速开始指南
quickstart:
	@echo "=== Food Safety Governance System Quick Start ==="
	@echo ""
	@echo "1. Install dependencies:"
	@echo "   make install"
	@echo ""
	@echo "2. Build contracts:"
	@echo "   make build"
	@echo ""
	@echo "3. Run tests:"
	@echo "   make test"
	@echo ""
	@echo "4. Start local node:"
	@echo "   make anvil"
	@echo ""
	@echo "5. Deploy locally (in another terminal):"
	@echo "   make deploy-local"
	@echo ""
	@echo "For more commands, run: make help" 