// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DataStructures.sol";

/**
 * @title Events
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有事件
 * @dev 事件用于记录重要操作和状态变化，便于前端监听和数据分析
 * 事件是区块链上的日志记录，不消耗存储空间但可以被前端和分析工具监听
 * 所有事件都按功能模块分类，便于理解和维护
 */
library Events {
    // ==================== 系统管理事件 ====================
    // 这一类事件记录系统级别的管理操作和状态变化

    /**
     * @notice 系统暂停/恢复事件
     * @dev 当系统管理员暂停或恢复系统运行时触发
     * 用于紧急情况下的系统控制和维护
     */
    event SystemPauseStatusChanged(bool isPaused, address operator, uint256 timestamp);
    // isPaused: 系统是否暂停的标志
    // operator: 执行操作的管理员地址
    // timestamp: 操作执行的时间戳

    /**
     * @notice 系统配置更新事件
     * @dev 当系统配置参数被修改时触发
     * 记录配置变更的历史，确保系统变更的透明性
     */
    event SystemConfigUpdated(
        string configName,      // 配置项名称（如"minComplaintDeposit"）
        uint256 oldValue,       // 修改前的值
        uint256 newValue,       // 修改后的值
        address operator,       // 执行修改的管理员地址
        uint256 timestamp       // 修改时间
    );

    /**
     * @notice 管理员权限变更事件
     * @dev 当用户的管理员权限被授予或撤销时触发
     * 确保权限变更的透明度和可追溯性
     */
    event AdminRoleChanged(address user, bool isAdmin, address operator, uint256 timestamp);
    // user: 权限被变更的用户地址
    // isAdmin: 是否为管理员的标志
    // operator: 执行权限变更的操作者
    // timestamp: 权限变更时间

    // ==================== 系统异常监控事件 ====================
    // 这一类事件记录系统运行中检测到的异常情况，便于监控和调试

    /**
     * @notice 系统状态不一致检测事件
     * @dev 当系统检测到数据状态不一致时触发
     * 用于监控和调试系统潜在问题，不中断正常流程
     */
    event SystemStateInconsistencyDetected(
        address indexed user,           // 相关用户地址
        uint256 indexed caseId,         // 相关案件ID（如果适用）
        string componentName,           // 发生不一致的组件名称
        string description,             // 不一致情况描述
        uint256 expectedValue,          // 期望值
        uint256 actualValue,            // 实际值
        uint256 timestamp               // 检测时间
    );

    /**
     * @notice 数据修复事件
     * @dev 当系统自动修复数据不一致时触发
     * 记录系统的自愈能力和修复历史
     */
    event SystemDataRepaired(
        address indexed user,           // 相关用户地址
        uint256 indexed caseId,         // 相关案件ID（如果适用）
        string componentName,           // 修复的组件名称
        string repairAction,            // 修复动作描述
        uint256 oldValue,               // 修复前的值
        uint256 newValue,               // 修复后的值
        uint256 timestamp               // 修复时间
    );

    /**
     * @notice 系统异常警告事件
     * @dev 当系统遇到异常但能够继续运行时触发
     * 区别于致命错误，这类异常不会中断流程但需要关注
     */
    event SystemAnomalyWarning(
        string category,                // 异常类别（如"FUND_MANAGEMENT"、"VOTING_SYSTEM"）
        string description,             // 异常描述
        uint256 severity,               // 严重程度等级 (1-5, 5最严重)
        address relatedContract,        // 相关合约地址
        bytes additionalData,           // 额外的调试数据
        uint256 timestamp               // 异常发生时间
    );

    /**
     * @notice 业务流程异常事件
     * @dev 当业务流程中出现需要特殊处理的异常时触发
     * 用于记录业务层面的异常处理情况
     */
    event BusinessProcessAnomaly(
        uint256 indexed caseId,         // 相关案件ID
        address indexed user,           // 相关用户地址
        string processName,             // 流程名称（如"清算"、"奖惩计算"）
        string anomalyType,             // 异常类型
        string recoveryAction,          // 恢复措施
        uint256 timestamp               // 异常处理时间
    );

    // ==================== 用户注册事件 ====================
    // 这一类事件记录用户和验证者的注册及状态变更

    /**
     * @notice 用户注册事件
     * @dev 当新用户注册到系统时触发
     * 记录用户的基本信息和初始保证金
     */
    event UserRegistered(
        address indexed user,       // 注册用户的地址（indexed便于查询）
        bool isEnterprise,          // 是否为企业用户
        uint256 initialDeposit,     // 初始保证金金额
        uint256 timestamp           // 注册时间
    );

    /**
     * @notice 验证者注册事件
     * @dev 当用户成为验证者时触发
     * 记录验证者的质押信息和初始声誉
     */
    event ValidatorRegistered(
        address indexed validator,  // 验证者地址
        uint256 stake,              // 质押的保证金数量
        uint256 reputationScore,    // 初始声誉分数
        uint256 timestamp           // 注册时间
    );

    /**
     * @notice 验证者状态更新事件
     * @dev 当验证者的活跃状态或声誉分数发生变化时触发
     * 用于跟踪验证者的表现和状态变化
     */
    event ValidatorStatusUpdated(
        address indexed validator,  // 验证者地址
        bool isActive,              // 是否为活跃状态
        uint256 newReputationScore, // 更新后的声誉分数
        uint256 timestamp           // 更新时间
    );

    // ==================== 投诉相关事件 ====================
    // 这一类事件记录投诉的创建和证据提交

    /**
     * @notice 投诉创建事件
     * @dev 当新的投诉案件被创建时触发
     * 记录投诉的基本信息，是案件生命周期的起点
     */
    event ComplaintCreated(
        uint256 indexed caseId,                 // 案件ID（indexed便于查询）
        address indexed complainant,            // 投诉者地址
        address indexed enterprise,             // 被投诉企业地址
        string complaintTitle,                  // 投诉标题
        DataStructures.RiskLevel riskLevel,     // 风险等级评估
        uint256 timestamp                       // 投诉创建时间
    );

    /**
     * @notice 投诉证据提交事件
     * @dev 当投诉者提交证据时触发
     * 记录证据的提交历史，确保证据链的完整性
     */
    event ComplaintEvidenceSubmitted(
        uint256 indexed caseId,     // 相关案件ID
        address indexed submitter,  // 证据提交者地址
        string ipfsHash,            // 证据在IPFS上的哈希值
        uint256 timestamp           // 证据提交时间
    );



    // ==================== 保证金相关事件 ====================
    // 这一类事件记录保证金的存入、冻结、解冻和扣除操作

    /**
     * @notice 保证金存入事件
     * @dev 当用户向系统存入保证金时触发
     * 记录保证金的存入历史和账户余额变化
     */
    event DepositMade(
        address indexed user,       // 存入保证金的用户地址
        uint256 amount,             // 存入金额
        uint256 totalDeposit,       // 存入后的总保证金余额
        uint256 timestamp           // 存入时间
    );

    /**
     * @notice 保证金冻结事件
     * @dev 当用户的保证金因参与案件而被冻结时触发
     * 防止用户在案件进行中撤回保证金
     */
    event DepositFrozen(
        uint256 indexed caseId,     // 相关案件ID
        address indexed user,       // 保证金被冻结的用户
        uint256 amount,             // 冻结金额
        string reason,              // 冻结原因
        uint256 timestamp           // 冻结时间
    );

    /**
     * @notice 保证金解冻事件
     * @dev 当案件结束后保证金被解冻时触发
     * 用户可以重新使用被解冻的保证金
     */
    event DepositUnfrozen(
        uint256 indexed caseId,     // 相关案件ID
        address indexed user,       // 保证金被解冻的用户
        uint256 amount,             // 解冻金额
        uint256 timestamp           // 解冻时间
    );

    /**
     * @notice 保证金扣除事件
     * @dev 当用户因惩罚或其他原因被扣除保证金时触发
     * 记录保证金的扣除历史和原因
     */
    event DepositDeducted(
        uint256 indexed caseId,     // 相关案件ID
        address indexed user,       // 被扣除保证金的用户
        uint256 amount,             // 扣除金额
        string reason,              // 扣除原因
        uint256 timestamp           // 扣除时间
    );

    // ==================== 动态保证金相关事件 ====================
    // 这一类事件记录动态保证金机制的运作过程

    /**
     * @notice 保证金状态变更事件
     * @dev 当用户的保证金状态发生变化时触发
     * 记录从健康状态到警告、限制、清算等状态的转换
     */
    event DepositStatusChanged(
        address indexed user,       // 用户地址
        uint8 oldStatus,            // 变更前的状态
        uint8 newStatus,            // 变更后的状态
        uint256 coverage,           // 当前保证金覆盖率
        uint256 timestamp           // 状态变更时间
    );

    /**
     * @notice 保证金警告事件
     * @dev 当用户的保证金不足触发警告时触发
     * 提醒用户及时补充保证金以避免操作限制
     */
    event DepositWarning(
        address indexed user,       // 收到警告的用户地址
        uint256 required,           // 所需的保证金数量
        uint256 available,          // 当前可用的保证金数量
        uint256 coverage,           // 保证金覆盖率百分比
        uint256 timestamp           // 警告发出时间
    );

    /**
     * @notice 用户操作限制事件
     * @dev 当用户因保证金不足被限制某些操作时触发
     * 保护系统免受保证金不足用户的潜在风险
     */
    event UserOperationRestricted(
        address indexed user,       // 被限制的用户地址
        string reason,              // 限制原因
        uint256 timestamp           // 限制生效时间
    );

    /**
     * @notice 用户清算事件
     * @dev 当用户保证金严重不足被强制清算时触发
     * 记录清算过程和相关的损失
     */
    event UserLiquidated(
        address indexed user,       // 被清算的用户地址
        uint256 liquidatedAmount,   // 被清算的金额
        uint256 penalty,            // 清算罚金
        string reason,              // 清算原因
        uint256 timestamp           // 清算时间
    );



    /**
     * @notice 动态保证金要求更新事件
     * @dev 当用户的保证金要求因风险状况变化而调整时触发
     * 记录保证金要求的动态调整过程
     */
    event DynamicDepositRequirementUpdated(
        address indexed user,       // 用户地址
        uint256 oldRequired,        // 调整前的要求金额
        uint256 newRequired,        // 调整后的要求金额
        string reason,              // 调整原因
        uint256 timestamp           // 调整时间
    );

    // ==================== 验证投票事件 ====================
    // 这一类事件记录验证者选择和投票过程

    /**
     * @notice 验证者选择事件
     * @dev 当系统为案件选择验证者时触发
     * 记录验证者选择的随机性和公正性
     */
    event ValidatorsSelected(
        uint256 indexed caseId,     // 案件ID
        address[] validators,       // 被选中的验证者地址列表
        uint256 randomSeed,         // 用于选择的随机种子
        uint256 timestamp           // 选择时间
    );

    /**
     * @notice 投票期开始事件
     * @dev 当案件进入投票阶段时触发
     * 标志着验证者可以开始对案件进行投票
     */
    event VotingPhaseStarted(
        uint256 indexed caseId,     // 案件ID
        uint256 votingDeadline,     // 投票截止时间
        uint256 validatorCount,     // 参与投票的验证者数量
        uint256 timestamp           // 投票期开始时间
    );

    /**
     * @notice 投票提交事件
     * @dev 当验证者提交投票时触发
     * 记录每个验证者的投票选择和理由
     */
    event VoteSubmitted(
        uint256 indexed caseId,             // 案件ID
        address indexed voter,              // 投票者地址
        DataStructures.VoteChoice choice,   // 投票选择（支持或反对投诉）
        string reason,                      // 投票理由
        uint256 evidenceCount,              // 投票时提供的证据数量
        uint256 timestamp                   // 投票时间
    );

    /**
     * @notice 投票期结束事件
     * @dev 当投票期截止时触发
     * 统计最终的投票结果，决定案件的初步结论
     */
    event VotingPhaseEnded(
        uint256 indexed caseId,     // 案件ID
        uint256 supportVotes,       // 支持投诉的票数
        uint256 rejectVotes,        // 反对投诉的票数
        uint256 timestamp           // 投票期结束时间
    );

    // ==================== 质疑相关事件 ====================
    // 这一类事件记录对投票结果的质疑过程

    /**
     * @notice 质疑期开始事件
     * @dev 当案件进入质疑阶段时触发
     * 允许用户对投票结果提出质疑
     */
    event ChallengePhaseStarted(
        uint256 indexed caseId,     // 案件ID
        uint256 challengeDeadline,  // 质疑期截止时间
        uint256 timestamp           // 质疑期开始时间
    );

    /**
     * @notice 质疑提交事件
     * @dev 当用户对验证者的投票提出质疑时触发
     * 记录质疑的详细信息和理由
     */
    event ChallengeSubmitted(
        uint256 indexed caseId,                     // 案件ID
        address indexed challenger,                 // 质疑者地址
        address indexed targetValidator,            // 被质疑的验证者地址
        DataStructures.ChallengeChoice choice,      // 质疑选择（支持或反对验证者）
        string reason,                              // 质疑理由
        uint256 challengeDeposit,                   // 质疑保证金
        uint256 timestamp                           // 质疑提交时间
    );

    /**
     * @notice 质疑期结束事件
     * @dev 当质疑期截止时触发
     * 统计质疑结果，决定是否需要修改投票结论
     */
    event ChallengePhaseEnded(
        uint256 indexed caseId,     // 案件ID
        uint256 totalChallenges,    // 总质疑数量
        bool resultChanged,         // 投票结果是否因质疑而改变
        uint256 timestamp           // 质疑期结束时间
    );

    /**
     * @notice 质疑结果处理事件
     * @dev 当单个质疑的结果被处理时触发
     * 记录质疑是否成功以及相关的奖惩
     */
    event ChallengeResultProcessed(
        uint256 indexed caseId,         // 案件ID
        address indexed challenger,     // 质疑者地址
        address indexed targetValidator, // 被质疑的验证者地址
        bool challengeSuccessful,       // 质疑是否成功
        uint256 timestamp               // 结果处理时间
    );

    // ==================== 奖惩相关事件 ====================
    // 这一类事件记录奖励和惩罚的计算与分配过程

    /**
     * @notice 奖惩计算开始事件
     * @dev 当案件进入奖惩计算阶段时触发
     * 标志着根据最终结果开始计算参与者的奖惩
     */
    event RewardPunishmentCalculationStarted(
        uint256 indexed caseId,     // 案件ID
        bool complaintUpheld,       // 投诉是否成立
        uint256 timestamp           // 计算开始时间
    );

    /**
     * @notice 用户诚信状态更新事件
     * @dev 当用户的诚信状态因参与案件而发生变化时触发
     * 记录用户信誉的变化历史
     */
    event UserIntegrityStatusUpdated(
        uint256 indexed caseId,                                     // 案件ID
        address indexed user,                                       // 用户地址
        DataStructures.IntegrityStatus oldStatus,                   // 更新前的诚信状态
        DataStructures.IntegrityStatus newStatus,                   // 更新后的诚信状态
        DataStructures.RewardPunishmentStatus rewardPunishmentStatus, // 奖惩状态
        uint256 timestamp                                           // 更新时间
    );

    /**
     * @notice 奖励发放事件
     * @dev 当参与者因正确表现获得奖励时触发
     * 记录奖励的分配历史和原因
     */
    event RewardDistributed(
        uint256 indexed caseId,     // 案件ID
        address indexed recipient,  // 奖励接收者地址
        uint256 amount,             // 奖励金额
        string reason,              // 奖励原因
        uint256 timestamp           // 奖励发放时间
    );

    /**
     * @notice 惩罚执行事件
     * @dev 当参与者因错误行为受到惩罚时触发
     * 记录惩罚的执行历史和原因
     */
    event PunishmentExecuted(
        uint256 indexed caseId,     // 案件ID
        address indexed target,     // 惩罚目标地址
        uint256 amount,             // 惩罚金额
        string reason,              // 惩罚原因
        uint256 timestamp           // 惩罚执行时间
    );

    // ==================== 资金池事件 ====================
    // 这一类事件记录系统资金池的状态变化

    /**
     * @notice 资金池状态更新事件
     * @dev 当系统资金池的各项余额发生变化时触发
     * 记录资金池的整体财务状况
     */
    event FundPoolUpdated(
        uint256 totalBalance,       // 总余额
        uint256 rewardPool,         // 奖励池余额
        uint256 operationalFund,    // 运营资金余额
        uint256 emergencyFund,      // 应急资金余额
        uint256 timestamp           // 更新时间
    );

    /**
     * @notice 资金转入事件
     * @dev 当资金从外部转入系统资金池时触发
     * 记录资金来源和转入历史
     */
    event FundsTransferredToPool(
        uint256 indexed caseId,     // 相关案件ID（如果适用）
        uint256 amount,             // 转入金额
        string source,              // 资金来源
        uint256 timestamp           // 转入时间
    );

    /**
     * @notice 资金转出事件
     * @dev 当资金从系统资金池转出时触发
     * 记录资金用途和转出历史
     */
    event FundsTransferredFromPool(
        address indexed recipient,  // 资金接收者地址
        uint256 amount,             // 转出金额
        string purpose,             // 转出用途
        uint256 timestamp           // 转出时间
    );

    // ==================== 案件状态事件 ====================
    // 这一类事件记录案件状态的流转过程

    /**
     * @notice 案件状态更新事件
     * @dev 当案件状态发生变化时触发
     * 记录案件在整个生命周期中的状态流转
     */
    event CaseStatusUpdated(
        uint256 indexed caseId,                 // 案件ID
        DataStructures.CaseStatus oldStatus,    // 更新前的状态
        DataStructures.CaseStatus newStatus,    // 更新后的状态
        address operator,                       // 执行状态更新的操作者
        uint256 timestamp                       // 状态更新时间
    );

    /**
     * @notice 案件完成事件
     * @dev 当案件处理完成时触发
     * 记录案件的最终结果和总结信息
     */
    event CaseCompleted(
        uint256 indexed caseId,         // 案件ID
        bool complaintUpheld,           // 投诉是否最终成立
        uint256 totalRewardAmount,      // 总奖励金额
        uint256 totalPunishmentAmount,  // 总惩罚金额
        string finalReport,             // 最终报告摘要
        uint256 timestamp               // 案件完成时间
    );

    /**
     * @notice 案件取消事件
     * @dev 当案件因特殊原因被取消时触发
     * 记录取消的原因和负责人
     */
    event CaseCancelled(
        uint256 indexed caseId,     // 案件ID
        string reason,              // 取消原因
        address operator,           // 执行取消操作的管理员
        uint256 timestamp           // 取消时间
    );

    // ==================== 消息发布事件 ====================
    // 这一类事件记录系统公告和风险警告的发布

    /**
     * @notice 公告发布事件
     * @dev 当系统发布重要公告时触发
     * 用于通知用户重要信息和政策变更
     */
    event AnnouncementPublished(
        uint256 indexed caseId,     // 相关案件ID（如果适用）
        string title,               // 公告标题
        string content,             // 公告内容
        address publisher,          // 发布者地址
        uint256 timestamp           // 发布时间
    );

    /**
     * @notice 风险警告发布事件
     * @dev 当对特定企业发布风险警告时触发
     * 提醒公众注意特定企业的食品安全风险
     */
    event RiskWarningPublished(
        address indexed enterprise,         // 被警告的企业地址
        DataStructures.RiskLevel riskLevel, // 风险等级
        string warningContent,              // 警告内容
        uint256 relatedCases,               // 相关案件数量
        uint256 timestamp                   // 警告发布时间
    );

    // ==================== 紧急事件 ====================
    // 这一类事件记录紧急情况和高风险案件的处理

    /**
     * @notice 紧急情况事件
     * @dev 当系统检测到紧急情况时触发
     * 用于快速响应食品安全紧急事件
     */
    event EmergencyTriggered(
        uint256 indexed caseId,     // 相关案件ID
        string emergencyType,       // 紧急情况类型
        string description,         // 详细描述
        address operator,           // 触发操作的管理员
        uint256 timestamp           // 紧急情况触发时间
    );

    /**
     * @notice 高风险案件处理事件
     * @dev 当高风险案件需要特殊处理时触发
     * 记录对高风险案件的特殊处理措施
     */
    event HighRiskCaseProcessed(
        uint256 indexed caseId,     // 高风险案件ID
        uint256 totalFrozenAmount,  // 总冻结金额
        address[] affectedUsers,    // 受影响的用户地址列表
        uint256 timestamp           // 处理时间
    );

    // ==================== 随机数相关事件 ====================
    // 这一类事件记录随机数生成和验证者选择过程

    /**
     * @notice 随机数请求事件
     * @dev 当系统请求随机数用于验证者选择时触发
     * 确保验证者选择过程的随机性和公正性
     */
    event RandomnessRequested(
        uint256 indexed caseId,     // 需要随机数的案件ID
        uint256 requestId,          // 随机数请求ID
        uint256 validatorPoolSize,  // 验证者池大小
        uint256 timestamp           // 请求时间
    );

    /**
     * @notice 随机数接收事件
     * @dev 当系统收到外部随机数服务提供的随机数时触发
     * 记录随机数的接收和使用过程
     */
    event RandomnessReceived(
        uint256 indexed caseId,     // 相关案件ID
        uint256 requestId,          // 对应的请求ID
        uint256 randomValue,        // 接收到的随机数值
        uint256 timestamp           // 接收时间
    );
}
