// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice VotingManager接口
 * @dev 定义DisputeManager需要调用的VotingManager函数
 */
interface IVotingManager {
    function isSelectedValidator(uint256 caseId, address validator) external view returns (bool);

}

/**
 * @notice FundManager接口
 * @dev 定义DisputeManager需要调用的FundManager函数
 */
interface IFundManager {
    function freezeDeposit(
        uint256 caseId,
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) external;

    function unfreezeDeposit(uint256 caseId, address user) external;
}

/**
 * @title DisputeManager
 * @author Food Safety Governance Team
 * @notice 质疑管理模块，负责处理对验证者投票结果的质疑
 * @dev 管理质疑流程，包括质疑提交、保证金管理、结果计算等
 * 这是确保投票公正性的重要模块，允许社区对验证者的决定提出异议
 * 通过质疑机制可以纠正可能的错误判断，维护系统的公正性
 */
contract DisputeManager is Ownable {
    // ==================== 状态变量 ====================
    /// @notice 治理合约地址 - 有权启动和结束质疑期的合约
    /// @dev 只有治理合约才能管理质疑会话的生命周期
    address public governanceContract;

    /// @notice 资金管理合约 - 负责处理质疑保证金的合约
    /// @dev 质疑保证金需要通过资金管理合约进行冻结和释放
    IFundManager public fundManager;

    /// @notice 投票管理合约 - 用于验证被质疑的验证者信息
    /// @dev 需要验证被质疑的验证者确实参与了相关案件的投票
    IVotingManager public votingManager;

    /// @notice 案件质疑信息映射 caseId => DisputeSession
    /// @dev 存储每个案件的完整质疑会话信息
    mapping(uint256 => DisputeSession) public disputeSessions;

    /// @notice 用户质疑历史记录 user => caseId => hasDisputed
    /// @dev 记录用户的质疑参与历史，防止重复操作
    mapping(address => mapping(uint256 => bool)) public userDisputeHistory;

    /// @notice 验证者被质疑次数统计 validator => disputeCount
    /// @dev 跟踪每个验证者被质疑的总次数，用于评估验证者表现
    mapping(address => uint256) public validatorDisputeCount;

    /// @notice 质疑成功率统计 challenger => successCount
    /// @dev 记录每个质疑者成功质疑的次数，评估质疑质量
    mapping(address => uint256) public challengerSuccessCount;

    /// @notice 质疑参与次数统计 challenger => totalCount
    /// @dev 记录每个质疑者的总参与次数，计算成功率使用
    mapping(address => uint256) public challengerTotalCount;

    // ==================== 结构体定义 ====================

    /**
     * @notice 质疑会话结构体
     * @dev 记录单个案件的完整质疑信息
     * 包含质疑期的时间管理、质疑统计和结果处理
     */
    struct DisputeSession {
        uint256 caseId; // 案件ID - 与此质疑会话关联的案件标识
        bool isActive; // 质疑期是否激活 - 当前是否可以提交质疑
        bool isCompleted; // 质疑是否完成 - 质疑流程是否已结束
        uint256 startTime; // 质疑开始时间 - 质疑期开始的时间戳
        uint256 endTime; // 质疑结束时间 - 质疑期截止的时间戳
        uint256 totalChallenges; // 总质疑数量 - 收到的质疑总数
        bool resultChanged; // 结果是否改变 - 质疑是否成功改变了投票结果
        // 质疑信息数组 - 存储所有提交的质疑详情
        DataStructures.ChallengeInfo[] challenges;
        mapping(address => DataStructures.ChallengeVotingInfo) challengeVotingInfo; // 质疑投票信息映射
        // 验证者质疑统计 validator => ChallengeStats
        mapping(address => ChallengeStats) validatorChallengeStats;
        // 质疑者映射 challenger => true - 快速查询某地址是否参与质疑
        mapping(address => bool) challengers;
    }

    /**
     * @notice 验证者质疑统计结构体
     * @dev 统计针对特定验证者的质疑情况
     * 包括支持和反对的质疑数量及质疑者列表
     */
    struct ChallengeStats {
        uint256 supportCount; // 支持验证者的质疑数量 - 认为验证者判断正确的质疑
        uint256 opposeCount; // 反对验证者的质疑数量 - 认为验证者判断错误的质疑
        bool hasBeenChallenged; // 是否被质疑过 - 该验证者是否收到过质疑
        address[] challengers; // 质疑者列表 - 所有质疑该验证者的地址
    }

    // ==================== 修饰符 ====================

    /**
     * @notice 只有治理合约可以调用
     * @dev 确保关键的质疑管理功能只能由授权的治理合约执行
     * 防止未授权访问质疑会话管理功能
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }

    /**
     * @notice 检查质疑期是否激活
     * @dev 确保质疑在正确的时间窗口内进行
     * 验证质疑期是否开始且未超时
     */
    modifier disputeActive(uint256 caseId) {
        DisputeSession storage session = disputeSessions[caseId];
        if (!session.isActive) {
            revert Errors.ChallengeNotStarted(caseId);
        }
        if (block.timestamp > session.endTime) {
            revert Errors.ChallengePeriodEnded(
                session.endTime,
                block.timestamp
            );
        }
        _;
    }

    /**
     * @notice 检查地址是否为零地址
     * @dev 防止将关键合约地址设置为零地址
     * 避免系统功能失效和资金丢失
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }

    // ==================== 构造函数 ====================

    /**
     * @dev 初始化质疑管理合约
     * 设置初始管理员，其他合约地址需要后续设置
     * @param _admin 管理员地址
     */
    constructor(address _admin) Ownable(_admin) {
    }

    // ==================== 质疑会话管理函数 ====================

    /**
     * @notice 开始质疑期
     * @dev 为指定案件创建新的质疑会话
     * 只能由治理合约调用，设置质疑期的时间限制
     * @param caseId 案件ID
     * @param challengeDuration 质疑持续时间（秒）
     */
    function startDisputeSession(
        uint256 caseId,
        uint256 challengeDuration
    ) external onlyGovernance {
        // 防止为同一案件重复创建质疑会话
        if (disputeSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "dispute session");
        }

        // 验证质疑持续时间的合理性
        if (challengeDuration == 0) {
            revert Errors.InvalidAmount(challengeDuration, 1);
        }

        // 创建并初始化质疑会话
        DisputeSession storage session = disputeSessions[caseId];
        session.caseId = caseId; // 设置关联的案件ID
        session.isActive = true; // 激活质疑期
        session.isCompleted = false; // 标记为未完成
        session.startTime = block.timestamp; // 设置质疑开始时间
        session.endTime = block.timestamp + challengeDuration; // 计算质疑结束时间
        session.totalChallenges = 0; // 初始化质疑计数
        session.resultChanged = false; // 初始化结果变更标志

        // 发出质疑期开始事件
        emit Events.ChallengePhaseStarted(
            caseId,
            session.endTime,
            block.timestamp
        );
    }

    /**
     * @notice 提交质疑
     * @dev 用户对特定验证者的投票决定提出质疑
     * 需要提交质疑保证金和支持证据
     * @param caseId 案件ID
     * @param targetValidator 被质疑的验证者地址
     * @param choice 质疑选择（支持或反对验证者）
     * @param reason 质疑理由
     * @param evidenceHash 证据哈希
     * @param challengeDeposit 最小质疑保证金
     */
    function submitChallenge(
        uint256 caseId,
        address targetValidator,
        DataStructures.ChallengeChoice choice,
        string calldata reason,
        string calldata evidenceHash,
        uint256 challengeDeposit
    ) external payable disputeActive(caseId) notZeroAddress(targetValidator) {
        // 验证质疑保证金金额与实际支付是否一致
        if (msg.value != challengeDeposit || challengeDeposit == 0) {
            revert Errors.InsufficientChallengeDeposit(
                msg.value,
                challengeDeposit
            );
        }

        // 检查是否尝试质疑自己，防止自我质疑的异常情况
        if (msg.sender == targetValidator) {
            revert Errors.CannotChallengeSelf(msg.sender);
        }

        // 检查是否已经质疑过该验证者，防止重复质疑
        if (_hasUserChallengedValidator(caseId, msg.sender, targetValidator)) {
            revert Errors.AlreadyChallenged(msg.sender, targetValidator);
        }

        // 检查质疑理由是否为空，确保质疑有明确的依据
        if (bytes(reason).length == 0) {
            revert Errors.EmptyChallengeReason();
        }

        // 验证证据哈希是否为空
        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }

        // 验证目标验证者确实参与了该案件的投票
        if (!votingManager.isSelectedValidator(caseId, targetValidator)) {
            revert Errors.ValidatorNotParticipating(targetValidator, caseId);
        }

        DisputeSession storage session = disputeSessions[caseId];

        // 创建完整的质疑信息结构体
        DataStructures.ChallengeInfo memory challengeInfo = DataStructures
            .ChallengeInfo({
            challenger: msg.sender, // 质疑者地址
            targetValidator: targetValidator, // 被质疑的验证者
            choice: choice, // 质疑选择（支持或反对）
            reason: reason, // 质疑理由
            evidenceHash: evidenceHash, // 支持证据哈希
            timestamp: block.timestamp, // 质疑时间
            challengeDeposit: challengeDeposit // 质疑保证金
        });

        // 更新质疑投票信息
        DataStructures.ChallengeVotingInfo challengeVotingInfo = challengeVotingInfo[targetValidator];
        challengeVotingInfo.targetValidator = targetValidator;
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            challengeVotingInfo.supporters.push(msg.sender); // 添加支持者
        } else {
            challengeVotingInfo.opponents.push(msg.sender); // 添加反对者
        }

        // 将质疑添加到会话中
        session.challenges.push(challengeInfo);
        session.totalChallenges++; // 增加质疑计数
        session.challengers[msg.sender] = true; // 标记用户已参与质疑

        // 更新针对目标验证者的质疑统计
        ChallengeStats storage stats = session.validatorChallengeStats[targetValidator];
        if (!stats.hasBeenChallenged) {
            stats.hasBeenChallenged = true; // 标记验证者已被质疑
        }

        stats.challengers.push(msg.sender); // 添加到质疑者列表

        // 根据质疑选择更新相应的计数
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            stats.supportCount++; // 支持验证者的质疑数量
        } else {
            stats.opposeCount++; // 反对验证者的质疑数量
        }

        // 更新全局统计数据
        userDisputeHistory[msg.sender][caseId] = true; // 记录用户质疑历史
        validatorDisputeCount[targetValidator]++; // 增加验证者被质疑次数
        challengerTotalCount[msg.sender]++; // 增加质疑者参与次数

        // 调用资金管理合约冻结质疑保证金
        // 质疑者和验证者都是DAO成员，采用相同的保证金处理机制
        // 注意：这里假设质疑者已经在系统中预存了足够的保证金
        // 实际的ETH支付应该通过单独的保证金存入流程处理
        fundManager.freezeDeposit(
            caseId,
            msg.sender,
            DataStructures.RiskLevel.MEDIUM, // 质疑默认为中等风险级别
            challengeDeposit // 基础保证金金额
        );

        // 发出质疑提交事件
        emit Events.ChallengeSubmitted(
            caseId,
            msg.sender,
            targetValidator,
            choice,
            reason,
            challengeDeposit,
            block.timestamp
        );
    }

    /**
     * @notice 结束质疑期并处理结果
     * @dev 计算质疑结果，决定是否改变原始投票结论
     * 只能在质疑期结束后由治理合约调用
     * @param caseId 案件ID
     * @return finalResult 最终结果
     * @return resultChanged 结果是否改变
     * @return challengerAddresses 质疑者地址数组
     * @return challengeSuccessful 质疑是否成功数组
     */
    function endDisputeSession(
        uint256 caseId
    ) external onlyGovernance returns (
        bool finalResult,
        bool resultChanged,
        address[] memory challengerAddresses,
        bool[] memory challengeSuccessful
    ) {
        DisputeSession storage session = disputeSessions[caseId];

        // 检查质疑会话是否处于活跃状态
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        // 检查是否已达到质疑期截止时间
        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }

        // 如果没有收到任何质疑，结果保持不变
        if (session.totalChallenges == 0) {
            session.isActive = false; // 停用质疑会话
            session.isCompleted = true; // 标记为已完成

            // 发出质疑期结束事件
            emit Events.ChallengePhaseEnded(caseId, 0, false, block.timestamp);

            // 返回空数组
            challengerAddresses = new address[](0);
            challengeSuccessful = new bool[](0);
            return (originalResult, false, challengerAddresses, challengeSuccessful);
        }

        // 根据质疑情况计算最终结果
        (finalResult, resultChanged) = _calculateDisputeResult(
            caseId,
            originalResult
        );

        // 准备质疑者信息数组
        challengerAddresses = new address[](session.challenges.length);
        challengeSuccessful = new bool[](session.challenges.length);

        // 计算每个质疑者的成功失败情况
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            challengerAddresses[i] = challenge.challenger;

            // 判断质疑是否成功
            if (resultChanged) {
                // 如果结果改变了，说明反对验证者的质疑成功
                challengeSuccessful[i] = (challenge.choice ==
                    DataStructures.ChallengeChoice.OPPOSE_VALIDATOR);
            } else {
                // 如果结果没改变，说明支持验证者的质疑成功
                challengeSuccessful[i] = (challenge.choice ==
                    DataStructures.ChallengeChoice.SUPPORT_VALIDATOR);
            }

            // 更新成功质疑者的统计
            if (challengeSuccessful[i]) {
                challengerSuccessCount[challenge.challenger]++;
            }
        }

        // 更新会话状态
        session.isActive = false; // 停用质疑会话
        session.isCompleted = true; // 标记为已完成
        session.resultChanged = resultChanged; // 记录结果是否改变

        // 处理质疑者的保证金解冻
        _processDisputeUnfreeze(caseId);

        // 发出质疑期结束事件
        emit Events.ChallengePhaseEnded(
            caseId,
            session.totalChallenges,
            resultChanged,
            block.timestamp
        );

        return (finalResult, resultChanged, challengerAddresses, challengeSuccessful);
    }

    /**
     * @notice 处理质疑者保证金解冻
     * @dev 内部函数，解冻所有质疑者的保证金
     * @param caseId 案件ID
     */
    function _processDisputeUnfreeze(uint256 caseId) internal {
        DisputeSession storage session = disputeSessions[caseId];

        // 遍历所有质疑，解冻质疑者的保证金
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];

            // 解冻质疑者的保证金
            // 质疑者和验证者采用相同的保证金处理机制
            fundManager.unfreezeDeposit(caseId, challenge.challenger);

            // 发出质疑结果处理事件
            emit Events.ChallengeResultProcessed(
                caseId,
                challenge.challenger,
                challenge.targetValidator,
                true, // 这里简化处理，具体成功失败由返回值传递
                block.timestamp
            );
        }
    }

    // ==================== 内部函数 ====================

    /**
     * @notice 检查用户是否已经质疑过特定验证者
     * @dev 内部函数，防止用户重复质疑同一验证者
     * 遍历已有质疑记录进行检查
     * @param caseId 案件ID
     * @param challenger 质疑者地址
     * @param targetValidator 目标验证者地址
     * @return 是否已经质疑过
     */
    function _hasUserChallengedValidator(
        uint256 caseId,
        address challenger,
        address targetValidator
    ) internal view returns (bool) {
        DisputeSession storage session = disputeSessions[caseId];

        // 遍历所有质疑记录
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            // 检查是否存在相同质疑者对相同验证者的质疑
            if (
                challenge.challenger == challenger &&
                challenge.targetValidator == targetValidator
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice 计算质疑结果
     * @dev 内部函数，根据质疑统计决定最终结果
     * 使用简单多数规则：反对验证者的质疑占多数则改变结果
     * @param caseId 案件ID
     * @param originalResult 原始投票结果
     * @return finalResult 最终结果
     * @return resultChanged 结果是否改变
     */
    function _calculateDisputeResult(
        uint256 caseId,
        bool originalResult
    ) internal view returns (bool finalResult, bool resultChanged) {
        DisputeSession storage session = disputeSessions[caseId];

        uint256 totalSupportValidators = 0; // 支持验证者的质疑总数
        uint256 totalOpposeValidators = 0; // 反对验证者的质疑总数

        // 统计所有质疑的倾向
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];

            if (
                challenge.choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR
            ) {
                totalSupportValidators++; // 支持验证者判断的质疑
            } else {
                totalOpposeValidators++; // 反对验证者判断的质疑
            }
        }

        // 如果反对验证者的质疑占多数，则推翻原始结果
        if (totalOpposeValidators > totalSupportValidators) {
            finalResult = !originalResult; // 结果取反
            resultChanged = true; // 标记结果已改变
        } else {
            finalResult = originalResult; // 保持原始结果
            resultChanged = false; // 结果未改变
        }

        return (finalResult, resultChanged);
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取质疑会话信息
     * @dev 公开查询函数，返回质疑会话的基本信息
     * 供前端和其他合约查询质疑状态
     * @param caseId 案件ID
     * @return 质疑会话的各项基本信息
     */
    function getDisputeSessionInfo(
        uint256 caseId
    )
    external
    view
    returns (
        uint256, // caseId - 案件ID
        bool, // isActive - 是否活跃
        bool, // isCompleted - 是否完成
        uint256, // startTime - 开始时间
        uint256, // endTime - 结束时间
        uint256, // totalChallenges - 总质疑数
        bool // resultChanged - 结果是否改变
    )
    {
        DisputeSession storage session = disputeSessions[caseId];

        return (
            session.caseId,
            session.isActive,
            session.isCompleted,
            session.startTime,
            session.endTime,
            session.totalChallenges,
            session.resultChanged
        );
    }

    /**
     * @notice 获取特定质疑信息
     * @dev 查询指定索引的质疑详细信息
     * @param caseId 案件ID
     * @param challengeIndex 质疑索引
     * @return 质疑详细信息
     */
    function getChallengeInfo(
        uint256 caseId,
        uint256 challengeIndex
    ) external view returns (DataStructures.ChallengeInfo memory) {
        DisputeSession storage session = disputeSessions[caseId];

        // 验证索引的有效性
        if (challengeIndex >= session.challenges.length) {
            revert Errors.InvalidAmount(
                challengeIndex,
                session.challenges.length
            );
        }

        return session.challenges[challengeIndex];
    }

    /**
     * @notice 获取验证者质疑统计
     * @dev 查询特定验证者在特定案件中的被质疑情况
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 质疑统计信息
     */
    function getValidatorChallengeStats(
        uint256 caseId,
        address validator
    )
    external
    view
    returns (
        uint256, // supportCount - 支持票数
        uint256, // opposeCount - 反对票数
        bool, // hasBeenChallenged - 是否被质疑
        address[] memory // challengers - 质疑者列表
    )
    {
        ChallengeStats storage stats = disputeSessions[caseId]
            .validatorChallengeStats[validator];

        return (
            stats.supportCount,
            stats.opposeCount,
            stats.hasBeenChallenged,
            stats.challengers
        );
    }

    /**
     * @notice 获取质疑者统计信息
     * @dev 查询质疑者的历史表现和成功率
     * @param challenger 质疑者地址
     * @return successCount 成功次数
     * @return totalCount 总参与次数
     * @return successRate 成功率（百分比）
     */
    function getChallengerStats(
        address challenger
    )
    external
    view
    returns (uint256 successCount, uint256 totalCount, uint256 successRate)
    {
        successCount = challengerSuccessCount[challenger];
        totalCount = challengerTotalCount[challenger];
        // 计算成功率，避免除零错误
        successRate = totalCount > 0 ? (successCount * 100) / totalCount : 0;

        return (successCount, totalCount, successRate);
    }

    /**
     * @notice 检查用户是否参与了某案件的质疑
     * @dev 快速查询用户的质疑参与历史
     * @param user 用户地址
     * @param caseId 案件ID
     * @return 是否参与了质疑
     */
    function hasUserDisputed(
        address user,
        uint256 caseId
    ) external view returns (bool) {
        return userDisputeHistory[user][caseId];
    }

    /**
     * @notice 获取案件的所有质疑
     * @dev 返回指定案件的完整质疑信息列表
     * @param caseId 案件ID
     * @return 质疑信息数组
     */
    function getAllChallenges(
        uint256 caseId
    ) external view returns (DataStructures.ChallengeInfo[] memory) {
        return disputeSessions[caseId].challenges;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     * @dev 设置有权管理质疑会话的治理合约地址
     * 只有合约所有者可以调用
     * @param _governanceContract 治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyOwner notZeroAddress(_governanceContract) {
        governanceContract = _governanceContract;
    }

    /**
     * @notice 设置资金管理合约地址
     * @dev 设置负责处理质疑保证金的资金管理合约地址
     * @param _fundManager 资金管理合约地址
     */
    function setFundManager(
        address _fundManager
    ) external onlyOwner notZeroAddress(_fundManager) {
        fundManager = IFundManager(_fundManager);
    }

    /**
     * @notice 设置投票管理合约地址
     * @dev 设置用于验证验证者信息的投票管理合约地址
     * @param _votingManager 投票管理合约地址
     */
    function setVotingManager(
        address _votingManager
    ) external onlyOwner notZeroAddress(_votingManager) {
        votingManager = IVotingManager(_votingManager);
    }

    /**
     * @notice 紧急暂停质疑会话
     * @dev 在紧急情况下暂停正在进行的质疑会话
     * 只有合约所有者可以调用，用于处理异常情况
     * @param caseId 案件ID
     */
    function emergencyPauseDispute(uint256 caseId) external onlyOwner {
        DisputeSession storage session = disputeSessions[caseId];

        // 检查质疑会话是否处于活跃状态
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        // 停用质疑会话
        session.isActive = false;

        // 发出紧急暂停事件
        emit Events.EmergencyTriggered(
            caseId,
            "Dispute Paused",
            "Emergency pause of dispute session",
            msg.sender,
            block.timestamp
        );
    }
}
