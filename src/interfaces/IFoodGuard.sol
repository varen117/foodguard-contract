// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFoodGuard
 * @dev 食品安全治理系统的核心接口定义
 */
interface IFoodGuard {
    // 枚举：案件状态
    enum CaseStatus {
        DEPOSIT_PENDING,    // 等待保证金存入
        COMPLAINT_SUBMITTED, // 投诉已提交
        RISK_ASSESSED,      // 风险已评估
        VOTING_IN_PROGRESS, // 投票进行中
        CHALLENGE_PHASE,    // 质疑阶段
        CHALLENGE_VOTING,   // 质疑投票中
        REWARD_CALCULATION, // 奖励计算中
        COMPLETED,          // 流程完成
        CANCELLED           // 案件取消
    }

    // 枚举：风险等级
    enum RiskLevel {
        LOW,        // 低风险
        MEDIUM,     // 中风险
        HIGH        // 高风险
    }

    // 枚举：用户角色
    enum UserRole {
        COMPLAINANT,    // 投诉者
        ENTERPRISE,     // 企业
        VALIDATOR,      // 验证者
        CHALLENGER      // 质疑者
    }

    // 枚举：诚信状态
    enum IntegrityStatus {
        HONEST,         // 诚实
        DISHONEST,      // 不诚实
        PENDING         // 待定
    }

    // 枚举：奖惩状态
    enum RewardPunishmentStatus {
        REWARD,         // 奖励
        PUNISHMENT,     // 惩罚
        NEUTRAL         // 中性
    }

    // 结构体：证据材料
    struct Evidence {
        string description;     // 证据描述
        string[] fileHashes;   // 文件哈希数组
        uint256 timestamp;     // 提交时间
        address submitter;     // 提交者地址
    }

    // 结构体：投票信息
    struct Vote {
        address voter;          // 投票者地址
        bool support;           // 是否支持（true=支持投诉成立，false=反对）
        Evidence evidence;      // 投票时提交的证据
        uint256 timestamp;      // 投票时间
        uint256 weight;         // 投票权重
    }

    // 结构体：质疑信息
    struct Challenge {
        address challenger;     // 质疑者地址
        bool challengeResult;   // 质疑目标（true=质疑验证结果，false=支持验证结果）
        Evidence evidence;      // 质疑证据
        uint256 timestamp;      // 质疑时间
        Vote[] challengeVotes;  // 针对质疑的投票
    }

    // 结构体：用户信息
    struct UserInfo {
        address userAddress;            // 用户地址
        UserRole role;                  // 用户角色
        IntegrityStatus integrity;      // 诚信状态
        RewardPunishmentStatus rpStatus; // 奖惩状态
        uint256 depositAmount;          // 保证金数额
        bool isActive;                  // 是否活跃
    }

    // 结构体：案件信息
    struct Case {
        uint256 caseId;                 // 案件ID
        address complainant;            // 投诉者地址
        address enterprise;             // 被投诉企业地址
        string location;                // 事发地点
        string description;             // 案件描述
        Evidence complaintEvidence;     // 投诉证据
        RiskLevel riskLevel;            // 风险等级
        CaseStatus status;              // 案件状态
        uint256 createTime;             // 创建时间
        uint256 deadline;               // 截止时间
        
        // 投票相关
        Vote[] votes;                   // 验证投票数组
        uint256 supportVotes;           // 支持票数
        uint256 opposeVotes;            // 反对票数
        
        // 质疑相关
        Challenge[] challenges;         // 质疑数组
        bool challengePhaseActive;      // 质疑阶段是否激活
        
        // 资金相关
        uint256 totalDeposit;           // 总保证金
        uint256 rewardPool;             // 奖励池
        uint256 punishmentPool;         // 惩罚池
        
        // 结果
        bool complaintSuccessful;       // 投诉是否成功
        mapping(address => UserInfo) participants; // 参与者信息
    }

    // 事件定义
    event CaseCreated(uint256 indexed caseId, address indexed complainant, address indexed enterprise);
    event DepositSubmitted(uint256 indexed caseId, address indexed user, uint256 amount);
    event VoteSubmitted(uint256 indexed caseId, address indexed voter, bool support);
    event ChallengeSubmitted(uint256 indexed caseId, address indexed challenger, bool challengeResult);
    event ChallengeVoteSubmitted(uint256 indexed caseId, uint256 indexed challengeIndex, address indexed voter, bool support);
    event CaseStatusChanged(uint256 indexed caseId, CaseStatus newStatus);
    event RewardDistributed(uint256 indexed caseId, address indexed recipient, uint256 amount);
    event PunishmentApplied(uint256 indexed caseId, address indexed target, uint256 amount);
    event CaseCompleted(uint256 indexed caseId, bool complaintSuccessful);

    // 核心功能接口
    function submitDeposit(uint256 caseId) external payable;
    function createComplaint(
        address enterprise,
        string memory location,
        string memory description,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external returns (uint256 caseId);
    
    function submitVote(
        uint256 caseId,
        bool support,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external;
    
    function submitChallenge(
        uint256 caseId,
        address targetValidator,
        bool challengeResult,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external;
    
    function submitChallengeVote(
        uint256 caseId,
        uint256 challengeIndex,
        bool support,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external;

    // 查询接口
    function getCaseInfo(uint256 caseId) external view returns (
        address complainant,
        address enterprise,
        string memory location,
        string memory description,
        RiskLevel riskLevel,
        CaseStatus status,
        uint256 createTime,
        bool complaintSuccessful
    );
    
    function getVoteCount(uint256 caseId) external view returns (uint256 support, uint256 oppose);
    function getChallengeCount(uint256 caseId) external view returns (uint256);
    function getUserInfo(uint256 caseId, address user) external view returns (UserInfo memory);
} 