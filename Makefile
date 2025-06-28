# 食品安全治理系统 Makefile
# 提供完整的开发、测试和部署命令管理

# 默认目标
.DEFAULT_GOAL := help

# 颜色定义
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m

# 配置变量
ANVIL_PORT := 8545
ANVIL_PID_FILE := /tmp/anvil.pid
RPC_URL := http://localhost:$(ANVIL_PORT)
CHAIN_ID := 31337
PRIVATE_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER_ADDRESS := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# 不再需要复杂的打印宏，直接使用简单的 echo 命令

# ==================== 帮助信息 ====================

.PHONY: help
help: ## 显示帮助信息
	@echo "$(BLUE)食品安全治理系统 - 可用命令:$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)快速开始:$(NC)"
	@echo "  make setup         # 初始化项目"
	@echo "  make test          # 运行所有测试"
	@echo "  make deploy        # 启动网络并部署"
	@echo "  make full-demo     # 完整演示流程"

# ==================== 依赖检查 ====================

.PHONY: check-deps
check-deps: ## 检查依赖
	@echo "$(BLUE)[INFO]$(NC) 检查依赖..."
	@command -v forge >/dev/null 2>&1 || (echo "$(RED)[ERROR]$(NC) Foundry未安装，请先安装Foundry" && exit 1)
	@command -v anvil >/dev/null 2>&1 || (echo "$(RED)[ERROR]$(NC) Anvil未安装，请确保Foundry完整安装" && exit 1)
	@command -v cast >/dev/null 2>&1 || (echo "$(RED)[ERROR]$(NC) Cast未安装，请确保Foundry完整安装" && exit 1)
	@echo "$(GREEN)[SUCCESS]$(NC) 依赖检查通过"

# ==================== Anvil 网络管理 ====================

.PHONY: check-anvil
check-anvil: ## 检查Anvil状态
	@if curl -s -X POST -H "Content-Type: application/json" \
		--data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
		$(RPC_URL) >/dev/null 2>&1; then \
		echo "$(GREEN)[SUCCESS]$(NC) Anvil正在运行"; \
	else \
		echo "$(YELLOW)[WARNING]$(NC) Anvil未运行"; \
	fi

.PHONY: start-anvil
start-anvil: ## 启动Anvil本地网络（前台运行，显示日志）
	@echo "$(BLUE)[INFO]$(NC) 启动Anvil本地网络..."
	@echo "$(YELLOW)网络配置:$(NC)"
	@echo "  端口: $(ANVIL_PORT)"
	@echo "  Chain ID: $(CHAIN_ID)"
	@echo "  部署者地址: $(DEPLOYER_ADDRESS)"
	@echo "  部署者私钥: $(PRIVATE_KEY)"
	@echo ""
	anvil \
		--host 0.0.0.0 \
		--port $(ANVIL_PORT) \
		--accounts 10 \
		--balance 10000 \
		--gas-limit 30000000 \
		--gas-price 1000000000 \
		--block-time 1 \
		--chain-id $(CHAIN_ID)

.PHONY: anvil-bg
anvil-bg: ## 启动Anvil本地网络（后台运行）
	@echo "$(BLUE)[INFO]$(NC) 在后台启动Anvil本地网络..."
	@echo "$(YELLOW)网络配置:$(NC)"
	@echo "  端口: $(ANVIL_PORT)"
	@echo "  Chain ID: $(CHAIN_ID)"
	@echo "  部署者地址: $(DEPLOYER_ADDRESS)"
	@echo ""
	@anvil \
		--host 0.0.0.0 \
		--port $(ANVIL_PORT) \
		--accounts 10 \
		--balance 10000 \
		--gas-limit 30000000 \
		--gas-price 1000000000 \
		--block-time 1 \
		--chain-id $(CHAIN_ID) > /dev/null 2>&1 & \
	echo $$! > $(ANVIL_PID_FILE)
	@echo "$(GREEN)[SUCCESS]$(NC) Anvil已在后台启动，PID文件: $(ANVIL_PID_FILE)"

.PHONY: stop-anvil
stop-anvil: ## 停止Anvil网络
	@echo "$(BLUE)[INFO]$(NC) 停止Anvil网络..."
	@pkill -f "anvil.*--port $(ANVIL_PORT)" || echo "$(YELLOW)[WARNING]$(NC) 没有找到运行的Anvil进程"
	@rm -f $(ANVIL_PID_FILE)
	@echo "$(GREEN)[SUCCESS]$(NC) Anvil停止命令已执行"

# ==================== 项目设置 ====================

.PHONY: setup
setup: check-deps ## 初始化项目环境
	@echo "$(BLUE)[INFO]$(NC) 初始化项目环境..."
	forge install --no-commit
	mkdir -p deployments coverage
	@echo "$(GREEN)[SUCCESS]$(NC) 项目环境初始化完成"

.PHONY: clean
clean: ## 清理构建文件
	@echo "$(BLUE)[INFO]$(NC) 清理构建文件..."
	forge clean
	rm -rf coverage/ lcov.info broadcast/ deployments/
	@echo "$(GREEN)[SUCCESS]$(NC) 清理完成"

