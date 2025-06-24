// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DataStructures
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有数据结构
 * @dev 包含案件信息、用户状态、投票数据等核心结构体
 */
library DataStructures {
    // ==================== 枚举定义 ====================

    /**
     * @notice 案件状态枚举
     * @dev 严格按照流程图定义的状态流转
     */
    enum CaseStatus {
        PENDING, // 待处理（刚创建投诉）
        DEPOSIT_LOCKED, // 保证金已锁定
        VOTING, // 投票中
        CHALLENGING, // 质疑中
        REWARD_PUNISHMENT, // 奖惩阶段
        COMPLETED, // 已完成
        CANCELLED // 已取消
    }

    /**
     * @notice 风险等级枚举
     */
    enum RiskLevel {
        LOW, // 低风险
        MEDIUM, // 中风险
        HIGH // 高风险
    }

    /**
     * @notice 用户诚信状态枚举
     */
    enum IntegrityStatus {
        HONEST, // 诚实
        DISHONEST // 不诚实
    }

    /**
     * @notice 奖惩状态枚举
     */
    enum RewardPunishmentStatus {
        NONE, // 无
        REWARD, // 奖励
        PUNISHMENT // 惩罚
    }

    /**
     * @notice 投票选择枚举
     */
    enum VoteChoice {
        SUPPORT_COMPLAINT, // 支持投诉（认为企业有问题）
        REJECT_COMPLAINT // 反对投诉（认为企业无问题）
    }

    /**
     * @notice 质疑选择枚举
     */
    enum ChallengeChoice {
        SUPPORT_VALIDATOR, // 支持验证者
        OPPOSE_VALIDATOR // 反对验证者
    }

    // ==================== 核心结构体定义 ====================

    /**
     * @notice 证据材料结构体
     * @dev 存储投诉、验证、质疑过程中的证据信息
     */
    struct Evidence {
        string description; // 证据描述
        string ipfsHash; // IPFS 存储哈希
        string location; // 事发地点
        uint256 timestamp; // 证据提交时间
        address submitter; // 证据提交者
        string evidenceType; // 证据类型（图片、视频、文档等）
    }

    /**
     * @notice 投票信息结构体
     */
    struct VoteInfo {
        address voter; // 投票者地址
        VoteChoice choice; // 投票选择
        uint256 timestamp; // 投票时间
        string reason; // 投票理由
        Evidence[] evidences; // 投票相关证据
        bool hasVoted; // 是否已投票
    }

    /**
     * @notice 质疑信息结构体
     */
    struct ChallengeInfo {
        address challenger; // 质疑者地址
        address targetValidator; // 被质疑的验证者地址
        ChallengeChoice choice; // 质疑选择
        string reason; // 质疑理由
        Evidence[] evidences; // 质疑证据
        uint256 timestamp; // 质疑时间
        uint256 challengeDeposit; // 质疑保证金
    }

    /**
     * @notice 用户状态信息结构体
     */
    struct UserStatus {
        IntegrityStatus integrity; // 诚信状态
        RewardPunishmentStatus rewardPunishment; // 奖惩状态
        uint256 totalDeposit; // 总保证金
        uint256 frozenDeposit; // 冻结保证金
        uint256 reputationScore; // 声誉分数
        uint256 participationCount; // 参与次数
        bool isValidator; // 是否为验证者
        bool isActive; // 是否活跃
        uint256 lastActiveTime; // 最后活跃时间
    }

    /**
     * @notice 投诉案件主结构体
     * @dev 记录一个完整投诉案件的所有信息
     */
    struct ComplaintCase {
        // 基本信息
        uint256 caseId; // 案件ID
        address complainant; // 投诉者地址
        address enterprise; // 被投诉企业地址
        string complaintTitle; // 投诉标题
        string complaintDescription; // 投诉详细描述
        string location; // 事发地点
        uint256 incidentTime; // 事发时间
        uint256 complaintTime; // 投诉时间
        // 状态和风险
        CaseStatus status; // 案件状态
        RiskLevel riskLevel; // 风险等级
        // 保证金信息
        uint256 complainantDeposit; // 投诉者保证金
        uint256 enterpriseDeposit; // 企业保证金
        bool depositsLocked; // 保证金是否已锁定
        // 证据材料
        Evidence[] complainantEvidences; // 投诉者证据
        Evidence[] enterpriseEvidences; // 企业回应证据
        // 验证者和投票信息
        address[] validators; // 参与验证的地址列表
        mapping(address => VoteInfo) votes; // 投票映射
        uint256 supportVotes; // 支持投诉的票数
        uint256 rejectVotes; // 反对投诉的票数
        uint256 votingDeadline; // 投票截止时间
        // 质疑信息
        ChallengeInfo[] challenges; // 质疑信息列表
        mapping(address => bool) hasChallenged; // 是否已质疑映射
        uint256 challengeDeadline; // 质疑截止时间
        bool challengePhaseActive; // 质疑阶段是否激活
        // 结果和奖惩
        bool complaintUpheld; // 投诉是否成立
        uint256 totalRewardAmount; // 总奖励金额
        uint256 totalPunishmentAmount; // 总惩罚金额
        mapping(address => uint256) individualRewards; // 个人奖励映射
        mapping(address => uint256) individualPunishments; // 个人惩罚映射
        // 元数据
        bool isCompleted; // 是否已完成
        uint256 completionTime; // 完成时间
        string finalReport; // 最终报告
    }

    /**
     * @notice 资金池信息结构体
     */
    struct FundPool {
        uint256 totalBalance; // 总余额
        uint256 reserveBalance; // 储备金余额
        uint256 rewardPool; // 奖励池余额
        uint256 operationalFund; // 运营资金
        uint256 emergencyFund; // 应急资金
    }

    /**
     * @notice 验证者信息结构体
     */
    struct ValidatorInfo {
        address validatorAddress; // 验证者地址
        uint256 stake; // 质押金额
        uint256 reputationScore; // 声誉分数
        uint256 totalCasesParticipated; // 参与案件总数
        uint256 successfulValidations; // 成功验证次数
        bool isActive; // 是否活跃
        uint256 lastActiveTime; // 最后活跃时间
    }

    /**
     * @notice 系统配置结构体
     */
    struct SystemConfig {
        uint256 minComplaintDeposit; // 最小投诉保证金
        uint256 maxComplaintDeposit; //最大投诉保证金
        uint256 minEnterpriseDeposit; // 最小企业保证金
        uint256 maxEnterpriseDeposit; //最大企业保证金
        uint256 minDaoDeposit; // 最小DAO成员保证金
        uint256 maxDaoDeposit; //最大DAO成员保证金
        uint256 votingPeriod; // 投票期限（秒）
        uint256 challengePeriod; // 质疑期限（秒）
        uint256 minValidators; // 最少验证者数量
        uint256 maxValidators; // 最多验证者数量
        uint256 rewardPoolPercentage; // 奖励池百分比
        uint256 operationalFeePercentage; // 运营费用百分比
    }
}
