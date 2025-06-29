// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../libraries/CommonModifiers.sol";
import "../interfaces/IModuleInterfaces.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

    /// @notice 案件的投票信息映射 (案件ID => 投票会话)
    mapping(uint256 => DataStructures.VotingSession) public votingSessions;

    /// @notice 用户参与的投票记录 (用户地址 => 案件ID => 是否已投票)
    mapping(address => mapping(uint256 => bool)) public userVotingHistory;

    // ========== 质疑相关状态变量 ==========

    /// @notice 案件质疑会话映射 (案件ID => 质疑会话)
    mapping(uint256 => DisputeSession) public disputeSessions;

    /// @notice 用户质疑历史记录映射 (用户地址 => 案件ID => 是否已质疑)
    mapping(address => mapping(uint256 => bool)) public userDisputeHistory;

    /// @notice 验证者被质疑次数统计映射 (验证者地址 => 被质疑次数)


    /// @notice 质疑者成功质疑次数统计映射 (质疑者地址 => 成功次数)
    mapping(address => uint256) public challengerSuccessCount;

    /// @notice 质疑者总参与次数统计映射 (质疑者地址 => 总参与次数)
    mapping(address => uint256) public challengerTotalCount;

    /// @notice 奖励成员列表 (案件ID => 用户角色 => 地址列表)
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public rewardMember;

    /// @notice 惩罚成员列表 (案件ID => 用户角色 => 地址列表)
    mapping(uint256 => mapping(DataStructures.UserRole => address[])) public punishMember;

    // ==================== 结构体定义 ====================

    /**
     * @notice 质疑会话结构体
     */
    struct DisputeSession {
        uint256 caseId; // 案件ID
        bool isActive; // 是否活跃
        bool isCompleted; // 是否已完成
        uint256 startTime; // 开始时间
        uint256 endTime; // 结束时间
        uint256 totalChallenges; // 总质疑数量
        DataStructures.ChallengeInfo[] challenges; // 质疑信息数组
        mapping(address => DataStructures.ChallengeVotingInfo) challengeVotingInfo; // 质疑投票信息 (目标验证者 => 投票信息)
        mapping(address => bool) challengers; // 质疑者映射 (质疑者地址 => 是否已质疑)
    }

    /**
     * @notice 质疑结果结构体（简化版，移除mapping）
     */
    struct DisputeResult {
        uint256 changedVotes; // 改变的投票数量
        uint256 finalSupportVotes; // 最终支持票数
        uint256 finalRejectVotes; // 最终反对票数
        bool finalComplaintUpheld; // 最终投诉是否成立
        address[] rewardedMembers; // 获得奖励的成员
        address[] punishedMembers; // 受到惩罚的成员
    }

    // ==================== 修饰符 ====================

    modifier caseExists(uint256 caseId) { // 案件ID
        if (votingSessions[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    modifier votingActive(uint256 caseId) { // 案件ID
        DataStructures.VotingSession storage session = votingSessions[caseId]; // 投票会话存储引用
        if (!session.isActive || block.timestamp > session.endTime) {
            revert Errors.VotingPeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    modifier disputeActive(uint256 caseId) { // 案件ID
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用
        if (!session.isActive) {
            revert Errors.ChallengeNotStarted(caseId);
        }
        if (block.timestamp > session.endTime) {
            revert Errors.ChallengePeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address initialOwner) Ownable(initialOwner) {} // 初始所有者地址

    // ==================== 投票管理函数 ====================

    /**
     * @notice 开始投票会话
     */
    function startVotingSessionWithValidators(
        uint256 caseId, // 案件ID
        address[] calldata selectedValidators, // 选定的验证者地址数组
        uint256 votingDuration // 投票持续时间(秒)
    ) external onlyGovernance returns (address[] memory) {
        if (votingSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "voting session");
        }

        if (selectedValidators.length == 0) {
            revert Errors.InsufficientValidators(0, 1);
        }

        // 验证所有验证者地址
        for (uint256 i = 0; i < selectedValidators.length; i++) { // 循环索引
            _requireNotZeroAddress(selectedValidators[i]);
        }

        // 创建并初始化投票会话
        DataStructures.VotingSession storage session = votingSessions[caseId]; // 投票会话存储引用
        session.caseId = caseId;
        session.selectedValidators = selectedValidators;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + votingDuration;
        session.isActive = true;
        session.isCompleted = false;

        // 发出投票会话开始事件
        emit Events.VoteSessionStart(caseId, selectedValidators,session.startTime, session.endTime , block.timestamp);

        return selectedValidators;
    }

    /**
     * @notice 提交投票
     */
    function submitVote(
        uint256 caseId, // 案件ID
        DataStructures.VoteChoice choice, // 投票选择
        string calldata reason, // 投票理由
        string calldata evidenceHash // 证据哈希
    ) external caseExists(caseId) votingActive(caseId) {
        DataStructures.VotingSession storage session = votingSessions[caseId]; // 投票会话存储引用

        // 验证用户是否已投票
        if (userVotingHistory[msg.sender][caseId]) {
            revert Errors.AlreadyVoted(msg.sender, caseId);
        }

        // 检查是否为选中的验证者
        bool isValidator = false; // 是否为验证者标志
        for (uint256 i = 0; i < session.selectedValidators.length; i++) { // 循环索引
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
            finalChoice: choice,
            supportVotes: 0,
            rejectVotes: 0,
            totalVotes: 0
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

        // 检查是否满足投票结束条件
        _checkAndUpdateVotingStatus(caseId);
    }

    /**
     * @notice 结束投票会话
     */
    function endVotingSession(uint256 caseId) // 案件ID
    external onlyGovernance caseExists(caseId) {

        DataStructures.VotingSession storage session = votingSessions[caseId]; // 投票会话存储引用

        if (session.isCompleted) {
            revert Errors.DuplicateOperation(address(0), "end voting");
        }

        // 标记投票会话为完成
        session.isActive = false;
        session.isCompleted = true;
        session.complaintUpheld = session.supportVotes > session.rejectVotes;
        // 发出投票完成事件
        emit Events.VotingCompleted(caseId, (session.supportVotes > session.rejectVotes), session.supportVotes, session.rejectVotes, block.timestamp);
    }

    // ==================== 质疑管理函数 ====================

    /**
     * @notice 开始质疑期
     * @param challengeDuration 质疑期时长
     * @param caseId 投诉案件id
     */
    function startDisputeSession(uint256 caseId, uint256 challengeDuration) external onlyGovernance { // 案件ID, 质疑持续时间(秒)
        // 防止为同一案件重复创建质疑会话
        if (disputeSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "dispute session");
        }

        // 验证质疑持续时间的合理性
        if (challengeDuration == 0) {
            revert Errors.InvalidAmount(challengeDuration, 1);
        }

        // 创建并初始化质疑会话
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用
        session.caseId = caseId;
        session.isActive = true;
        session.isCompleted = false;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + challengeDuration;
        session.totalChallenges = 0;

        // 发出质疑期开始事件
        emit Events.ChallengePhaseStarted(caseId, session.endTime, block.timestamp);
    }

    /**
     * @notice 提交质疑
     */
    function submitChallenge(
        uint256 caseId, // 案件ID
        address targetValidator, // 目标验证者地址
        DataStructures.ChallengeChoice choice, // 质疑选择
        string calldata reason, // 质疑理由
        string calldata evidenceHash // 证据哈希
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

        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用

        // 更新质疑投票信息
        DataStructures.ChallengeVotingInfo storage info = session.challengeVotingInfo[targetValidator]; // 质疑投票信息存储引用
        info.targetValidator = targetValidator;
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            info.supporters.push(msg.sender);
        } else {
            info.opponents.push(msg.sender);
        }

        // 创建完整的质疑信息结构体并添加到会话中
        DataStructures.ChallengeInfo memory challengeInfo = DataStructures.ChallengeInfo({ // 质疑信息内存结构体
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
        challengerTotalCount[msg.sender]++;

        // 发出质疑提交事件
        emit Events.ChallengeSubmitted(caseId, msg.sender, targetValidator, choice, reason, 0, block.timestamp);
    }

    /**
     * @notice 结束质疑期并处理结果
     */
    function endDisputeSession(
        uint256 caseId, // 案件ID
        address complainantAddress, // 投诉者地址
        address enterpriseAddress // 企业地址
    ) external onlyGovernance returns (bool) {
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用

        // 验证会话状态和时间
        _validateDisputeSessionEnd(session, caseId);

        // 处理验证者的质疑结果并更新投票
        (bool resultChanged, bool newResult) = _processValidatorChallenges(caseId, session, complainantAddress, enterpriseAddress); // 质疑结果内存结构体

        // 更新会话状态
        session.isActive = false;
        session.isCompleted = true;

        // 发出质疑期结束事件
        emit Events.ChallengePhaseEnded(caseId, session.totalChallenges, resultChanged, block.timestamp);

        return newResult;
    }



    // ==================== 内部函数 ====================

    /**
     * @notice 检查并更新投票状态
     * @dev 在提交投票后检查是否满足投票结束条件
     * @param caseId 案件ID
     */
    function _checkAndUpdateVotingStatus(uint256 caseId) internal {
        DataStructures.VotingSession storage session = votingSessions[caseId];

        // 检查条件1：所有验证者都已完成投票
        bool allVoted = session.totalVotes >= session.selectedValidators.length;

        // 检查条件2：投票时间已结束
        bool timeEnded = block.timestamp >= session.endTime;

        // 如果满足任一条件且会话仍然活跃，否则结束投票
        if ((allVoted || timeEnded) && session.isActive) {
            session.isActive = false;
            session.isCompleted = true;
            session.complaintUpheld = session.supportVotes > session.rejectVotes;

            // 发出投票完成事件
            emit Events.VotingCompleted(
                caseId,
                session.complaintUpheld,
                session.supportVotes,
                session.rejectVotes,
                block.timestamp
            );
        }
    }

    /**
     * @notice 验证质疑会话结束的前置条件
     */
    function _validateDisputeSessionEnd(DisputeSession storage session, uint256 caseId) internal view { // 质疑会话存储引用, 案件ID
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
        uint256 caseId, // 案件ID
        DisputeSession storage session, // 质疑会话存储引用
        address complainantAddress,
        address enterpriseAddress
    ) internal returns (bool, bool){ // 质疑结果内存结构体
        // 简化实现：基于质疑会话中的信息处理
        DataStructures.VotingSession storage votingSession = votingSessions[caseId];

        // 遍历所有质疑，统计结果
        for (uint256 i = 0; i < session.challenges.length; i++) { // 循环索引
            DataStructures.ChallengeInfo storage challenge = session.challenges[i]; // 质疑信息存储引用
            address targetValidator = challenge.targetValidator; // 目标验证者地址
            DataStructures.VoteInfo memory voteInfo = votingSession.votes[targetValidator];
            DataStructures.ChallengeVotingInfo storage challengeInfo = session.challengeVotingInfo[targetValidator]; // 质疑投票信息存储引用

            // 检查是否有质疑且反对者多于支持者（质疑成功）
            bool isChallengeSuccessful = challengeInfo.opponents.length > challengeInfo.supporters.length; // 质疑是否成功

            if (isChallengeSuccessful) {
                //质疑者成功质疑次数统计映射
                challengerSuccessCount[challenge.challenger]++;
                // 处理奖惩
                _addAddressesToRewardList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents);
                _addAddressesToPunishList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters);
                punishMember[caseId][DataStructures.UserRole.DAO_MEMBER].push(targetValidator);
                if (voteInfo.choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
                    voteInfo.finalChoice = DataStructures.VoteChoice.REJECT_COMPLAINT; // 翻转投票选择
                    votingSession.supportVotes -= 1;
                    votingSession.rejectVotes += 1;
                }
            } else {
                // 质疑失败，维持原结果
                _addAddressesToRewardList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.supporters);
                _addAddressesToPunishList(caseId, DataStructures.UserRole.DAO_MEMBER, challengeInfo.opponents);
                rewardMember[caseId][DataStructures.UserRole.DAO_MEMBER].push(targetValidator);
            }
        }
        bool newResult = votingSession.supportVotes > votingSession.rejectVotes;// 投诉是否成立
        bool resultChanged = votingSession.complaintUpheld != newResult;//总结果是否改变
        // 计算最终结果
        votingSession.complaintUpheld = newResult;
        if (newResult) {
            //投诉成立，企业受罚
            punishMember[caseId][DataStructures.UserRole.ENTERPRISE].push(enterpriseAddress);
        } else {
            //投诉不成立,投诉者受罚
            punishMember[caseId][DataStructures.UserRole.COMPLAINANT].push(complainantAddress);
        }
        return (resultChanged, newResult);
    }

    /**
     * @notice 批量添加地址到奖励列表
     */
    function _addAddressesToRewardList(
        uint256 caseId, // 案件ID
        DataStructures.UserRole role, // 用户角色
        address[] storage addresses // 地址数组存储引用
    ) internal {
        for (uint i = 0; i < addresses.length; i++) { // 循环索引
            rewardMember[caseId][role].push(addresses[i]);
        }
    }

    /**
     * @notice 批量添加地址到惩罚列表
     */
    function _addAddressesToPunishList(
        uint256 caseId, // 案件ID
        DataStructures.UserRole role, // 用户角色
        address[] storage addresses // 地址数组存储引用
    ) internal {
        for (uint i = 0; i < addresses.length; i++) { // 循环索引
            punishMember[caseId][role].push(addresses[i]);
        }
    }

    /**
     * @notice 检查用户是否已经质疑过特定验证者
     */
    function _hasUserChallengedValidator(
        uint256 caseId, // 案件ID
        address challenger, // 质疑者地址
        address targetValidator // 目标验证者地址
    ) internal view returns (bool) {
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用

        for (uint256 i = 0; i < session.challenges.length; i++) { // 循环索引
            DataStructures.ChallengeInfo storage challenge = session.challenges[i]; // 质疑信息存储引用
            if (challenge.challenger == challenger && challenge.targetValidator == targetValidator) {
                return true;
            }
        }

        return false;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取案件的投票奖励和惩罚成员（内部函数，返回映射引用）
     * @param caseId 案件ID
     */
    function getVotingRewardAndPunishmentMembers(uint256 caseId) internal view returns (
        mapping(DataStructures.UserRole => address[]) storage,
        mapping(DataStructures.UserRole => address[]) storage) {
        return (rewardMember[caseId], punishMember[caseId]);
    }
    /**
     * @notice 检查验证者是否参与案件
     */
    function isSelectedValidator(uint256 caseId, address validator) public view returns (bool) { // 案件ID, 验证者地址
        if (votingSessions[caseId].caseId == 0) {
            return false;
        }

        address[] memory validators = votingSessions[caseId].selectedValidators; // 验证者数组内存引用
        for (uint256 i = 0; i < validators.length; i++) { // 循环索引
            if (validators[i] == validator) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice 获取特定质疑信息
     */
    function getChallengeInfo(uint256 caseId, uint256 challengeIndex) external view returns (DataStructures.ChallengeInfo memory) { // 案件ID, 质疑索引
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用

        if (challengeIndex >= session.challenges.length) {
            revert Errors.InvalidAmount(challengeIndex, session.challenges.length);
        }

        return session.challenges[challengeIndex];
    }

    /**
     * @notice 获取质疑者统计信息
     */
    function getChallengerStats(address challenger) external view returns (uint256 successCount, uint256 totalCount, uint256 successRate) { // 质疑者地址; 成功次数, 总次数, 成功率
        successCount = challengerSuccessCount[challenger];
        totalCount = challengerTotalCount[challenger];
        successRate = totalCount > 0 ? (successCount * 100) / totalCount : 0;
        return (successCount, totalCount, successRate);
    }

    /**
     * @notice 检查用户是否参与了某案件的质疑
     */
    function hasUserDisputed(address user, uint256 caseId) external view returns (bool) { // 用户地址, 案件ID
        return userDisputeHistory[user][caseId];
    }

    /**
     * @notice 获取案件的奖励成员列表
     */
    function getRewardMembers(uint256 caseId, DataStructures.UserRole role) external view returns (address[] memory) { // 案件ID, 用户角色
        return rewardMember[caseId][role];
    }

    /**
     * @notice 获取案件的惩罚成员列表
     */
    function getPunishMembers(uint256 caseId, DataStructures.UserRole role) external view returns (address[] memory) { // 案件ID, 用户角色
        return punishMember[caseId][role];
    }

    /**
     * @notice 获取案件的所有奖惩结果概览
     */
    function getCaseRewardPunishmentSummary(uint256 caseId) external view returns ( // 案件ID
        uint256 totalRewardedDAO, // 奖励的DAO成员总数
        uint256 totalPunishedDAO, // 惩罚的DAO成员总数
        bool complainantRewarded, // 投诉者是否获得奖励
        bool enterprisePunished // 企业是否受到惩罚
    ) {
        totalRewardedDAO = rewardMember[caseId][DataStructures.UserRole.DAO_MEMBER].length;
        totalPunishedDAO = punishMember[caseId][DataStructures.UserRole.DAO_MEMBER].length;
        complainantRewarded = rewardMember[caseId][DataStructures.UserRole.COMPLAINANT].length > 0;
        enterprisePunished = punishMember[caseId][DataStructures.UserRole.ENTERPRISE].length > 0;

        return (totalRewardedDAO, totalPunishedDAO, complainantRewarded, enterprisePunished);
    }

    /**
     * @notice 检查投票期是否已结束
     */
    function isVotingPeriodEnded(uint256 caseId) external view returns (bool) {
        DataStructures.VotingSession storage session = votingSessions[caseId];
        if (session.caseId == 0) return false;
        return block.timestamp > session.endTime;
        }

    /**
     * @notice 检查质疑期是否已结束
     */
    function isChallengePeriodEnded(uint256 caseId) external view returns (bool) {
        DisputeSession storage session = disputeSessions[caseId];
        if (session.caseId == 0) return false;
        return block.timestamp > session.endTime;
    }

    /**
     * @notice 检查是否所有验证者都已投票
     */
    function areAllValidatorsVoted(uint256 caseId) external view returns (bool) {
        DataStructures.VotingSession storage session = votingSessions[caseId];
        if (session.caseId == 0 || !session.isActive) return false;

        return session.totalVotes >= session.selectedValidators.length;
    }

    /**
     * @notice 检查投票会话是否已完成
     */
    function isVotingSessionCompleted(uint256 caseId) external view returns (bool) {
        DataStructures.VotingSession storage session = votingSessions[caseId];
        if (session.caseId == 0) return false;
        return session.isCompleted;
    }



    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     */
    function setGovernanceContract(address _governanceContract) external onlyOwner notZeroAddress(_governanceContract) { // 治理合约地址
        governanceContract = _governanceContract;
    }

    /**
     * @notice 设置资金管理合约地址
     */
    function setFundManager(address _fundManager) external onlyOwner notZeroAddress(_fundManager) { // 资金管理合约地址
        fundManager = IFundManager(_fundManager);
    }

    /**
     * @notice 设置参与者池管理合约地址
     */
    function setPoolManager(address _poolManager) external onlyOwner notZeroAddress(_poolManager) { // 参与者池管理合约地址
        poolManager = IParticipantPoolManager(_poolManager);
    }

    /**
     * @notice 紧急暂停质疑会话
     */
    function emergencyPauseDispute(uint256 caseId) external onlyOwner { // 案件ID
        DisputeSession storage session = disputeSessions[caseId]; // 质疑会话存储引用

        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        session.isActive = false;

        emit Events.EmergencyTriggered(caseId, "Emergency pause of dispute session", msg.sender, block.timestamp);
    }


}
