// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，支持最新的安全特性

import "@openzeppelin/contracts/access/AccessControl.sol"; // 导入访问控制，实现角色管理
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // 导入重入攻击防护
import "@openzeppelin/contracts/utils/Pausable.sol"; // 导入暂停功能，用于紧急情况
import "../libraries/DataStructures.sol"; // 导入数据结构库
import "../libraries/Errors.sol"; // 导入错误处理库
import "../libraries/Events.sol"; // 导入事件库

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
contract FundManager is AccessControl, ReentrancyGuard, Pausable {
    // ==================== 角色定义 ====================
    // 使用基于角色的访问控制，确保不同功能只能由相应权限的地址调用

    /// @notice 治理角色 - 拥有系统配置权限和重要决策权
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice 操作员角色 - 拥有日常操作权限，如冻结/解冻保证金
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

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

    /// @notice 用户角色映射 - 记录用户的角色
    mapping(address => DataStructures.UserRole) public userRole;

    /// @notice 系统常量定义 - 规定系统运行的基本限制
    uint256 public constant MIN_DEPOSIT = 0.01 ether; // 最小保证金：0.01 ETH
    uint256 public constant MAX_DEPOSIT = 100 ether; // 最大保证金：100 ETH
    uint256 public constant MAX_CONCURRENT_CASES = 10; // 最大并发案件数：10个
    uint256 public constant LIQUIDATION_PENALTY_RATE = 10; // 清算罚金比例：10%

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
     * @dev 防止将关键功能的地址参数设置为零地址
     * 零地址会导致资金丢失或功能失效
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }

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
            minComplaintDeposit: 0.05 ether, // 投诉最小保证金：防止恶意投诉
            maxComplaintDeposit: 10 ether, // 投诉最大保证金：避免门槛过高
            minEnterpriseDeposit: 1 ether, // 企业最小保证金：确保企业有足够经济责任
            maxEnterpriseDeposit: 50 ether, // 企业最大保证金：合理上限
            minDaoDeposit: 0.1 ether, // DAO成员最小保证金：验证者参与门槛
            maxDaoDeposit: 20 ether, // DAO成员最大保证金：合理上限
            votingPeriod: 7 days, // 投票期限：7天，给验证者充分时间分析
            challengePeriod: 3 days, // 质疑期限：3天，平衡效率和公正性
            minValidators: 3, // 最少验证者：保证基本的决策有效性
            maxValidators: 15, // 最多验证者：避免决策效率过低
            rewardPoolPercentage: 70, // 奖励池比例：70%用于奖励正确参与者
            operationalFeePercentage: 10 // 运营费用比例：10%用于系统运营
        });

        // 初始化动态保证金配置 - 这些参数控制风险管理和保证金调整
        dynamicConfig = DataStructures.DynamicDepositConfig({
            warningThreshold: 130, // 警告阈值：130%，保证金充足的标准
            restrictionThreshold: 120, // 限制阈值：120%，开始限制操作
            liquidationThreshold: 110, // 清算阈值：110%，强制清算临界点
            highRiskMultiplier: 200, // 高风险倍数：200%，高风险案件需要双倍保证金
            mediumRiskMultiplier: 150, // 中风险倍数：150%，中等风险案件增加50%
            lowRiskMultiplier: 120, // 低风险倍数：120%，低风险案件增加20%
            concurrentCaseExtra: 50, // 并发案件额外：每个并发案件增加50%保证金
            reputationDiscountThreshold: 800, // 声誉折扣门槛：800分以上享受折扣
            reputationDiscountRate: 20, // 声誉折扣率：高声誉用户减少20%保证金
            reputationPenaltyThreshold: 300, // 声誉惩罚门槛：300分以下增加保证金
            reputationPenaltyRate: 50 // 声誉惩罚率：低声誉用户增加50%保证金
        });

        // 初始化资金池
        fundPool = DataStructures.FundPool({
            totalBalance: 0, // 初始总余额为0
            reserveBalance: 0, // 初始储备金为0
            rewardPool: 0, // 初始奖励池为0
            operationalFund: 0, // 初始运营资金为0
            emergencyFund: 0 // 初始应急资金为0
        });
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
        if (profile.activeCaseCount > 0) {
            uint256 extraRate = profile.activeCaseCount * dynamicConfig.concurrentCaseExtra;
            required += (baseAmount * extraRate) / 100;
        }

        // 步骤3：声誉调整（激励机制）
        // 设计原理：鼓励长期良好表现，惩罚不良行为
        uint256 reputation = userReputation[user];
        if (reputation >= dynamicConfig.reputationDiscountThreshold) {
            // 声誉好的用户享受折扣（≥800分减少20%）
            // 公式：required = required * (100 - 20) / 100 = required * 0.8
            required = (required * (100 - dynamicConfig.reputationDiscountRate)) / 100;
        } else if (reputation <= dynamicConfig.reputationPenaltyThreshold) {
            // 声誉差的用户需要更多保证金（≤300分增加50%）
            // 公式：required = required * (100 + 50) / 100 = required * 1.5
            required = (required * (100 + dynamicConfig.reputationPenaltyRate)) / 100;
        }
        // 中等声誉用户（300-800分）不做调整，使用基础计算结果

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

        // 如果用户没有活跃案件，直接设为健康状态
        if (requiredAmount == 0) {
            profile.status = DataStructures.DepositStatus.HEALTHY;
            return;
        }

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

            // 发出警告事件，提醒用户注意保证金不足
            emit Events.DepositWarning(
                user,
                requiredAmount,
                totalDeposit,
                coverage,
                block.timestamp
            );
        } else if (coverage >= dynamicConfig.liquidationThreshold) {
            // 限制状态（110%-120%）：保证金严重不足，限制高风险操作
            profile.status = DataStructures.DepositStatus.RESTRICTED;
            profile.operationRestricted = true; // 开始限制用户操作

            // 发出操作限制事件
            emit Events.UserOperationRestricted(
                user,
                "Deposit below restriction threshold",
                block.timestamp
            );
        } else {
            // 清算状态（<110%）：保证金极度不足，触发强制清算
            profile.status = DataStructures.DepositStatus.LIQUIDATION;
            profile.operationRestricted = true; // 完全限制用户操作

            // 触发清算流程，保护系统安全
            _triggerLiquidation(user);
        }

        // 如果状态发生变化，发出状态变更事件
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
     * @dev 强制清算机制，当用户保证金严重不足时自动执行
     * 清算流程设计：
     * 1. 强制退出所有案件并解冻保证金：避免资金状态不一致
     * 2. 计算清算罚金（10%）：基于解冻后的实际可用资金
     * 3. 将罚金转入系统资金池：增强系统资金实力
     * 清算的必要性：保护系统免受无力承担责任的用户影响
     *
     * 说明：先解冻再扣罚金，避免资金状态不一致导致的下溢风险
     * @param user 被清算的用户地址
     */
    function _triggerLiquidation(address user) internal {
        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 记录清算前的状态用于异常检测
        uint256 preExitFrozenAmount = profile.frozenAmount;
        uint256 preExitTotalDeposit = profile.totalDeposit;
        // uint256 preExitActiveCases = profile.activeCaseCount;

        // 步骤1：先强制退出所有活跃案件并解冻保证金
        // 这样可以确保所有冻结资金都正确释放，避免状态不一致
        _forceExitAllCases(user);

        // 异常检测1：验证强制退出后的状态
        if (profile.frozenAmount != 0) {
            emit Events.BusinessProcessAnomaly(
                0, // 不特定于某个案件
                user,
                "User Liquidation",
                "Non-zero frozen amount after force exit",
                "Continue liquidation with warning",
                block.timestamp
            );
        }

        if (profile.activeCaseCount != 0) {
            emit Events.BusinessProcessAnomaly(
                0,
                user,
                "User Liquidation",
                "Non-zero active case count after force exit",
                "Reset active case count to zero",
                block.timestamp
            );
            profile.activeCaseCount = 0; // 强制修复
        }

        // 步骤2：基于解冻后的实际资金计算罚金
        uint256 totalDeposit = profile.totalDeposit; // 获取解冻后的总保证金

        // 异常检测2：验证保证金计算的合理性
        if (totalDeposit > preExitTotalDeposit) {
            // 理论上总保证金不应该在清算过程中增加
            emit Events.SystemAnomalyWarning(
                "FUND_MANAGEMENT",
                "Total deposit increased during liquidation process",
                4, // 高严重程度
                address(this),
                abi.encode(user, preExitTotalDeposit, totalDeposit, preExitFrozenAmount),
                block.timestamp
            );
        }

        uint256 penalty = (totalDeposit * LIQUIDATION_PENALTY_RATE) / 100;
        uint256 liquidatedAmount = totalDeposit > penalty ? totalDeposit - penalty : 0;

        // 异常检测3：验证罚金计算的合理性
        if (penalty > totalDeposit) {
            emit Events.BusinessProcessAnomaly(
                0,
                user,
                "User Liquidation",
                "Calculated penalty exceeds total deposit",
                "Adjust penalty to total deposit amount",
                block.timestamp
            );
            penalty = totalDeposit; // 调整为最大可能值
            liquidatedAmount = 0;
        }

        // 步骤3：扣除惩罚金并转入系统资金池
        if (penalty > 0 && totalDeposit >= penalty) {
            profile.totalDeposit -= penalty; // 从用户保证金中扣除罚金
            _addToFundPool(penalty, "Liquidation penalty"); // 罚金进入系统资金池
        } else if (penalty > 0) {
            // 异常情况：无法扣除足够的罚金
            emit Events.BusinessProcessAnomaly(
                0,
                user,
                "User Liquidation",
                "Insufficient funds for penalty deduction",
                "Skip penalty deduction",
                block.timestamp
            );
        }

        // 发出清算事件，记录清算详情
        emit Events.UserLiquidated(
            user,
            liquidatedAmount, // 用户实际损失的金额
            penalty, // 被扣除的罚金
            "Insufficient deposit coverage", // 清算原因
            block.timestamp
        );

        // 最终状态验证
        if (profile.totalDeposit < 0) {
            // 这应该永远不会发生，但作为最后的安全检查
            emit Events.SystemAnomalyWarning(
                "FUND_MANAGEMENT",
                "Negative total deposit after liquidation",
                5, // 最高严重程度
                address(this),
                abi.encode(user, profile.totalDeposit),
                block.timestamp
            );
            profile.totalDeposit = 0; // 强制修复
        }
    }

    /**
     * @notice 强制用户退出所有案件
     * @dev 安全的保证金解冻机制，添加下溢保护
     *
     * 设计说明：为什么要逐个解冻而不是直接归零？
     * 1. 事件完整性：每个案件解冻都需要独立的事件记录，便于外部系统监听
     * 2. 状态验证：通过逐个解冻可以检测系统状态是否一致，发现潜在问题
     * 3. 数据清理：必须清除每个案件在caseFrozenDeposits中的记录
     * 4. 审计跟踪：提供完整的资金流动记录，便于问题排查和审计
     * 5. 安全性：逐步验证比直接操作更安全，可以暴露隐藏的系统问题
     *
     * 虽然直接 profile.frozenAmount = 0 更简洁，但会丢失重要信息且可能掩盖系统bug
     *
     * @param user 用户地址
     */
    function _forceExitAllCases(address user) internal {
        uint256[] storage activeCases = userActiveCases[user];
        DataStructures.UserDepositProfile storage profile = userProfiles[user];

        // 记录解冻前的总金额，用于验证
        uint256 initialFrozenAmount = profile.frozenAmount;
        uint256 totalUnfrozen = 0;

        for (uint256 i = 0; i < activeCases.length; i++) {
            uint256 caseId = activeCases[i];
            uint256 frozenAmount = caseFrozenDeposits[caseId][user]; // 添加映射名称

            if (frozenAmount > 0) {
                // 安全检查：防止下溢导致的revert
                if (profile.frozenAmount >= frozenAmount) {
                    // 正常解冻保证金：实际释放用户的冻结资金
                    profile.frozenAmount -= frozenAmount;
                    totalUnfrozen += frozenAmount;
                } else {
                    // 异常情况：档案中的冻结金额不足，强制归零确保继续执行
                    totalUnfrozen += profile.frozenAmount; // 记录实际解冻的金额
                    profile.frozenAmount = 0;
                }
                // 清除案件相关的冻结记录
                caseFrozenDeposits[caseId][user] = 0;

                // 为每个案件发出解冻事件，便于外部系统追踪
                emit Events.DepositUnfrozen(
                    caseId,
                    user,
                    frozenAmount,
                    block.timestamp
                );
            }
        }

        // 清空活跃案件列表和相关计数
        delete userActiveCases[user];
        profile.activeCaseCount = 0;
        profile.requiredAmount = 0; // 重置所需保证金

        // 最终状态一致性检查：检测并处理系统异常
        if (profile.frozenAmount > 0) {
            //检测到系统状态不一致！
            // 这是一个严重的系统异常，表明资金账目存在偏差

            // 记录异常检测事件，便于系统监控和调试
            emit Events.SystemStateInconsistencyDetected(
                user,
                0, // 不特定于某个案件
                "FundManager._forceExitAllCases",
                "Residual frozen amount after case exits",
                0, // 期望的冻结金额应该为0
                profile.frozenAmount, // 实际残余的冻结金额
                block.timestamp
            );

            // 记录数据修复事件
            uint256 repairedAmount = profile.frozenAmount;
            profile.frozenAmount = 0; // 强制归零，确保状态一致性

            emit Events.SystemDataRepaired(
                user,
                0,
                "FundManager._forceExitAllCases",
                "Force reset residual frozen amount to zero",
                repairedAmount, // 修复前的错误值
                0, // 修复后的正确值
                block.timestamp
            );

            // 发出系统异常警告，表明这是一个需要关注的问题
            emit Events.SystemAnomalyWarning(
                "FUND_MANAGEMENT",
                "Detected inconsistent frozen amount during force exit, auto-repaired",
                3, // 中等严重程度
                address(this),
                abi.encode(user, repairedAmount, totalUnfrozen, initialFrozenAmount),
                block.timestamp
            );
        }

        // 验证总解冻金额的一致性
        if (totalUnfrozen != initialFrozenAmount && initialFrozenAmount > 0) {
            // 检测到解冻金额与初始冻结金额不一致
            emit Events.SystemStateInconsistencyDetected(
                user,
                0,
                "FundManager._forceExitAllCases",
                "Total unfrozen amount mismatch with initial frozen amount",
                initialFrozenAmount, // 期望解冻的总金额
                totalUnfrozen, // 实际解冻的总金额
                block.timestamp
            );
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
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused notZeroAddress(user) {

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
            "Case processing",
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
        uint256 amount,
        DataStructures.UserRole role
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

        // 更新角色映射
        userRole[user] = role;

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

    function hasUserRole(address user, DataStructures.UserRole role) external view returns (bool) {
        return userRole[user] == role;
    }
}
