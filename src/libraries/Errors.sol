// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @author Food Safety Governance Team
 * @notice 简化的错误定义，只保留核心业务必需的错误
 */
library Errors {
    // ==================== 基础错误 ====================

    error ZeroAddress();
    error InvalidAmount(uint256 provided, uint256 required);
    error InsufficientPermission(address caller, string requiredRole);
    error DuplicateOperation(address user, string operation);

    // ==================== 案件相关错误 ====================

    error CaseNotFound(uint256 caseId);
    error InvalidCaseStatus(uint256 caseId, uint8 currentStatus, uint8 requiredStatus);
    error CaseAlreadyCompleted(uint256 caseId);
    error InvalidRiskLevel(uint8 riskLevel);

    // ==================== 用户和权限错误 ====================

    error UserNotRegistered(address user);
    error UserHasRegistered(address user);
    error InvalidUserRole(address user, uint8 currentRole, uint8 requiredRole);
    error UserRoleIncorrect(address user, uint8 currentRole, string message );
    error EnterpriseNotRegistered(address enterprise);
    error InsufficientReputation(address user, uint256 current, uint256 required);
    error InvalidTimestamp(uint256 provided, uint256 current);
    error InsufficientDynamicDeposit(address user, uint256 required, uint256 available);

    // ==================== 保证金和资金错误 ====================

    error InsufficientComplaintDeposit(uint256 provided, uint256 required);
    error InsufficientEnterpriseDeposit(uint256 provided, uint256 required);
    error InsufficientValidatorDeposit(uint256 provided, uint256 required);
    error InsufficientBalance(address user, uint256 required, uint256 available);
    error TransferFailed(address to, uint256 amount);
    error UserInLiquidation(address user);
    error UserOperationRestricted(address user, string reason);

    // ==================== 投票相关错误 ====================

    error VotingNotStarted(uint256 caseId);
    error VotingPeriodEnded(uint256 deadline, uint256 currentTime);
    error AlreadyVoted(address voter, uint256 caseId);
    error InvalidVoteChoice(uint8 choice);
    error EmptyVoteReason();
    error ValidatorNotParticipating(address validator, uint256 caseId);
    error InsufficientValidators(uint256 current, uint256 required);
    error NotAuthorizedValidator(address user);
    error InsufficientAvailableParticipants(uint256 caseId);

    // ==================== 质疑相关错误 ====================

    error ChallengeNotStarted(uint256 caseId);
    error ChallengePeriodEnded(uint256 deadline, uint256 currentTime);
    error AlreadyChallenged(address challenger, address validator);
    error InvalidChallengeChoice(uint8 choice);
    error EmptyChallengeReason();
    error OperationTooEarly(uint256 currentTime, uint256 requiredTime);
    error EmptyEvidenceDescription();

    // ==================== 奖惩相关错误 ====================

    error RewardPunishmentNotStarted(uint256 caseId);
    error RewardPunishmentAlreadyProcessed(uint256 caseId);
    error RewardCalculationError(string reason);
    error PunishmentCalculationError(string reason);
    error NoRewardOrPunishmentMembers(string reason);

    // ==================== 内容验证错误 ====================

    error EmptyComplaintContent();
    error CannotComplainAgainstSelf(address complainant, address defendant);

    // ==================== 系统配置错误 ====================

    error InvalidConfiguration(string parameter, uint256 value);
}