.PHONY: build
build: ## 编译合约
	@echo "$(BLUE)[INFO]$(NC) 编译智能合约..."
	forge build

# ==================== 测试命令 ====================

.PHONY: test-unit
test-unit: build ## 运行单元测试
	@echo "$(BLUE)[INFO]$(NC) 运行单元测试..."
	forge test --match-contract FundManagerTest -v
	# 可以在这里添加更多单元测试

.PHONY: test-integration
test-integration: build ## 运行集成测试
	@echo "$(BLUE)[INFO]$(NC) 运行集成测试..."
	forge test --match-contract SystemIntegrationTest -v

.PHONY: test
test: test-unit test-integration ## 运行所有测试
	@echo "$(GREEN)[SUCCESS]$(NC) 所有测试通过！"
	@echo ""
	@echo "$(BLUE)测试总结:$(NC)"
	@echo "  ✅ 智能合约编译成功"
	@echo "  ✅ 单元测试通过"
	@echo "  ✅ 集成测试通过"

.PHONY: test-coverage
test-coverage: build ## 生成测试覆盖率报告
	@echo "$(BLUE)[INFO]$(NC) 生成测试覆盖率报告..."
	forge coverage --report lcov
	@if command -v genhtml >/dev/null 2>&1; then \
		mkdir -p coverage; \
		genhtml lcov.info -o coverage/ 2>/dev/null; \
		echo "$(GREEN)[SUCCESS]$(NC) HTML覆盖率报告生成在 coverage/ 目录"; \
	else \
		echo "$(YELLOW)[WARNING]$(NC) 未安装lcov工具，跳过HTML报告生成"; \
	fi

.PHONY: test-gas
test-gas: build ## 生成Gas使用报告
	@echo "$(BLUE)[INFO]$(NC) 生成Gas使用报告..."
	forge test --gas-report

.PHONY: test-fork
test-fork: ## 使用Fork模式测试
	@echo "$(BLUE)[INFO]$(NC) 运行Fork模式测试..."
	@if curl -s $(RPC_URL) >/dev/null 2>&1; then \
		forge test --fork-url $(RPC_URL) --match-contract SystemIntegrationTest -vv; \
	else \
		echo "$(RED)[ERROR]$(NC) Anvil未运行，请先执行 make start-anvil"; \
		exit 1; \
	fi

# ==================== 部署命令 ====================

.PHONY: deploy-contracts
deploy-contracts: build ## 部署合约
	@echo "$(BLUE)[INFO]$(NC) 部署智能合约到本地网络..."
	@echo "$(YELLOW)部署配置:$(NC)"
	@echo "  RPC URL: $(RPC_URL)"
	@echo "  私钥: $(PRIVATE_KEY)"
	@echo "  部署者: $(DEPLOYER_ADDRESS)"
	@echo ""
	@mkdir -p deployments
	forge script script/DeployFoodSafetyGovernance.s.sol \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--legacy

.PHONY: deploy
deploy: anvil-bg deploy-contracts test-fork ## 完整部署流程
	@echo ""
	@echo "==================================="
	@echo "$(GREEN)[SUCCESS]$(NC) 部署完成！"
	@echo ""
	@echo "$(BLUE)网络信息:$(NC)"
	@echo "  RPC URL: $(RPC_URL)"
	@echo "  Chain ID: $(CHAIN_ID)"
	@echo "  部署者: $(DEPLOYER_ADDRESS)"
	@echo ""
	@echo "$(BLUE)合约地址:$(NC)"
	@echo "  查看广播文件获取具体地址: broadcast/"
	@echo ""
	@echo "$(BLUE)后续步骤:$(NC)"
	@echo "  1. 运行测试验证功能: make test"
	@echo "  2. 查看覆盖率报告: make test-coverage"
	@echo "  3. 停止本地网络: make stop-anvil"
	@echo "==================================="

.PHONY: deploy-quick
deploy-quick: anvil-bg deploy-contracts ## 快速部署（跳过测试）
	@echo "$(GREEN)[SUCCESS]$(NC) 快速部署完成"

# ==================== 开发工具 ====================

.PHONY: format
format: ## 格式化代码
	@echo "$(BLUE)[INFO]$(NC) 格式化Solidity代码..."
	forge fmt

.PHONY: lint
lint: ## 代码静态检查
	@echo "$(BLUE)[INFO]$(NC) 执行代码静态检查..."
	forge build 2>&1 | grep -i warning || echo "$(GREEN)[SUCCESS]$(NC) 无警告"

.PHONY: size
size: build ## 检查合约大小
	@echo "$(BLUE)[INFO]$(NC) 检查合约大小..."
	forge build --sizes

.PHONY: snapshot
snapshot: ## 生成Gas快照
	@echo "$(BLUE)[INFO]$(NC) 生成Gas快照..."
	forge snapshot

# ==================== 调试命令 ====================

.PHONY: debug-fund
debug-fund: build ## 调试FundManager测试
	@echo "$(BLUE)[INFO]$(NC) 调试FundManager测试..."
	forge test --match-contract FundManagerTest -vvvv

