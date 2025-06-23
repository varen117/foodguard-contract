# 食品安全治理合约系统 (FoodGuard Contract)

![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-363636?style=flat-square&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-Framework-red?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

一个基于区块链的食品安全治理系统，通过去中心化方式处理食品安全投诉，实现透明、公正的争议解决机制。

## 🎯 项目愿景

解决传统食品安全投诉处理中的痛点：
- **不透明**：传统流程缺乏透明度，用户无法跟踪处理进度
- **监管不力**：缺乏有效的监督机制和第三方验证
- **赔偿困难**：争议解决周期长，赔偿机制不完善
- **信任缺失**：企业和消费者之间缺乏可信的仲裁机制

## 🏗️ 系统架构

### 核心模块

```
FoodSafetyGovernance (主合约)
├── FundManager (资金管理)
├── VotingManager (投票管理) 
├── DisputeManager (质疑管理)
└── RewardPunishmentManager (奖惩管理)
```

### 数据结构库
- **DataStructures.sol**: 统一数据结构定义
- **Errors.sol**: 自定义错误类型
- **Events.sol**: 事件定义

## 🔄 治理流程

系统严格按照以下流程图实现：

```
投诉创建 → 保证金锁定 → 验证者投票 → 质疑期 → 奖惩分配 → 案件完结
```

### 详细流程

1. **投诉阶段**: 用户创建投诉，提交证据和保证金
2. **锁定阶段**: 系统锁定双方保证金，防止恶意行为
3. **投票阶段**: 随机选择验证者进行投票验证
4. **质疑阶段**: 允许对投票结果提出质疑
5. **奖惩阶段**: 根据最终结果分配奖励和惩罚
6. **完结阶段**: 案件结束，资金释放

## 💰 经济模型

### 保证金机制
- **投诉保证金**: 0.1 ETH (防止恶意投诉)
- **企业保证金**: 1.0 ETH (确保企业参与)
- **质疑保证金**: 0.05 ETH (质疑验证者决定)

### 资金分配
- **奖励池**: 70% (激励诚实参与)
- **运营费用**: 10% (系统维护)
- **储备金**: 20% (风险控制)

## 🛠️ 技术特性

### 安全设计
- ✅ **重入防护**: 防止重入攻击
- ✅ **访问控制**: 基于角色的权限管理
- ✅ **暂停机制**: 紧急情况下可暂停合约
- ✅ **Gas优化**: 使用 `via_ir` 编译优化

### 模块化架构
- ✅ **职责分离**: 每个模块负责特定功能
- ✅ **可升级性**: 支持模块独立升级
- ✅ **事件追踪**: 完整的操作日志记录

### 数据完整性
- ✅ **状态机**: 严格的状态流转控制
- ✅ **数据验证**: 全面的输入验证机制
- ✅ **错误处理**: 详细的错误类型定义

## 📋 当前状态

### ✅ 已完成
- [x] 完整的合约架构设计
- [x] 所有核心模块实现
- [x] 数据结构和事件定义
- [x] 编译成功 (解决栈深度问题)
- [x] 基础功能测试 (4/10 测试通过)
- [x] 部署脚本和配置

### 🔄 进行中
- [ ] 修复投诉创建中的算术溢出问题
- [ ] 完善验证者注册和选择机制
- [ ] 质疑系统的详细实现

### 📋 待完成
- [ ] 完整的单元测试覆盖
- [ ] 集成测试和端到端测试
- [ ] Gas 优化和性能调优
- [ ] 安全审计和漏洞修复
- [ ] 前端界面开发

## 🧪 测试结果

```bash
Running 10 tests...
✅ test_AdminFunctions() - 管理员功能测试
✅ test_ReentrancyProtection() - 重入防护测试  
✅ test_UserRegistration() - 用户注册测试
✅ test_UserRegistrationFailures() - 注册失败测试
❌ test_ComplaintCreation() - 投诉创建测试 (算术溢出)
❌ test_CompleteComplaintFlow() - 完整流程测试 (算术溢出)
... (其他测试)

通过率: 40% (4/10)
```

## 🚀 快速开始

### 环境要求
- **Foundry**: 最新版本
- **Solidity**: >= 0.8.20
- **Node.js**: >= 16.0.0

### 安装与编译

```bash
# 克隆项目
git clone [repository-url]
cd foodguard-contract

# 安装依赖
forge install

# 编译合约
make build

# 运行测试
make test

# 部署到本地网络
make deploy-local
```

### 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件
PRIVATE_KEY=your_private_key
SEPOLIA_RPC_URL=your_sepolia_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 📚 合约接口

### 主要函数

```solidity
// 用户注册
function registerUser() external payable
function registerEnterprise() external payable

// 投诉流程
function createComplaint(...) external payable returns (uint256 caseId)
function endVotingAndStartChallenge(uint256 caseId) external
function endChallengeAndProcessRewards(uint256 caseId) external

// 查询函数
function getCaseInfo(uint256 caseId) external view returns (CaseInfo memory)
function getTotalCases() external view returns (uint256)
```

## 🔧 开发工具

### Makefile 命令

```bash
make build          # 编译合约
make test           # 运行测试
make test-v         # 详细测试输出
make clean          # 清理构建文件
make deploy-local   # 部署到本地网络
make deploy-sepolia # 部署到 Sepolia 测试网
```

## 📈 Gas 消耗分析

| 操作 | Gas 消耗 | 优化状态 |
|------|----------|----------|
| 用户注册 | ~175K | ✅ 已优化 |
| 企业注册 | ~98K | ✅ 已优化 |
| 投诉创建 | ~TBD | 🔄 优化中 |
| 投票提交 | ~TBD | 📋 待测试 |

## 🛡️ 安全考虑

### 已实现的安全措施
- **重入防护**: 使用 OpenZeppelin 的 ReentrancyGuard
- **访问控制**: 基于角色的权限管理
- **输入验证**: 全面的参数验证
- **整数溢出**: Solidity 0.8+ 内置保护

### 风险评估
- **治理攻击**: 通过经济激励和声誉机制缓解
- **女巫攻击**: 通过保证金机制防范
- **共谋行为**: 通过随机选择验证者降低风险

## 🤝 贡献指南

我们欢迎社区贡献！请遵循以下步骤：

1. Fork 项目仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交变更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 代码规范
- 遵循 Solidity 样式指南
- 添加详细的中文注释
- 编写相应的单元测试
- 确保 Gas 优化

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 📞 联系方式

- **项目维护者**: Food Safety Governance Team
- **技术支持**: [GitHub Issues](../../issues)
- **文档**: [项目文档](./docs/)

## 🙏 致谢

感谢所有为食品安全治理事业做出贡献的开发者和社区成员。让我们共同构建一个更安全、更透明的食品安全生态系统！

---

*此项目正在积极开发中，欢迎反馈和建议！* 🚀
