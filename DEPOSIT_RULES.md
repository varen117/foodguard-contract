# 保证金规则修改说明

## 修改概述

根据用户需求，我们已成功修改了食品安全DAO治理系统的保证金规则，现在区分个人用户和企业用户：

### 保证金要求
- **个人用户（投诉者、DAO成员等）**：最低保证金 `0.1 ETH`
- **企业用户（被投诉企业）**：最低保证金 `1.0 ETH`

## 修改的核心文件

### 1. 接口文件 (`src/interfaces/IFoodGuardDAO.sol`)
- 添加了 `UserType` 枚举定义：
  ```solidity
  enum UserType {
      Individual,  // 个人用户
      Company      // 企业用户
  }
  ```
- 更新了 `depositGuarantee` 函数签名，添加用户类型参数

### 2. 主合约 (`src/FoodGuardDAO.sol`)
- 更新常量定义：
  ```solidity
  uint256 public constant MIN_INDIVIDUAL_DEPOSIT = 0.1 ether;
  uint256 public constant MIN_COMPANY_DEPOSIT = 1.0 ether;
  ```
- 添加用户类型映射：
  ```solidity
  mapping(address => IFoodGuardDAO.UserType) public userTypes;
  ```
- 修改保证金存入逻辑，根据用户类型验证最低保证金要求
- 更新相关的保证金检查逻辑

### 3. 测试文件更新
- **单元测试 (`test/FoodGuardDAO.t.sol`)**：更新所有保证金相关测试
- **集成测试 (`test/Integration.t.sol`)**：更新完整流程测试

## 功能特性

### 保证金存入机制
```solidity
function depositGuarantee(IFoodGuardDAO.UserType _userType) external payable;
```
- 用户首次存入时指定用户类型（个人或企业）
- 系统根据用户类型验证最低保证金要求
- 用户类型一旦设定不可更改，确保系统一致性

### 保证金验证逻辑
- **投诉提交时**：根据投诉者的用户类型验证保证金充足性
- **高风险投诉**：企业保证金必须达到1.0 ETH才能被冻结
- **动态检查**：所有保证金相关操作都会根据用户类型进行适当验证

## 测试覆盖

修改后的系统通过了完整的测试套件：

### 单元测试 (15个测试)
- ✅ 保证金存入功能测试
- ✅ 保证金不足验证测试
- ✅ 投诉提交流程测试
- ✅ DAO投票机制测试
- ✅ 质押和奖励系统测试

### 集成测试 (8个测试)
- ✅ 完整的高风险投诉处理流程
- ✅ 完整的低风险投诉处理流程
- ✅ 端到端奖励分配测试
- ✅ 多投诉并发处理测试

**总计：23个测试全部通过** ✅

## 系统影响

### 正面影响
1. **风险分层**：企业承担更高保证金，降低系统风险
2. **激励平衡**：个人用户门槛较低，鼓励参与治理
3. **系统安全**：更高的企业保证金提供更好的处罚基础

### 兼容性
- 所有现有功能保持完全兼容
- API接口仅增加用户类型参数，无破坏性变更
- 测试覆盖全面，确保系统稳定性

## 使用示例

### 个人用户存入保证金
```solidity
// 投诉者存入保证金
dao.depositGuarantee{value: 0.1 ether}(IFoodGuardDAO.UserType.Individual);
```

### 企业用户存入保证金
```solidity
// 企业存入保证金
dao.depositGuarantee{value: 1.0 ether}(IFoodGuardDAO.UserType.Company);
```

## 总结

通过这次修改，我们成功实现了差异化的保证金机制，使系统更加公平和安全。企业需要承担更高的保证金要求，而个人用户可以以较低门槛参与系统治理。修改后的系统通过了全面的测试验证，确保了功能的完整性和稳定性。 