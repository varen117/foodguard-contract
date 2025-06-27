// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../libraries/CommonModifiers.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice 资金管理合约接口
 * @dev 定义合约需要调用的资金管理合约函数
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
 * @notice 参与者池管理合约接口
 * @dev 定义合约需要调用的参与者池管理函数
 */
interface IParticipantPoolManager {
    function canParticipateInCase(
        uint256 caseId,
        address user,
        DataStructures.UserRole requiredRole
    ) external view returns (bool);
}

/**
 * @title VotingDisputeManager
 * @author Food Safety Governance Team
 * @notice 投票和质疑管理模块的合并版本，负责处理验证者投票和质疑流程
 * @dev 整合了投票管理和质疑管理的所有功能，简化系统架构
 */
contract VotingDisputeManager is Ownable, CommonModifiers {
    // ==================== 状态变量 ====================

    /// @notice 资金管理合约实例
    IFundManager public fundManager;

    /// @notice 参与者池管理合约实例
    IParticipantPoolManager public poolManager;

    // ========== 投票相关状态变量 ==========

    /// @notice 案件的投票信息映射
    mapping(uint256 => DataStructures.VotingSession) public votingSessions;

    /// @notice 用户参与的投票记录
    mapping(address => mapping(uint256 => bool)) public userVotingHistory;

    // ========== 质疑相关状态变量 ==========

    /// @notice 案件质疑会话映射
    mapping(uint256 => DisputeSession) public disputeSessions;

    /// @notice 用户质疑历史记录映射
    mapping(address => mapping(uint256 => bool)) public userDisputeHistory;

    /// @notice 验证者被质疑次数统计映射
    mapping(address => uint256) public validatorDisputeCount;

    /// @notice 质疑者成功质疑次数统计映射
    mapping(address => uint256) public challengerSuccessCount;

    /// @notice 质疑者总参与次数统计映射
    mapping(address => uint256) public challengerTotalCount;

    /// @notice 奖励成员列表
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public rewardMember;

    /// @notice 惩罚成员列表
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public punishMember;

    // ==================== 结构体定义 ====================

    /**
     * @notice 质疑会话结构体
     */
    struct DisputeSession {
        uint256 caseId;
        bool isActive;
        bool isCompleted;
        uint256 startTime;
        uint256 endTime;
        uint256 totalChallenges;
        bool resultChanged;
        DataStructures.ChallengeInfo[] challenges;
        mapping(address => DataStructures.ChallengeVotingInfo) challengeVotingInfo;
        mapping(address => bool) challengers;
    }

    /**
     * @notice 质疑结果结构体（简化版，移除mapping）
     */
    struct DisputeResult {
        uint256 changedVotes;
        uint256 finalSupportVotes;
        uint256 finalRejectVotes;
        bool finalComplaintUpheld;
        address[] rewardedMembers;
        address[] punishedMembers;
    }

    // ==================== 修饰符 ====================

    modifier caseExists(uint256 caseId) {
        if (votingSessions[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    modifier votingActive(uint256 caseId) {
        DataStructures.VotingSession storage session = votingSessions[caseId];
        if (!session.isActive || block.timestamp > session.endTime) {
            revert Errors.VotingPeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    modifier disputeActive(uint256 caseId) {
        DisputeSession storage session = disputeSessions[caseId];
        if (!session.isActive) {
            revert Errors.ChallengeNotStarted(caseId);
        }
        if (block.timestamp > session.endTime) {
            revert Errors.ChallengePeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ==================== 投票管理函数 ====================

    /**
     * @notice 开始投票会话（指定验证者）
     */
    function startVotingSessionWithValidators(
        uint256 caseId,
        address[] calldata selectedValidators,
        uint256 votingDuration
    ) external onlyGovernance returns (address[] memory) {
        if (votingSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "voting session");
        }

        if (selectedValidators.length == 0) {
            revert Errors.InsufficientValidators(0, 1);
        }

        // 验证所有验证者地址
        for (uint256 i = 0; i < selectedValidators.length; i++) {
            _requireNotZeroAddress(selectedValidators[i]);
        }

        // 创建并初始化投票会话
        DataStructures.VotingSession storage session = votingSessions[caseId];
        session.caseId = caseId;
        session.selectedValidators = selectedValidators;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + votingDuration;
        session.isActive = true;
        session.isCompleted = false;

        // 发出验证者选择事件
        emit Events.ValidatorsSelected(caseId, selectedValidators, block.timestamp);

        // 发出投票期开始事件
        emit Events.VotingPhaseStarted(caseId, session.endTime, block.timestamp);

        return selectedValidators;
    }

    /**
     * @notice 提交投票
     */
    function submitVote(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string calldata evidenceHash
    ) external caseExists(caseId) votingActive(caseId) {
        DataStructures.VotingSession storage session = votingSessions[caseId];

        // 验证用户是否已投票
        if (userVotingHistory[msg.sender][caseId]) {
            revert Errors.AlreadyVoted(msg.sender, caseId);
        }

        // 检查是否为选中的验证者
        bool isValidator = false;
        for (uint256 i = 0; i < session.selectedValidators.length; i++) {
            if (session.selectedValidators[i] == msg.sender) {
                isValidator = true;
                break;
            }
        }

        if (!isValidator) {
            revert Errors.ValidatorNotParticipating(msg.sender, caseId);
        }

        // 检查投票理由和证据
        if (bytes(reason).length == 0) {
            revert Errors.EmptyVoteReason();
        }

        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }

        // 记录投票信息
        session.votes[msg.sender] = DataStructures.VoteInfo({
            voter: msg.sender,
            choice: choice,
            timestamp: block.timestamp,
            reason: reason,
            evidenceHash: evidenceHash,
            hasVoted: true,
            finalChoice: choice
        });

        // 更新投票统计
        if (choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
            session.supportVotes++;
        } else {
            session.rejectVotes++;
        }
        session.totalVotes++;

        // 标记用户已投票
        userVotingHistory[msg.sender][caseId] = true;

        // 发出投票事件
        emit Events.VoteSubmitted(caseId, msg.sender, choice, block.timestamp);
    }

    /**
     * @notice 结束投票会话
     */
    function endVotingSession(uint256 caseId)
    external onlyGovernance caseExists(caseId) {

        DataStructures.VotingSession storage session = votingSessions[caseId];

        if (session.isCompleted) {
            revert Errors.DuplicateOperation(address(0), "end voting");
        }

        // 标记投票会话为完成
        session.isActive = false;
        session.isCompleted = true;

        // 发出投票完成事件
        emit Events.VotingCompleted(caseId, (session.supportVotes > session.rejectVotes), session.supportVotes, session.rejectVotes, block.timestamp);
    }

    // ==================== 质疑管理函数 ====================

    /**
     * @notice 开始质疑期
     * @param challengeDuration 质疑期时长
     * @param caseId 投诉案件id
     */
    function startDisputeSession(uint256 caseId, uint256 challengeDuration) external onlyGovernance {
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
        session.caseId = caseId;
        session.isActive = true;
        session.isCompleted = false;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + challengeDuration;
        session.totalChallenges = 0;
        session.resultChanged = false;

        // 发出质疑期开始事件
        emit Events.ChallengePhaseStarted(caseId, session.endTime, block.timestamp);
    }

    /**
     * @notice 提交质疑
     */
    function submitChallenge(
        uint256 caseId,
        address targetValidator,
        DataStructures.ChallengeChoice choice,
        string calldata reason,
        string calldata evidenceHash
    ) external disputeActive(caseId) notZeroAddress(targetValidator) {
        // 验证质疑者必须是DAO成员且未参与此案件
        if (!poolManager.canParticipateInCase(caseId, msg.sender, DataStructures.UserRole.DAO_MEMBER)) {
            revert Errors.InvalidUserRole(
                msg.sender,
                uint8(DataStructures.UserRole.DAO_MEMBER),
                uint8(DataStructures.UserRole.DAO_MEMBER)
            );
        }

        // 检查是否尝试质疑自己
        if (msg.sender == targetValidator) {
            revert Errors.InsufficientPermission(msg.sender, "Cannot challenge self");
        }

        // 检查是否已经质疑过该验证者
        if (_hasUserChallengedValidator(caseId, msg.sender, targetValidator)) {
            revert Errors.AlreadyChallenged(msg.sender, targetValidator);
        }

        // 检查质疑理由和证据
        if (bytes(reason).length == 0) {
            revert Errors.EmptyChallengeReason();
        }

        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }

        // 验证目标验证者确实参与了该案件的投票
        if (!isSelectedValidator(caseId, targetValidator)) {
            revert Errors.ValidatorNotParticipating(targetValidator, caseId);
        }

        DisputeSession storage session = disputeSessions[caseId];

        // 更新质疑投票信息
        DataStructures.ChallengeVotingInfo storage info = session.challengeVotingInfo[targetValidator];
        info.targetValidator = targetValidator;
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            info.supporters.push(msg.sender);
        } else {
            info.opponents.push(msg.sender);
        }

        // 创建完整的质疑信息结构体并添加到会话中
        DataStructures.ChallengeInfo memory challengeInfo = DataStructures.ChallengeInfo({
            challenger: msg.sender,
            targetValidator: targetValidator,
            choice: choice,
            reason: reason,
            evidenceHash: evidenceHash,
            timestamp: block.timestamp,
            challengeDeposit: 0
        });
        session.challenges.push(challengeInfo);
        session.totalChallenges++;
        session.challengers[msg.sender] = true;

        // 更新全局统计数据
        userDisputeHistory[msg.sender][caseId] = true;
        validatorDisputeCount[targetValidator]++;
        challengerTotalCount[msg.sender]++;

        // 发出质疑提交事件
        emit Events.ChallengeSubmitted(caseId, msg.sender, targetValidator, choice, reason, 0, block.timestamp);
    }

    /**
     * @notice 结束质疑期并处理结果
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
        _processFinalRewardPunishment(caseId, disputeResult.finalComplaintUpheld, complainantAddress, enterpriseAddress);

        // 更新会话状态
        _finalizeDisputeSession(session, disputeResult.changedVotes > 0);

        // 更新统计数据
        _updateChallengerStats(caseId, session);

        // 发出质疑期结束事件
        emit Events.ChallengePhaseEnded(caseId, session.totalChallenges, disputeResult.finalComplaintUpheld, block.timestamp);

        return disputeResult.finalComplaintUpheld;
    }

    /**
     * @notice 处理质疑者结果记录
     * @dev 由于质疑不再需要保证金，此函数仅用于记录质疑结果
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

        // 遍历所有质疑，记录结果
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            address challenger = challenge.challenger;
            address targetValidator = challenge.targetValidator;

            // 判断质疑是否成功，用于事件记录
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator];
            bool isSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length;

            // 发出质疑结果处理事件（不再涉及保证金解冻）
            emit Events.ChallengeResultProcessed(caseId, challenger, targetValidator, isSuccessful, block.timestamp);
        }

        // 发出质疑处理完成事件
        emit Events.DepositUnfrozen(caseId, address(this), session.challenges.length, block.timestamp);
    }

    // ==================== 内部函数 ====================

    /**
     * @notice 验证质疑会话结束的前置条件
     */
    function _validateDisputeSessionEnd(DisputeSession storage session, uint256 caseId) internal view {
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }
    }

    /**
     * @notice 处理验证者的质疑结果并更新投票
     */
    function _processValidatorChallenges(
        uint256 caseId,
        DisputeSession storage session
    ) internal returns (DisputeResult memory disputeResult) {
        // 简化实现：基于质疑会话中的信息处理
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
                _addAddressesToRewardList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents);
                _addAddressesToPunishList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters);
                punishMember[caseId][DataStructures.UserRole.DAO_MEMBER].push(targetValidator);

                // 模拟投票翻转（简化逻辑）
                disputeResult.finalRejectVotes++;
            } else {
                // 质疑失败，维持原结果
                _addAddressesToRewardList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters);
                _addAddressesToPunishList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents);

                // 维持原投票
                disputeResult.finalSupportVotes++;
            }
        }

        // 计算最终结果
        disputeResult.finalComplaintUpheld = disputeResult.finalSupportVotes > disputeResult.finalRejectVotes;

        return disputeResult;
    }

    /**
     * @notice 更新最终投票统计
     */
    function _updateFinalVotingStats(uint256 caseId, DisputeResult memory disputeResult) internal {
        // 直接更新投票会话的最终结果
        DataStructures.VotingSession storage session = votingSessions[caseId];
        session.supportVotes = disputeResult.finalSupportVotes;
        session.rejectVotes = disputeResult.finalRejectVotes;
        session.complaintUpheld = disputeResult.finalComplaintUpheld;

        // 如果有具体的验证者投票被改变，也要更新他们的最终选择
        if (disputeResult.changedVotes > 0) {
            _updateChangedValidatorVotes(caseId, disputeResult);
        }

        // 发出质疑结果导致的投票变更事件
        if (disputeResult.changedVotes > 0) {
            emit Events.ChallengeCompleted(caseId, true, disputeResult.changedVotes, block.timestamp);
        }

        // 更新本地统计记录
        _recordFinalVotingStats(caseId, disputeResult);
    }

    /**
     * @notice 更新被质疑成功的验证者的投票选择
     */
    function _updateChangedValidatorVotes(uint256 caseId, DisputeResult memory disputeResult) internal {
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
                DataStructures.VoteInfo storage voteInfo = votingSessions[caseId].votes[targetValidator];

                // 确定新的投票选择（翻转原选择）
                DataStructures.VoteChoice newChoice;
                if (voteInfo.choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
                    newChoice = DataStructures.VoteChoice.REJECT_COMPLAINT;
                } else {
                    newChoice = DataStructures.VoteChoice.SUPPORT_COMPLAINT;
                }

                // 更新验证者的最终选择
                voteInfo.finalChoice = newChoice;
            }
        }
    }

    /**
     * @notice 记录最终投票统计数据
     */
    function _recordFinalVotingStats(uint256 caseId, DisputeResult memory disputeResult) internal {
        DisputeSession storage session = disputeSessions[caseId];
        session.resultChanged = disputeResult.changedVotes > 0;
    }

    /**
     * @notice 处理最终的奖惩分配
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
     */
    function _finalizeDisputeSession(DisputeSession storage session, bool resultChanged) internal {
        session.isActive = false;
        session.isCompleted = true;
        session.resultChanged = resultChanged;
    }

    /**
     * @notice 更新质疑者统计数据
     */
    function _updateChallengerStats(uint256 caseId, DisputeSession storage session) internal {
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
     * @notice 批量添加地址到奖励列表
     */
    function _addAddressesToRewardList(
        uint256 caseId,
        DataStructures.UserRole role,
        address[] storage addresses
    ) internal {
        for (uint i = 0; i < addresses.length; i++) {
            rewardMember[caseId][role].push(addresses[i]);
        }
    }

    /**
     * @notice 批量添加地址到惩罚列表
     */
    function _addAddressesToPunishList(
        uint256 caseId,
        DataStructures.UserRole role,
        address[] storage addresses
    ) internal {
        for (uint i = 0; i < addresses.length; i++) {
            punishMember[caseId][role].push(addresses[i]);
        }
    }

    /**
     * @notice 检查用户是否已经质疑过特定验证者
     */
    function _hasUserChallengedValidator(
        uint256 caseId,
        address challenger,
        address targetValidator
    ) internal view returns (bool) {
        DisputeSession storage session = disputeSessions[caseId];

        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            if (challenge.challenger == challenger && challenge.targetValidator == targetValidator) {
                return true;
            }
        }

        return false;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取投票会话信息（分解版本，避免mapping返回）
     */
    function getVotingSessionInfo(uint256 caseId) external view caseExists(caseId) returns (
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
    ) {
        DataStructures.VotingSession storage session = votingSessions[caseId];

        return (
            session.caseId,
            session.selectedValidators,
            session.supportVotes,
            session.rejectVotes,
            session.totalVotes,
            session.startTime,
            session.endTime,
            session.isActive,
            session.isCompleted,
            session.complaintUpheld
        );
    }

    /**
     * @notice 获取验证者投票信息
     */
    function getValidatorVote(uint256 caseId, address validator) external view caseExists(caseId) returns (DataStructures.VoteInfo memory) {
        return votingSessions[caseId].votes[validator];
    }

    /**
     * @notice 检查验证者是否参与案件
     */
    function isSelectedValidator(uint256 caseId, address validator) public view returns (bool) {
        if (votingSessions[caseId].caseId == 0) {
            return false;
        }

        address[] memory validators = votingSessions[caseId].selectedValidators;
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == validator) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice 获取案件验证者列表
     */
    function getCaseValidators(uint256 caseId) external view caseExists(caseId) returns (address[] memory) {
        return votingSessions[caseId].selectedValidators;
    }

    /**
     * @notice 获取质疑会话信息
     */
    function getDisputeSessionInfo(uint256 caseId) external view returns (
        uint256, bool, bool, uint256, uint256, uint256, bool
    ) {
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
     */
    function getChallengeInfo(uint256 caseId, uint256 challengeIndex) external view returns (DataStructures.ChallengeInfo memory) {
        DisputeSession storage session = disputeSessions[caseId];

        if (challengeIndex >= session.challenges.length) {
            revert Errors.InvalidAmount(challengeIndex, session.challenges.length);
        }

        return session.challenges[challengeIndex];
    }

    /**
     * @notice 获取质疑者统计信息
     */
    function getChallengerStats(address challenger) external view returns (uint256 successCount, uint256 totalCount, uint256 successRate) {
        successCount = challengerSuccessCount[challenger];
        totalCount = challengerTotalCount[challenger];
        successRate = totalCount > 0 ? (successCount * 100) / totalCount : 0;
        return (successCount, totalCount, successRate);
    }

    /**
     * @notice 检查用户是否参与了某案件的质疑
     */
    function hasUserDisputed(address user, uint256 caseId) external view returns (bool) {
        return userDisputeHistory[user][caseId];
    }

    /**
     * @notice 获取案件的所有质疑
     */
    function getAllChallenges(uint256 caseId) external view returns (DataStructures.ChallengeInfo[] memory) {
        return disputeSessions[caseId].challenges;
    }

    /**
     * @notice 获取案件的奖励成员列表
     */
    function getRewardMembers(uint256 caseId, DataStructures.UserRole role) external view returns (address[] memory) {
        return rewardMember[caseId][role];
    }

    /**
     * @notice 获取案件的惩罚成员列表
     */
    function getPunishMembers(uint256 caseId, DataStructures.UserRole role) external view returns (address[] memory) {
        return punishMember[caseId][role];
    }

    /**
     * @notice 获取案件的所有奖惩结果概览
     */
    function getCaseRewardPunishmentSummary(uint256 caseId) external view returns (
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
     * @notice 检查是否可以进行质疑结果处理
     */
    function canProcessDisputeUnfreeze(uint256 caseId) external view returns (bool canProcess, string memory reason) {
        DisputeSession storage session = disputeSessions[caseId];

        if (session.caseId == 0) {
            return (false, "Dispute session does not exist");
        }

        if (!session.isCompleted) {
            return (false, "Dispute session not completed");
        }

        if (session.isActive) {
            return (false, "Dispute session still active");
        }

        if (session.challenges.length == 0) {
            return (false, "No challenges to process");
        }

        return (true, "Ready for dispute result processing");
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     */
    function setGovernanceContract(address _governanceContract) external onlyOwner notZeroAddress(_governanceContract) {
        governanceContract = _governanceContract;
    }

    /**
     * @notice 设置资金管理合约地址
     */
    function setFundManager(address _fundManager) external onlyOwner notZeroAddress(_fundManager) {
        fundManager = IFundManager(_fundManager);
    }

    /**
     * @notice 设置参与者池管理合约地址
     */
    function setPoolManager(address _poolManager) external onlyOwner notZeroAddress(_poolManager) {
        poolManager = IParticipantPoolManager(_poolManager);
    }

    /**
     * @notice 紧急暂停质疑会话
     */
    function emergencyPauseDispute(uint256 caseId) external onlyOwner {
        DisputeSession storage session = disputeSessions[caseId];

        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        session.isActive = false;

        emit Events.EmergencyTriggered(caseId, "Emergency pause of dispute session", msg.sender, block.timestamp);
    }
}
