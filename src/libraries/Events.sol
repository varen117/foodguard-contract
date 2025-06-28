// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DataStructures.sol";

/**
 * @title Events
 * @author Food Safety Governance Team
 * @notice 简化的事件定义，只保留核心业务必需的事件
 */
library Events {
    // ==================== 用户管理事件 ====================

    event UserRegistered(
        address indexed user,
        bool isEnterprise,
        uint256 depositAmount,
        uint256 timestamp
    );

    // ==================== 案件管理事件 ====================

    event ComplaintCreated(
        uint256 indexed caseId,
        address indexed complainant,
        address indexed enterprise,
        string complaintTitle,
        DataStructures.RiskLevel riskLevel,
        uint256 timestamp
    );

    event CaseStatusUpdated(
        uint256 indexed caseId,
        DataStructures.CaseStatus oldStatus,
        DataStructures.CaseStatus newStatus,
        uint256 timestamp
    );

    event CaseCompleted(
        uint256 indexed caseId,
        bool complaintUpheld,
        uint256 totalRewardAmount,
        uint256 totalPunishmentAmount,
        uint256 timestamp
    );

    // ==================== 投票管理事件 ====================

    event ValidatorsSelected(
        uint256 indexed caseId,
        address[] validators,
        uint256 startTime,
        uint256 endTime,
        uint256 timestamp

    );

    event VoteSubmitted(
        uint256 indexed caseId,
        address indexed voter,
        DataStructures.VoteChoice choice,
        uint256 timestamp
    );

    event VotingCompleted(
        uint256 indexed caseId,
        bool complaintUpheld,
        uint256 supportVotes,
        uint256 rejectVotes,
        uint256 timestamp
    );

    // ==================== 质疑管理事件 ====================

    event ChallengePhaseStarted(
        uint256 indexed caseId,
        uint256 endTime,
        uint256 timestamp
    );

    event ChallengeSubmitted(
        uint256 indexed caseId,
        address indexed challenger,
        address indexed targetValidator,
        DataStructures.ChallengeChoice choice,
        string reason,
        uint256 challengeDeposit,
        uint256 timestamp
    );

    event ChallengeCompleted(
        uint256 indexed caseId,
        bool resultChanged,
        uint256 totalChallenges,
        uint256 timestamp
    );

    event ChallengePhaseEnded(
        uint256 indexed caseId,
        uint256 totalChallenges,
        bool resultChanged,
        uint256 timestamp
    );

    event ChallengeResultProcessed(
        uint256 indexed caseId,
        address indexed challenger,
        address indexed targetValidator,
        bool successful,
        uint256 timestamp
    );

    event EmergencyTriggered(
        uint256 indexed caseId,
        string reason,
        address triggeredBy,
        uint256 timestamp
    );

    // ==================== 奖惩管理事件 ====================

    event RewardPunishmentCalculationStarted(
        uint256 indexed caseId,
        bool complaintUpheld,
        uint256 timestamp
    );

    event RewardDistributed(
        uint256 indexed caseId,
        address indexed recipient,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    event PunishmentExecuted(
        uint256 indexed caseId,
        address indexed target,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    // ==================== 资金管理事件 ====================

    event DepositFrozen(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        DataStructures.RiskLevel riskLevel,
        uint256 timestamp
    );

    event DepositUnfrozen(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event DepositMade(
        address indexed user,
        uint256 amount,
        uint256 totalDeposit,
        uint256 timestamp
    );

    event FundsTransferredFromPool(
        address indexed recipient,
        uint256 amount,
        string purpose,
        uint256 timestamp
    );

    event FundsTransferredToPool(
        address indexed sender,
        uint256 amount,
        string purpose,
        uint256 timestamp
    );

    // ==================== 系统监控事件 ====================

    event BusinessProcessAnomaly(
        uint256 indexed caseId,
        address indexed user,
        string processName,
        string description,
        string action,
        uint256 timestamp
    );

    event RiskWarningPublished(
        address indexed enterprise,
        DataStructures.RiskLevel riskLevel,
        string reason,
        uint256 additionalInfo,
        uint256 timestamp
    );

    event CaseCancelled(
        uint256 indexed caseId,
        string reason,
        address cancelledBy,
        uint256 timestamp
    );
}
