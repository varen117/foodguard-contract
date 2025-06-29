// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用最新稳定版本的Solidity

import "../libraries/DataStructures.sol"; // 导入数据结构库
import "../libraries/Errors.sol"; // 导入错误处理库
import "../libraries/Events.sol"; // 导入事件库
import "../libraries/CommonModifiers.sol";
import "../interfaces/IModuleInterfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // 导入所有权控制

/**
 * @title RewardPunishmentManager
 * @author Food Safety Governance Team
 * @notice 奖惩管理模块，负责根据投票和质疑结果计算和分配奖励与惩罚
 * @dev 根据流程图逻辑处理复杂的奖惩计算，管理用户诚信状态
 * 这是食品安全治理系统的奖惩核心，实现了完整的激励机制：
 * 1. 多角色奖惩：处理投诉者、企业、验证者、质疑者的奖惩逻辑
 * 2. 动态计算：根据风险等级、参与表现、历史声誉动态计算奖惩金额
 * 3. 诚信管理：实时更新用户诚信状态，影响后续参与权限
 * 4. 声誉系统：维护长期声誉分数，实现声誉激励
 * 5. 公平机制：确保正确参与者获得奖励，错误参与者承担相应惩罚
 */
contract RewardPunishmentManager is Ownable {
    // ==================== 状态变量 ====================

    /// @notice 治理合约地址 - 唯一有权调用奖惩处理函数的合约
    /// @dev 确保奖惩处理只能由经过验证的治理流程触发
    address public governanceContract;

    /// @notice 资金管理合约地址 - 处理奖励发放和惩罚扣除的合约
    /// @dev 与资金管理模块协作，实现奖惩的实际执行
    address public fundManager;

    /// @notice 用户状态映射 - 记录每个用户的完整状态信息
    /// @dev 包括诚信状态、声誉分数、参与次数等关键信息
    mapping(address => DataStructures.UserStatus) public userStatuses;

    /// @notice 案件奖惩记录映射 - 每个案件的详细奖惩分配记录
    /// @dev 键值对：caseId => RewardPunishmentRecord，记录案件相关的所有奖惩信息
    mapping(uint256 => RewardPunishmentRecord) public caseRewards;

    /// @notice 用户总奖励统计 - 用户历史累计获得的奖励金额
    /// @dev 用于声誉计算和用户激励展示
    mapping(address => uint256) public totalUserRewards;

    /// @notice 用户总惩罚统计 - 用户历史累计承担的惩罚金额
    /// @dev 用于风险评估和用户信用记录
    mapping(address => uint256) public totalUserPunishments;

    /// @notice 案件是否已处理奖惩标记 - 防止重复处理同一案件
    /// @dev 键值对：caseId => processed，确保每个案件只处理一次奖惩
    mapping(uint256 => bool) public caseProcessed;

    // ==================== 结构体定义 ====================

    /**
     * @notice 奖惩记录结构体 - 记录单个案件的完整奖惩信息
     * @dev 这是奖惩系统的核心数据结构，包含案件的所有奖惩细节
     */
    struct RewardPunishmentRecord {
        uint256 caseId; // 案件ID - 唯一标识符
        bool complaintUpheld; // 投诉是否成立 - 决定奖惩方向的关键标志
        DataStructures.RiskLevel riskLevel; // 风险等级 - 影响奖惩金额的重要因素
        uint256 totalRewardAmount; // 总奖励金额 - 该案件发放的奖励总额
        uint256 totalPunishmentAmount; // 总惩罚金额 - 该案件执行的惩罚总额
        bool isProcessed; // 是否已处理 - 避免重复处理的标志位
        uint256 processTime; // 处理时间 - 记录奖惩处理的时间戳
        // 个人奖惩映射 - 记录每个参与者的具体奖惩情况
        mapping(address => PersonalReward) personalRewards; // 个人奖励详情
        mapping(address => PersonalPunishment) personalPunishments; // 个人惩罚详情
        // 参与者列表 - 便于遍历和统计
        address complainantRewardRecipient; // 获得补偿的投诉用户
        address complainantPunishmentTarget; // 获得惩罚的投诉用户
        address enterpriseRewardRecipients; // 获得奖励的企业用户
        address enterprisePunishmentTargets; // 获得惩罚的企业用户
        address[] daoRewardRecipients; // 获得奖励的dao用户列表
        address[] daoRewardPunishmentTargets;//获得惩罚的dao用户列表
    }

    /**
     * @notice 个人奖励记录 - 记录单个用户在特定案件中的奖励信息
     */
    struct PersonalReward {
        uint256 amount; // 奖励金额
        string reason; // 奖励原因
        bool claimed; // 是否已领取
    }

    /**
     * @notice 个人惩罚记录 - 记录单个用户在特定案件中的惩罚信息
     */
    struct PersonalPunishment {
        uint256 amount; // 惩罚金额
        string reason; // 惩罚原因
        bool executed; // 是否已执行
    }

    /**
     * @notice 奖惩计算参数
     */
    struct CalculationParams {
        uint256 caseId;
        bool complaintUpheld;
        DataStructures.RiskLevel riskLevel;
        address complainant;
        address enterprise;
        address[] validators;
        address[] challengers;
        mapping(address => DataStructures.VoteInfo) votes;
        mapping(address => bool) challengeResults;
    }

    // ==================== 修饰符 ====================

    /**
     * @notice 只有治理合约可以调用
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }

    /**
     * @notice 检查案件是否未处理
     */
    modifier caseNotProcessed(uint256 caseId) {
        if (caseProcessed[caseId]) {
            revert Errors.RewardPunishmentAlreadyProcessed(caseId);
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address _admin) Ownable(_admin) {
    }

    // ==================== 核心奖惩处理函数 ====================

    /**
     * @notice 处理案件奖惩（主要入口函数）
     * @param caseId 案件ID
     */
    function processCaseRewardPunishment(
        uint256 caseId,
        address complainantRewards,
        address enterpriseRewards,
        address[] memory daoRewards,
        address complainantPunishments,
        address enterprisePunishments,
        address[] memory daoPunishments,
        bool complaintUpheld,
        DataStructures.RiskLevel riskLevel
    ) external onlyGovernance caseNotProcessed(caseId) {
        RewardPunishmentRecord storage record = caseRewards[caseId];
        if (record.isProcessed) {
            revert Errors.RewardPunishmentAlreadyProcessed(caseId);
        }
        if (complainantRewards == address(0) &&
        enterpriseRewards == address(0) &&
        daoRewards.length == 0 &&
        complainantPunishments == address(0) &&
        enterprisePunishments == address(0) &&
            daoPunishments.length == 0) {
            revert Errors.NoRewardOrPunishmentMembers("No Reward or Punishment Members");
        }

        // 创建奖惩记录
        record.caseId = caseId;
        record.complainantRewardRecipient = complainantRewards;
        record.complainantPunishmentTarget = complainantPunishments;
        record.enterpriseRewardRecipients = enterpriseRewards;
        record.enterprisePunishmentTargets = enterprisePunishments;
        record.daoRewardRecipients = daoRewards;
        record.daoRewardPunishmentTargets = daoPunishments;
        // 投诉是否成立
        record.complaintUpheld = complaintUpheld;
        // 风险等级
        record.riskLevel = riskLevel;
        //处理时间
        record.processTime = block.timestamp;
        record.isProcessed = false;

        // 获取系统配置和用户接口
        IFundManager fundManagerContract = IFundManager(fundManager);

        // 计算总奖励金额和总惩罚金额
        _calculateTotalAmounts(record, fundManagerContract);

        // 分配奖励和惩罚
        _allocateRewardsAndPunishments(record, fundManagerContract);

        // 发放奖励到获胜者保证金、扣除罚金从失败者保证金
        _distributeRewardsToDeposits(record, fundManagerContract);

        emit Events.RewardPunishmentCalculationStarted(
            caseId,
            complaintUpheld,
            block.timestamp
        );

        // 标记案件已处理
        caseProcessed[caseId] = true;
        record.isProcessed = true;
    }

    /**
     * @notice 计算总奖励金额和总惩罚金额
     */
    function _calculateTotalAmounts(
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        // 获取系统配置
        DataStructures.SystemConfig memory config = fundManagerContract.getSystemConfig();

        // 根据风险等级确定惩罚比例
        uint256 punishmentRate;
        if (record.riskLevel == DataStructures.RiskLevel.HIGH) {
            punishmentRate = 100; // 高风险：100%的保证金作为惩罚
        } else if (record.riskLevel == DataStructures.RiskLevel.MEDIUM) {
            punishmentRate = 50;  // 中风险：50%的保证金作为惩罚
        } else {
            punishmentRate = 20;  // 低风险：20%的保证金作为惩罚
        }

        // 计算总惩罚金额
        uint256 totalPunishments = 0;

        // 计算DAO成员惩罚金额（验证者和质疑者）
        for (uint256 i = 0; i < record.daoRewardPunishmentTargets.length; i++) {
            uint256 userDeposit = fundManagerContract.getCaseFrozenDeposit(record.caseId, record.daoRewardPunishmentTargets[i]);
            totalPunishments += (userDeposit * punishmentRate) / 100;
        }

        if (record.complaintUpheld) {
            // 投诉成立：企业受惩罚
            if (record.enterprisePunishmentTargets != address(0)) {
                uint256 userDeposit = fundManagerContract.getCaseFrozenDeposit(record.caseId, record.enterprisePunishmentTargets);
                totalPunishments += (userDeposit * punishmentRate) / 100;
            }
            } else {
            // 投诉不成立：投诉者受惩罚
            if (record.complainantPunishmentTarget != address(0)) {
                uint256 userDeposit = fundManagerContract.getCaseFrozenDeposit(record.caseId, record.complainantPunishmentTarget);
                totalPunishments += (userDeposit * punishmentRate) / 100;
            }
        }

        record.totalPunishmentAmount = totalPunishments;

        // 计算可用于奖励的金额
        uint256 availableRewardAmount;
        if (record.complaintUpheld) {
            // 投诉成立：totalPunishments的80%用于奖励金额，20%存入基金库
            availableRewardAmount = (totalPunishments * 80) / 100;
        } else {
            // 投诉不成立：全部惩罚金额用于奖励
            availableRewardAmount = totalPunishments;
        }

        record.totalRewardAmount = availableRewardAmount;
    }

    /**
     * @notice 分配奖励和惩罚
     */
    function _allocateRewardsAndPunishments(
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        // 获取系统配置
        DataStructures.SystemConfig memory config = fundManagerContract.getSystemConfig();

        // 计算各角色的奖励权重（基于最小保证金）
        uint256 complainantWeight = config.minComplaintDeposit;
        uint256 enterpriseWeight = config.minEnterpriseDeposit;
        uint256 daoWeight = config.minDaoDeposit;

        // 计算总权重
        uint256 totalRewardRecipients = (record.complainantRewardRecipient != address(0) ? 1 : 0) +
                                       (record.enterpriseRewardRecipients != address(0) ? 1 : 0) +
                                       record.daoRewardRecipients.length;

        if (totalRewardRecipients > 0) {
            uint256 totalWeight = (record.complainantRewardRecipient != address(0) ? complainantWeight : 0) +
                                 (record.enterpriseRewardRecipients != address(0) ? enterpriseWeight : 0) +
                                 record.daoRewardRecipients.length * daoWeight;

            // 分配投诉者奖励（如果有）
            if (record.complainantRewardRecipient != address(0)) {
                uint256 complainantRewardAmount = (record.totalRewardAmount * complainantWeight) / totalWeight;
                record.personalRewards[record.complainantRewardRecipient] = PersonalReward({
                    amount: complainantRewardAmount,
                    reason: "Complaint reward",
                    claimed: false
                });
            }

            // 分配企业奖励（如果有）
            if (record.enterpriseRewardRecipients != address(0)) {
                uint256 enterpriseRewardAmount = (record.totalRewardAmount * enterpriseWeight) / totalWeight;
                record.personalRewards[record.enterpriseRewardRecipients] = PersonalReward({
                    amount: enterpriseRewardAmount,
                    reason: "Enterprise compensation",
                    claimed: false
                });
            }

            // 分配DAO成员奖励
            _allocateRoleRewards(
                record.daoRewardRecipients,
                record,
                daoWeight,
                totalWeight,
                "DAO member reward"
            );
        }

        // 分配惩罚 - 根据实际保证金和风险等级计算
        uint256 punishmentRate;
        if (record.riskLevel == DataStructures.RiskLevel.HIGH) {
            punishmentRate = 100; // 高风险：100%的保证金作为惩罚
        } else if (record.riskLevel == DataStructures.RiskLevel.MEDIUM) {
            punishmentRate = 50;  // 中风险：50%的保证金作为惩罚
        } else {
            punishmentRate = 20;  // 低风险：20%的保证金作为惩罚
        }

        // 分配投诉者惩罚（如果有）
        if (record.complainantPunishmentTarget != address(0)) {
            _allocateSinglePunishment(
                record.complainantPunishmentTarget,
                record,
                punishmentRate,
                fundManagerContract,
                "False complaint penalty"
            );
        }

        // 分配企业惩罚（如果有）
        if (record.enterprisePunishmentTargets != address(0)) {
            _allocateSinglePunishment(
                record.enterprisePunishmentTargets,
                record,
                punishmentRate,
                fundManagerContract,
                "Food safety violation penalty"
            );
        }

        // 分配DAO成员惩罚
        _allocateRolePunishmentsByDeposit(
            record.daoRewardPunishmentTargets,
            record,
            punishmentRate,
            fundManagerContract,
            "Incorrect validation/challenge penalty"
        );
    }

    /**
     * @notice 为单个地址分配基于保证金的惩罚
     */
    function _allocateSinglePunishment(
        address target,
        RewardPunishmentRecord storage record,
        uint256 punishmentRate,
        IFundManager fundManagerContract,
        string memory reason
    ) internal {
        if (target != address(0)) {
            uint256 userDeposit = fundManagerContract.getCaseFrozenDeposit(record.caseId, target);
            uint256 punishmentAmount = (userDeposit * punishmentRate) / 100;

            record.personalPunishments[target] = PersonalPunishment({
                amount: punishmentAmount,
                reason: reason,
                executed: false
            });
        }
    }

    /**
     * @notice 为多个地址分配基于保证金的惩罚
     */
    function _allocateRolePunishmentsByDeposit(
        address[] memory targets,
        RewardPunishmentRecord storage record,
        uint256 punishmentRate,
        IFundManager fundManagerContract,
        string memory reason
    ) internal {
        for (uint256 i = 0; i < targets.length; i++) {
            uint256 userDeposit = fundManagerContract.getCaseFrozenDeposit(record.caseId, targets[i]);
            uint256 punishmentAmount = (userDeposit * punishmentRate) / 100;

            record.personalPunishments[targets[i]] = PersonalPunishment({
                amount: punishmentAmount,
                reason: reason,
                executed: false
            });
        }
    }

    /**
     * @notice 为特定角色分配奖励
     */
    function _allocateRoleRewards(
        address[] memory recipients,
        RewardPunishmentRecord storage record,
        uint256 roleWeight,
        uint256 totalWeight,
        string memory reason
    ) internal {
        if (recipients.length == 0) return;

        uint256 roleRewardAmount = (record.totalRewardAmount * recipients.length * roleWeight) / totalWeight;
        uint256 individualReward = roleRewardAmount / recipients.length;

        for (uint256 i = 0; i < recipients.length; i++) {
            record.personalRewards[recipients[i]] = PersonalReward({
                amount: individualReward,
                reason: reason,
                claimed: false
            });
        }
    }

    /**
     * @notice 发放奖励到用户保证金余额
     */
    function _distributeRewardsToDeposits(
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        // 发放投诉者奖励（如果有）
        if (record.complainantRewardRecipient != address(0)) {
            PersonalReward storage reward = record.personalRewards[record.complainantRewardRecipient];

            if (reward.amount > 0 && !reward.claimed) {
                // 调用fundManager增加用户保证金
                fundManagerContract.addRewardToDeposit(record.complainantRewardRecipient, reward.amount);

                // 更新用户统计
                totalUserRewards[record.complainantRewardRecipient] += reward.amount;

                // 标记为已领取
                reward.claimed = true;

                // 发送奖励分发事件
                emit Events.RewardDistributed(
                    record.caseId,
                    record.complainantRewardRecipient,
                    reward.amount,
                    reward.reason,
                    block.timestamp
                );
            }
        }

        // 发放企业奖励（如果有）
        if (record.enterpriseRewardRecipients != address(0)) {
            PersonalReward storage reward = record.personalRewards[record.enterpriseRewardRecipients];

            if (reward.amount > 0 && !reward.claimed) {
                // 调用fundManager增加用户保证金
                fundManagerContract.addRewardToDeposit(record.enterpriseRewardRecipients, reward.amount);

                // 更新用户统计
                totalUserRewards[record.enterpriseRewardRecipients] += reward.amount;

                // 标记为已领取
                reward.claimed = true;

                // 发送奖励分发事件
                emit Events.RewardDistributed(
                    record.caseId,
                    record.enterpriseRewardRecipients,
                    reward.amount,
                    reward.reason,
                    block.timestamp
                );
            }
        }

        // 发放DAO成员奖励
        _distributeRoleRewards(record.daoRewardRecipients, record, fundManagerContract);

        // 执行惩罚
        _executePunishments(record, fundManagerContract);

        // 如果投诉成立，将惩罚的20%存入基金库
        if (record.complaintUpheld) {
            uint256 toFundPool = (record.totalPunishmentAmount * 20) / 100;

            // 这里应该调用fundManager将资金转入基金库
             fundManagerContract._addToFundPool(toFundPool, "Punishment penalty");
        }
    }

    /**
     * @notice 执行惩罚
     */
    function _executePunishments(
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        // 执行投诉者惩罚（如果有）
        if (record.complainantPunishmentTarget != address(0)) {
            _executeSinglePunishment(record.complainantPunishmentTarget, record, fundManagerContract);
        }

        // 执行企业惩罚（如果有）
        if (record.enterprisePunishmentTargets != address(0)) {
            _executeSinglePunishment(record.enterprisePunishmentTargets, record, fundManagerContract);
        }

        // 执行DAO成员惩罚
        _executeRolePunishments(record.daoRewardPunishmentTargets, record, fundManagerContract);
    }

    /**
     * @notice 执行单个地址的惩罚
     */
    function _executeSinglePunishment(
        address target,
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        PersonalPunishment storage punishment = record.personalPunishments[target];

        if (punishment.amount > 0 && !punishment.executed) {
            // 更新用户统计
            totalUserPunishments[target] += punishment.amount;
            fundManagerContract.decreaseRewardToDeposit(target, punishment.amount);
            // 标记为已执行
            punishment.executed = true;

            // 发送惩罚执行事件
            emit Events.PunishmentExecuted(
                record.caseId,
                target,
                punishment.amount,
                punishment.reason,
                block.timestamp
            );
        }
    }

    /**
     * @notice 执行多个地址的惩罚
     */
    function _executeRolePunishments(
        address[] memory targets,
        RewardPunishmentRecord storage record
    ) internal {
        for (uint256 i = 0; i < targets.length; i++) {
            _executeSinglePunishment(targets[i], record);
        }
    }

    /**
     * @notice 为特定角色分发奖励到保证金
     */
    function _distributeRoleRewards(
        address[] memory recipients,
        RewardPunishmentRecord storage record,
        IFundManager fundManagerContract
    ) internal {
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            PersonalReward storage reward = record.personalRewards[recipient];

            if (reward.amount > 0 && !reward.claimed) {
                // 调用fundManager增加用户保证金
                fundManagerContract.addRewardToDeposit(recipient, reward.amount);

                // 更新用户统计
                totalUserRewards[recipient] += reward.amount;

                // 标记为已领取
                reward.claimed = true;

                // 发送奖励分发事件
                emit Events.RewardDistributed(
                    record.caseId,
                    recipient,
                    reward.amount,
                    reward.reason,
                    block.timestamp
                );
            }
        }
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取案件奖惩记录
     */
    function getCaseRewardRecord(
        uint256 caseId
    )
    external
    view
    returns (
        uint256, // caseId
        bool, // complaintUpheld
        uint8, // riskLevel
        uint256, // totalRewardAmount
        uint256, // totalPunishmentAmount
        bool, // isProcessed
        uint256 // processTime
    )
    {
        RewardPunishmentRecord storage record = caseRewards[caseId];

        return (
            record.caseId,
            record.complaintUpheld,
            uint8(record.riskLevel),
            record.totalRewardAmount,
            record.totalPunishmentAmount,
            record.isProcessed,
            record.processTime
        );
    }

    /**
     * @notice 获取个人奖励信息
     */
    function getPersonalReward(
        uint256 caseId,
        address user
    ) external view returns (PersonalReward memory) {
        return caseRewards[caseId].personalRewards[user];
    }

    /**
     * @notice 获取个人惩罚信息
     */
    function getPersonalPunishment(
        uint256 caseId,
        address user
    ) external view returns (PersonalPunishment memory) {
        return caseRewards[caseId].personalPunishments[user];
    }

    /**
     * @notice 获取用户状态
     */
    function getUserStatus(
        address user
    ) external view returns (DataStructures.UserStatus memory) {
        return userStatuses[user];
    }

    /**
     * @notice 获取用户总奖励和惩罚统计
     */
    function getUserStats(
        address user
    )
    external
    view
    returns (
        uint256 totalRewards,
        uint256 totalPunishments,
        uint256 participationCount,
        uint256 reputationScore
    )
    {
        DataStructures.UserStatus storage status = userStatuses[user];

        return (
            totalUserRewards[user],
            totalUserPunishments[user],
            status.participationCount,
            status.reputationScore
        );
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyOwner {
        if (_governanceContract == address(0)) {
            revert Errors.ZeroAddress();
        }
        governanceContract = _governanceContract;
    }

    /**
     * @notice 设置资金管理合约地址
     */
    function setFundManager(address _fundManager) external onlyOwner {
        if (_fundManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        fundManager = _fundManager;
    }


}
