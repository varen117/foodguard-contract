// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFoodGuard.sol";
import "../libraries/Utils.sol";
import "./AccessControl.sol";
import "./VotingSystem.sol";
import "./DepositManager.sol";

/**
 * @title ChallengeSystem
 * @dev 质疑系统合约
 * 处理对验证者投票结果的质疑，以及质疑阶段的投票
 */
contract ChallengeSystem is Ownable, ReentrancyGuard {
    
    // 引用其他合约
    AccessControl public accessControl;
    VotingSystem public votingSystem;
    DepositManager public depositManager;
    
    // 质疑配置参数
    struct ChallengeConfig {
        uint256 challengePeriod;        // 质疑期限
        uint256 minChallengeDeposit;    // 最小质疑保证金
        uint256 challengeVotingPeriod;  // 质疑投票期限
        uint256 challengeQuorum;        // 质疑投票法定人数
    }
    
    // 质疑信息扩展结构
    struct ChallengeInfo {
        uint256 caseId;                     // 关联案件ID
        uint256 challengeId;                // 质疑ID
        address challenger;                 // 质疑者
        address targetValidator;            // 被质疑的验证者（新增）
        bool challengeOriginalResult;       // 质疑原结果（true=质疑，false=支持）
        IFoodGuard.Evidence evidence;       // 质疑证据
        uint256 challengeTime;              // 质疑时间
        uint256 challengeDeposit;           // 质疑保证金
        
        // 质疑投票状态
        bool votingActive;                  // 质疑投票是否活跃
        bool votingCompleted;               // 质疑投票是否完成
        uint256 votingDeadline;             // 质疑投票截止时间
        address[] challengeVoters;          // 质疑投票者列表
        mapping(address => IFoodGuard.Vote) challengeVotes; // 质疑投票记录
        mapping(address => bool) hasVotedOnChallenge; // 是否已对质疑投票
        uint256 supportChallengeVotes;      // 支持质疑的票数
        uint256 opposeChallengeVotes;       // 反对质疑的票数
        uint256 totalChallengeWeight;       // 质疑投票总权重
        
        // 质疑结果和奖惩标记
        bool challengeResult;               // 质疑结果（true=质疑成功）
        bool originalResultOverturned;      // 原结果是否被推翻
        mapping(address => bool) rewardTargets;  // 奖励对象标记（新增）
        mapping(address => bool) punishmentTargets; // 惩罚对象标记（新增）
        address[] rewardList;               // 奖励名单（新增）
        address[] punishmentList;           // 惩罚名单（新增）
    }
    
    // 存储案件的质疑信息
    mapping(uint256 => ChallengeInfo[]) public caseChallenges; // caseId => challenges
    mapping(uint256 => bool) public caseInChallengePhase;     // 案件是否在质疑阶段
    mapping(uint256 => uint256) public challengeStartTime;    // 质疑开始时间
    
    // 质疑配置
    ChallengeConfig public challengeConfig;
    
    // 全局计数器
    uint256 public nextChallengeId = 1;
    
    // 事件定义
    event ChallengePhaseStarted(uint256 indexed caseId, uint256 startTime, uint256 deadline);
    event ChallengeSubmitted(uint256 indexed caseId, uint256 indexed challengeId, address indexed challenger, bool challengeOriginalResult);
    event ChallengeVotingStarted(uint256 indexed caseId, uint256 indexed challengeId, uint256 deadline);
    event ChallengeVoteSubmitted(uint256 indexed caseId, uint256 indexed challengeId, address indexed voter, bool support);
    event ChallengeCompleted(uint256 indexed caseId, uint256 indexed challengeId, bool challengeSuccessful);
    event ChallengePhaseEnded(uint256 indexed caseId, bool originalResultChanged);

    constructor(address _accessControl, address _votingSystem, address _depositManager) Ownable(msg.sender) {
        require(_accessControl != address(0), "ChallengeSystem: Invalid access control address");
        require(_votingSystem != address(0), "ChallengeSystem: Invalid voting system address");
        require(_depositManager != address(0), "ChallengeSystem: Invalid deposit manager address");
        
        accessControl = AccessControl(_accessControl);
        votingSystem = VotingSystem(_votingSystem);
        depositManager = DepositManager(_depositManager);
        
        // 初始化质疑配置
        challengeConfig = ChallengeConfig({
            challengePeriod: Utils.CHALLENGE_PERIOD,
            minChallengeDeposit: 0.05 ether,
            challengeVotingPeriod: 2 days,
            challengeQuorum: 5000 // 50%
        });
    }

    // 修饰符：检查质疑权限
    modifier canChallenge() {
        require(accessControl.canComplain(msg.sender), "ChallengeSystem: Not authorized to challenge");
        _;
    }

    // 修饰符：检查质疑阶段是否活跃
    modifier onlyActiveChallengePhase(uint256 caseId) {
        require(caseInChallengePhase[caseId], "ChallengeSystem: Challenge phase not active");
        require(
            block.timestamp <= challengeStartTime[caseId] + challengeConfig.challengePeriod,
            "ChallengeSystem: Challenge period expired"
        );
        _;
    }

    /**
     * @dev 开始质疑阶段
     */
    function startChallengePhase(uint256 caseId) external onlyOwner {
        require(caseId > 0, "ChallengeSystem: Invalid case ID");
        require(!caseInChallengePhase[caseId], "ChallengeSystem: Challenge phase already active");
        
        // 检查投票是否已完成
        (, , , , , bool isActive, bool isCompleted, ) = votingSystem.getCaseVotingInfo(caseId);
        require(!isActive && isCompleted, "ChallengeSystem: Voting not completed");

        caseInChallengePhase[caseId] = true;
        challengeStartTime[caseId] = block.timestamp;
        
        uint256 deadline = block.timestamp + challengeConfig.challengePeriod;
        
        emit ChallengePhaseStarted(caseId, block.timestamp, deadline);
    }

    /**
     * @dev 提交质疑 - 可以针对特定验证者的证据进行质疑
     */
    function submitChallenge(
        uint256 caseId,
        address targetValidator,          // 被质疑的验证者（新增参数）
        bool challengeOriginalResult,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external payable nonReentrant onlyActiveChallengePhase(caseId) canChallenge {
        require(msg.value >= challengeConfig.minChallengeDeposit, "ChallengeSystem: Insufficient challenge deposit");
        require(Utils.validateEvidenceHashes(evidenceFiles), "ChallengeSystem: Invalid evidence format");
        require(targetValidator != address(0), "ChallengeSystem: Invalid target validator");
        
        // 验证目标验证者确实参与了该案件的验证
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        bool validTarget = false;
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == targetValidator) {
                validTarget = true;
                break;
            }
        }
        require(validTarget, "ChallengeSystem: Target validator did not participate in voting");
        
        // 确保质疑者未参与过本次验证
        for (uint256 i = 0; i < validators.length; i++) {
            require(validators[i] != msg.sender, "ChallengeSystem: Challengers cannot be validators");
        }

        // 创建质疑证据
        IFoodGuard.Evidence memory evidence = IFoodGuard.Evidence({
            description: evidenceDescription,
            fileHashes: evidenceFiles,
            timestamp: block.timestamp,
            submitter: msg.sender
        });

        // 创建质疑信息
        uint256 challengeId = nextChallengeId++;
        ChallengeInfo storage challenge = caseChallenges[caseId].push();
        
        challenge.caseId = caseId;
        challenge.challengeId = challengeId;
        challenge.challenger = msg.sender;
        challenge.targetValidator = targetValidator;    // 记录被质疑的验证者
        challenge.challengeOriginalResult = challengeOriginalResult;
        challenge.evidence = evidence;
        challenge.challengeTime = block.timestamp;
        challenge.challengeDeposit = msg.value;
        challenge.votingActive = false;
        challenge.votingCompleted = false;

        emit ChallengeSubmitted(caseId, challengeId, msg.sender, challengeOriginalResult);
    }

    /**
     * @dev 开始质疑投票
     */
    function startChallengeVoting(uint256 caseId, uint256 challengeIndex) external onlyOwner {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        require(!challenge.votingActive, "ChallengeSystem: Challenge voting already active");
        require(!challenge.votingCompleted, "ChallengeSystem: Challenge voting already completed");

        challenge.votingActive = true;
        challenge.votingDeadline = block.timestamp + challengeConfig.challengeVotingPeriod;

        emit ChallengeVotingStarted(caseId, challenge.challengeId, challenge.votingDeadline);
    }

    /**
     * @dev 对质疑进行投票 - 只允许未参与过验证和质疑的成员投票
     */
    function voteOnChallenge(
        uint256 caseId,
        uint256 challengeIndex,
        bool supportChallenge,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external nonReentrant {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        require(accessControl.canVote(msg.sender), "ChallengeSystem: Not authorized to vote");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        require(challenge.votingActive, "ChallengeSystem: Challenge voting not active");
        require(!challenge.votingCompleted, "ChallengeSystem: Challenge voting completed");
        require(block.timestamp <= challenge.votingDeadline, "ChallengeSystem: Challenge voting period expired");
        require(!challenge.hasVotedOnChallenge[msg.sender], "ChallengeSystem: Already voted on challenge");
        
        // 确保投票者未参与过本次验证
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        for (uint256 i = 0; i < validators.length; i++) {
            require(validators[i] != msg.sender, "ChallengeSystem: Validators cannot vote on challenges");
        }
        
        // 确保投票者未提交过质疑
        ChallengeInfo[] storage allChallenges = caseChallenges[caseId];
        for (uint256 i = 0; i < allChallenges.length; i++) {
            require(allChallenges[i].challenger != msg.sender, "ChallengeSystem: Challengers cannot vote on other challenges");
        }

        // 验证证据格式
        require(Utils.validateEvidenceHashes(evidenceFiles), "ChallengeSystem: Invalid evidence format");

        // 计算投票权重
        (, uint256 availableAmount, , , bool isActive) = depositManager.getUserDeposit(msg.sender);
        require(isActive, "ChallengeSystem: Voter deposit not active");
        
        uint256 weight = Utils.calculateVotingWeight(availableAmount);
        require(weight > 0, "ChallengeSystem: No voting weight");

        // 创建投票记录
        IFoodGuard.Evidence memory evidence = IFoodGuard.Evidence({
            description: evidenceDescription,
            fileHashes: evidenceFiles,
            timestamp: block.timestamp,
            submitter: msg.sender
        });

        IFoodGuard.Vote memory vote = IFoodGuard.Vote({
            voter: msg.sender,
            support: supportChallenge,
            evidence: evidence,
            timestamp: block.timestamp,
            weight: weight
        });

        // 更新投票状态
        challenge.hasVotedOnChallenge[msg.sender] = true;
        challenge.challengeVotes[msg.sender] = vote;
        challenge.challengeVoters.push(msg.sender);
        challenge.totalChallengeWeight += weight;

        if (supportChallenge) {
            challenge.supportChallengeVotes += weight;
        } else {
            challenge.opposeChallengeVotes += weight;
        }

        emit ChallengeVoteSubmitted(caseId, challenge.challengeId, msg.sender, supportChallenge);

        // 检查是否可以提前完成质疑投票
        _checkChallengeVotingCompletion(caseId, challengeIndex);
    }

    /**
     * @dev 完成质疑投票并计算奖惩标记
     */
    function completeChallengeVoting(uint256 caseId, uint256 challengeIndex) external nonReentrant {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        require(challenge.votingActive, "ChallengeSystem: Challenge voting not active");
        require(!challenge.votingCompleted, "ChallengeSystem: Challenge voting already completed");
        
        // 检查是否满足完成条件
        bool isExpired = block.timestamp > challenge.votingDeadline;
        bool hasQuorum = _hasChallengeQuorum(caseId, challengeIndex);
        
        require(isExpired || hasQuorum, "ChallengeSystem: Challenge voting not ready for completion");

        // 计算质疑结果
        bool challengeSuccessful = false;
        if (challenge.totalChallengeWeight > 0) {
            uint256 supportPercentage = (challenge.supportChallengeVotes * Utils.PERCENTAGE_BASE) / challenge.totalChallengeWeight;
            challengeSuccessful = supportPercentage > challengeConfig.challengeQuorum;
        }

        // 更新状态
        challenge.votingCompleted = true;
        challenge.votingActive = false;
        challenge.challengeResult = challengeSuccessful;
        
        // 标记奖惩对象
        _markRewardAndPunishmentTargets(caseId, challengeIndex, challengeSuccessful);

        emit ChallengeCompleted(caseId, challenge.challengeId, challengeSuccessful);
    }
    
    /**
     * @dev 内部函数：标记奖惩对象
     */
    function _markRewardAndPunishmentTargets(uint256 caseId, uint256 challengeIndex, bool challengeSuccessful) internal {
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        
        // 1. 标记质疑者的奖惩状态
        if (challengeSuccessful) {
            // 质疑成功，质疑者获得奖励
            challenge.rewardTargets[challenge.challenger] = true;
            challenge.rewardList.push(challenge.challenger);
            
            // 被质疑的验证者受到惩罚
            challenge.punishmentTargets[challenge.targetValidator] = true;
            challenge.punishmentList.push(challenge.targetValidator);
        } else {
            // 质疑失败，质疑者受到惩罚
            challenge.punishmentTargets[challenge.challenger] = true;
            challenge.punishmentList.push(challenge.challenger);
        }
        
        // 2. 标记质疑投票者的奖惩状态
        for (uint256 i = 0; i < challenge.challengeVoters.length; i++) {
            address voter = challenge.challengeVoters[i];
            IFoodGuard.Vote storage vote = challenge.challengeVotes[voter];
            
            // 检查投票者是否站在多数一边
            bool voterOnWinningSide = (vote.support == challengeSuccessful);
            
            if (voterOnWinningSide) {
                // 投票者站在赢的一方，获得奖励
                if (!challenge.rewardTargets[voter]) {
                    challenge.rewardTargets[voter] = true;
                    challenge.rewardList.push(voter);
                }
            } else {
                // 投票者站在输的一方，受到惩罚
                if (!challenge.punishmentTargets[voter]) {
                    challenge.punishmentTargets[voter] = true;
                    challenge.punishmentList.push(voter);
                }
            }
        }
    }

    /**
     * @dev 结束质疑阶段
     */
    function endChallengePhase(uint256 caseId) external onlyOwner returns (bool originalResultChanged) {
        require(caseInChallengePhase[caseId], "ChallengeSystem: Challenge phase not active");
        require(
            block.timestamp > challengeStartTime[caseId] + challengeConfig.challengePeriod,
            "ChallengeSystem: Challenge period not expired"
        );

        // 检查是否有成功的质疑
        ChallengeInfo[] storage challenges = caseChallenges[caseId];
        uint256 successfulChallenges = 0;
        
        for (uint256 i = 0; i < challenges.length; i++) {
            if (challenges[i].votingCompleted && challenges[i].challengeResult) {
                successfulChallenges++;
                challenges[i].originalResultOverturned = true;
            }
        }

        // 如果有成功的质疑，原结果被推翻
        originalResultChanged = successfulChallenges > 0;
        
        // 结束质疑阶段
        caseInChallengePhase[caseId] = false;
        
        emit ChallengePhaseEnded(caseId, originalResultChanged);
        
        return originalResultChanged;
    }

    /**
     * @dev 内部函数：检查质疑投票是否达到法定人数
     */
    function _hasChallengeQuorum(uint256 caseId, uint256 challengeIndex) internal view returns (bool) {
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        
        // 获取原投票的验证者数量
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        uint256 totalValidators = validators.length;
        
        uint256 quorumRequired = (totalValidators * challengeConfig.challengeQuorum) / Utils.PERCENTAGE_BASE;
        return challenge.challengeVoters.length >= quorumRequired;
    }

    /**
     * @dev 内部函数：检查质疑投票是否可以提前完成
     */
    function _checkChallengeVotingCompletion(uint256 caseId, uint256 challengeIndex) internal {
        if (_hasChallengeQuorum(caseId, challengeIndex)) {
            // 达到法定人数，可以完成投票
            this.completeChallengeVoting(caseId, challengeIndex);
        }
    }

    // ========== 查询函数 ==========

    /**
     * @dev 获取案件的质疑数量
     */
    function getChallengeCount(uint256 caseId) external view returns (uint256) {
        return caseChallenges[caseId].length;
    }

    /**
     * @dev 获取质疑基本信息
     */
    function getChallengeInfo(uint256 caseId, uint256 challengeIndex) external view returns (
        uint256 challengeId,
        address challenger,
        address targetValidator,
        bool challengeOriginalResult,
        uint256 challengeTime,
        uint256 challengeDeposit,
        bool votingActive,
        bool votingCompleted,
        bool challengeResult
    ) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        return (
            challenge.challengeId,
            challenge.challenger,
            challenge.targetValidator,
            challenge.challengeOriginalResult,
            challenge.challengeTime,
            challenge.challengeDeposit,
            challenge.votingActive,
            challenge.votingCompleted,
            challenge.challengeResult
        );
    }
    
    /**
     * @dev 获取质疑的奖惩标记信息
     */
    function getChallengeRewardPunishmentInfo(uint256 caseId, uint256 challengeIndex) external view returns (
        address[] memory rewardList,
        address[] memory punishmentList
    ) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        return (challenge.rewardList, challenge.punishmentList);
    }
    
    /**
     * @dev 检查地址是否为奖励对象
     */
    function isRewardTarget(uint256 caseId, uint256 challengeIndex, address user) external view returns (bool) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        return caseChallenges[caseId][challengeIndex].rewardTargets[user];
    }
    
    /**
     * @dev 检查地址是否为惩罚对象
     */
    function isPunishmentTarget(uint256 caseId, uint256 challengeIndex, address user) external view returns (bool) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        return caseChallenges[caseId][challengeIndex].punishmentTargets[user];
    }

    /**
     * @dev 获取质疑投票统计
     */
    function getChallengeVotingStats(uint256 caseId, uint256 challengeIndex) external view returns (
        uint256 supportVotes,
        uint256 opposeVotes,
        uint256 totalWeight,
        uint256 voterCount,
        uint256 deadline
    ) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        
        ChallengeInfo storage challenge = caseChallenges[caseId][challengeIndex];
        return (
            challenge.supportChallengeVotes,
            challenge.opposeChallengeVotes,
            challenge.totalChallengeWeight,
            challenge.challengeVoters.length,
            challenge.votingDeadline
        );
    }

    /**
     * @dev 检查用户是否对特定质疑投过票
     */
    function hasVotedOnChallenge(uint256 caseId, uint256 challengeIndex, address voter) external view returns (bool) {
        require(challengeIndex < caseChallenges[caseId].length, "ChallengeSystem: Invalid challenge index");
        return caseChallenges[caseId][challengeIndex].hasVotedOnChallenge[voter];
    }

    /**
     * @dev 更新质疑配置（仅owner）
     */
    function updateChallengeConfig(
        uint256 _challengePeriod,
        uint256 _minChallengeDeposit,
        uint256 _challengeVotingPeriod,
        uint256 _challengeQuorum
    ) external onlyOwner {
        require(_challengePeriod >= 1 days && _challengePeriod <= 7 days, "ChallengeSystem: Invalid challenge period");
        require(_minChallengeDeposit > 0, "ChallengeSystem: Invalid min challenge deposit");
        require(_challengeVotingPeriod >= 1 days && _challengeVotingPeriod <= 5 days, "ChallengeSystem: Invalid challenge voting period");
        require(_challengeQuorum <= Utils.PERCENTAGE_BASE, "ChallengeSystem: Invalid challenge quorum");

        challengeConfig.challengePeriod = _challengePeriod;
        challengeConfig.minChallengeDeposit = _minChallengeDeposit;
        challengeConfig.challengeVotingPeriod = _challengeVotingPeriod;
        challengeConfig.challengeQuorum = _challengeQuorum;
    }

    /**
     * @dev 获取质疑配置
     */
    function getChallengeConfig() external view returns (ChallengeConfig memory) {
        return challengeConfig;
    }
} 