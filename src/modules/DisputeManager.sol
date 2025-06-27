// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../libraries/CommonModifiers.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice 投票管理合约接口
 * @dev 定义DisputeManager需要调用的投票管理合约函数
 * 用于验证质疑目标的合法性和获取投票会话信息
 */
interface IVotingManager {
    /**
     * @notice 检查指定验证者是否参与了指定案件的投票
     * @dev 质疑者只能质疑确实参与了投票的验证者
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 是否为该案件的选中验证者
     */
    function isSelectedValidator(uint256 caseId, address validator) external view returns (bool);

    /**
     * @notice 获取投票会话的基本信息
     * @dev 返回指定案件的投票会话基本数据，避免返回包含mapping的结构体
     * @param caseId 案件ID
     * @return caseId_ 案件ID
     * @return selectedValidators 选中的验证者列表
     * @return supportVotes 支持票数
     * @return rejectVotes 反对票数
     * @return totalVotes 总票数
     * @return startTime 开始时间
     * @return endTime 结束时间
     * @return isActive 是否活跃
     * @return isCompleted 是否完成
     * @return complaintUpheld 投诉是否成立
     */
    function getVotingSessionInfo(uint256 caseId) external view returns (
        uint256 caseId_,
        address[] memory selectedValidators,
        uint256 supportVotes,
        uint256 rejectVotes,
        uint256 totalVotes,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isCompleted,
        bool complaintUpheld
    );

    /**
     * @notice 获取验证者的投票信息
     * @dev 获取指定验证者在指定案件中的投票详情
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return voteInfo 验证者的投票信息
     */
    function getValidatorVote(uint256 caseId, address validator) external view returns (DataStructures.VoteInfo memory);

    /**
     * @notice 更新验证者的最终投票选择
     * @dev 在质疑期结束后，根据质疑结果更新验证者的最终投票
     * 只能由有权限的合约调用（如DisputeManager）
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @param newChoice 新的投票选择
     * @param reason 更改原因
     */
    function updateValidatorFinalChoice(
        uint256 caseId,
        address validator,
        DataStructures.VoteChoice newChoice,
        string calldata reason
    ) external;

    /**
     * @notice 更新投票会话的最终统计结果
     * @dev 在质疑期结束后，更新最终的投票统计数据
     * 只能由有权限的合约调用（如DisputeManager）
     * @param caseId 案件ID
     * @param finalSupportVotes 最终支持票数
     * @param finalRejectVotes 最终反对票数
     * @param finalComplaintUpheld 最终投诉是否成立
     */
    function updateFinalVotingResult(
        uint256 caseId,
        uint256 finalSupportVotes,
        uint256 finalRejectVotes,
        bool finalComplaintUpheld
    ) external;
}

/**
 * @notice 资金管理合约接口
 * @dev 定义DisputeManager需要调用的资金管理合约函数
 * 用于处理质疑过程中的保证金冻结和解冻操作
 */
interface IFundManager {
    /**
     * @notice 冻结用户保证金
     * @dev 在用户提交质疑时冻结相应的保证金，确保质疑的严肃性
     * @param caseId 案件ID
     * @param user 用户地址
     * @param riskLevel 案件风险级别
     * @param baseAmount 基础保证金金额
     */
    function freezeDeposit(
        uint256 caseId,
        address user,
        DataStructures.RiskLevel riskLevel,
        uint256 baseAmount
    ) external;

    /**
     * @notice 解冻用户保证金
     * @dev 在质疑期结束后解冻用户的保证金，恢复资金可用性
     * @param caseId 案件ID
     * @param user 用户地址
     */
    function unfreezeDeposit(uint256 caseId, address user) external;
}

/**
 * @notice 参与者池管理合约接口
 * @dev 定义DisputeManager需要调用的参与者池管理函数
 * 用于验证质疑者的角色权限和参与资格
 */
