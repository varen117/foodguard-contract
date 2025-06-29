// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，支持最新的安全特性

import "@openzeppelin/contracts/access/AccessControl.sol"; // 导入访问控制，实现角色管理
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // 导入重入攻击防护
import "@openzeppelin/contracts/utils/Pausable.sol"; // 导入暂停功能，用于紧急情况
import "../libraries/DataStructures.sol"; // 导入数据结构库
import "../libraries/Errors.sol"; // 导入错误处理库
import "../libraries/Events.sol"; // 导入事件库
import "../libraries/CommonModifiers.sol"; // 导入公共修饰符库

/**
 * @title FundManager
 * @author Food Safety Governance Team
 * @notice 资金管理模块，负责处理动态保证金、奖励池和资金分配
 * @dev 实现动态保证金管理、分层清算等功能
 * 这是食品安全治理系统的资金核心，实现了以下关键功能：
 * 1. 动态保证金计算：根据风险等级、声誉分数、并发案件数量动态调整保证金要求
 * 2. 简单冻结机制：直接冻结用户保证金，逻辑简单明确
 * 3. 分层风险管理：设置多级警告阈值，逐步限制用户操作直至强制清算
 * 4. 自动清算系统：当用户保证金严重不足时自动执行清算流程
 */
contract FundManager is AccessControl, ReentrancyGuard, Pausable, CommonModifiers {
    // ==================== 角色定义 ====================
    // 统一使用治理合约权限系统，与其他模块保持一致

    /// @notice 治理角色 - 拥有系统配置权限和重要决策权
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ==================== 状态变量 ====================

    /// @notice 系统资金池 - 管理系统中的各类资金
    /// @dev 包括总余额、奖励池、运营资金等不同用途的资金分类
    DataStructures.FundPool public fundPool;

    /// @notice 系统配置 - 存储系统运行的各项参数
    /// @dev 包括保证金限额、投票期限、验证者数量等核心配置
    DataStructures.SystemConfig public systemConfig;

    /// @notice 动态保证金配置 - 控制动态保证金计算的各项参数
    /// @dev 这些参数决定了保证金如何根据风险、声誉、并发案件数动态调整
    DataStructures.DynamicDepositConfig public dynamicConfig;

    /// @notice 用户保证金档案 - 每个用户的详细保证金状态
    /// @dev 包括总保证金、冻结金额、状态等级、操作限制等信息
    mapping(address => DataStructures.UserDepositProfile) public userProfiles;

    /// @notice 案件相关冻结保证金映射 - caseId => user => amount
    /// @dev 记录每个案件中每个用户被冻结的具体金额
    mapping(uint256 => mapping(address => uint256)) public caseFrozenDeposits;

    /// @notice 用户活跃案件列表 - 记录用户当前参与的所有案件
    /// @dev 用于计算并发案件数量和管理用户的案件参与状态
    mapping(address => uint256[]) public userActiveCases;

    /// @notice 用户待领取奖励 - 用户获得但尚未提取的奖励金额
    /// @dev 奖励来自成功的投票、质疑等参与活动caseFrozenDeposits
    mapping(address => uint256) public pendingRewards;

    /// @notice 用户声誉分数缓存 - 从奖惩管理模块获取的声誉数据缓存
    /// @dev 用于动态保证金计算，避免跨合约调用的gas消耗
    mapping(address => uint256) public userReputation;

    /// @notice 系统常量定义 - 规定系统运行的基本限制
    uint256 public constant MIN_DEPOSIT = 0.01 ether; // 最小保证金：0.01 ETH
    uint256 public constant MAX_CONCURRENT_CASES = 10; // 最大并发案件数：10个

    // ==================== 治理合约设置 ====================

    /// @notice 权限委托映射 - 允许治理合约委托特定操作给其他合约
    /// @dev 格式: functionSelector => delegatedContract => isAuthorized
    mapping(bytes4 => mapping(address => bool)) public functionDelegations;

    /// @notice 批量权限委托事件
    event DelegationUpdated(bytes4 indexed functionSelector, address indexed delegatedContract, bool authorized);

    // ==================== 修饰符 ====================

    /**
     * @notice 检查用户保证金状态是否健康
     * @dev 在执行重要操作前确保用户状态符合要求
     * 1. 更新用户状态，重新计算保证金覆盖率
     * 2. 禁止清算状态用户进行操作
     * 3. 禁止操作受限用户进行高风险操作
     * @param user 要检查的用户地址
     */
    modifier onlyHealthyUser(address user) {
        _updateUserStatus(user); // 先更新用户状态，确保数据最新
        DataStructures.UserDepositProfile storage profile = userProfiles[user];
        // 清算状态的用户不能进行任何操作
        if (profile.status == DataStructures.DepositStatus.LIQUIDATION) {
            revert Errors.UserInLiquidation(user);
        }
        // 操作受限的用户不能进行高风险操作
        if (profile.operationRestricted) {
            revert Errors.UserOperationRestricted(user, "Insufficient deposit");
        }
        _;
    }

    /**
     * @notice 检查地址是否为零地址
     * @dev 防止将关键合约地址设置为零地址
     * 零地址会导致资金丢失或功能失效
     */
    // notZeroAddress 修饰符已在 CommonModifiers 中定义

    // ==================== 构造函数 ====================

    /**
     * @dev 初始化资金管理合约，设置所有关键参数
     * @param admin 管理员地址，将获得默认管理员和治理角色
     */
    constructor(address admin) {
        // 授予角色权限
        _grantRole(DEFAULT_ADMIN_ROLE, admin); // 默认管理员角色，可以管理其他角色
        _grantRole(GOVERNANCE_ROLE, admin); // 治理角色，可以修改系统配置

        // 初始化系统配置 - 这些参数控制整个治理系统的运行
        systemConfig = DataStructures.SystemConfig({
            minComplaintDeposit: 0.01 ether,
            minEnterpriseDeposit: 0.1 ether,
            minDaoDeposit: 0.05 ether,
            votingPeriod: 3 days,
            challengePeriod: 2 days,
            minValidators: 3,
            maxValidators: 15,
            rewardPoolPercentage: 30,
            operationalFeePercentage: 5
        });

        // 初始化动态保证金配置
        dynamicConfig = DataStructures.DynamicDepositConfig({
            warningThreshold: 130,
            restrictionThreshold: 120,
            liquidationThreshold: 110,
            highRiskMultiplier: 200,
            mediumRiskMultiplier: 150,
            lowRiskMultiplier: 120,
            reputationDiscountThreshold: 800,
            reputationDiscountRate: 20
        });

        // 初始化资金池
        fundPool = DataStructures.FundPool({
            totalBalance: 0,
            rewardPool: 0,
            operationalFund: 0,
            reserveBalance: 0
        });
    }

    // ==================== 治理合约设置 ====================

    /**
     * @notice 设置治理合约地址
     * @dev 只有管理员可以设置，设置后治理合约获得治理权限
     * @param _governanceContract 治理合约地址
     */
    function setGovernanceContract(address _governanceContract) external onlyRole(DEFAULT_ADMIN_ROLE) notZeroAddress(_governanceContract) {
        _setGovernanceContract(_governanceContract);

        // 授予治理合约治理权限
        _grantRole(GOVERNANCE_ROLE, _governanceContract);

        emit Events.BusinessProcessAnomaly(
            0,
            _governanceContract,
            "Governance Setup",
            "Governance contract address updated",
            "New governance contract granted GOVERNANCE_ROLE",
            block.timestamp
        );
    }

    /**
     * @notice 智能权限委托 - 允许治理合约委托特定功能给其他合约
     * @dev 这个机制确保系统可以自动运行，同时保持安全性
     * @param functionSelector 要委托的函数选择器
     * @param delegatedContract 被委托的合约地址
     * @param authorized 是否授权
     */
    function setFunctionDelegation(
        bytes4 functionSelector,
        address delegatedContract,
        bool authorized
    ) external onlyRole(GOVERNANCE_ROLE) notZeroAddress(delegatedContract) {
        functionDelegations[functionSelector][delegatedContract] = authorized;
        emit DelegationUpdated(functionSelector, delegatedContract, authorized);
    }

    /**
     * @notice 批量设置权限委托 - 高效设置多个委托权限
     * @dev 用于一次性设置系统启动所需的所有委托权限
     * @param functionSelectors 函数选择器数组
     * @param delegatedContracts 被委托合约地址数组
     * @param authorizations 授权状态数组
     */
    function batchSetFunctionDelegations(
        bytes4[] calldata functionSelectors,
        address[] calldata delegatedContracts,
        bool[] calldata authorizations
    ) external onlyRole(GOVERNANCE_ROLE) {
        require(
            functionSelectors.length == delegatedContracts.length &&
            delegatedContracts.length == authorizations.length,
            "Arrays length mismatch"
        );

        for (uint256 i = 0; i < functionSelectors.length; i++) {
            require(delegatedContracts[i] != address(0), "Zero address delegation");
            functionDelegations[functionSelectors[i]][delegatedContracts[i]] = authorizations[i];
            emit DelegationUpdated(functionSelectors[i], delegatedContracts[i], authorizations[i]);
        }
    }

    /**
     * @notice 智能权限检查修饰符
     * @dev 检查调用者是否有治理权限或被委托权限
     */
    modifier onlyGovernanceOrDelegated() {
        bool hasGovernanceRole = hasRole(GOVERNANCE_ROLE, msg.sender);
        bool hasDelegatedPermission = functionDelegations[msg.sig][msg.sender];

        if (!hasGovernanceRole && !hasDelegatedPermission) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE_OR_DELEGATED");
        }
        _;
    }

    // ==================== 动态保证金核心函数 ====================

    /**
     * @notice 计算用户所需的动态保证金
     * @dev 动态保证金算法的核心函数，根据多个因素计算最终保证金要求
     * 算法设计思路：
     * 1. 基础风险调整：根据案件风险等级调整基础保证金
     * 2. 并发案件惩罚：参与多个案件的用户需要额外保证金，防止过度杠杆
     * 3. 声誉激励机制：高声誉用户享受折扣，低声誉用户承担更高成本
     * 4. 计算公式：final = base * risk_multiplier * (1 + concurrent_penalty) * reputation_factor
     * @param user 用户地址
     * @param riskLevel 案件风险等级（影响风险倍数）
     * @param baseAmount 基础保证金金额（系统配置的最低要求）
     * @return required 所需保证金金额（经过所有因素调整后的最终金额）
     */
    function calculateRequiredDeposit(
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) public view returns (uint256 required) {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 步骤1：基础金额 * 风险倍数
        // 风险倍数设计：高风险200%，中风险150%，低风险120%
        // 这反映了不同案件的复杂性和潜在损失
        uint256 riskMultiplier = _getRiskMultiplier(riskLevel);
        required = (baseAmount * riskMultiplier) / 100;

        // 步骤2：并发案件额外要求
        // 设计原理：防止用户同时参与过多案件，分散注意力和责任
        // 每个活跃案件增加50%的额外保证金要求
        if (profile.activeCaseCount > 1) {
            // 每个额外案件增加50%
            uint256 extraRate = (profile.activeCaseCount - 1) * 50;
            if (extraRate > 200) extraRate = 200; // 最多增加200%
            required = (required * (100 + extraRate)) / 100;
        }

        // 步骤3：声誉调整：根据用户历史表现调整保证金要求
        // 高声誉用户可以享受保证金折扣
        uint256 reputation = userReputation[user];
        if (reputation >= dynamicConfig.reputationDiscountThreshold) {
            // 声誉好的用户享受折扣（≥800分减少20%）
            required = (required * (100 - dynamicConfig.reputationDiscountRate)) / 100;
        }

        return required;
    }

    /**
     * @notice 更新用户保证金状态
     * @dev 分层风险管理的核心函数，实现渐进式风险控制
     * 算法设计：
     * 1. 计算保证金覆盖率 = 用户总保证金 / 所需保证金 * 100%
     * 2. 根据覆盖率分配状态等级，实现渐进式风险管理
     * 3. 状态等级说明：
     *    - HEALTHY（≥130%）：健康状态，无限制
     *    - WARNING（120%-130%）：警告状态，提醒但不限制
     *    - RESTRICTED（110%-120%）：限制状态，禁止高风险操作
     *    - LIQUIDATION（<110%）：清算状态，强制清算
     * @param user 用户地址
     */
    function _updateUserStatus(address user) internal {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        uint256 totalDeposit = profile.totalDeposit;
        uint256 requiredAmount = profile.requiredAmount;
        string memory descrption;
        string memory action;
        // 如果用户没有活跃案件，直接设为健康状态
        profile.status = requiredAmount == 0 ? DataStructures.DepositStatus.HEALTHY : profile.status;

        // 计算保证金覆盖率（百分比）
        // 覆盖率 = 用户拥有的保证金 / 系统要求的保证金 * 100%
        uint256 coverage = (totalDeposit * 100) / requiredAmount;
        DataStructures.DepositStatus oldStatus = profile.status;

        // 分层风险管理：根据覆盖率确定用户状态
        if (coverage >= dynamicConfig.warningThreshold) {
            // 健康状态（≥130%）：保证金充足，无任何限制
            profile.status = DataStructures.DepositStatus.HEALTHY;
            profile.operationRestricted = false;
        } else if (coverage >= dynamicConfig.restrictionThreshold) {
            // 警告状态（120%-130%）：保证金略显不足，发出警告但不限制操作
            profile.status = DataStructures.DepositStatus.WARNING;
            profile.operationRestricted = false;
            profile.lastWarningTime = block.timestamp; // 记录警告时间
            descrption = "Warning: deposit below warning threshold";
            action = "User advised to top up deposit";
        } else {
            // 清算状态（<110%）：保证金极度不足，限制用户后续活动
            profile.status = DataStructures.DepositStatus.LIQUIDATION;
            profile.operationRestricted = true; // 完全限制用户新操作

            // 只有状态改变时才处理清算逻辑，避免重复处理
            if (oldStatus != DataStructures.DepositStatus.LIQUIDATION) {
                // 只限制用户活动，不强制退出已有案件
                (descrption, action) = _handleUserInsufficientFunds(user);

            }
        }
        // 记录状态变化事件
        emit Events.BusinessProcessAnomaly(
            0,
            user,
            "User Insufficient Funds",
            descrption,
            action,
            block.timestamp
        );

    }

    /**
     * @notice 处理用户保证金不足的情况
     * @dev 新的清算机制：只限制用户活动，不强制退出已有案件
     * 处理逻辑：
     * 1. 限制用户所有新的案件操作：防止进一步风险暴露
     * 2. 保留已经进行中的案件：这些案件的保证金在参与时是足够的
     * 3. 记录状态变化：便于审计和监控
     * 设计原理：
     * - 已经参与的案件在参与时保证金是充足的，系统已验证过风险
     * - 只需要防止用户参与新的案件，避免进一步扩大风险敞口
     * - 保护现有案件的参与者和系统的稳定性
     *
     * @param user 保证金不足的用户地址
     */
    function _handleUserInsufficientFunds(address user) internal returns (string memory descrption, string memory action){
        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 记录处理前的状态用于监控
        uint256 currentTotalDeposit = profile.totalDeposit;
        uint256 currentFrozenAmount = profile.frozenAmount;
        uint256 currentActiveCaseCount = profile.activeCaseCount;
        string memory descrption = "User deposit below liquidation threshold";
        string memory action = "Operation restricted, existing cases preserved";

        // 验证状态一致性：确保用户状态正确设置
        if (profile.status != DataStructures.DepositStatus.LIQUIDATION) {
            descrption = "Status not set to LIQUIDATION";
            action = "Force set status to LIQUIDATION";
            profile.status = DataStructures.DepositStatus.LIQUIDATION;
        }

        if (!profile.operationRestricted) {
            descrption = "Operation not restricted";
            action = "Force set operation restriction";
            profile.operationRestricted = true;
        }
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
            revert Errors.InsufficientBalance(
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
     * @notice 冻结用户保证金
     * @param caseId 案件ID
     * @param user 用户地址
     * @param riskLevel 案件风险等级（影响所需保证金计算）
     * @param baseAmount 基础冻结金额（系统配置的基础要求）
     */
    function freezeDeposit(
        uint256 caseId,
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) external onlyGovernanceOrDelegated whenNotPaused notZeroAddress(user) {

        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 步骤1：计算实际需要冻结的金额
        // 使用动态保证金算法，考虑风险、声誉、并发案件等因素
        uint256 requiredAmount = calculateRequiredDeposit(user, riskLevel, baseAmount);
        uint256 available = profile.totalDeposit - profile.frozenAmount; // 用户当前可用保证金

        uint256 freezeAmount = requiredAmount; // 默认冻结所需的完整金额

        // 步骤2：检查保证金是否充足
        if (available < requiredAmount) {
            revert Errors.InsufficientBalance(user, requiredAmount, available);
        }

        // 步骤3：执行冻结操作
        profile.frozenAmount += freezeAmount; // 增加用户的冻结金额
        caseFrozenDeposits[caseId][user] = freezeAmount; // 记录案件相关的冻结金额

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
            DataStructures.RiskLevel.MEDIUM,
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
    ) external onlyGovernanceOrDelegated whenNotPaused notZeroAddress(user) {
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

    /**
     * @notice 将奖励添加到用户保证金余额
     * @dev 由RewardPunishmentManager调用，将奖励直接添加到用户的保证金余额中
     * @param user 用户地址
     * @param amount 奖励金额
     */
    function addRewardToDeposit(
        address user,
        uint256 amount
    ) external onlyGovernanceOrDelegated whenNotPaused notZeroAddress(user) {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount, 1);
        }

        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 将奖励添加到用户保证金余额
        profile.totalDeposit += amount;

        // 更新用户状态
        _updateUserStatus(user);

        // 发出奖励添加事件
        emit Events.DepositMade(
            user,
            amount,
            profile.totalDeposit,
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
            address(this),
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
     * @notice 获取资金池状态
     */
    function getFundPool() external view returns (DataStructures.FundPool memory) {
        return fundPool;
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

    // ==================== 管理函数 ====================

    /**
     * @notice 更新动态保证金配置
     */
    function updateDynamicConfig(
        DataStructures.DynamicDepositConfig calldata newConfig
    ) external onlyGovernanceOrDelegated {
        dynamicConfig = newConfig;
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
    onlyGovernanceOrDelegated
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