.PHONY: debug-integration
debug-integration: build ## 调试集成测试
	@echo "$(BLUE)[INFO]$(NC) 调试集成测试..."
	forge test --match-contract SystemIntegrationTest -vvvv

# ==================== 一键操作 ====================

.PHONY: full-test
full-test: clean build test test-coverage ## 完整测试流程
	@echo "$(GREEN)[SUCCESS]$(NC) 完整测试流程完成"

.PHONY: full-demo
full-demo: clean setup build deploy test-coverage ## 完整演示流程
	@echo "$(GREEN)[SUCCESS]$(NC) 完整演示流程完成！"
	@echo ""
	@echo "$(GREEN)🎉 恭喜！食品安全治理系统演示完成$(NC)"
	@echo "$(BLUE)你已经成功：$(NC)"
	@echo "  ✅ 编译了所有智能合约"
	@echo "  ✅ 部署到本地网络"
	@echo "  ✅ 通过了所有测试"
	@echo "  ✅ 生成了覆盖率报告"

.PHONY: dev-reset
dev-reset: stop-anvil clean setup build test ## 开发环境重置
	@echo "$(GREEN)[SUCCESS]$(NC) 开发环境重置完成"

# ==================== 验证命令 ====================

.PHONY: health-check
health-check: ## 系统健康检查
	@echo "$(BLUE)[INFO]$(NC) 执行系统健康检查..."
	@echo "检查Foundry安装..."
	@forge --version || (echo "$(RED)[ERROR]$(NC) Foundry未安装" && exit 1)
	@echo "检查依赖..."
	@test -d lib/openzeppelin-contracts || (echo "$(RED)[ERROR]$(NC) 依赖缺失，请运行 make setup" && exit 1)
	@echo "检查合约编译..."
	@make build > /dev/null
	@echo "$(GREEN)[SUCCESS]$(NC) 系统健康检查通过"

.PHONY: verify-system
verify-system: health-check test ## 验证系统功能
	@echo "$(BLUE)[INFO]$(NC) 验证系统功能..."
	@echo "1. ✅ 检查编译状态"
	@echo "2. ✅ 运行基础测试"
	@echo "3. ✅ 运行集成测试"
	@echo "$(GREEN)[SUCCESS]$(NC) 系统验证完成"

# ==================== 性能测试 ====================

.PHONY: benchmark
benchmark: test-gas snapshot ## 性能基准测试
	@echo "$(BLUE)[INFO]$(NC) 执行性能基准测试..."
	@echo "$(GREEN)[SUCCESS]$(NC) 基准测试完成"

.PHONY: stress-test
stress-test: build ## 压力测试
	@echo "$(BLUE)[INFO]$(NC) 执行压力测试..."
	forge test --match-test test_SystemEdgeCases -v
	forge test --match-test test_MultipleOperations -v
	@echo "$(GREEN)[SUCCESS]$(NC) 压力测试完成"

# ==================== 环境管理 ====================

.PHONY: show-env
show-env: ## 显示环境信息
	@echo "$(BLUE)环境信息:$(NC)"
	@echo "  ANVIL_PORT: $(ANVIL_PORT)"
	@echo "  RPC_URL: $(RPC_URL)"
	@echo "  CHAIN_ID: $(CHAIN_ID)"
	@echo "  DEPLOYER_ADDRESS: $(DEPLOYER_ADDRESS)"
	@echo "  PRIVATE_KEY: $(PRIVATE_KEY)"

.PHONY: show-addresses
show-addresses: ## 显示部署地址
	@echo "$(BLUE)[INFO]$(NC) 查找部署地址..."
	@if [ -d "broadcast" ]; then \
		find broadcast -name "*.json" | head -5; \
	else \
		echo "$(YELLOW)[WARNING]$(NC) 未找到部署记录"; \
	fi

# ==================== 清理命令 ====================

.PHONY: clean-all
clean-all: stop-anvil clean ## 完全清理
	@echo "$(BLUE)[INFO]$(NC) 执行完全清理..."
	@echo "$(GREEN)[SUCCESS]$(NC) 完全清理完成"

# ==================== 别名 ====================

.PHONY: t
t: test ## test的简写

.PHONY: d
d: deploy ## deploy的简写

.PHONY: b
b: build ## build的简写

.PHONY: c
c: clean ## clean的简写

.PHONY: s
s: start-anvil ## start-anvil的简写

.PHONY: sb
sb: anvil-bg ## anvil-bg的简写 (start background)

.PHONY: q
q: stop-anvil ## stop-anvil的简写 (quit)

# ==================== 文档 ====================

.PHONY: docs
docs: ## 查看部署文档
	@echo "$(BLUE)查看部署和测试教学文档:$(NC)"
	@echo "文档位置: DEPLOYMENT_AND_TESTING_GUIDE.md"
	@echo ""
	@echo "$(YELLOW)主要章节:$(NC)"
	@echo "  - 系统概述"
	@echo "  - 环境准备" 
	@echo "  - 快速开始"
	@echo "  - 详细部署步骤"
	@echo "  - 测试流程"
	@echo "  - 功能验证"
	@echo "  - 故障排除" 