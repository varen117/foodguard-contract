// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，确保安全性和最新特性

/**
 * @title DataStructures
 * @author Food Safety Governance Team
 * @notice 简化的数据结构定义，只保留核心业务必需的结构
 */
library DataStructures {
    // ==================== 核心枚举 ====================

    enum CaseStatus {
        PENDING,            // 待处理
        DEPOSIT_LOCKED,     // 保证金已锁定
        VOTING,             // 投票中
        CHALLENGING,        // 质疑中
        REWARD_PUNISHMENT,  // 奖惩阶段
        COMPLETED,          // 已完成
        CANCELLED           // 已取消
    }

    enum RiskLevel {
        LOW,     // 低风险
        MEDIUM,  // 中风险
        HIGH     // 高风险
    }

    enum VoteChoice {
        SUPPORT_COMPLAINT,  // 支持投诉
        REJECT_COMPLAINT    // 反对投诉
    }

    enum ChallengeChoice {
        SUPPORT_VALIDATOR,  // 支持验证者
        OPPOSE_VALIDATOR    // 反对验证者
    }

    enum UserRole {
        COMPLAINANT,    // 投诉者
        ENTERPRISE,     // 企业
        DAO_MEMBER      // DAO成员（可以担任验证者和质疑者）
    }

    enum DepositStatus {
        HEALTHY,        // 健康状态
        WARNING,        // 警告状态
        RESTRICTED,     // 限制状态
        LIQUIDATION     // 清算状态
    }

    enum IntegrityStatus {
        HONEST,         // 诚实
        DISHONEST       // 不诚实
    }

    enum RewardPunishmentStatus {
        NONE,           // 无
        REWARD,         // 奖励
        PUNISHMENT      // 惩罚
    }

    enum ChallengeType {
        EVIDENCE_DISPUTE,    // 证据争议
        PROCESS_VIOLATION,   // 流程违规
        BIAS_ACCUSATION     // 偏见指控
    }

    // ==================== 核心结构体 ====================

    /**
     * @notice 投票信息
     */
    struct VoteInfo {
        address voter;
        VoteChoice choice;
        uint256 timestamp;
        string reason;
        string evidenceHash;
        bool hasVoted;
    }

    /**
     * @notice 质疑信息
     */
    struct ChallengeInfo {
        address challenger;
        address targetValidator;
        ChallengeChoice choice;
        string reason;
        string evidenceHash;
        uint256 timestamp;
        uint256 challengeDeposit;
    }

    /**
     * @notice 质疑投票信息
     */
    struct ChallengeVotingInfo {
        address targetValidator;
        address[] supporters;
        address[] opponents;
    }

    /**
     * @notice 验证者信息
     */
    struct ValidatorInfo {
        address validatorAddress;
        uint256 stake;
        uint256 reputationScore;
        uint256 totalCasesParticipated;
        uint256 successfulValidations;
        bool isActive;
        uint256 lastActiveTime;
    }

    /**
     * @notice 用户状态
     */
    struct UserStatus {
        uint256 reputationScore;
        uint256 participationCount;
        bool isActive;
        uint256 lastActiveTime;
        IntegrityStatus integrity;
        RewardPunishmentStatus rewardPunishment;
    }

    /**
     * @notice 资金池
     */
    struct FundPool {
        uint256 totalBalance;
        uint256 rewardPool;
        uint256 operationalFund;
        uint256 reserveBalance;
    }

    /**
     * @notice 系统配置
     */
    struct SystemConfig {
        uint256 minComplaintDeposit;
        uint256 minEnterpriseDeposit;
        uint256 minDaoDeposit;
        uint256 votingPeriod;
        uint256 challengePeriod;
        uint256 minValidators;
        uint256 maxValidators;
        uint256 rewardPoolPercentage;
        uint256 operationalFeePercentage;
    }

    /**
     * @notice 动态保证金配置
     */
    struct DynamicDepositConfig {
        uint256 warningThreshold;           // 130%
        uint256 restrictionThreshold;       // 120%
        uint256 liquidationThreshold;       // 110%
        uint256 highRiskMultiplier;         // 200%
        uint256 mediumRiskMultiplier;       // 150%
        uint256 lowRiskMultiplier;          // 120%
        uint256 reputationDiscountThreshold; // 800分
        uint256 reputationDiscountRate;     // 20%
    }

    /**
     * @notice 用户保证金档案
     */
    struct UserDepositProfile {
        uint256 totalDeposit;
        uint256 frozenAmount;
        uint256 requiredAmount;
        uint256 activeCaseCount;
        DepositStatus status;
        uint256 lastWarningTime;
        bool operationRestricted;
    }
}
