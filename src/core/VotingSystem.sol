// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFoodGuard.sol";
import "../libraries/Utils.sol";
import "./AccessControl.sol";
import "./DepositManager.sol";

/**
 * @title VotingSystem
 * @dev 投票系统合约
 * 处理DAO成员对食品安全投诉案件的验证投票
 */
contract VotingSystem is Ownable, ReentrancyGuard {
    
    // 引用访问控制合约和保证金管理合约
    AccessControl public accessControl;
    DepositManager public depositManager;
    
    // 投票配置参数
    struct VotingConfig {
        uint256 minValidators;          // 最少验证者数量
        uint256 maxValidators;          // 最多验证者数量
        uint256 votingPeriod;           // 投票期限
        uint256 quorumPercentage;       // 法定人数百分比
        uint256 majorityThreshold;      // 多数票阈值
    }
    
    // 案件投票状态
    struct CaseVoting {
        uint256 caseId;                 // 案件ID
        address[] validators;           // 验证者数组
        mapping(address => bool) hasVoted;        // 是否已投票
        mapping(address => IFoodGuard.Vote) votes; // 投票记录
        uint256 supportVotes;           // 支持票数（权重总和）
        uint256 opposeVotes;            // 反对票数（权重总和）
        uint256 totalWeight;            // 总投票权重
        uint256 deadline;               // 投票截止时间
        bool isActive;                  // 是否活跃
        bool isCompleted;               // 是否完成
        bool result;                    // 投票结果（true=投诉成立）
        IFoodGuard.RiskLevel riskLevel; // 风险等级
    }
    
    // 存储所有案件的投票信息
    mapping(uint256 => CaseVoting) public caseVotings;
    mapping(uint256 => uint256[]) public caseVoteList; // 案件的投票ID列表
    
    // 投票配置
    VotingConfig public votingConfig;
    
    // 事件定义
    event VotingStarted(uint256 indexed caseId, address[] validators, uint256 deadline);
    event VoteSubmitted(uint256 indexed caseId, address indexed voter, bool support, uint256 weight);
    event VotingCompleted(uint256 indexed caseId, bool result, uint256 supportVotes, uint256 opposeVotes);
    event ValidatorsSelected(uint256 indexed caseId, address[] validators);
    event VotingConfigUpdated(uint256 minValidators, uint256 maxValidators, uint256 votingPeriod);

    constructor(address _accessControl, address _depositManager) Ownable(msg.sender) {
        require(_accessControl != address(0), "VotingSystem: Invalid access control address");
        require(_depositManager != address(0), "VotingSystem: Invalid deposit manager address");
        accessControl = AccessControl(_accessControl);
        depositManager = DepositManager(_depositManager);
        
        // 初始化投票配置
        votingConfig = VotingConfig({
            minValidators: 5,
            maxValidators: 15,
            votingPeriod: 3 days,
            quorumPercentage: 6000, // 60%
            majorityThreshold: 5000 // 50%
        });
    }

    // 修饰符：检查投票权限
    modifier onlyAuthorizedVoter(uint256 caseId) {
        require(accessControl.canVote(msg.sender), "VotingSystem: Not authorized to vote");
        require(isValidatorForCase(caseId, msg.sender), "VotingSystem: Not a validator for this case");
        _;
    }

    // 修饰符：检查案件投票是否活跃
    modifier onlyActiveVoting(uint256 caseId) {
        require(caseVotings[caseId].isActive, "VotingSystem: Voting not active");
        require(!caseVotings[caseId].isCompleted, "VotingSystem: Voting already completed");
        require(block.timestamp <= caseVotings[caseId].deadline, "VotingSystem: Voting period expired");
        _;
    }

    /**
     * @dev 开始投票流程
     */
    function startVoting(
        uint256 caseId,
        IFoodGuard.RiskLevel riskLevel,
        string memory description,
        uint256 evidenceCount
    ) external onlyOwner returns (address[] memory selectedValidators) {
        require(caseId > 0, "VotingSystem: Invalid case ID");
        require(!caseVotings[caseId].isActive, "VotingSystem: Voting already active");

        // 计算所需验证者数量（基于风险等级）
        uint256 validatorCount = _calculateValidatorCount(riskLevel, evidenceCount);
        
        // 随机选择验证者
        selectedValidators = _selectValidators(caseId, validatorCount);
        require(selectedValidators.length >= votingConfig.minValidators, "VotingSystem: Insufficient validators");

        // 计算投票截止时间
        uint256 deadline = Utils.calculateVotingDeadline(riskLevel, block.timestamp);

        // 初始化投票状态
        CaseVoting storage voting = caseVotings[caseId];
        voting.caseId = caseId;
        voting.validators = selectedValidators;
        voting.deadline = deadline;
        voting.isActive = true;
        voting.isCompleted = false;
        voting.riskLevel = riskLevel;

        emit VotingStarted(caseId, selectedValidators, deadline);
        emit ValidatorsSelected(caseId, selectedValidators);

        return selectedValidators;
    }

    /**
     * @dev 提交投票
     */
    function submitVote(
        uint256 caseId,
        bool support,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external nonReentrant onlyActiveVoting(caseId) onlyAuthorizedVoter(caseId) {
        CaseVoting storage voting = caseVotings[caseId];
        require(!voting.hasVoted[msg.sender], "VotingSystem: Already voted");

        // 验证证据格式
        require(Utils.validateEvidenceHashes(evidenceFiles), "VotingSystem: Invalid evidence format");

        // 计算投票权重（基于保证金）
        (uint256 totalAmount, , , , bool isActive) = depositManager.getUserDeposit(msg.sender);
        require(isActive, "VotingSystem: Voter deposit not active");
        
        uint256 weight = Utils.calculateVotingWeight(totalAmount);
        require(weight > 0, "VotingSystem: No voting weight");

        // 创建投票记录
        IFoodGuard.Evidence memory evidence = IFoodGuard.Evidence({
            description: evidenceDescription,
            fileHashes: evidenceFiles,
            timestamp: block.timestamp,
            submitter: msg.sender
        });

        IFoodGuard.Vote memory vote = IFoodGuard.Vote({
            voter: msg.sender,
            support: support,
            evidence: evidence,
            timestamp: block.timestamp,
            weight: weight
        });

        // 更新投票状态
        voting.hasVoted[msg.sender] = true;
        voting.votes[msg.sender] = vote;
        voting.totalWeight += weight;

        if (support) {
            voting.supportVotes += weight;
        } else {
            voting.opposeVotes += weight;
        }

        emit VoteSubmitted(caseId, msg.sender, support, weight);

        // 检查是否可以提前结束投票
        _checkEarlyCompletion(caseId);
    }

    /**
     * @dev 完成投票（可由任何人调用，如果时间到期）
     */
    function completeVoting(uint256 caseId) external nonReentrant {
        CaseVoting storage voting = caseVotings[caseId];
        require(voting.isActive, "VotingSystem: Voting not active");
        require(!voting.isCompleted, "VotingSystem: Voting already completed");
        
        // 检查是否到期或达到完成条件
        bool isExpired = block.timestamp > voting.deadline;
        bool hasQuorum = _hasQuorum(caseId);
        
        require(isExpired || hasQuorum, "VotingSystem: Voting not ready for completion");

        // 计算投票结果
        bool result = false;
        if (hasQuorum) {
            // 计算多数票结果
            uint256 totalVotes = voting.supportVotes + voting.opposeVotes;
            if (totalVotes > 0) {
                uint256 supportPercentage = (voting.supportVotes * Utils.PERCENTAGE_BASE) / totalVotes;
                result = supportPercentage > votingConfig.majorityThreshold;
            }
        }

        // 更新状态
        voting.isCompleted = true;
        voting.isActive = false;
        voting.result = result;

        emit VotingCompleted(caseId, result, voting.supportVotes, voting.opposeVotes);
    }

    /**
     * @dev 内部函数：计算所需验证者数量
     */
    function _calculateValidatorCount(
        IFoodGuard.RiskLevel riskLevel,
        uint256 evidenceCount
    ) internal view returns (uint256) {
        uint256 baseCount = votingConfig.minValidators;
        
        // 根据风险等级调整
        if (riskLevel == IFoodGuard.RiskLevel.HIGH) {
            baseCount = votingConfig.maxValidators;
        } else if (riskLevel == IFoodGuard.RiskLevel.MEDIUM) {
            baseCount = (votingConfig.minValidators + votingConfig.maxValidators) / 2;
        }
        
        // 根据证据数量微调
        if (evidenceCount >= 5) {
            baseCount += 2;
        } else if (evidenceCount >= 3) {
            baseCount += 1;
        }
        
        // 确保在范围内
        if (baseCount > votingConfig.maxValidators) {
            baseCount = votingConfig.maxValidators;
        }
        if (baseCount < votingConfig.minValidators) {
            baseCount = votingConfig.minValidators;
        }
        
        return baseCount;
    }

    /**
     * @dev 内部函数：随机选择验证者
     */
    function _selectValidators(
        uint256 caseId,
        uint256 count
    ) internal view returns (address[] memory) {
        // 获取随机种子
        uint256 seed = Utils.getRandomSeed(caseId, block.number);
        
        // 这里应该实现更复杂的随机选择算法
        // 为演示目的，返回空数组，实际使用时需要从AccessControl获取活跃DAO成员
        address[] memory validators = new address[](count);
        
        // 实际实现需要：
        // 1. 从AccessControl获取所有活跃DAO成员
        // 2. 使用随机算法选择指定数量的成员
        // 3. 确保选择的成员有足够的保证金和信任分数
        
        return validators;
    }

    /**
     * @dev 内部函数：检查是否达到法定人数
     */
    function _hasQuorum(uint256 caseId) internal view returns (bool) {
        CaseVoting storage voting = caseVotings[caseId];
        uint256 totalValidators = voting.validators.length;
        uint256 votedValidators = 0;
        
        for (uint256 i = 0; i < totalValidators; i++) {
            if (voting.hasVoted[voting.validators[i]]) {
                votedValidators++;
            }
        }
        
        uint256 quorumRequired = (totalValidators * votingConfig.quorumPercentage) / Utils.PERCENTAGE_BASE;
        return votedValidators >= quorumRequired;
    }

    /**
     * @dev 内部函数：检查是否可以提前完成投票
     */
    function _checkEarlyCompletion(uint256 caseId) internal {
        CaseVoting storage voting = caseVotings[caseId];
        
        // 如果所有验证者都已投票，可以提前结束
        bool allVoted = true;
        for (uint256 i = 0; i < voting.validators.length; i++) {
            if (!voting.hasVoted[voting.validators[i]]) {
                allVoted = false;
                break;
            }
        }
        
        if (allVoted || _hasQuorum(caseId)) {
            // 触发完成逻辑
            this.completeVoting(caseId);
        }
    }

    /**
     * @dev 检查地址是否是特定案件的验证者
     */
    function isValidatorForCase(uint256 caseId, address validator) public view returns (bool) {
        address[] memory validators = caseVotings[caseId].validators;
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == validator) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev 获取案件投票信息
     */
    function getCaseVotingInfo(uint256 caseId) external view returns (
        address[] memory validators,
        uint256 supportVotes,
        uint256 opposeVotes,
        uint256 totalWeight,
        uint256 deadline,
        bool isActive,
        bool isCompleted,
        bool result
    ) {
        CaseVoting storage voting = caseVotings[caseId];
        return (
            voting.validators,
            voting.supportVotes,
            voting.opposeVotes,
            voting.totalWeight,
            voting.deadline,
            voting.isActive,
            voting.isCompleted,
            voting.result
        );
    }

    /**
     * @dev 获取特定投票者的投票信息
     */
    function getVoteInfo(uint256 caseId, address voter) external view returns (
        bool hasVoted,
        bool support,
        uint256 weight,
        uint256 timestamp,
        string memory evidenceDescription
    ) {
        CaseVoting storage voting = caseVotings[caseId];
        if (!voting.hasVoted[voter]) {
            return (false, false, 0, 0, "");
        }
        
        IFoodGuard.Vote storage vote = voting.votes[voter];
        return (
            true,
            vote.support,
            vote.weight,
            vote.timestamp,
            vote.evidence.description
        );
    }

    /**
     * @dev 更新投票配置（仅owner）
     */
    function updateVotingConfig(
        uint256 _minValidators,
        uint256 _maxValidators,
        uint256 _votingPeriod,
        uint256 _quorumPercentage,
        uint256 _majorityThreshold
    ) external onlyOwner {
        require(_minValidators > 0 && _minValidators <= _maxValidators, "VotingSystem: Invalid validator counts");
        require(_votingPeriod >= Utils.MIN_VOTING_PERIOD && _votingPeriod <= Utils.MAX_VOTING_PERIOD, "VotingSystem: Invalid voting period");
        require(_quorumPercentage <= Utils.PERCENTAGE_BASE, "VotingSystem: Invalid quorum percentage");
        require(_majorityThreshold <= Utils.PERCENTAGE_BASE, "VotingSystem: Invalid majority threshold");

        votingConfig.minValidators = _minValidators;
        votingConfig.maxValidators = _maxValidators;
        votingConfig.votingPeriod = _votingPeriod;
        votingConfig.quorumPercentage = _quorumPercentage;
        votingConfig.majorityThreshold = _majorityThreshold;

        emit VotingConfigUpdated(_minValidators, _maxValidators, _votingPeriod);
    }

    /**
     * @dev 更新访问控制合约地址（仅owner）
     */
    function updateAccessControl(address _accessControl) external onlyOwner {
        require(_accessControl != address(0), "VotingSystem: Invalid access control address");
        accessControl = AccessControl(_accessControl);
    }

    /**
     * @dev 获取投票配置
     */
    function getVotingConfig() external view returns (VotingConfig memory) {
        return votingConfig;
    }
} 