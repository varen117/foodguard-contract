// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，支持自定义错误特性

/**
 * @title Errors
 * @author Food Safety Governance Team
 * @notice 定义食品安全治理系统中使用的所有自定义错误
 * @dev 使用自定义错误而不是 require + string 来节约 gas
 * 自定义错误比传统字符串错误消耗更少的gas，同时提供更好的调试信息
 * 所有错误都按功能模块分类，便于维护和理解
 */
library Errors {
    // ==================== 通用错误 ====================
    // 这一类错误是系统中最基础的错误类型，在多个模块中都可能遇到

    /// @notice 零地址错误 - 当传入地址为0x0时抛出
    /// @dev 防止将关键合约地址设置为零地址，避免资金丢失
    error ZeroAddress();

    /// @notice 无效的金额 - 当提供的金额不符合要求时抛出
    /// @dev 比较提供的金额与所需金额，在保证金不足等场景使用
    error InvalidAmount(uint256 provided, uint256 required);

    /// @notice 权限不足 - 当调用者没有执行特定操作的权限时抛出
    /// @dev 基于角色的访问控制，防止未授权操作
    error InsufficientPermission(address caller, string requiredRole);

    /// @notice 操作超时 - 当操作超过预设时间限制时抛出
    /// @dev 确保时间敏感的操作在规定时间内完成
    error OperationTimeout(uint256 deadline, uint256 currentTime);

    /// @notice 重复操作 - 当用户尝试重复执行某个操作时抛出
    /// @dev 防止投票、质疑等操作被重复执行
    error DuplicateOperation(address user, string operation);

    /// @notice 系统暂停 - 当系统处于维护或紧急状态时抛出
    /// @dev 紧急情况下暂停系统所有操作的安全机制
    error SystemPaused();

    // ==================== 案件相关错误 ====================
    // 这一类错误与投诉案件的生命周期管理相关

    /// @notice 案件不存在 - 当查询的案件ID不存在时抛出
    /// @dev 防止对不存在的案件进行操作
    error CaseNotFound(uint256 caseId);

    /// @notice 案件状态无效 - 当案件状态与预期不符时抛出
    /// @dev 确保案件按照正确的状态流转进行操作
    error InvalidCaseStatus(
        uint256 caseId,        // 案件ID
        uint8 currentStatus,   // 当前状态
        uint8 requiredStatus   // 要求的状态
    );

    /// @notice 案件已完成 - 当尝试操作已完成的案件时抛出
    /// @dev 防止对已结束的案件进行修改
    error CaseAlreadyCompleted(uint256 caseId);

    /// @notice 案件已取消 - 当尝试操作已取消的案件时抛出
    /// @dev 防止对已取消的案件继续进行流程
    error CaseAlreadyCancelled(uint256 caseId);

    /// @notice 案件风险等级无效 - 当设置了不存在的风险等级时抛出
    /// @dev 确保风险等级在预定义的范围内（LOW, MEDIUM, HIGH）
    error InvalidRiskLevel(uint8 riskLevel);

    // ==================== 投诉相关错误 ====================
    // 这一类错误与投诉创建和管理相关

    /// @notice 投诉保证金不足 - 当投诉者提供的保证金低于要求时抛出
    /// @dev 确保投诉者有足够的经济责任承担投诉后果
    error InsufficientComplaintDeposit(uint256 provided, uint256 required);

    /// @notice 投诉者不能对自己的企业投诉 - 防止自我投诉的恶意行为
    /// @dev 避免企业通过自我投诉来操纵系统
    error CannotComplainAgainstSelf(address complainant, address enterprise);

    /// @notice 投诉内容为空 - 当投诉描述或标题为空时抛出
    /// @dev 确保投诉包含有意义的内容
    error EmptyComplaintContent();

    /// @notice 投诉证据不足 - 当提供的证据数量不满足要求时抛出
    /// @dev 确保投诉有足够的证据支撑
    error InsufficientEvidence(uint256 provided, uint256 required);

    /// @notice 重复投诉 - 当对同一企业进行重复投诉时抛出
    /// @dev 防止恶意重复投诉，保护企业权益
    error DuplicateComplaint(address complainant, address enterprise);

    // ==================== 企业相关错误 ====================
    // 这一类错误与企业注册和参与治理相关

    /// @notice 企业保证金不足 - 当企业提供的保证金低于要求时抛出
    /// @dev 确保企业有足够的保证金参与治理流程
    error InsufficientEnterpriseDeposit(uint256 provided, uint256 required);

    /// @notice 企业未注册 - 当企业尚未在系统中注册时抛出
    /// @dev 确保只有注册企业才能参与治理流程
    error EnterpriseNotRegistered(address enterprise);

    /// @notice 企业已被暂停 - 当企业因违规被暂停时抛出
    /// @dev 防止被暂停的企业继续参与系统
    error EnterpriseSuspended(address enterprise);

    /// @notice 企业保证金已锁定 - 当企业的保证金正在被使用时抛出
    /// @dev 防止企业在参与案件时撤回保证金
    error EnterpriseDepositLocked(address enterprise);

    // ==================== 验证者相关错误 ====================
    // 这一类错误与验证者的选择、权限和管理相关

    /// @notice 验证者数量不足 - 当参与验证的人数低于最低要求时抛出
    /// @dev 确保有足够的验证者参与，保证决策的公正性
    error InsufficientValidators(uint256 current, uint256 required);

    /// @notice 验证者数量超限 - 当验证者数量超过系统限制时抛出
    /// @dev 防止验证者过多影响效率和gas消耗
    error TooManyValidators(uint256 current, uint256 maximum);

    /// @notice 不是有效的验证者 - 当用户没有验证者资格时抛出
    /// @dev 确保只有合格的验证者才能参与投票
    error NotAuthorizedValidator(address user);

    /// @notice 验证者已质疑过 - 当验证者已经被质疑时抛出
    /// @dev 防止对同一验证者重复质疑
    error ValidatorAlreadyChallenged(address validator);

    /// @notice 验证者声誉不足 - 当验证者声誉分数不满足要求时抛出
    /// @dev 确保只有高声誉的验证者参与重要案件
    error InsufficientValidatorReputation(
        address validator,  // 验证者地址
        uint256 current,    // 当前声誉分数
        uint256 required    // 要求的声誉分数
    );

    /// @notice 验证者保证金不足 - 当验证者保证金低于要求时抛出
    /// @dev 确保验证者有足够的经济激励保持诚实
    error InsufficientValidatorDeposit(uint256 provided, uint256 required);

    // ==================== 投票相关错误 ====================
    // 这一类错误与投票流程和规则相关

    /// @notice 投票期未开始 - 当在投票期开始前尝试投票时抛出
    /// @dev 确保投票在正确的时间窗口内进行
    error VotingNotStarted(uint256 caseId);

    /// @notice 投票期已结束 - 当在投票截止时间后尝试投票时抛出
    /// @dev 保证投票的时效性，防止延迟投票
    error VotingPeriodEnded(uint256 deadline, uint256 currentTime);

    /// @notice 已经投过票 - 当验证者尝试重复投票时抛出
    /// @dev 确保每个验证者只能投票一次
    error AlreadyVoted(address voter, uint256 caseId);

    /// @notice 投票选择无效 - 当提供了不在允许范围内的投票选项时抛出
    /// @dev 确保投票选择在预定义的选项中
    error InvalidVoteChoice(uint8 choice);

    /// @notice 投票理由为空 - 当投票时未提供理由时抛出
    /// @dev 确保投票有明确的逻辑依据
    error EmptyVoteReason();

    /// @notice 验证者未参与此案件 - 当验证者不在案件的验证者列表中时抛出
    /// @dev 确保只有被选中的验证者才能参与投票
    error ValidatorNotParticipating(address validator, uint256 caseId);

    // ==================== 质疑相关错误 ====================
    // 这一类错误与质疑流程和规则相关

    /// @notice 质疑期未开始 - 当在质疑期开始前尝试质疑时抛出
    /// @dev 确保质疑在正确的时间窗口内进行
    error ChallengeNotStarted(uint256 caseId);

    /// @notice 质疑期已结束 - 当在质疑截止时间后尝试质疑时抛出
    /// @dev 保证质疑的时效性，维护流程秩序
    error ChallengePeriodEnded(uint256 deadline, uint256 currentTime);

    /// @notice 质疑保证金不足 - 当质疑者提供的保证金低于要求时抛出
    /// @dev 防止恶意质疑，确保质疑者有经济责任
    error InsufficientChallengeDeposit(uint256 provided, uint256 required);

    /// @notice 已经质疑过该验证者 - 当质疑者重复质疑同一验证者时抛出
    /// @dev 防止重复质疑，避免骚扰行为
    error AlreadyChallenged(address challenger, address validator);

    /// @notice 不能质疑自己 - 当验证者尝试质疑自己时抛出
    /// @dev 防止自我质疑的异常情况
    error CannotChallengeSelf(address challenger);

    /// @notice 质疑选择无效 - 当提供了不在允许范围内的质疑选项时抛出
    /// @dev 确保质疑选择在预定义的选项中
    error InvalidChallengeChoice(uint8 choice);

    /// @notice 质疑理由为空 - 当质疑时未提供理由时抛出
    /// @dev 确保质疑有明确的逻辑依据
    error EmptyChallengeReason();

    /// @notice 被质疑的验证者未参与投票 - 当质疑目标不在投票者列表中时抛出
    /// @dev 确保只能质疑实际参与投票的验证者
    error TargetValidatorNotParticipating(address validator, uint256 caseId);

    // ==================== 资金相关错误 ====================
    // 这一类错误与资金管理、转账和计算相关

    /// @notice 余额不足 - 当用户余额无法满足操作需求时抛出
    /// @dev 防止资金不足时的非法操作
    error InsufficientBalance(
        address user,       // 用户地址
        uint256 required,   // 所需金额
        uint256 available   // 可用金额
    );

    /// @notice 保证金已被冻结 - 当尝试使用已冻结的保证金时抛出
    /// @dev 防止在案件进行中撤回保证金
    error DepositAlreadyFrozen(address user, uint256 amount);

    /// @notice 资金转移失败 - 当ETH或代币转账失败时抛出
    /// @dev 处理底层转账失败的情况
    error TransferFailed(address to, uint256 amount);

    /// @notice 资金池余额不足 - 当系统资金池无法满足支付需求时抛出
    /// @dev 确保系统有足够资金进行奖励分配
    error InsufficientFundPool(uint256 required, uint256 available);

    /// @notice 奖励计算错误 - 当奖励金额计算出现异常时抛出
    /// @dev 处理奖励分配算法的异常情况
    error RewardCalculationError(string reason);

    /// @notice 惩罚计算错误 - 当惩罚金额计算出现异常时抛出
    /// @dev 处理惩罚分配算法的异常情况
    error PunishmentCalculationError(string reason);

    // ==================== 动态保证金相关错误 ====================
    // 这一类错误与动态保证金机制相关

    /// @notice 保证金状态异常 - 当用户保证金状态与预期不符时抛出
    /// @dev 确保保证金状态转换的正确性
    error InvalidDepositStatus(address user, uint8 currentStatus, uint8 expectedStatus);

    /// @notice 用户操作被限制 - 当用户因保证金不足被限制操作时抛出
    /// @dev 保护系统免受保证金不足用户的风险
    error UserOperationRestricted(address user, string reason);

    /// @notice 保证金不足以满足动态要求 - 当用户保证金无法满足动态计算的要求时抛出
    /// @dev 根据用户风险状况动态调整保证金要求
    error InsufficientDynamicDeposit(address user, uint256 required, uint256 available);

    /// @notice 用户处于清算状态 - 当用户保证金严重不足面临清算时抛出
    /// @dev 强制清算机制的触发条件
    error UserInLiquidation(address user);



    /// @notice 声誉分数过低 - 当用户声誉不满足特定操作要求时抛出
    /// @dev 基于声誉的准入机制
    error InsufficientReputation(address user, uint256 current, uint256 required);

    /// @notice 并发案件数量过多 - 当用户同时参与的案件超过限制时抛出
    /// @dev 防止用户过度参与导致的风险
    error TooManyConcurrentCases(address user, uint256 current, uint256 limit);

    // ==================== 奖惩相关错误 ====================
    // 这一类错误与奖励和惩罚机制相关

    /// @notice 奖惩阶段未开始 - 当在奖惩阶段开始前尝试处理时抛出
    /// @dev 确保奖惩在正确的时机进行
    error RewardPunishmentNotStarted(uint256 caseId);

    /// @notice 奖惩已经处理过 - 当尝试重复处理奖惩时抛出
    /// @dev 防止重复分配奖励或惩罚
    error RewardPunishmentAlreadyProcessed(uint256 caseId);

    /// @notice 无效的奖惩类型 - 当提供了不存在的奖惩类型时抛出
    /// @dev 确保奖惩类型在预定义范围内
    error InvalidRewardPunishmentType(uint8 rewardType);

    /// @notice 奖励金额超出限制 - 当奖励金额超过系统设定的上限时抛出
    /// @dev 防止异常的高额奖励
    error RewardAmountExceeded(uint256 amount, uint256 limit);

    /// @notice 惩罚金额超出保证金 - 当惩罚金额超过用户保证金时抛出
    /// @dev 确保惩罚金额在合理范围内
    error PunishmentExceedsDeposit(uint256 punishment, uint256 deposit);

    // ==================== 时间相关错误 ====================
    // 这一类错误与时间验证和时间窗口相关

    /// @notice 时间戳无效 - 当提供的时间戳不合理时抛出
    /// @dev 验证时间戳的合理性
    error InvalidTimestamp(uint256 provided, uint256 current);

    /// @notice 事件时间不能晚于投诉时间 - 当事发时间在投诉时间之后时抛出
    /// @dev 确保时间逻辑的合理性
    error IncidentTimeAfterComplaint(
        uint256 incidentTime,   // 事发时间
        uint256 complaintTime   // 投诉时间
    );

    /// @notice 操作过早 - 当操作在允许时间之前执行时抛出
    /// @dev 确保操作在正确的时间窗口内
    error OperationTooEarly(uint256 currentTime, uint256 allowedTime);

    /// @notice 操作过晚 - 当操作超过截止时间时抛出
    /// @dev 确保操作的时效性
    error OperationTooLate(uint256 currentTime, uint256 deadline);

    // ==================== 证据相关错误 ====================
    // 这一类错误与证据提交和验证相关

    /// @notice 证据描述为空 - 当证据没有提供描述信息时抛出
    /// @dev 确保证据有明确的说明
    error EmptyEvidenceDescription();

    /// @notice 无效的 IPFS 哈希 - 当IPFS哈希格式不正确时抛出
    /// @dev 验证IPFS哈希的有效性
    error InvalidIPFSHash(string hash);



    // ==================== 配置相关错误 ====================
    // 这一类错误与系统配置和参数设置相关

    /// @notice 配置参数无效 - 当配置参数值不合理时抛出
    /// @dev 验证系统配置参数的合理性
    error InvalidConfiguration(string parameter, uint256 value);

    /// @notice 配置超出范围 - 当配置值超出允许范围时抛出
    /// @dev 确保配置参数在安全范围内
    error ConfigurationOutOfRange(
        string parameter,   // 参数名称
        uint256 value,      // 设置的值
        uint256 min,        // 最小值
        uint256 max         // 最大值
    );

    /// @notice 只有管理员可以修改配置 - 当非管理员尝试修改配置时抛出
    /// @dev 保护系统配置的安全性
    error OnlyAdminCanModifyConfig();

    // ==================== 随机数相关错误 ====================
    // 这一类错误与随机数生成和验证者选择相关

    /// @notice 随机数生成失败 - 当随机数生成过程出现错误时抛出
    /// @dev 处理随机数生成的异常情况
    error RandomGenerationFailed();

    /// @notice 随机数种子无效 - 当随机数种子不符合要求时抛出
    /// @dev 确保随机数的安全性和不可预测性
    error InvalidRandomSeed();

    /// @notice 验证者选择失败 - 当无法选择足够验证者时抛出
    /// @dev 处理验证者选择算法的异常情况
    error ValidatorSelectionFailed(string reason);
}
