// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，确保安全性和最新特性

/**
 * @title DataStructures
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有数据结构
 * @dev 包含案件信息、用户状态、投票数据等核心结构体
 * 这个库是整个系统的数据基础，定义了所有关键的数据结构和枚举类型
 */
library DataStructures {
    // ==================== 枚举定义 ====================

    /**
     * @notice 案件状态枚举
     * @dev 严格按照流程图定义的状态流转，每个状态都有明确的前置条件和后续状态
     * 状态流转顺序：PENDING -> DEPOSIT_LOCKED -> VOTING -> CHALLENGING -> REWARD_PUNISHMENT -> COMPLETED
     */
    enum CaseStatus {
        PENDING, // 待处理（刚创建投诉，等待保证金锁定）
        DEPOSIT_LOCKED, // 保证金已锁定（投诉方和企业方都已提交保证金）
        VOTING, // 投票中（验证者正在对案件进行投票表决）
        CHALLENGING, // 质疑中（对投票结果存在异议，进入质疑流程）
        REWARD_PUNISHMENT, // 奖惩阶段（根据最终结果进行奖励和惩罚分配）
        COMPLETED, // 已完成（案件处理完毕，所有流程结束）
        CANCELLED // 已取消（案件因各种原因被取消，保证金退还）
    }

    /**
     * @notice 风险等级枚举
     * @dev 根据投诉内容的严重程度和影响范围进行分级
     * 不同风险等级会影响保证金要求和验证者数量
     */
    enum RiskLevel {
        LOW, // 低风险（轻微食品安全问题，影响范围小）
        MEDIUM, // 中风险（一般食品安全问题，有一定影响）
        HIGH // 高风险（严重食品安全问题，影响范围大，危害严重）
    }

    /**
     * @notice 用户诚信状态枚举
     * @dev 基于用户历史行为和表现进行评估
     * 影响用户的保证金要求和参与权限
     */
    enum IntegrityStatus {
        HONEST, // 诚实（用户行为良好，历史记录优秀）
        DISHONEST // 不诚实（用户有不良记录，需要限制参与）
    }

    /**
     * @notice 奖惩状态枚举
     * @dev 记录用户当前的奖惩状态，影响后续参与
     */
    enum RewardPunishmentStatus {
        NONE, // 无（正常状态，无奖励也无惩罚）
        REWARD, // 奖励（因良好表现获得奖励）
        PUNISHMENT // 惩罚（因不当行为受到惩罚）
    }

    /**
     * @notice 投票选择枚举
     * @dev 验证者对投诉案件的表态选择
     * 这是投票阶段的核心选择项
     */
    enum VoteChoice {
        SUPPORT_COMPLAINT, // 支持投诉（认为企业确实存在食品安全问题）
        REJECT_COMPLAINT // 反对投诉（认为企业没有问题，投诉不成立）
    }

    /**
     * @notice 质疑选择枚举
     * @dev 在质疑阶段，参与者对被质疑验证者的态度
     * 用于解决投票阶段可能存在的争议
     */
    enum ChallengeChoice {
        SUPPORT_VALIDATOR, // 支持验证者（认为被质疑的验证者判断正确）
        OPPOSE_VALIDATOR // 反对验证者（认为被质疑的验证者判断错误）
    }

    // ==================== 核心结构体定义 ====================

    /**
     * @notice 证据材料结构体（简化版）
     * @dev 只存储IPFS哈希，简化证据管理
     * 证据内容的详细信息存储在IPFS中，链上只记录哈希
     */
    struct Evidence {
        string ipfsHash; // IPFS 存储哈希（分布式存储确保证据不被篡改）
    }

    /**
     * @notice 投票信息结构体
     * @dev 记录验证者的投票详情，确保投票过程透明可追溯
     */
    struct VoteInfo {
        address voter; // 投票者地址（验证者的唯一标识）
        VoteChoice choice; // 投票选择（支持或反对投诉）
        uint256 timestamp; // 投票时间（确保在有效期内投票）
        string reason; // 投票理由（投票依据和逻辑说明）
        string evidenceHash; // 投票相关证据哈希（支持投票决定的证据材料IPFS哈希）
        bool hasVoted; // 是否已投票（防止重复投票）
        uint256 SupportersNumber; // 支持者数量（支持该投票的质疑者数量）
        uint256 OpponentsNumber; // 反对者数量（反对该投票的质疑者数量）
        address[] supporters; // 支持者列表（支持该投票的质疑者地址）
        address[] opponents; // 反对者列表（反对该投票的质疑者地址）
    }

    /**
     * @notice 质疑信息结构体
     * @dev 记录对验证者投票的质疑信息，维护系统公正性
     */
    struct ChallengeInfo {
        address challenger; // 质疑者地址（发起质疑的用户）
        address targetValidator; // 被质疑的验证者地址（质疑目标）
        ChallengeChoice choice; // 质疑选择（支持或反对被质疑的验证者）
        string reason; // 质疑理由（质疑的依据和逻辑）
        string evidenceHash; // 质疑证据哈希（支持质疑观点的证据材料IPFS哈希）
        uint256 timestamp; // 质疑时间（确保在质疑期限内）
        uint256 challengeDeposit; // 质疑保证金（防止恶意质疑，确保质疑的严肃性）
    }

    /**
     * @notice 用户状态信息结构体
     * @dev 全面记录用户在系统中的状态和表现
     * 这是用户信誉和参与能力的综合体现
     */
    struct UserStatus {
        IntegrityStatus integrity; // 诚信状态（基于历史行为的诚信评级）
        RewardPunishmentStatus rewardPunishment; // 奖惩状态（当前的奖惩情况）
        uint256 totalDeposit; // 总保证金（用户在系统中的总质押金额）
        uint256 frozenDeposit; // 冻结保证金（因参与案件而被暂时冻结的金额）
        uint256 reputationScore; // 声誉分数（基于历史表现的数值化评分）
        uint256 participationCount; // 参与次数（参与投票和验证的总次数）
        bool isValidator; // 是否为验证者（是否具备验证者资格）
        bool isActive; // 是否活跃（当前是否在系统中活跃参与）
        uint256 lastActiveTime; // 最后活跃时间（最近一次参与系统活动的时间）
    }

    /**
     * @notice 投诉案件主结构体
     * @dev 记录一个完整投诉案件的所有信息
     * 这是系统的核心数据结构，包含案件从创建到完成的全部信息
     */
    struct ComplaintCase {
        // ============ 基本信息部分 ============
        uint256 caseId; // 案件ID（系统分配的唯一标识符）
        address complainant; // 投诉者地址（发起投诉的用户）
        address enterprise; // 被投诉企业地址（被指控的企业）
        string complaintTitle; // 投诉标题（简要概括投诉内容）
        string complaintDescription; // 投诉详细描述（详细的问题说明）
        string location; // 事发地点（问题发生的具体位置）
        uint256 incidentTime; // 事发时间（问题发生的时间）
        uint256 complaintTime; // 投诉时间（投诉提交的时间）

        // ============ 状态和风险评估部分 ============
        CaseStatus status; // 案件状态（当前处于哪个处理阶段）
        RiskLevel riskLevel; // 风险等级（根据问题严重程度分级）

        // ============ 保证金管理部分 ============
        uint256 complainantDeposit; // 投诉者保证金（投诉方需要锁定的保证金）
        uint256 enterpriseDeposit; // 企业保证金（企业方需要锁定的保证金）
        bool depositsLocked; // 保证金是否已锁定（确保双方都已提交保证金）

        // ============ 证据材料部分 ============
        string complainantEvidenceHash; // 投诉者证据哈希（投诉方提供的证据材料IPFS哈希）

        // ============ 验证投票部分 ============
        address[] validators; // 参与验证的地址列表（所有参与投票的验证者）
        mapping(address => VoteInfo) votes; // 投票映射（每个验证者的投票详情）
        uint256 supportVotes; // 支持投诉的票数（认为投诉成立的投票数）
        uint256 rejectVotes; // 反对投诉的票数（认为投诉不成立的投票数）
        uint256 votingDeadline; // 投票截止时间（投票阶段的时间限制）

        // ============ 质疑处理部分 ============
        ChallengeInfo[] challenges; // 质疑信息列表（所有对投票结果的质疑）
        mapping(address => bool) hasChallenged; // 是否已质疑映射（防止重复质疑）
        uint256 challengeDeadline; // 质疑截止时间（质疑阶段的时间限制）
        bool challengePhaseActive; // 质疑阶段是否激活（当前是否允许质疑）

        // ============ 结果和奖惩部分 ============
        bool complaintUpheld; // 投诉是否成立（最终的判决结果）
        uint256 totalRewardAmount; // 总奖励金额（分配给正确参与者的总奖励）
        uint256 totalPunishmentAmount; // 总惩罚金额（对错误参与者的总惩罚）
        mapping(address => uint256) individualRewards; // 个人奖励映射（每个人获得的具体奖励）
        mapping(address => uint256) individualPunishments; // 个人惩罚映射（每个人受到的具体惩罚）

        // ============ 元数据部分 ============
        bool isCompleted; // 是否已完成（案件是否处理完毕）
        uint256 completionTime; // 完成时间（案件结束的时间）
        string finalReport; // 最终报告（案件处理的总结报告）
    }

    /**
     * @notice 资金池信息结构体
     * @dev 管理系统的各类资金池，确保资金的合理分配和使用
     */
    struct FundPool {
        uint256 totalBalance; // 总余额（系统中的全部资金）
        uint256 reserveBalance; // 储备金余额（应急和保障用途的资金）
        uint256 rewardPool; // 奖励池余额（用于奖励优秀参与者的资金）
        uint256 operationalFund; // 运营资金（系统日常运营所需的资金）
        uint256 emergencyFund; // 应急资金（处理紧急情况的专用资金）
    }

    /**
     * @notice 验证者信息结构体
     * @dev 记录验证者的详细信息和表现数据
     * 用于评估验证者的能力和可信度
     */
    struct ValidatorInfo {
        address validatorAddress; // 验证者地址（验证者的唯一标识）
        uint256 stake; // 质押金额（验证者质押的保证金数量）
        uint256 reputationScore; // 声誉分数（基于历史表现的信誉评分）
        uint256 totalCasesParticipated; // 参与案件总数（参与验证的案件数量）
        uint256 successfulValidations; // 成功验证次数（判断正确的验证次数）
        bool isActive; // 是否活跃（当前是否在系统中活跃）
        uint256 lastActiveTime; // 最后活跃时间（最近一次参与验证的时间）
    }

    /**
     * @notice 系统配置结构体
     * @dev 定义系统运行的各项参数和规则
     * 这些参数决定了系统的运行机制和经济模型
     */
    struct SystemConfig {
        uint256 minComplaintDeposit; // 最小投诉保证金（投诉者需要的最低保证金）
        uint256 maxComplaintDeposit; // 最大投诉保证金（投诉者保证金的上限）
        uint256 minEnterpriseDeposit; // 最小企业保证金（企业需要的最低保证金）
        uint256 maxEnterpriseDeposit; // 最大企业保证金（企业保证金的上限）
        uint256 minDaoDeposit; // 最小DAO成员保证金（DAO成员的最低保证金）
        uint256 maxDaoDeposit; // 最大DAO成员保证金（DAO成员保证金的上限）
        uint256 votingPeriod; // 投票期限（投票阶段的持续时间，以秒为单位）
        uint256 challengePeriod; // 质疑期限（质疑阶段的持续时间，以秒为单位）
        uint256 minValidators; // 最少验证者数量（案件需要的最少验证者数）
        uint256 maxValidators; // 最多验证者数量（案件允许的最多验证者数）
        uint256 rewardPoolPercentage; // 奖励池百分比（保证金中用于奖励的比例）
        uint256 operationalFeePercentage; // 运营费用百分比（用于系统运营的费用比例）
    }

    /**
     * @notice 动态保证金配置
     * @dev 根据用户状态和风险情况动态调整保证金要求
     * 实现更精准的风险管理和资金效率
     */
    struct DynamicDepositConfig {
        uint256 warningThreshold; // 警告阈值 (130%) - 保证金不足时的警告线
        uint256 restrictionThreshold; // 限制阈值 (120%) - 开始限制用户操作的临界点
        uint256 liquidationThreshold; // 清算阈值 (110%) - 强制清算的临界点
        uint256 highRiskMultiplier; // 高风险倍数 (200%) - 高风险案件的保证金倍数
        uint256 mediumRiskMultiplier; // 中风险倍数 (150%) - 中风险案件的保证金倍数
        uint256 lowRiskMultiplier; // 低风险倍数 (120%) - 低风险案件的保证金倍数
        uint256 concurrentCaseExtra; // 并发案件额外要求 (50% per case) - 每个并发案件的额外保证金
        uint256 reputationDiscountThreshold; // 声誉折扣门槛 (800分) - 享受保证金折扣的声誉分数
        uint256 reputationDiscountRate; // 声誉折扣率 (20%) - 高声誉用户的保证金折扣比例
        uint256 reputationPenaltyThreshold; // 声誉惩罚门槛 (300分) - 需要额外保证金的声誉分数
        uint256 reputationPenaltyRate; // 声誉惩罚率 (50%) - 低声誉用户的保证金增加比例
    }

    /**
     * @notice 用户保证金状态
     * @dev 根据保证金充足程度划分的用户状态等级
     * 不同状态对应不同的操作权限和风险管理措施
     */
    enum DepositStatus {
        HEALTHY,    // 健康状态 - 保证金充足，可以正常参与所有活动
        WARNING,    // 警告状态 - 保证金略显不足，需要关注但暂不限制
        RESTRICTED, // 限制状态 - 保证金严重不足，限制部分高风险操作
        LIQUIDATION // 清算状态 - 保证金极度不足，面临强制清算风险
    }

    /**
     * @notice 用户保证金档案
     * @dev 详细记录用户的保证金状况和相关信息
     * 用于动态保证金管理和风险控制
     */
    struct UserDepositProfile {
        uint256 totalDeposit;           // 总保证金 - 用户在系统中的全部保证金
        uint256 frozenAmount;           // 冻结金额 - 因参与案件而暂时冻结的保证金
        uint256 requiredAmount;         // 所需保证金 - 根据用户状态计算的最低要求
        uint256 activeCaseCount;        // 活跃案件数量 - 当前正在参与的案件数

        DepositStatus status;           // 保证金状态 - 当前的保证金健康状态
        uint256 lastWarningTime;        // 最后警告时间 - 上次发出保证金不足警告的时间
        bool operationRestricted;       // 是否限制操作 - 因保证金不足而限制某些操作
    }


}