interface IParticipantPoolManager {
    /**
     * @notice 检查用户是否可以参与指定案件的指定角色
     * @dev 验证用户是否具有合适的角色且未参与该案件的其他阶段
     * @param caseId 案件ID
     * @param user 用户地址
     * @param requiredRole 要求的角色类型
     * @return 是否可以参与
     */
    function canParticipateInCase(
        uint256 caseId,
        address user,
        DataStructures.UserRole requiredRole
    ) external view returns (bool);
}

/**
 * @title DisputeManager
 * @author Food Safety Governance Team
 * @notice 质疑管理模块，负责处理对验证者投票结果的质疑
 * @dev 管理质疑流程，包括质疑提交、保证金管理、结果计算等
 * 这是确保投票公正性的重要模块，允许社区对验证者的决定提出异议
 * 通过质疑机制可以纠正可能的错误判断，维护系统的公正性
 */
contract DisputeManager is Ownable, CommonModifiers {
    // ==================== 状态变量 ====================
    // governanceContract 已在 CommonModifiers 中定义

    /// @notice 资金管理合约实例
    /// @dev 负责处理质疑保证金的冻结和解冻操作
    /// 质疑保证金需要通过资金管理合约进行统一管理
    IFundManager public fundManager;

    /// @notice 投票管理合约实例
    /// @dev 用于验证被质疑的验证者信息和获取投票会话数据
    /// 需要验证被质疑的验证者确实参与了相关案件的投票
    IVotingManager public votingManager;

    /// @notice 参与者池管理合约实例
    /// @dev 用于验证用户角色和参与权限
    /// 验证质疑者是否具有DAO_MEMBER角色且未参与此案件
    IParticipantPoolManager public poolManager;

    /// @notice 案件质疑会话映射
    /// @dev 存储每个案件的完整质疑会话信息
    /// 键：案件ID，值：质疑会话结构体
    /// 包含质疑期时间管理、质疑统计和结果处理
    mapping(uint256 => DisputeSession) public disputeSessions;

    /// @notice 用户质疑历史记录映射
    /// @dev 记录用户的质疑参与历史，防止重复操作和恶意行为
    /// 第一层键：用户地址，第二层键：案件ID，值：是否已质疑
    mapping(address => mapping(uint256 => bool)) public userDisputeHistory;

    /// @notice 验证者被质疑次数统计映射
    /// @dev 跟踪每个验证者被质疑的总次数，用于评估验证者表现
    /// 键：验证者地址，值：累计被质疑次数
    /// 被质疑次数过多可能影响验证者的信誉和选中概率
    mapping(address => uint256) public validatorDisputeCount;

    /// @notice 质疑者成功质疑次数统计映射
    /// @dev 记录每个质疑者成功质疑的次数，评估质疑质量
    /// 键：质疑者地址，值：成功质疑次数
    /// 成功率高的质疑者在系统中具有更高的可信度
    mapping(address => uint256) public challengerSuccessCount;

    /// @notice 质疑者总参与次数统计映射
    /// @dev 记录每个质疑者的总参与次数，用于计算成功率
    /// 键：质疑者地址，值：总参与次数
    /// 与成功次数结合可以计算质疑者的准确率
    mapping(address => uint256) public challengerTotalCount;

    // @notice 奖励成员列表
    // caseid => (role => address[])
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public rewardMember;
    // @notice 惩罚成员列表
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public punishMember;

    // ==================== 结构体定义 ====================

    /**
     * @notice 质疑会话结构体
     * @dev 记录单个案件的完整质疑信息和状态管理
     * 包含质疑期的时间管理、质疑统计和结果处理
     * 每个案件只有一个质疑会话，管理该案件的所有质疑活动
     */
    struct DisputeSession {
        uint256 caseId;             // 案件ID：与此质疑会话关联的案件唯一标识符
        bool isActive;              // 质疑期激活状态：当前是否可以提交新的质疑
        bool isCompleted;           // 质疑完成状态：质疑流程是否已结束并处理完毕
        uint256 startTime;          // 质疑开始时间：质疑期开始的时间戳
        uint256 endTime;            // 质疑结束时间：质疑期截止的时间戳
        uint256 totalChallenges;    // 总质疑数量：收到的质疑总数，用于统计和分析
        bool resultChanged;         // 结果改变标志：质疑是否成功改变了原始投票结果

        // 质疑信息存储
        DataStructures.ChallengeInfo[] challenges;                             // 质疑信息数组：存储所有提交的质疑详细信息
        mapping(address => DataStructures.ChallengeVotingInfo) challengeVotingInfo; // 质疑投票信息映射：按验证者分组的质疑信息
        mapping(address => ChallengeStats) validatorChallengeStats;             // 验证者质疑统计：每个验证者的被质疑情况统计
        mapping(address => bool) challengers;                                  // 质疑者映射：快速查询某地址是否参与质疑
    }

    /**
     * @notice 验证者质疑统计结构体
     * @dev 统计针对特定验证者的质疑情况，用于分析和决策
     * 包括支持和反对的质疑数量及质疑者列表
     */
    struct ChallengeStats {
        uint256 supportCount;       // 支持验证者的质疑数量：认为验证者判断正确的质疑总数
        uint256 opposeCount;        // 反对验证者的质疑数量：认为验证者判断错误的质疑总数
        bool hasBeenChallenged;     // 被质疑标志：该验证者是否在此案件中收到过质疑
        address[] challengers;      // 质疑者地址列表：所有质疑该验证者的用户地址
    }

    /**
     * @notice 质疑结果结构体
     * @dev 封装质疑处理的结果信息，用于统一管理质疑结果数据
     */
    struct DisputeResult {
        uint256 changedVotes;           // 被改变的投票数量
        uint256 finalSupportVotes;     // 最终支持票数
        uint256 finalRejectVotes;      // 最终反对票数
        bool finalComplaintUpheld;     // 最终投诉是否成立
        mapping(DataStructures.UserRole => address[]) rewardMember; //奖励成员列表
        mapping(DataStructures.UserRole => address[]) punishMember;//惩罚成员列表
    }

    // ==================== 修饰符 ====================

    // onlyGovernance 修饰符已在 CommonModifiers 中定义

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

    // notZeroAddress 修饰符已在 CommonModifiers 中定义

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
     * @notice 提交质疑（仅限DAO成员且未参与此案件）
     * @dev 质疑者必须是DAO_MEMBER角色且未参与此案件的验证或质疑
     * 使用统一的保证金处理机制，支持角色权限验证
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
        // 验证质疑者必须是DAO成员且未参与此案件
        if (!poolManager.canParticipateInCase(caseId, msg.sender, DataStructures.UserRole.DAO_MEMBER)) {
            revert Errors.InvalidUserRole(
                msg.sender,
                uint8(DataStructures.UserRole.DAO_MEMBER),
                uint8(DataStructures.UserRole.DAO_MEMBER)
            );
        }

        // 验证质疑保证金金额与实际支付是否一致
        if (msg.value != challengeDeposit || challengeDeposit == 0) {
            revert Errors.InvalidAmount(
                msg.value,
                challengeDeposit
            );
        }

        // 检查是否尝试质疑自己，防止自我质疑的异常情况
        if (msg.sender == targetValidator) {
            revert Errors.InsufficientPermission(msg.sender, "Cannot challenge self");
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
        DataStructures.ChallengeVotingInfo storage info = session.challengeVotingInfo[targetValidator];
        info.targetValidator = targetValidator;
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            info.supporters.push(msg.sender); // 添加支持者
        } else {
            info.opponents.push(msg.sender); // 添加反对者
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
     * @param complainantAddress 投诉者地址
     * @param enterpriseAddress 企业地址
     */
    function endDisputeSession(
        uint256 caseId,
        address complainantAddress,
        address enterpriseAddress
    ) external onlyGovernance returns (bool) {
        DisputeSession storage session = disputeSessions[caseId];

        // 验证会话状态和时间
        _validateDisputeSessionEnd(session, caseId);

        // 处理验证者的质疑结果并更新投票
        DisputeResult memory disputeResult = _processValidatorChallenges(caseId, session);

        // 更新最终投票统计
        _updateFinalVotingStats(caseId, disputeResult);

        // 处理最终的奖惩分配
        _processFinalRewardPunishment(
            caseId,
            disputeResult.finalComplaintUpheld,
            complainantAddress,
            enterpriseAddress
        );

        // 更新会话状态
        _finalizeDisputeSession(session, disputeResult.changedVotes > 0);

        // 更新统计数据
        _updateChallengerStats(caseId, session);

        // 发出质疑期结束事件
        emit Events.ChallengePhaseEnded(
            caseId,
            session.totalChallenges,
            disputeResult.finalComplaintUpheld,
            block.timestamp
        );

        // 注意：保证金解冻应该在奖惩处理完成后由单独的函数处理
        // 这样可以确保奖惩流程完全完成后再释放资金
        // 调用者需要在适当的时机调用 processDisputeUnfreeze() 函数

        return disputeResult.finalComplaintUpheld;
    }

    /**
     * @notice 处理质疑者保证金解冻
     * @dev 在质疑流程和奖惩处理完成后，解冻所有质疑者的保证金
     * 只能由治理合约调用，确保在适当的时机释放资金
     * @param caseId 案件ID
     */
    function processDisputeUnfreeze(uint256 caseId) external onlyGovernance {
        DisputeSession storage session = disputeSessions[caseId];

        // 验证质疑会话是否已经完成
        if (!session.isCompleted) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        // 验证质疑会话是否已经不再活跃
        if (session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 1, 0);
        }

        // 遍历所有质疑，解冻质疑者的保证金
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            address challenger = challenge.challenger;
            address targetValidator = challenge.targetValidator;

            // 判断质疑是否成功，用于事件记录
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator];
            bool isSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length;

            // 解冻质疑者的保证金
            fundManager.unfreezeDeposit(caseId, challenger);

            // 发出质疑结果处理事件，记录实际的成功失败状态
            emit Events.ChallengeResultProcessed(
                caseId,
                challenger,
                targetValidator,
                isSuccessful,
                block.timestamp
            );
        }

        // 发出保证金解冻完成事件
        emit Events.DepositUnfrozen(
            caseId,
            address(this), // 使用合约地址作为标识
            session.challenges.length, // 解冻的质疑者数量
            block.timestamp
        );
    }

    // ==================== 内部函数 ====================

    /**
     * @notice 验证质疑会话结束的前置条件
     * @dev 检查会话状态和时间条件
     * @param session 质疑会话存储引用
     * @param caseId 案件ID
     */
    function _validateDisputeSessionEnd(
        DisputeSession storage session,
        uint256 caseId
    ) internal view {
        // 检查质疑会话是否处于活跃状态
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        // 检查是否已达到质疑期截止时间
        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }
    }

    /**
     * @notice 处理验证者的质疑结果并更新投票
     * @dev 遍历所有验证者，根据质疑情况调整其投票选择
     * @param caseId 案件ID
     * @param session 质疑会话存储引用
     * @return disputeResult 质疑处理结果
     */
    function _processValidatorChallenges(
        uint256 caseId,
        DisputeSession storage session
    ) internal returns (DisputeResult memory disputeResult) {
        // 简化实现：基于质疑会话中的信息处理
        // 初始化基础数据
        disputeResult.finalSupportVotes = 0;
        disputeResult.finalRejectVotes = 0;

        // 遍历所有质疑，统计结果
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            address targetValidator = challenge.targetValidator;
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator];

            // 检查是否有质疑且反对者多于支持者（质疑成功）
            bool isChallengeSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length;

            if (isChallengeSuccessful) {
                // 质疑成功，记录变化
                disputeResult.changedVotes++;

                // 处理奖惩
                _addAddressesToList(DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents, disputeResult, true);
                _addAddressesToList(DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters, disputeResult, false);
                disputeResult.punishMember[DataStructures.UserRole.DAO_MEMBER].push(targetValidator);

                // 模拟投票翻转（简化逻辑）
                disputeResult.finalRejectVotes++;
            } else {
                // 质疑失败，维持原结果
                _addAddressesToList(, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters, true);
                _addAddressesToList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents, false);

                // 维持原投票
                disputeResult.finalSupportVotes++;
            }
        }

        // 计算最终结果
        disputeResult.finalComplaintUpheld = disputeResult.finalSupportVotes > disputeResult.finalRejectVotes;

        return disputeResult;
    }

    /**
     * @notice 处理投票翻转的情况
     * @dev 当验证者被成功质疑时，翻转其投票并处理相关奖惩
     * @param caseId 案件ID
     * @param validatorAddress 验证者地址
     * @param challengeInfo 质疑投票信息
     * @param currentSupportVotes 当前支持票数
     * @param currentRejectVotes 当前反对票数
     * @return newSupportVotes 新的支持票数
     * @return newRejectVotes 新的反对票数
     */
    function _handleVoteReversal(
        uint256 caseId,
        address validatorAddress,
        DataStructures.ChallengeVotingInfo storage challengeInfo,
        uint256 currentSupportVotes,
        uint256 currentRejectVotes
    ) internal returns (uint256 newSupportVotes, uint256 newRejectVotes) {
        // 获取原始投票信息 - 需要通过VotingManager获取
        // 注意：这里需要调用votingManager来更新实际的投票信息
        // 为了保持逻辑不变，这里模拟原始逻辑

        // 翻转投票统计（假设翻转一票）
        newSupportVotes = currentSupportVotes - 1;
        newRejectVotes = currentRejectVotes + 1;

        // 奖励反对者（质疑成功者）
        _addAddressesToList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents, true);

        // 惩罚支持者（质疑失败者）
        _addAddressesToList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters, false);

        // 惩罚被质疑成功的验证者
        punishMember[caseId][DataStructures.UserRole.DAO_MEMBER].push(validatorAddress);

        return (newSupportVotes, newRejectVotes);
    }

    /**
     * @notice 处理投票维持的情况
     * @dev 当验证者没有被成功质疑时，维持原投票结果并处理奖惩
     * @param caseId 案件ID
     * @param challengeInfo 质疑投票信息
     */
    function _handleVoteMaintained(
        uint256 caseId,
        DataStructures.ChallengeVotingInfo storage challengeInfo
    ) internal {
        // 维持原投票结果，奖励支持者，惩罚反对者
        _addAddressesToList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters, true);
        _addAddressesToList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents, false);
    }

    /**
     * @notice 更新最终投票统计
     * @dev 将质疑结果直接应用到投票管理器中，实现真正的投票数据更新
     * @param caseId 案件ID
     * @param disputeResult 质疑处理结果
     */
    function _updateFinalVotingStats(
        uint256 caseId,
        DisputeResult memory disputeResult
    ) internal {
        // 直接调用VotingManager更新最终投票结果
        votingManager.updateFinalVotingResult(
            caseId,
            disputeResult.finalSupportVotes,
            disputeResult.finalRejectVotes,
            disputeResult.finalComplaintUpheld
        );

        // 如果有具体的验证者投票被改变，也要更新他们的最终选择
        if (disputeResult.changedVotes > 0) {
            _updateChangedValidatorVotes(caseId, disputeResult);
        }

        // 发出质疑结果导致的投票变更事件
        if (disputeResult.changedVotes > 0) {
            emit Events.ChallengeCompleted(
                caseId,
                true,                             // 结果确实发生了改变
                disputeResult.changedVotes,       // 改变的投票数量
                block.timestamp
            );
        }

        // 更新本地统计记录，为查询功能提供支持
        _recordFinalVotingStats(caseId, disputeResult);
    }

    /**
     * @notice 更新被质疑成功的验证者的投票选择
     * @dev 遍历所有被成功质疑的验证者，翻转其投票选择
     * @param caseId 案件ID
     * @param disputeResult 质疑处理结果
     */
    function _updateChangedValidatorVotes(
        uint256 caseId,
        DisputeResult memory disputeResult
    ) internal {
        DisputeSession storage session = disputeSessions[caseId];

        // 遍历所有质疑，找出被成功质疑的验证者
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            address targetValidator = challenge.targetValidator;
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator];

            // 检查是否质疑成功（反对者多于支持者）
            bool isChallengeSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length;

            if (isChallengeSuccessful) {
                // 获取验证者的原始投票
                DataStructures.VoteInfo memory voteInfo = votingManager.getValidatorVote(caseId, targetValidator);

                // 确定新的投票选择（翻转原选择）
                DataStructures.VoteChoice newChoice;
                if (voteInfo.choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
                    newChoice = DataStructures.VoteChoice.REJECT_COMPLAINT;
                } else {
                    newChoice = DataStructures.VoteChoice.SUPPORT_COMPLAINT;
                }

                // 调用VotingManager更新验证者的最终选择
                votingManager.updateValidatorFinalChoice(
                    caseId,
                    targetValidator,
                    newChoice,
                    "Vote reversed due to successful challenge"
                );
            }
        }
    }

    /**
     * @notice 记录最终投票统计数据
     * @dev 内部函数，将最终统计数据保存到合约状态中
     * @param caseId 案件ID
     * @param disputeResult 质疑处理结果
     */
    function _recordFinalVotingStats(
        uint256 caseId,
        DisputeResult memory disputeResult
    ) internal {
        // 在质疑会话中记录最终的统计信息
        DisputeSession storage session = disputeSessions[caseId];

        // 记录质疑是否改变了最终结果
        session.resultChanged = disputeResult.changedVotes > 0;

        // 现在我们可以真正更新投票管理器中的数据
        // 不再需要通过事件来间接记录，而是直接调用VotingManager的方法
    }

    /**
     * @notice 处理最终的奖惩分配
     * @dev 根据最终结果决定投诉者和企业的奖惩
     * @param caseId 案件ID
     * @param finalComplaintUpheld 最终投诉是否成立
     * @param complainantAddress 投诉者地址
     * @param enterpriseAddress 企业地址
     */
    function _processFinalRewardPunishment(
        uint256 caseId,
        bool finalComplaintUpheld,
        address complainantAddress,
        address enterpriseAddress
    ) internal {
        if (finalComplaintUpheld) {
            // 投诉成立，奖励投诉者，惩罚企业
            rewardMember[caseId][DataStructures.UserRole.COMPLAINANT].push(complainantAddress);
            punishMember[caseId][DataStructures.UserRole.ENTERPRISE].push(enterpriseAddress);
        } else {
            // 投诉不成立，惩罚投诉者，奖励企业
            punishMember[caseId][DataStructures.UserRole.COMPLAINANT].push(complainantAddress);
            rewardMember[caseId][DataStructures.UserRole.ENTERPRISE].push(enterpriseAddress);
        }
    }

    /**
     * @notice 完成质疑会话
     * @dev 更新会话的最终状态
     * @param session 质疑会话存储引用
     * @param resultChanged 结果是否发生改变
     */
    function _finalizeDisputeSession(
        DisputeSession storage session,
        bool resultChanged
    ) internal {
        session.isActive = false;
        session.isCompleted = true;
        session.resultChanged = resultChanged;
    }

    /**
     * @notice 更新质疑者统计数据
     * @dev 更新成功质疑次数等统计信息
     * @param caseId 案件ID
     * @param session 质疑会话存储引用
     */
    function _updateChallengerStats(
        uint256 caseId,
        DisputeSession storage session
    ) internal {
        // 遍历所有质疑，更新质疑者的成功统计
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            address challenger = challenge.challenger;
            address targetValidator = challenge.targetValidator;

            // 检查这个质疑是否成功
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator];
            bool isSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length;

            if (isSuccessful) {
                challengerSuccessCount[challenger]++;
            }
        }
    }

    /**
     * @notice 批量添加地址到奖励或惩罚列表
     * @dev 统一处理奖励和惩罚列表的地址添加，支持存储数组
     * @param caseId 案件ID
     * @param role 用户角色
     * @param addresses 地址数组（存储类型）
     * @param isReward 是否为奖励列表（true为奖励，false为惩罚）
     */
    function _addAddressesToList(
        DataStructures.UserRole role,
        address[] storage addresses,
        DisputeResult memory disputeResult,
        bool isReward
    ) internal {
        for (uint i = 0; i < addresses.length; i++) {
            if (isReward) {
                disputeResult.rewardMember[role].push(addresses[i]);
            } else {
                disputeResult.punishMember[role].push(addresses[i]);
            }
        }
    }

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

    /**
     * @notice 获取案件的奖励成员列表
     * @dev 返回指定案件中特定角色的奖励成员地址列表
     * @param caseId 案件ID
     * @param role 用户角色
     * @return 奖励成员地址数组
     */
    function getRewardMembers(
        uint256 caseId,
        DataStructures.UserRole role
    ) external view returns (address[] memory) {
        return rewardMember[caseId][role];
    }

    /**
     * @notice 获取案件的惩罚成员列表
     * @dev 返回指定案件中特定角色的惩罚成员地址列表
     * @param caseId 案件ID
     * @param role 用户角色
     * @return 惩罚成员地址数组
     */
    function getPunishMembers(
        uint256 caseId,
        DataStructures.UserRole role
    ) external view returns (address[] memory) {
        return punishMember[caseId][role];
    }

    /**
 * @notice 获取案件的所有奖惩结果概览
     * @dev 返回案件的奖惩结果统计信息
     * @param caseId 案件ID
     * @return totalRewardedDAO DAO成员奖励总数
     * @return totalPunishedDAO DAO成员惩罚总数
     * @return complainantRewarded 投诉者是否获得奖励
     * @return enterprisePunished 企业是否受到惩罚
     */
    function getCaseRewardPunishmentSummary(
        uint256 caseId
    ) external view returns (
        uint256 totalRewardedDAO,
        uint256 totalPunishedDAO,
        bool complainantRewarded,
        bool enterprisePunished
    ) {
        totalRewardedDAO = rewardMember[caseId][DataStructures.UserRole.DAO_MEMBER].length;
        totalPunishedDAO = punishMember[caseId][DataStructures.UserRole.DAO_MEMBER].length;
        complainantRewarded = rewardMember[caseId][DataStructures.UserRole.COMPLAINANT].length > 0;
        enterprisePunished = punishMember[caseId][DataStructures.UserRole.ENTERPRISE].length > 0;

        return (totalRewardedDAO, totalPunishedDAO, complainantRewarded, enterprisePunished);
    }

    /**
     * @notice 检查是否可以进行保证金解冻
     * @dev 查询质疑会话是否已完成，可以进行保证金解冻
     * @param caseId 案件ID
     * @return canUnfreeze 是否可以解冻
     * @return reason 不能解冻的原因（如果适用）
     */
    function canProcessDisputeUnfreeze(
        uint256 caseId
    ) external view returns (bool canUnfreeze, string memory reason) {
        DisputeSession storage session = disputeSessions[caseId];

        // 检查质疑会话是否存在
        if (session.caseId == 0) {
            return (false, "Dispute session does not exist");
        }

        // 检查质疑会话是否已经完成
        if (!session.isCompleted) {
            return (false, "Dispute session not completed");
        }

        // 检查质疑会话是否仍然活跃
        if (session.isActive) {
            return (false, "Dispute session still active");
        }

        // 检查是否有质疑者需要解冻保证金
        if (session.challenges.length == 0) {
            return (false, "No challenges to unfreeze");
        }

        return (true, "Ready for deposit unfreeze");
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
     * @notice 设置参与者池管理合约地址
     * @dev 设置用于验证用户角色和参与权限的参与者池管理合约地址
     * @param _poolManager 参与者池管理合约地址
     */
    function setPoolManager(
        address _poolManager
    ) external onlyOwner notZeroAddress(_poolManager) {
        poolManager = IParticipantPoolManager(_poolManager);
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
            "Emergency pause of dispute session",
            msg.sender,
            block.timestamp
        );
    }
}
