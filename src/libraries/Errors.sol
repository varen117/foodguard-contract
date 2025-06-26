// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有自定义错误
 * @dev 使用自定义错误而不是 require + string 来节约 gas
 */
library Errors {
    // ==================== 通用错误 ====================

    /// @notice 零地址错误
    error ZeroAddress();

    /// @notice 无效的金额
    error InvalidAmount(uint256 provided, uint256 required);

    /// @notice 权限不足
    error InsufficientPermission(address caller, string requiredRole);

    /// @notice 操作超时
    error OperationTimeout(uint256 deadline, uint256 currentTime);

    /// @notice 重复操作
    error DuplicateOperation(address user, string operation);

    /// @notice 系统暂停
    error SystemPaused();

    // ==================== 案件相关错误 ====================

    /// @notice 案件不存在
    error CaseNotFound(uint256 caseId);

    /// @notice 案件状态无效
    error InvalidCaseStatus(
        uint256 caseId,
        uint8 currentStatus,
        uint8 requiredStatus
    );

    /// @notice 案件已完成
    error CaseAlreadyCompleted(uint256 caseId);

    /// @notice 案件已取消
    error CaseAlreadyCancelled(uint256 caseId);

    /// @notice 案件风险等级无效
    error InvalidRiskLevel(uint8 riskLevel);

    // ==================== 投诉相关错误 ====================

    /// @notice 投诉保证金不足
    error InsufficientComplaintDeposit(uint256 provided, uint256 required);

    /// @notice 投诉者不能对自己的企业投诉
    error CannotComplainAgainstSelf(address complainant, address enterprise);

    /// @notice 投诉内容为空
    error EmptyComplaintContent();

    /// @notice 投诉证据不足
    error InsufficientEvidence(uint256 provided, uint256 required);

    /// @notice 重复投诉
    error DuplicateComplaint(address complainant, address enterprise);

    // ==================== 企业相关错误 ====================

    /// @notice 企业保证金不足
    error InsufficientEnterpriseDeposit(uint256 provided, uint256 required);

    /// @notice 企业未注册
    error EnterpriseNotRegistered(address enterprise);

    /// @notice 企业已被暂停
    error EnterpriseSuspended(address enterprise);

    /// @notice 企业保证金已锁定
    error EnterpriseDepositLocked(address enterprise);

    // ==================== 验证者相关错误 ====================

    /// @notice 验证者数量不足
    error InsufficientValidators(uint256 current, uint256 required);

    /// @notice 验证者数量超限
    error TooManyValidators(uint256 current, uint256 maximum);

    /// @notice 不是有效的验证者
    error NotAuthorizedValidator(address user);

    /// @notice 验证者已质疑过
    error ValidatorAlreadyChallenged(address validator);

    /// @notice 验证者声誉不足
    error InsufficientValidatorReputation(
        address validator,
        uint256 current,
        uint256 required
    );

    /// @notice 验证者保证金不足
    error InsufficientValidatorDeposit(uint256 provided, uint256 required);

    // ==================== 投票相关错误 ====================

    /// @notice 投票期未开始
    error VotingNotStarted(uint256 caseId);

    /// @notice 投票期已结束
    error VotingPeriodEnded(uint256 deadline, uint256 currentTime);

    /// @notice 已经投过票
    error AlreadyVoted(address voter, uint256 caseId);

    /// @notice 投票选择无效
    error InvalidVoteChoice(uint8 choice);

    /// @notice 投票理由为空
    error EmptyVoteReason();

    /// @notice 验证者未参与此案件
    error ValidatorNotParticipating(address validator, uint256 caseId);

    // ==================== 质疑相关错误 ====================

    /// @notice 质疑期未开始
    error ChallengeNotStarted(uint256 caseId);

    /// @notice 质疑期已结束
    error ChallengePeriodEnded(uint256 deadline, uint256 currentTime);

    /// @notice 质疑保证金不足
    error InsufficientChallengeDeposit(uint256 provided, uint256 required);

    /// @notice 已经质疑过该验证者
    error AlreadyChallenged(address challenger, address validator);

    /// @notice 不能质疑自己
    error CannotChallengeSelf(address challenger);

    /// @notice 质疑选择无效
    error InvalidChallengeChoice(uint8 choice);

    /// @notice 质疑理由为空
    error EmptyChallengeReason();

    /// @notice 被质疑的验证者未参与投票
    error TargetValidatorNotParticipating(address validator, uint256 caseId);

    // ==================== 资金相关错误 ====================

    /// @notice 余额不足
    error InsufficientBalance(
        address user,
        uint256 required,
        uint256 available
    );

    /// @notice 保证金已被冻结
    error DepositAlreadyFrozen(address user, uint256 amount);

    /// @notice 资金转移失败
    error TransferFailed(address to, uint256 amount);

    /// @notice 资金池余额不足
    error InsufficientFundPool(uint256 required, uint256 available);

    /// @notice 奖励计算错误
    error RewardCalculationError(string reason);

    /// @notice 惩罚计算错误
    error PunishmentCalculationError(string reason);

    // ==================== 动态保证金相关错误 ====================

    /// @notice 保证金状态异常
    error InvalidDepositStatus(address user, uint8 currentStatus, uint8 expectedStatus);

    /// @notice 用户操作被限制
    error UserOperationRestricted(address user, string reason);

    /// @notice 保证金不足以满足动态要求
    error InsufficientDynamicDeposit(address user, uint256 required, uint256 available);

    /// @notice 用户处于清算状态
    error UserInLiquidation(address user);

    /// @notice 互助池相关错误
    error MutualPoolError(string reason);

    /// @notice 互助池余额不足
    error InsufficientPoolBalance(uint256 required, uint256 available);

    /// @notice 用户未加入互助池
    error NotPoolMember(address user);

    /// @notice 声誉分数过低
    error InsufficientReputation(address user, uint256 current, uint256 required);

    /// @notice 并发案件数量过多
    error TooManyConcurrentCases(address user, uint256 current, uint256 limit);

    // ==================== 奖惩相关错误 ====================

    /// @notice 奖惩阶段未开始
    error RewardPunishmentNotStarted(uint256 caseId);

    /// @notice 奖惩已经处理过
    error RewardPunishmentAlreadyProcessed(uint256 caseId);

    /// @notice 无效的奖惩类型
    error InvalidRewardPunishmentType(uint8 rewardType);

    /// @notice 奖励金额超出限制
    error RewardAmountExceeded(uint256 amount, uint256 limit);

    /// @notice 惩罚金额超出保证金
    error PunishmentExceedsDeposit(uint256 punishment, uint256 deposit);

    // ==================== 时间相关错误 ====================

    /// @notice 时间戳无效
    error InvalidTimestamp(uint256 provided, uint256 current);

    /// @notice 事件时间不能晚于投诉时间
    error IncidentTimeAfterComplaint(
        uint256 incidentTime,
        uint256 complaintTime
    );

    /// @notice 操作过早
    error OperationTooEarly(uint256 currentTime, uint256 allowedTime);

    /// @notice 操作过晚
    error OperationTooLate(uint256 currentTime, uint256 deadline);

    // ==================== 证据相关错误 ====================

    /// @notice 证据描述为空
    error EmptyEvidenceDescription();

    /// @notice 无效的 IPFS 哈希
    error InvalidIPFSHash(string hash);

    /// @notice 证据类型无效
    error InvalidEvidenceType(string evidenceType);

    /// @notice 证据已存在
    error EvidenceAlreadyExists(string ipfsHash);

    // ==================== 配置相关错误 ====================

    /// @notice 配置参数无效
    error InvalidConfiguration(string parameter, uint256 value);

    /// @notice 配置超出范围
    error ConfigurationOutOfRange(
        string parameter,
        uint256 value,
        uint256 min,
        uint256 max
    );

    /// @notice 只有管理员可以修改配置
    error OnlyAdminCanModifyConfig();

    // ==================== 随机数相关错误 ====================

    /// @notice 随机数生成失败
    error RandomGenerationFailed();

    /// @notice 随机数种子无效
    error InvalidRandomSeed();

    /// @notice 验证者选择失败
    error ValidatorSelectionFailed(string reason);
}
