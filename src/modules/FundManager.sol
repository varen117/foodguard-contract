// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";

/**
 * @title FundManager
 * @author Food Safety Governance Team
 * @notice 资金管理模块，负责处理动态保证金、奖励池和资金分配
 * @dev 实现动态保证金管理、互助池、分层清算等功能
 */
contract FundManager is AccessControl, ReentrancyGuard, Pausable {
    // ==================== 角色定义 ====================

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ==================== 状态变量 ====================

    /// @notice 系统资金池
    DataStructures.FundPool public fundPool;

    /// @notice 系统配置
    DataStructures.SystemConfig public systemConfig;

    /// @notice 动态保证金配置
    DataStructures.DynamicDepositConfig public dynamicConfig;

    /// @notice 互助保证金池
    DataStructures.MutualGuaranteePool public mutualPool;

    /// @notice 用户保证金档案
    mapping(address => DataStructures.UserDepositProfile) public userProfiles;

    /// @notice 用户在互助池中的信息
    mapping(address => DataStructures.PoolMemberInfo) public poolMembers;

    /// @notice 案件相关冻结保证金映射
    mapping(uint256 => mapping(address => uint256)) public caseFrozenDeposits;

    /// @notice 用户活跃案件列表
    mapping(address => uint256[]) public userActiveCases;

    /// @notice 用户待领取奖励
    mapping(address => uint256) public pendingRewards;

    /// @notice 用户声誉分数 (从RewardPunishmentManager获取的缓存)
    mapping(address => uint256) public userReputation;

    /// @notice 常量
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    uint256 public constant MAX_DEPOSIT = 100 ether;
    uint256 public constant MAX_CONCURRENT_CASES = 10;
    uint256 public constant LIQUIDATION_PENALTY_RATE = 10; // 10%

    // ==================== 修饰符 ====================

    /**
     * @notice 检查用户保证金状态是否健康
     */
    modifier onlyHealthyUser(address user) {
        _updateUserStatus(user);
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        if (profile.status == DataStructures.DepositStatus.LIQUIDATION) {
            revert Errors.UserInLiquidation(user);
        }
        if (profile.operationRestricted) {
            revert Errors.UserOperationRestricted(user, "Insufficient deposit");
        }
        _;
    }

    /**
     * @notice 检查地址是否为零地址
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);

        // 初始化系统配置
        systemConfig = DataStructures.SystemConfig({
            minComplaintDeposit: 0.05 ether,
            maxComplaintDeposit: 10 ether,
            minEnterpriseDeposit: 1 ether,
            maxEnterpriseDeposit: 50 ether,
            minDaoDeposit: 0.1 ether,
            maxDaoDeposit: 20 ether,
            votingPeriod: 7 days,
            challengePeriod: 3 days,
            minValidators: 3,
            maxValidators: 15,
            rewardPoolPercentage: 70,
            operationalFeePercentage: 10
        });

        // 初始化动态保证金配置
        dynamicConfig = DataStructures.DynamicDepositConfig({
            warningThreshold: 130,      // 130%
            restrictionThreshold: 120,  // 120%
            liquidationThreshold: 110,  // 110%
            highRiskMultiplier: 200,    // 200%
            mediumRiskMultiplier: 150,  // 150%
            lowRiskMultiplier: 120,     // 120%
            concurrentCaseExtra: 50,    // 50%
            reputationDiscountThreshold: 800, // 800分
            reputationDiscountRate: 20, // 20%
            reputationPenaltyThreshold: 300,  // 300分
            reputationPenaltyRate: 50   // 50%
        });

        // 初始化互助池
        mutualPool = DataStructures.MutualGuaranteePool({
            totalBalance: 0,
            totalContributions: 0,
            activeMembers: 0,
            coverageProvided: 0,
            isActive: true
        });
    }

    // ==================== 动态保证金核心函数 ====================

    /**
     * @notice 计算用户所需的动态保证金
     * @param user 用户地址
     * @param riskLevel 案件风险等级
     * @param baseAmount 基础保证金金额
     * @return required 所需保证金金额
     */
    function calculateRequiredDeposit(
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) public view returns (uint256 required) {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        // 基础金额 * 风险倍数
        uint256 riskMultiplier = _getRiskMultiplier(riskLevel);
        required = (baseAmount * riskMultiplier) / 100;
        
        // 并发案件额外要求
        if (profile.activeCaseCount > 0) {
            uint256 extraRate = profile.activeCaseCount * dynamicConfig.concurrentCaseExtra;
            required += (baseAmount * extraRate) / 100;
        }
        
        // 声誉调整
        uint256 reputation = userReputation[user];
        if (reputation >= dynamicConfig.reputationDiscountThreshold) {
            // 声誉好的用户享受折扣
            required = (required * (100 - dynamicConfig.reputationDiscountRate)) / 100;
        } else if (reputation <= dynamicConfig.reputationPenaltyThreshold) {
            // 声誉差的用户需要更多保证金
            required = (required * (100 + dynamicConfig.reputationPenaltyRate)) / 100;
        }
        
        return required;
    }

    /**
     * @notice 更新用户保证金状态
     * @param user 用户地址
     */
    function _updateUserStatus(address user) internal {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        uint256 totalDeposit = profile.totalDeposit;
        uint256 requiredAmount = profile.requiredAmount;
        
        if (requiredAmount == 0) {
            profile.status = DataStructures.DepositStatus.HEALTHY;
            return;
        }
        
        uint256 coverage = (totalDeposit * 100) / requiredAmount;
        DataStructures.DepositStatus oldStatus = profile.status;
        
        if (coverage >= dynamicConfig.warningThreshold) {
            profile.status = DataStructures.DepositStatus.HEALTHY;
            profile.operationRestricted = false;
        } else if (coverage >= dynamicConfig.restrictionThreshold) {
            profile.status = DataStructures.DepositStatus.WARNING;
            profile.operationRestricted = false;
            profile.lastWarningTime = block.timestamp;
            
            emit Events.DepositWarning(
                user,
                requiredAmount,
                totalDeposit,
                coverage,
                block.timestamp
            );
        } else if (coverage >= dynamicConfig.liquidationThreshold) {
            profile.status = DataStructures.DepositStatus.RESTRICTED;
            profile.operationRestricted = true;
            
            emit Events.UserOperationRestricted(
                user,
                "Deposit below restriction threshold",
                block.timestamp
            );
        } else {
            profile.status = DataStructures.DepositStatus.LIQUIDATION;
            profile.operationRestricted = true;
            
            // 触发清算流程
            _triggerLiquidation(user);
        }
        
        if (oldStatus != profile.status) {
            emit Events.DepositStatusChanged(
                user,
                uint8(oldStatus),
                uint8(profile.status),
                coverage,
                block.timestamp
            );
        }
    }

    /**
     * @notice 触发用户清算
     * @param user 用户地址
     */
    function _triggerLiquidation(address user) internal {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        uint256 totalDeposit = profile.totalDeposit;
        uint256 penalty = (totalDeposit * LIQUIDATION_PENALTY_RATE) / 100;
        uint256 liquidatedAmount = totalDeposit - penalty;
        
        // 扣除惩罚金
        if (penalty > 0) {
            profile.totalDeposit -= penalty;
            _addToFundPool(penalty, "Liquidation penalty");
        }
        
        // 退出所有活跃案件
        _forceExitAllCases(user);
        
        emit Events.UserLiquidated(
            user,
            liquidatedAmount,
            penalty,
            "Insufficient deposit coverage",
            block.timestamp
        );
    }

    /**
     * @notice 强制用户退出所有案件
     * @param user 用户地址
     */
    function _forceExitAllCases(address user) internal {
        uint256[] storage activeCases = userActiveCases[user];
        
        for (uint256 i = 0; i < activeCases.length; i++) {
            uint256 caseId = activeCases[i];
            uint256 frozenAmount = caseFrozenDeposits[caseId][user];
            
            if (frozenAmount > 0) {
                // 解冻保证金
                userProfiles[user].frozenAmount -= frozenAmount;
                caseFrozenDeposits[caseId][user] = 0;
                
                emit Events.DepositUnfrozen(
                    caseId,
                    user,
                    frozenAmount,
                    block.timestamp
                );
            }
        }
        
        // 清空活跃案件列表
        delete userActiveCases[user];
        userProfiles[user].activeCaseCount = 0;
    }

    // ==================== 互助池功能 ====================

    /**
     * @notice 加入互助池
     * @param contribution 贡献金额
     */
    function joinMutualPool(uint256 contribution) external payable nonReentrant {
        if (msg.value != contribution) {
            revert Errors.InvalidAmount(msg.value, contribution);
        }
        
        if (contribution < MIN_DEPOSIT) {
            revert Errors.InvalidAmount(contribution, MIN_DEPOSIT);
        }
        
        DataStructures.PoolMemberInfo storage member = poolMembers[msg.sender];
        
        if (!member.isActive) {
            mutualPool.activeMembers++;
            member.joinTime = block.timestamp;
            member.isActive = true;
        }
        
        member.contribution += contribution;
        member.lastActiveTime = block.timestamp;
        
        mutualPool.totalBalance += contribution;
        mutualPool.totalContributions += contribution;
        
        // 加入互助池的用户可以降低个人保证金要求
        userProfiles[msg.sender].poolContribution = member.contribution;
        
        emit Events.MutualPoolContribution(
            msg.sender,
            contribution,
            member.contribution,
            block.timestamp
        );
    }

    /**
     * @notice 互助池为用户提供担保
     * @param user 需要担保的用户
     * @param amount 担保金额
     */
    function provideMutualCoverage(
        address user,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        _provideMutualCoverage(user, amount);
    }

    /**
     * @notice 内部函数：互助池为用户提供担保
     * @param user 需要担保的用户
     * @param amount 担保金额
     */
    function _provideMutualCoverage(
        address user,
        uint256 amount
    ) internal {
        if (mutualPool.totalBalance < amount) {
            revert Errors.InsufficientPoolBalance(amount, mutualPool.totalBalance);
        }
        
        if (!poolMembers[user].isActive) {
            revert Errors.NotPoolMember(user);
        }
        
        mutualPool.totalBalance -= amount;
        mutualPool.coverageProvided += amount;
        
        // 临时增加用户的有效保证金
        userProfiles[user].totalDeposit += amount;
        
        emit Events.MutualPoolCoverage(
            user,
            amount,
            mutualPool.totalBalance,
            block.timestamp
        );
    }

    // ==================== 保证金管理函数 ====================

    /**
     * @notice 存入保证金
     */
    function depositFunds() external payable whenNotPaused nonReentrant {
        if (msg.value < MIN_DEPOSIT) {
            revert Errors.InvalidAmount(msg.value, MIN_DEPOSIT);
        }

        DataStructures.UserDepositProfile storage profile = userProfiles[msg.sender];
        
        if (profile.totalDeposit + msg.value > MAX_DEPOSIT) {
            revert Errors.InvalidAmount(
                profile.totalDeposit + msg.value,
                MAX_DEPOSIT
            );
        }

        profile.totalDeposit += msg.value;
        
        // 更新用户状态
        _updateUserStatus(msg.sender);

        emit Events.DepositMade(
            msg.sender,
            msg.value,
            profile.totalDeposit,
            block.timestamp
        );
    }

    /**
     * @notice 提取可用保证金
     * @param amount 提取金额
     */
    function withdrawFunds(uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyHealthyUser(msg.sender) 
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount, 1);
        }

        DataStructures.UserDepositProfile storage profile = userProfiles[msg.sender];
        uint256 available = profile.totalDeposit - profile.frozenAmount;
        
        if (available < amount) {
            revert Errors.InsufficientBalance(msg.sender, amount, available);
        }
        
        // 检查提取后是否满足最低要求
        uint256 remaining = profile.totalDeposit - amount;
        if (remaining < profile.requiredAmount) {
            revert Errors.InsufficientDynamicDeposit(
                msg.sender,
                profile.requiredAmount,
                remaining
            );
        }

        profile.totalDeposit -= amount;
        
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Errors.TransferFailed(msg.sender, amount);
        }

        // 更新状态
        _updateUserStatus(msg.sender);

        emit Events.FundsTransferredFromPool(
            msg.sender,
            amount,
            "Withdrawal",
            block.timestamp
        );
    }

    /**
     * @notice 冻结用户保证金（智能冻结）
     * @param caseId 案件ID
     * @param user 用户地址
     * @param riskLevel 案件风险等级
     * @param baseAmount 基础冻结金额
     */
    function smartFreezeDeposit(
        uint256 caseId,
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused notZeroAddress(user) {
        
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        // 计算实际需要冻结的金额
        uint256 requiredAmount = calculateRequiredDeposit(user, riskLevel, baseAmount);
        uint256 available = profile.totalDeposit - profile.frozenAmount;
        
        uint256 freezeAmount = requiredAmount;
        
        // 如果用户保证金不足，尝试使用互助池
        if (available < requiredAmount && poolMembers[user].isActive) {
            uint256 shortfall = requiredAmount - available;
            if (mutualPool.totalBalance >= shortfall) {
                _provideMutualCoverage(user, shortfall);
                available = profile.totalDeposit - profile.frozenAmount;
            }
        }
        
        // 如果仍然不足，冻结所有可用金额
        if (available < requiredAmount) {
            freezeAmount = available;
        }
        
        if (freezeAmount == 0) {
            revert Errors.InsufficientBalance(user, requiredAmount, available);
        }
        
        // 执行冻结
        profile.frozenAmount += freezeAmount;
        caseFrozenDeposits[caseId][user] = freezeAmount;
        
        // 更新案件信息
        userActiveCases[user].push(caseId);
        profile.activeCaseCount++;
        profile.requiredAmount += requiredAmount;
        
        // 更新状态
        _updateUserStatus(user);

        emit Events.DepositFrozen(
            caseId,
            user,
            freezeAmount,
            "Smart case processing",
            block.timestamp
        );
    }

    /**
     * @notice 解冻用户保证金
     * @param caseId 案件ID
     * @param user 用户地址
     */
    function unfreezeDeposit(
        uint256 caseId,
        address user
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused notZeroAddress(user) {
        uint256 frozenAmount = caseFrozenDeposits[caseId][user];
        if (frozenAmount == 0) {
            revert Errors.InvalidAmount(frozenAmount, 1);
        }

        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        profile.frozenAmount -= frozenAmount;
        caseFrozenDeposits[caseId][user] = 0;
        
        // 从活跃案件列表中移除
        _removeActiveCase(user, caseId);
        profile.activeCaseCount--;
        
        // 重新计算所需保证金
        _recalculateRequiredAmount(user);
        
        // 更新状态
        _updateUserStatus(user);

        emit Events.DepositUnfrozen(
            caseId,
            user,
            frozenAmount,
            block.timestamp
        );
    }

    // ==================== 辅助函数 ====================

    /**
     * @notice 获取风险倍数
     */
    function _getRiskMultiplier(DataStructures.RiskLevel riskLevel) internal view returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return dynamicConfig.highRiskMultiplier;
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return dynamicConfig.mediumRiskMultiplier;
        } else {
            return dynamicConfig.lowRiskMultiplier;
        }
    }

    /**
     * @notice 从活跃案件列表中移除案件
     */
    function _removeActiveCase(address user, uint256 caseId) internal {
        uint256[] storage activeCases = userActiveCases[user];
        for (uint256 i = 0; i < activeCases.length; i++) {
            if (activeCases[i] == caseId) {
                activeCases[i] = activeCases[activeCases.length - 1];
                activeCases.pop();
                break;
            }
        }
    }

    /**
     * @notice 重新计算用户所需保证金
     */
    function _recalculateRequiredAmount(address user) internal {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        uint256 totalRequired = 0;
        
        uint256[] storage activeCases = userActiveCases[user];
        for (uint256 i = 0; i < activeCases.length; i++) {
            uint256 caseId = activeCases[i];
            uint256 frozenAmount = caseFrozenDeposits[caseId][user];
            totalRequired += frozenAmount;
        }
        
        profile.requiredAmount = totalRequired;
    }

    /**
     * @notice 向资金池添加资金
     */
    function _addToFundPool(uint256 amount, string memory source) internal {
        uint256 rewardPoolShare = (amount * systemConfig.rewardPoolPercentage) / 100;
        uint256 operationalShare = (amount * systemConfig.operationalFeePercentage) / 100;
        uint256 reserveShare = amount - rewardPoolShare - operationalShare;

        fundPool.totalBalance += amount;
        fundPool.rewardPool += rewardPoolShare;
        fundPool.operationalFund += operationalShare;
        fundPool.reserveBalance += reserveShare;

        emit Events.FundsTransferredToPool(
            0,
            amount,
            source,
            block.timestamp
        );
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取用户保证金状态
     */
    function getUserDepositStatus(address user) 
        external 
        view 
        returns (DataStructures.UserDepositProfile memory) 
    {
        return userProfiles[user];
    }

    /**
     * @notice 获取用户可用保证金
     */
    function getAvailableDeposit(address user) external view returns (uint256) {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        if (profile.frozenAmount > profile.totalDeposit) {
            return 0;
        }
        return profile.totalDeposit - profile.frozenAmount;
    }

    /**
     * @notice 检查用户是否可以参与新案件
     */
    function canParticipateInCase(
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) external view returns (bool) {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        if (profile.operationRestricted) {
            return false;
        }
        
        if (profile.activeCaseCount >= MAX_CONCURRENT_CASES) {
            return false;
        }
        
        uint256 requiredAmount = calculateRequiredDeposit(user, riskLevel, baseAmount);
        uint256 available = profile.totalDeposit - profile.frozenAmount;
        
        return available >= requiredAmount;
    }

    /**
     * @notice 获取案件相关冻结保证金
     */
    function getCaseFrozenDeposit(
        uint256 caseId,
        address user
    ) external view returns (uint256) {
        return caseFrozenDeposits[caseId][user];
    }

    /**
     * @notice 获取资金池状态
     */
    function getFundPoolStatus()
        external
        view
        returns (DataStructures.FundPool memory)
    {
        return fundPool;
    }

    /**
     * @notice 获取系统配置
     */
    function getSystemConfig()
        external
        view
        returns (DataStructures.SystemConfig memory)
    {
        return systemConfig;
    }

    /**
     * @notice 获取动态保证金配置
     */
    function getDynamicConfig()
        external
        view
        returns (DataStructures.DynamicDepositConfig memory)
    {
        return dynamicConfig;
    }

    /**
     * @notice 获取互助池状态
     */
    function getMutualPoolStatus()
        external
        view
        returns (DataStructures.MutualGuaranteePool memory)
    {
        return mutualPool;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 更新动态保证金配置
     */
    function updateDynamicConfig(
        DataStructures.DynamicDepositConfig calldata newConfig
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dynamicConfig = newConfig;
    }

    /**
     * @notice 更新用户声誉分数（由RewardPunishmentManager调用）
     */
    function updateUserReputation(
        address user,
        uint256 reputation
    ) external onlyRole(OPERATOR_ROLE) {
        userReputation[user] = reputation;
        
        // 重新计算用户保证金要求
        _recalculateRequiredAmount(user);
        _updateUserStatus(user);
    }

    /**
     * @notice 批量检查用户状态
     */
    function batchCheckUserStatus(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            _updateUserStatus(users[i]);
        }
    }

    /**
     * @notice 处理用户注册时的保证金存入
     * @param user 用户地址
     * @param amount 保证金金额
     */
    function registerUserDeposit(
        address user,
        uint256 amount
    )
    external
    payable
    onlyRole(OPERATOR_ROLE)
    whenNotPaused
    notZeroAddress(user)
    {
        if (msg.value != amount) {
            revert Errors.InvalidAmount(msg.value, amount);
        }

        if (amount < MIN_DEPOSIT) {
            revert Errors.InvalidAmount(amount, MIN_DEPOSIT);
        }

        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        
        if (profile.totalDeposit + amount > MAX_DEPOSIT) {
            revert Errors.InvalidAmount(
                profile.totalDeposit + amount,
                MAX_DEPOSIT
            );
        }

        profile.totalDeposit += amount;
        
        // 更新用户状态
        _updateUserStatus(user);

        emit Events.DepositMade(
            user,
            amount,
            profile.totalDeposit,
            block.timestamp
        );
    }

    /**
     * @notice 接收ETH
     */
    receive() external payable {
        _addToFundPool(msg.value, "Direct deposit");
    }
}
