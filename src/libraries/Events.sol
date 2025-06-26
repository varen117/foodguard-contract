// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DataStructures.sol";

/**
 * @title Events
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有事件
 * @dev 事件用于记录重要操作和状态变化，便于前端监听和数据分析
 */
library Events {
    // ==================== 系统管理事件 ====================

    /**
     * @notice 系统暂停/恢复事件
     */
    event SystemPauseStatusChanged(bool isPaused, address operator, uint256 timestamp);

    /**
     * @notice 系统配置更新事件
     */
    event SystemConfigUpdated(
        string configName,
        uint256 oldValue,
        uint256 newValue,
        address operator,
        uint256 timestamp
    );

    /**
     * @notice 管理员权限变更事件
     */
    event AdminRoleChanged(address user, bool isAdmin, address operator, uint256 timestamp);

    // ==================== 用户注册事件 ====================

    /**
     * @notice 用户注册事件
     */
    event UserRegistered(
        address indexed user,
        bool isEnterprise,
        uint256 initialDeposit,
        uint256 timestamp
    );

    /**
     * @notice 验证者注册事件
     */
    event ValidatorRegistered(
        address indexed validator,
        uint256 stake,
        uint256 reputationScore,
        uint256 timestamp
    );

    /**
     * @notice 验证者状态更新事件
     */
    event ValidatorStatusUpdated(
        address indexed validator,
        bool isActive,
        uint256 newReputationScore,
        uint256 timestamp
    );

    // ==================== 投诉相关事件 ====================

    /**
     * @notice 投诉创建事件
     */
    event ComplaintCreated(
        uint256 indexed caseId,
        address indexed complainant,
        address indexed enterprise,
        string complaintTitle,
        DataStructures.RiskLevel riskLevel,
        uint256 timestamp
    );

    /**
     * @notice 投诉证据提交事件
     */
    event ComplaintEvidenceSubmitted(
        uint256 indexed caseId,
        address indexed submitter,
        string ipfsHash,
        string evidenceType,
        uint256 timestamp
    );

    /**
     * @notice 企业回应事件
     */
    event EnterpriseResponse(
        uint256 indexed caseId,
        address indexed enterprise,
        string responseDescription,
        uint256 evidenceCount,
        uint256 timestamp
    );

    // ==================== 保证金相关事件 ====================

    /**
     * @notice 保证金存入事件
     */
    event DepositMade(
        address indexed user,
        uint256 amount,
        uint256 totalDeposit,
        uint256 timestamp
    );

    /**
     * @notice 保证金冻结事件
     */
    event DepositFrozen(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice 保证金解冻事件
     */
    event DepositUnfrozen(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @notice 保证金扣除事件
     */
    event DepositDeducted(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    // ==================== 动态保证金相关事件 ====================

    /**
     * @notice 保证金状态变更事件
     */
    event DepositStatusChanged(
        address indexed user,
        uint8 oldStatus,
        uint8 newStatus,
        uint256 coverage,
        uint256 timestamp
    );

    /**
     * @notice 保证金警告事件
     */
    event DepositWarning(
        address indexed user,
        uint256 required,
        uint256 available,
        uint256 coverage,
        uint256 timestamp
    );

    /**
     * @notice 用户操作限制事件
     */
    event UserOperationRestricted(
        address indexed user,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice 用户清算事件
     */
    event UserLiquidated(
        address indexed user,
        uint256 liquidatedAmount,
        uint256 penalty,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice 互助池相关事件
     */
    event MutualPoolContribution(
        address indexed user,
        uint256 amount,
        uint256 totalContribution,
        uint256 timestamp
    );

    /**
     * @notice 互助池担保事件
     */
    event MutualPoolCoverage(
        address indexed beneficiary,
        uint256 amount,
        uint256 poolBalance,
        uint256 timestamp
    );

    /**
     * @notice 动态保证金要求更新事件
     */
    event DynamicDepositRequirementUpdated(
        address indexed user,
        uint256 oldRequired,
        uint256 newRequired,
        string reason,
        uint256 timestamp
    );

    // ==================== 验证投票事件 ====================

    /**
     * @notice 验证者选择事件
     */
    event ValidatorsSelected(
        uint256 indexed caseId,
        address[] validators,
        uint256 randomSeed,
        uint256 timestamp
    );

    /**
     * @notice 投票期开始事件
     */
    event VotingPhaseStarted(
        uint256 indexed caseId,
        uint256 votingDeadline,
        uint256 validatorCount,
        uint256 timestamp
    );

    /**
     * @notice 投票提交事件
     */
    event VoteSubmitted(
        uint256 indexed caseId,
        address indexed voter,
        DataStructures.VoteChoice choice,
        string reason,
        uint256 evidenceCount,
        uint256 timestamp
    );

    /**
     * @notice 投票期结束事件
     */
    event VotingPhaseEnded(
        uint256 indexed caseId,
        uint256 supportVotes,
        uint256 rejectVotes,
        uint256 timestamp
    );

    // ==================== 质疑相关事件 ====================

    /**
     * @notice 质疑期开始事件
     */
    event ChallengePhaseStarted(
        uint256 indexed caseId,
        uint256 challengeDeadline,
        uint256 timestamp
    );

    /**
     * @notice 质疑提交事件
     */
    event ChallengeSubmitted(
        uint256 indexed caseId,
        address indexed challenger,
        address indexed targetValidator,
        DataStructures.ChallengeChoice choice,
        string reason,
        uint256 challengeDeposit,
        uint256 timestamp
    );

    /**
     * @notice 质疑期结束事件
     */
    event ChallengePhaseEnded(
        uint256 indexed caseId,
        uint256 totalChallenges,
        bool resultChanged,
        uint256 timestamp
    );

    /**
     * @notice 质疑结果处理事件
     */
    event ChallengeResultProcessed(
        uint256 indexed caseId,
        address indexed challenger,
        address indexed targetValidator,
        bool challengeSuccessful,
        uint256 timestamp
    );

    // ==================== 奖惩相关事件 ====================

    /**
     * @notice 奖惩计算开始事件
     */
    event RewardPunishmentCalculationStarted(
        uint256 indexed caseId,
        bool complaintUpheld,
        uint256 timestamp
    );

    /**
     * @notice 用户诚信状态更新事件
     */
    event UserIntegrityStatusUpdated(
        uint256 indexed caseId,
        address indexed user,
        DataStructures.IntegrityStatus oldStatus,
        DataStructures.IntegrityStatus newStatus,
        DataStructures.RewardPunishmentStatus rewardPunishmentStatus,
        uint256 timestamp
    );

    /**
     * @notice 奖励发放事件
     */
    event RewardDistributed(
        uint256 indexed caseId,
        address indexed recipient,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice 惩罚执行事件
     */
    event PunishmentExecuted(
        uint256 indexed caseId,
        address indexed target,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    // ==================== 资金池事件 ====================

    /**
     * @notice 资金池状态更新事件
     */
    event FundPoolUpdated(
        uint256 totalBalance,
        uint256 rewardPool,
        uint256 operationalFund,
        uint256 emergencyFund,
        uint256 timestamp
    );

    /**
     * @notice 资金转入事件
     */
    event FundsTransferredToPool(
        uint256 indexed caseId,
        uint256 amount,
        string source,
        uint256 timestamp
    );

    /**
     * @notice 资金转出事件
     */
    event FundsTransferredFromPool(
        address indexed recipient,
        uint256 amount,
        string purpose,
        uint256 timestamp
    );

    // ==================== 案件状态事件 ====================

    /**
     * @notice 案件状态更新事件
     */
    event CaseStatusUpdated(
        uint256 indexed caseId,
        DataStructures.CaseStatus oldStatus,
        DataStructures.CaseStatus newStatus,
        address operator,
        uint256 timestamp
    );

    /**
     * @notice 案件完成事件
     */
    event CaseCompleted(
        uint256 indexed caseId,
        bool complaintUpheld,
        uint256 totalRewardAmount,
        uint256 totalPunishmentAmount,
        string finalReport,
        uint256 timestamp
    );

    /**
     * @notice 案件取消事件
     */
    event CaseCancelled(
        uint256 indexed caseId,
        string reason,
        address operator,
        uint256 timestamp
    );

    // ==================== 消息发布事件 ====================

    /**
     * @notice 公告发布事件
     */
    event AnnouncementPublished(
        uint256 indexed caseId,
        string title,
        string content,
        address publisher,
        uint256 timestamp
    );

    /**
     * @notice 风险警告发布事件
     */
    event RiskWarningPublished(
        address indexed enterprise,
        DataStructures.RiskLevel riskLevel,
        string warningContent,
        uint256 relatedCases,
        uint256 timestamp
    );

    // ==================== 紧急事件 ====================

    /**
     * @notice 紧急情况事件
     */
    event EmergencyTriggered(
        uint256 indexed caseId,
        string emergencyType,
        string description,
        address operator,
        uint256 timestamp
    );

    /**
     * @notice 高风险案件处理事件
     */
    event HighRiskCaseProcessed(
        uint256 indexed caseId,
        uint256 totalFrozenAmount,
        address[] affectedUsers,
        uint256 timestamp
    );

    // ==================== 随机数相关事件 ====================

    /**
     * @notice 随机数请求事件
     */
    event RandomnessRequested(
        uint256 indexed caseId,
        uint256 requestId,
        uint256 validatorPoolSize,
        uint256 timestamp
    );

    /**
     * @notice 随机数接收事件
     */
    event RandomnessReceived(
        uint256 indexed caseId,
        uint256 requestId,
        uint256 randomValue,
        uint256 timestamp
    );
}
