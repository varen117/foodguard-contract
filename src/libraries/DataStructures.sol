// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，确保安全性和最新特性

/**
 * @title DataStructures
 * @author Food Safety Governance Team
 * @notice 食品安全治理系统的核心数据结构定义库
 * @dev 定义了系统中使用的所有枚举类型和结构体，为各个模块提供统一的数据格式
 */
library DataStructures {
    // ==================== 核心枚举 ====================

    /**
     * @notice 案件状态枚举
     * @dev 定义案件在整个生命周期中的各个状态，确保流程的有序进行
     */
    enum CaseStatus {
        PENDING,            // 待处理：案件刚创建，等待系统分配验证者
        DEPOSIT_LOCKED,     // 保证金已锁定：各方保证金已冻结，等待进入投票阶段
        VOTING,             // 投票中：验证者正在对案件进行表决
        CHALLENGING,        // 质疑中：投票结束后的质疑期，允许对结果提出异议
        REWARD_PUNISHMENT,  // 奖惩阶段：正在处理各方的奖励和惩罚分配
        COMPLETED,          // 已完成：案件处理完毕，所有流程结束
        CANCELLED           // 已取消：案件被管理员取消或因异常情况终止
    }

    /**
     * @notice 风险等级枚举
     * @dev 根据食品安全问题的严重程度分类，影响验证者选择和保证金要求
     */
    enum RiskLevel {
        LOW,     // 低风险：轻微问题，如包装缺陷、标签不当
        MEDIUM,  // 中风险：中等问题，如质量问题、轻微污染
        HIGH     // 高风险：严重问题，如食物中毒、重大食品安全隐患
    }

    /**
     * @notice 投票选择枚举
     * @dev 验证者对投诉案件的表决选项，决定案件的初步结果
     */
    enum VoteChoice {
        SUPPORT_COMPLAINT,  // 支持投诉：认为投诉有理，企业确实存在问题
        REJECT_COMPLAINT    // 反对投诉：认为投诉无理，企业没有实质性问题
    }

    /**
     * @notice 质疑选择枚举
     * @dev 质疑者对验证者判断的态度，用于质疑期间的立场表达
     */
    enum ChallengeChoice {
        SUPPORT_VALIDATOR,  // 支持验证者：认为验证者的判断是正确的
        OPPOSE_VALIDATOR    // 反对验证者：认为验证者的判断存在错误
    }

    /**
     * @notice 用户角色枚举
     * @dev 定义系统中用户的基本角色类型，决定用户的权限和功能
     */
    enum UserRole {
        COMPLAINANT,    // 投诉者：提交食品安全投诉的普通用户
        ENTERPRISE,     // 企业：被投诉的食品生产、销售或服务企业
        DAO_MEMBER      // DAO成员：治理参与者，可以担任验证者和质疑者角色
    }

    /**
     * @notice 保证金状态枚举
     * @dev 用户保证金账户的健康状况，用于风险管理和操作限制
     */
    enum DepositStatus {
        HEALTHY,        // 健康状态：保证金充足，可以正常参与所有操作
        WARNING,        // 警告状态：保证金不足但仍可参与，需要尽快补充
        RESTRICTED,     // 限制状态：保证金严重不足，限制部分高风险操作
        LIQUIDATION     // 清算状态：保证金极度不足，面临强制清算风险
    }

    /**
     * @notice 诚信状态枚举
     * @dev 评估用户的诚信度和可信度，基于历史行为表现
     */
    enum IntegrityStatus {
        HONEST,         // 诚实：用户行为诚信，历史记录良好
        DISHONEST       // 不诚实：用户有不良行为记录，可信度受质疑
    }

    /**
     * @notice 奖惩状态枚举
     * @dev 用户最近的奖惩情况，影响信誉和参与权限
     */
    enum RewardPunishmentStatus {
        NONE,           // 无：没有特殊的奖惩记录，处于中性状态
        REWARD,         // 奖励：最近获得了奖励，信誉提升
        PUNISHMENT      // 惩罚：最近受到了惩罚，信誉下降
    }

    /**
     * @notice 质疑类型枚举
     * @dev 质疑的具体分类，帮助系统更好地处理不同类型的质疑
     */
    enum ChallengeType {
        EVIDENCE_DISPUTE,    // 证据争议：对提供的证据真实性或有效性提出质疑
        PROCESS_VIOLATION,   // 流程违规：认为投票或处理流程存在违规行为
        BIAS_ACCUSATION     // 偏见指控：指控验证者存在偏见或利益冲突
    }

    // ==================== 核心结构体 ====================

    /**
     * @notice 投票信息结构体
     * @dev 记录单个验证者的投票详细信息，包括选择、理由和证据
     */
    struct VoteInfo {
        address voter;          // 投票者地址：提交投票的验证者以太坊地址
        VoteChoice choice;      // 投票选择：支持或反对投诉
        uint256 timestamp;      // 投票时间戳：投票提交的具体时间
        string reason;          // 投票理由：验证者对其判断的详细说明
        string evidenceHash;    // 证据哈希：支持投票决定的证据文件哈希
        bool hasVoted;          // 投票状态：标记该验证者是否已经完成投票
    }

    /**
     * @notice 投票会话结构体
     * @dev 管理单个案件的完整投票流程，包括参与者、时间和结果统计
     */
    struct VotingSession {
        uint256 caseId;                                     // 案件ID：关联的案件唯一标识符
        address[] selectedValidators;                       // 选中的验证者：参与此案件投票的验证者地址列表
        mapping(address => DataStructures.VoteInfo) votes;  // 投票记录映射：验证者地址到其投票信息的映射
        uint256 supportVotes;                               // 支持票数：认为投诉成立的投票数量
        uint256 rejectVotes;                                // 反对票数：认为投诉不成立的投票数量
        uint256 totalVotes;                                 // 总投票数：已提交的投票总数
        uint256 startTime;                                  // 开始时间：投票期开始的时间戳
        uint256 endTime;                                    // 结束时间：投票期截止的时间戳
        bool isActive;                                      // 激活状态：投票期是否正在进行中
        bool isCompleted;                                   // 完成状态：投票是否已经结束并处理完毕
        bool complaintUpheld;                               // 投诉结果：最终是否支持投诉（投诉是否成立）
    }

    /**
     * @notice 质疑信息结构体
     * @dev 记录单个质疑的完整信息，包括质疑者、目标和具体内容
     */
    struct ChallengeInfo {
        address challenger;         // 质疑者地址：提出质疑的DAO成员以太坊地址
        address targetValidator;    // 目标验证者：被质疑的验证者地址
        ChallengeChoice choice;     // 质疑选择：支持或反对验证者的判断
        string reason;              // 质疑理由：质疑者对其立场的详细说明
        string evidenceHash;        // 质疑证据：支持质疑的证据文件哈希值
        uint256 timestamp;          // 质疑时间：质疑提交的时间戳
        uint256 challengeDeposit;   // 质疑保证金：质疑者为此质疑支付的保证金数额
    }

    /**
     * @notice 质疑投票信息结构体
     * @dev 汇总针对特定验证者的所有质疑信息，便于统计和分析
     */
    struct ChallengeVotingInfo {
        address targetValidator;                // 目标验证者：被质疑的验证者地址
        address[] supporters;                   // 支持者列表：支持该验证者判断的质疑者地址列表
        address[] opponents;                    // 反对者列表：反对该验证者判断的质疑者地址列表
        DataStructures.ChallengeInfo[] challenges; // 质疑详情：针对该验证者的所有质疑详细信息
    }

    /**
     * @notice 验证者信息结构体
     * @dev 记录验证者的基本信息、参与历史和表现统计
     */
    struct ValidatorInfo {
        address validatorAddress;       // 验证者地址：验证者的以太坊账户地址
        uint256 stake;                  // 质押金额：验证者质押的代币数量
        uint256 reputationScore;        // 信誉分数：基于历史表现计算的信誉值
        uint256 totalCasesParticipated; // 参与案件总数：验证者累计参与的案件数量
        uint256 successfulValidations;  // 成功验证数：验证者正确判断的案件数量
        bool isActive;                  // 活跃状态：验证者当前是否处于活跃状态
        uint256 lastActiveTime;         // 最后活跃时间：验证者最后一次参与活动的时间戳
    }

    /**
     * @notice 用户状态结构体
     * @dev 记录用户的综合状态信息，用于权限管理和风险评估
     */
    struct UserStatus {
        uint256 reputationScore;                // 信誉分数：用户的综合信誉评分
        uint256 participationCount;             // 参与次数：用户累计参与的活动次数
        bool isActive;                          // 活跃状态：用户当前是否处于活跃状态
        uint256 lastActiveTime;                 // 最后活跃时间：用户最后一次活动的时间戳
        IntegrityStatus integrity;              // 诚信状态：用户的诚信度评级
        RewardPunishmentStatus rewardPunishment; // 奖惩状态：用户最近的奖惩情况
    }

    /**
     * @notice 资金池结构体
     * @dev 管理系统的各类资金池，确保资金使用的透明性和安全性
     */
    struct FundPool {
        uint256 totalBalance;       // 总余额：资金池的总资金量
        uint256 rewardPool;         // 奖励池：专门用于分发奖励的资金
        uint256 operationalFund;    // 运营资金：用于系统运营和维护的资金
        uint256 reserveBalance;     // 储备资金：应急和风险缓冲资金
    }

    /**
     * @notice 系统配置结构体
     * @dev 定义系统运行的关键参数，可通过治理机制调整
     */
    struct SystemConfig {
        uint256 minComplaintDeposit;        // 最低投诉保证金：投诉者需要支付的最小保证金额度
        uint256 minEnterpriseDeposit;       // 最低企业保证金：企业注册和参与时的最小保证金
        uint256 minDaoDeposit;              // 最低DAO保证金：DAO成员参与治理的最小保证金
        uint256 votingPeriod;               // 投票期时长：验证者投票的时间窗口（秒）
        uint256 challengePeriod;            // 质疑期时长：质疑阶段的时间窗口（秒）
        uint256 minValidators;              // 最少验证者数：每个案件最少需要的验证者数量
        uint256 maxValidators;              // 最多验证者数：每个案件最多允许的验证者数量
        uint256 rewardPoolPercentage;       // 奖励池比例：分配给奖励的资金比例
        uint256 operationalFeePercentage;   // 运营费比例：用于系统运营的费用比例
    }

    /**
     * @notice 动态保证金配置结构体
     * @dev 控制动态保证金系统的各项参数，实现智能风险管理
     */
    struct DynamicDepositConfig {
        uint256 warningThreshold;           // 警告阈值（130%）：保证金低于此比例时发出警告
        uint256 restrictionThreshold;       // 限制阈值（120%）：保证金低于此比例时限制操作
        uint256 liquidationThreshold;       // 清算阈值（110%）：保证金低于此比例时可能被清算
        uint256 highRiskMultiplier;         // 高风险倍数（200%）：高风险案件的保证金倍数
        uint256 mediumRiskMultiplier;       // 中风险倍数（150%）：中风险案件的保证金倍数
        uint256 lowRiskMultiplier;          // 低风险倍数（120%）：低风险案件的保证金倍数
        uint256 reputationDiscountThreshold; // 信誉折扣阈值（800分）：享受保证金折扣的信誉门槛
        uint256 reputationDiscountRate;     // 信誉折扣率（20%）：高信誉用户享受的保证金折扣比例
    }

    /**
     * @notice 用户保证金档案结构体
     * @dev 详细记录用户的保证金状况，用于动态保证金管理
     */
    struct UserDepositProfile {
        uint256 totalDeposit;       // 总保证金：用户在系统中的总保证金数额
        uint256 frozenAmount;       // 冻结金额：当前被冻结用于参与案件的保证金数额
        uint256 requiredAmount;     // 要求金额：当前系统要求的最低保证金数额
        uint256 activeCaseCount;    // 活跃案件数：用户当前参与的进行中案件数量
        DepositStatus status;       // 保证金状态：用户保证金账户的当前健康状况
        uint256 lastWarningTime;    // 最后警告时间：最后一次发出保证金不足警告的时间戳
        bool operationRestricted;   // 操作限制：是否因保证金不足而限制用户操作
    }
}
