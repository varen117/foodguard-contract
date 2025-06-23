// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";

/**
 * @title DisputeManager
 * @author Food Safety Governance Team
 * @notice 质疑管理模块，负责处理对验证者投票结果的质疑
 * @dev 管理质疑流程，包括质疑提交、保证金管理、结果计算等
 */
contract DisputeManager {
    // ==================== 状态变量 ====================
    
    /// @notice 管理员地址
    address public admin;
    
    /// @notice 治理合约地址
    address public governanceContract;
    
    /// @notice 资金管理合约地址
    address public fundManager;
    
    /// @notice 投票管理合约地址
    address public votingManager;
    
    /// @notice 案件质疑信息映射 caseId => DisputeSession
    mapping(uint256 => DisputeSession) public disputeSessions;
    
    /// @notice 用户质疑历史记录 user => caseId => hasDisputed
    mapping(address => mapping(uint256 => bool)) public userDisputeHistory;
    
    /// @notice 验证者被质疑次数统计 validator => disputeCount
    mapping(address => uint256) public validatorDisputeCount;
    
    /// @notice 质疑成功率统计 challenger => successCount
    mapping(address => uint256) public challengerSuccessCount;
    
    /// @notice 质疑参与次数统计 challenger => totalCount
    mapping(address => uint256) public challengerTotalCount;
    
    // ==================== 结构体定义 ====================
    
    /**
     * @notice 质疑会话结构体
     * @dev 记录单个案件的完整质疑信息
     */
    struct DisputeSession {
        uint256 caseId;                    // 案件ID
        bool isActive;                     // 质疑期是否激活
        bool isCompleted;                  // 质疑是否完成
        uint256 startTime;                 // 质疑开始时间
        uint256 endTime;                   // 质疑结束时间
        uint256 totalChallenges;           // 总质疑数量
        bool resultChanged;                // 结果是否改变
        
        // 质疑信息数组
        DataStructures.ChallengeInfo[] challenges;
        
        // 验证者质疑统计 validator => ChallengeStats
        mapping(address => ChallengeStats) validatorChallengeStats;
        
        // 质疑者映射 challenger => true
        mapping(address => bool) challengers;
    }
    
    /**
     * @notice 验证者质疑统计结构体
     */
    struct ChallengeStats {
        uint256 supportCount;              // 支持验证者的质疑数量
        uint256 opposeCount;               // 反对验证者的质疑数量
        bool hasBeenChallenged;            // 是否被质疑过
        address[] challengers;             // 质疑者列表
    }
    
    // ==================== 修饰符 ====================
    
    /**
     * @notice 只有管理员可以调用
     */
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Errors.InsufficientPermission(msg.sender, "ADMIN");
        }
        _;
    }
    
    /**
     * @notice 只有治理合约可以调用
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }
    
    /**
     * @notice 检查质疑期是否激活
     */
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
    
    /**
     * @notice 检查地址是否为零地址
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }
    
    // ==================== 构造函数 ====================
    
    constructor(address _admin) {
        admin = _admin;
    }
    
    // ==================== 质疑会话管理函数 ====================
    
    /**
     * @notice 开始质疑期
     * @param caseId 案件ID
     * @param challengeDuration 质疑持续时间（秒）
     */
    function startDisputeSession(
        uint256 caseId,
        uint256 challengeDuration
    ) external onlyGovernance {
        if (disputeSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "dispute session");
        }
        
        if (challengeDuration == 0) {
            revert Errors.InvalidAmount(challengeDuration, 1);
        }
        
        DisputeSession storage session = disputeSessions[caseId];
        session.caseId = caseId;
        session.isActive = true;
        session.isCompleted = false;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + challengeDuration;
        session.totalChallenges = 0;
        session.resultChanged = false;
        
        emit Events.ChallengePhaseStarted(
            caseId,
            session.endTime,
            block.timestamp
        );
    }
    
    /**
     * @notice 提交质疑
     * @param caseId 案件ID
     * @param targetValidator 被质疑的验证者地址
     * @param choice 质疑选择（支持或反对验证者）
     * @param reason 质疑理由
     * @param evidenceHashes 证据哈希数组
     * @param evidenceTypes 证据类型数组
     * @param evidenceDescriptions 证据描述数组
     * @param challengeDeposit 质疑保证金
     */
    function submitChallenge(
        uint256 caseId,
        address targetValidator,
        DataStructures.ChallengeChoice choice,
        string calldata reason,
        string[] calldata evidenceHashes,
        string[] calldata evidenceTypes,
        string[] calldata evidenceDescriptions,
        uint256 challengeDeposit
    ) external payable disputeActive(caseId) notZeroAddress(targetValidator) {
        
        // 验证质疑保证金
        if (msg.value != challengeDeposit || challengeDeposit == 0) {
            revert Errors.InsufficientChallengeDeposit(msg.value, challengeDeposit);
        }
        
        // 检查是否质疑自己
        if (msg.sender == targetValidator) {
            revert Errors.CannotChallengeSelf(msg.sender);
        }
        
        // 检查是否已经质疑过该验证者
        if (_hasUserChallengedValidator(caseId, msg.sender, targetValidator)) {
            revert Errors.AlreadyChallenged(msg.sender, targetValidator);
        }
        
        // 检查质疑理由是否为空
        if (bytes(reason).length == 0) {
            revert Errors.EmptyChallengeReason();
        }
        
        // 验证证据数组长度一致
        if (evidenceHashes.length != evidenceTypes.length || 
            evidenceTypes.length != evidenceDescriptions.length) {
            revert Errors.InsufficientEvidence(evidenceHashes.length, evidenceTypes.length);
        }
        
        // TODO: 验证目标验证者确实参与了该案件的投票
        // 这需要调用 VotingManager 来验证
        
        DisputeSession storage session = disputeSessions[caseId];
        
        // 创建证据数组
        DataStructures.Evidence[] memory evidences = new DataStructures.Evidence[](evidenceHashes.length);
        for (uint256 i = 0; i < evidenceHashes.length; i++) {
            evidences[i] = DataStructures.Evidence({
                description: evidenceDescriptions[i],
                ipfsHash: evidenceHashes[i],
                location: "", // 将在主合约中设置
                timestamp: block.timestamp,
                submitter: msg.sender,
                evidenceType: evidenceTypes[i]
            });
        }
        
        // 创建质疑信息
        DataStructures.ChallengeInfo memory challengeInfo = DataStructures.ChallengeInfo({
            challenger: msg.sender,
            targetValidator: targetValidator,
            choice: choice,
            reason: reason,
            evidences: evidences,
            timestamp: block.timestamp,
            challengeDeposit: challengeDeposit
        });
        
        // 添加质疑到会话
        session.challenges.push(challengeInfo);
        session.totalChallenges++;
        session.challengers[msg.sender] = true;
        
        // 更新验证者质疑统计
        ChallengeStats storage stats = session.validatorChallengeStats[targetValidator];
        if (!stats.hasBeenChallenged) {
            stats.hasBeenChallenged = true;
        }
        
        stats.challengers.push(msg.sender);
        
        if (choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
            stats.supportCount++;
        } else {
            stats.opposeCount++;
        }
        
        // 更新用户质疑历史
        userDisputeHistory[msg.sender][caseId] = true;
        
        // 更新统计数据
        validatorDisputeCount[targetValidator]++;
        challengerTotalCount[msg.sender]++;
        
        // TODO: 调用资金管理合约冻结质疑保证金
        // 这需要将ETH转发给FundManager合约
        
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
     * @param caseId 案件ID
     * @param originalResult 原始投票结果
     * @return finalResult 最终结果
     * @return resultChanged 结果是否改变
     */
    function endDisputeSession(
        uint256 caseId,
        bool originalResult
    ) external onlyGovernance returns (bool finalResult, bool resultChanged) {
        DisputeSession storage session = disputeSessions[caseId];
        
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }
        
        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }
        
        // 如果没有质疑，结果保持不变
        if (session.totalChallenges == 0) {
            session.isActive = false;
            session.isCompleted = true;
            
            emit Events.ChallengePhaseEnded(
                caseId,
                0,
                false,
                block.timestamp
            );
            
            return (originalResult, false);
        }
        
        // 计算质疑结果
        (finalResult, resultChanged) = _calculateDisputeResult(caseId, originalResult);
        
        session.isActive = false;
        session.isCompleted = true;
        session.resultChanged = resultChanged;
        
        // 处理质疑者的诚信状态和奖惩
        _processDisputeRewards(caseId, resultChanged);
        
        emit Events.ChallengePhaseEnded(
            caseId,
            session.totalChallenges,
            resultChanged,
            block.timestamp
        );
        
        return (finalResult, resultChanged);
    }
    
    // ==================== 内部函数 ====================
    
    /**
     * @notice 检查用户是否已经质疑过特定验证者
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
        
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            if (challenge.challenger == challenger && challenge.targetValidator == targetValidator) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @notice 计算质疑结果
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
        
        uint256 totalSupportValidators = 0;    // 支持验证者的质疑总数
        uint256 totalOpposeValidators = 0;     // 反对验证者的质疑总数
        
        // 统计所有质疑
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            
            if (challenge.choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR) {
                totalSupportValidators++;
            } else {
                totalOpposeValidators++;
            }
        }
        
        // 如果反对验证者的质疑占多数，则结果取反
        if (totalOpposeValidators > totalSupportValidators) {
            finalResult = !originalResult;
            resultChanged = true;
        } else {
            finalResult = originalResult;
            resultChanged = false;
        }
        
        return (finalResult, resultChanged);
    }
    
    /**
     * @notice 处理质疑奖励和惩罚
     * @param caseId 案件ID
     * @param resultChanged 结果是否改变
     */
    function _processDisputeRewards(uint256 caseId, bool resultChanged) internal {
        DisputeSession storage session = disputeSessions[caseId];
        
        for (uint256 i = 0; i < session.challenges.length; i++) {
            DataStructures.ChallengeInfo storage challenge = session.challenges[i];
            
            bool challengeSuccessful = false;
            
            // 判断质疑是否成功
            if (resultChanged) {
                // 如果结果改变了，反对验证者的质疑成功
                challengeSuccessful = (challenge.choice == DataStructures.ChallengeChoice.OPPOSE_VALIDATOR);
            } else {
                // 如果结果没改变，支持验证者的质疑成功
                challengeSuccessful = (challenge.choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR);
            }
            
            if (challengeSuccessful) {
                challengerSuccessCount[challenge.challenger]++;
            }
            
            emit Events.ChallengeResultProcessed(
                caseId,
                challenge.challenger,
                challenge.targetValidator,
                challengeSuccessful,
                block.timestamp
            );
        }
    }
    
    // ==================== 查询函数 ====================
    
    /**
     * @notice 获取质疑会话信息
     * @param caseId 案件ID
     * @return 质疑会话基本信息
     */
    function getDisputeSessionInfo(uint256 caseId) external view returns (
        uint256,    // caseId
        bool,       // isActive
        bool,       // isCompleted
        uint256,    // startTime
        uint256,    // endTime
        uint256,    // totalChallenges
        bool        // resultChanged
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
     * @param caseId 案件ID
     * @param challengeIndex 质疑索引
     * @return 质疑详细信息
     */
    function getChallengeInfo(
        uint256 caseId,
        uint256 challengeIndex
    ) external view returns (DataStructures.ChallengeInfo memory) {
        DisputeSession storage session = disputeSessions[caseId];
        
        if (challengeIndex >= session.challenges.length) {
            revert Errors.InvalidAmount(challengeIndex, session.challenges.length);
        }
        
        return session.challenges[challengeIndex];
    }
    
    /**
     * @notice 获取验证者质疑统计
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 质疑统计信息
     */
    function getValidatorChallengeStats(
        uint256 caseId,
        address validator
    ) external view returns (
        uint256,        // supportCount
        uint256,        // opposeCount
        bool,           // hasBeenChallenged
        address[] memory // challengers
    ) {
        ChallengeStats storage stats = disputeSessions[caseId].validatorChallengeStats[validator];
        
        return (
            stats.supportCount,
            stats.opposeCount,
            stats.hasBeenChallenged,
            stats.challengers
        );
    }
    
    /**
     * @notice 获取质疑者统计信息
     * @param challenger 质疑者地址
     * @return successCount 成功次数
     * @return totalCount 总参与次数
     * @return successRate 成功率（百分比）
     */
    function getChallengerStats(address challenger) external view returns (
        uint256 successCount,
        uint256 totalCount,
        uint256 successRate
    ) {
        successCount = challengerSuccessCount[challenger];
        totalCount = challengerTotalCount[challenger];
        successRate = totalCount > 0 ? (successCount * 100) / totalCount : 0;
        
        return (successCount, totalCount, successRate);
    }
    
    /**
     * @notice 检查用户是否参与了某案件的质疑
     * @param user 用户地址
     * @param caseId 案件ID
     * @return 是否参与了质疑
     */
    function hasUserDisputed(address user, uint256 caseId) external view returns (bool) {
        return userDisputeHistory[user][caseId];
    }
    
    /**
     * @notice 获取案件的所有质疑
     * @param caseId 案件ID
     * @return 质疑信息数组
     */
    function getAllChallenges(uint256 caseId) external view returns (DataStructures.ChallengeInfo[] memory) {
        return disputeSessions[caseId].challenges;
    }
    
    // ==================== 管理函数 ====================
    
    /**
     * @notice 设置治理合约地址
     * @param _governanceContract 治理合约地址
     */
    function setGovernanceContract(address _governanceContract) external onlyAdmin notZeroAddress(_governanceContract) {
        governanceContract = _governanceContract;
    }
    
    /**
     * @notice 设置资金管理合约地址
     * @param _fundManager 资金管理合约地址
     */
    function setFundManager(address _fundManager) external onlyAdmin notZeroAddress(_fundManager) {
        fundManager = _fundManager;
    }
    
    /**
     * @notice 设置投票管理合约地址
     * @param _votingManager 投票管理合约地址
     */
    function setVotingManager(address _votingManager) external onlyAdmin notZeroAddress(_votingManager) {
        votingManager = _votingManager;
    }
    
    /**
     * @notice 紧急暂停质疑会话
     * @param caseId 案件ID
     */
    function emergencyPauseDispute(uint256 caseId) external onlyAdmin {
        DisputeSession storage session = disputeSessions[caseId];
        
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }
        
        session.isActive = false;
        
        emit Events.EmergencyTriggered(
            caseId,
            "Dispute Paused",
            "Emergency pause of dispute session",
            msg.sender,
            block.timestamp
        );
    }
} 