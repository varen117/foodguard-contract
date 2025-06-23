// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFoodGuard.sol";
import "../libraries/Utils.sol";
import "./AccessControl.sol";
import "./DepositManager.sol";
import "./VotingSystem.sol";
import "./ChallengeSystem.sol";

/**
 * @title RewardPunishmentSystem
 * @dev 奖惩系统合约
 * 根据投票和质疑结果，对所有参与者进行奖励分配和惩罚执行
 */
contract RewardPunishmentSystem is Ownable, ReentrancyGuard {
    
    // 引用其他合约
    AccessControl public accessControl;
    DepositManager public depositManager;
    VotingSystem public votingSystem;
    ChallengeSystem public challengeSystem;
    
    // 奖惩配置
    struct RewardConfig {
        uint256 baseRewardRate;         // 基础奖励率 (%)
        uint256 bonusMultiplier;        // 奖励倍数
        uint256 punishmentRate;         // 惩罚率 (%)
        uint256 slashingThreshold;      // 惩罚阈值
        uint256 platformFeeRate;        // 平台手续费率 (%)
    }
    
    // 用户奖惩记录
    struct UserRewardPunishment {
        address user;                           // 用户地址
        IFoodGuard.UserRole role;               // 用户角色
        IFoodGuard.IntegrityStatus integrity;   // 诚信状态
        IFoodGuard.RewardPunishmentStatus status; // 奖惩状态
        uint256 rewardAmount;                   // 奖励金额
        uint256 punishmentAmount;               // 惩罚金额
        string reason;                          // 奖惩原因
        bool processed;                         // 是否已处理
    }
    
    // 案件奖惩汇总
    struct CaseRewardSummary {
        uint256 caseId;                     // 案件ID
        uint256 totalRewardPool;            // 总奖励池
        uint256 totalPunishmentPool;        // 总惩罚池
        uint256 distributedRewards;         // 已分配奖励
        uint256 platformFees;               // 平台费用
        bool isCompleted;                   // 是否完成
        bool complaintSuccessful;           // 投诉是否成功
        mapping(address => UserRewardPunishment) userRecords; // 用户记录
        address[] participants;             // 参与者列表
    }
    
    // 存储案件奖惩记录
    mapping(uint256 => CaseRewardSummary) public caseRewards;
    
    // 奖惩配置
    RewardConfig public rewardConfig;
    
    // 统计数据
    uint256 public totalRewardsDistributed;
    uint256 public totalPunishmentsApplied;
    uint256 public totalPlatformFees;
    
    // 事件定义
    event RewardCalculationStarted(uint256 indexed caseId);
    event UserRewardCalculated(uint256 indexed caseId, address indexed user, IFoodGuard.RewardPunishmentStatus status, uint256 amount);
    event RewardDistributed(uint256 indexed caseId, address indexed user, uint256 amount);
    event PunishmentApplied(uint256 indexed caseId, address indexed user, uint256 amount);
    event CaseRewardCompleted(uint256 indexed caseId, uint256 totalRewards, uint256 totalPunishments);
    event ConfigUpdated(uint256 baseRewardRate, uint256 punishmentRate, uint256 platformFeeRate);

    constructor(
        address _accessControl,
        address _depositManager,
        address _votingSystem,
        address _challengeSystem
    ) Ownable(msg.sender) {
        require(_accessControl != address(0), "RewardPunishmentSystem: Invalid access control address");
        require(_depositManager != address(0), "RewardPunishmentSystem: Invalid deposit manager address");
        require(_votingSystem != address(0), "RewardPunishmentSystem: Invalid voting system address");
        require(_challengeSystem != address(0), "RewardPunishmentSystem: Invalid challenge system address");
        
        accessControl = AccessControl(_accessControl);
        depositManager = DepositManager(_depositManager);
        votingSystem = VotingSystem(_votingSystem);
        challengeSystem = ChallengeSystem(_challengeSystem);
        
        // 初始化奖惩配置
        rewardConfig = RewardConfig({
            baseRewardRate: 1000,       // 10%
            bonusMultiplier: 150,       // 1.5x
            punishmentRate: 2000,       // 20%
            slashingThreshold: 5000,    // 50%
            platformFeeRate: 200        // 2%
        });
    }

    /**
     * @dev 计算案件的奖惩分配
     */
    function calculateRewards(uint256 caseId) external onlyOwner nonReentrant {
        require(caseId > 0, "RewardPunishmentSystem: Invalid case ID");
        require(!caseRewards[caseId].isCompleted, "RewardPunishmentSystem: Rewards already calculated");
        
        // 获取投票结果
        (address[] memory validators, uint256 supportVotes, uint256 opposeVotes, , , bool isActive, bool isCompleted, bool votingResult) = votingSystem.getCaseVotingInfo(caseId);
        require(!isActive && isCompleted, "RewardPunishmentSystem: Voting not completed");
        
        // 检查质疑阶段是否结束
        require(!challengeSystem.caseInChallengePhase(caseId), "RewardPunishmentSystem: Challenge phase still active");
        
        emit RewardCalculationStarted(caseId);
        
        // 初始化案件奖惩汇总
        CaseRewardSummary storage summary = caseRewards[caseId];
        summary.caseId = caseId;
        summary.complaintSuccessful = votingResult;
        
        // 计算基础奖励池
        (uint256 totalCaseDeposit) = depositManager.totalCaseDeposits(caseId);
        summary.totalRewardPool = Utils.calculatePercentage(totalCaseDeposit, rewardConfig.baseRewardRate);
        
        // 处理验证者奖惩
        _processValidatorRewards(caseId, validators, votingResult);
        
        // 处理质疑者奖惩
        _processChallengerRewards(caseId, votingResult);
        
        // 处理投诉者和企业
        _processComplainantAndEnterpriseRewards(caseId, votingResult);
        
        // 计算平台费用
        summary.platformFees = Utils.calculatePercentage(summary.totalRewardPool, rewardConfig.platformFeeRate);
        
        summary.isCompleted = true;
        
        emit CaseRewardCompleted(caseId, summary.distributedRewards, summary.totalPunishmentPool);
    }

    /**
     * @dev 处理验证者奖惩
     */
    function _processValidatorRewards(
        uint256 caseId,
        address[] memory validators,
        bool votingResult
    ) internal {
        CaseRewardSummary storage summary = caseRewards[caseId];
        
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            
            // 获取验证者投票信息
            (bool hasVoted, bool support, uint256 weight, , ) = votingSystem.getVoteInfo(caseId, validator);
            
            if (!hasVoted) continue;
            
            // 判断验证者是否投票正确
            bool votedCorrectly = (support == votingResult);
            
            UserRewardPunishment storage record = summary.userRecords[validator];
            record.user = validator;
            record.role = IFoodGuard.UserRole.VALIDATOR;
            
            if (votedCorrectly) {
                // 投票正确，给予奖励
                record.integrity = IFoodGuard.IntegrityStatus.HONEST;
                record.status = IFoodGuard.RewardPunishmentStatus.REWARD;
                record.rewardAmount = Utils.calculateRewardShare(summary.totalRewardPool, weight, _getTotalCorrectWeight(caseId, votingResult));
                record.reason = "Correct validation";
                
                // 添加到参与者列表
                summary.participants.push(validator);
                summary.distributedRewards += record.rewardAmount;
                
                emit UserRewardCalculated(caseId, validator, IFoodGuard.RewardPunishmentStatus.REWARD, record.rewardAmount);
            } else {
                // 投票错误，给予惩罚
                record.integrity = IFoodGuard.IntegrityStatus.DISHONEST;
                record.status = IFoodGuard.RewardPunishmentStatus.PUNISHMENT;
                record.punishmentAmount = Utils.calculatePercentage(weight * 1 ether, rewardConfig.punishmentRate); // 基于权重计算惩罚
                record.reason = "Incorrect validation";
                
                summary.totalPunishmentPool += record.punishmentAmount;
                
                emit UserRewardCalculated(caseId, validator, IFoodGuard.RewardPunishmentStatus.PUNISHMENT, record.punishmentAmount);
            }
        }
    }

    /**
     * @dev 处理质疑者奖惩
     */
    function _processChallengerRewards(uint256 caseId, bool finalResult) internal {
        CaseRewardSummary storage summary = caseRewards[caseId];
        uint256 challengeCount = challengeSystem.getChallengeCount(caseId);
        
        for (uint256 i = 0; i < challengeCount; i++) {
            (uint256 challengeId, address challenger, address targetValidator, bool challengeOriginalResult, , , , bool votingCompleted, bool challengeResult) = challengeSystem.getChallengeInfo(caseId, i);
            
            if (!votingCompleted) continue;
            
            UserRewardPunishment storage record = summary.userRecords[challenger];
            record.user = challenger;
            record.role = IFoodGuard.UserRole.CHALLENGER;
            
            // 质疑成功的逻辑
            if (challengeResult) {
                record.integrity = IFoodGuard.IntegrityStatus.HONEST;
                record.status = IFoodGuard.RewardPunishmentStatus.REWARD;
                record.rewardAmount = Utils.calculatePercentage(summary.totalRewardPool, 500); // 5% 奖励给成功质疑者
                record.reason = "Successful challenge";
                
                summary.participants.push(challenger);
                summary.distributedRewards += record.rewardAmount;
                
                emit UserRewardCalculated(caseId, challenger, IFoodGuard.RewardPunishmentStatus.REWARD, record.rewardAmount);
            } else {
                record.integrity = IFoodGuard.IntegrityStatus.DISHONEST;
                record.status = IFoodGuard.RewardPunishmentStatus.PUNISHMENT;
                record.punishmentAmount = 0.05 ether; // 固定惩罚失败质疑者
                record.reason = "Failed challenge";
                
                summary.totalPunishmentPool += record.punishmentAmount;
                
                emit UserRewardCalculated(caseId, challenger, IFoodGuard.RewardPunishmentStatus.PUNISHMENT, record.punishmentAmount);
            }
            
            // 处理质疑投票者
            _processChallengeVoters(caseId, i, challengeResult);
        }
    }

    /**
     * @dev 处理质疑投票者奖惩
     */
    function _processChallengeVoters(uint256 caseId, uint256 challengeIndex, bool challengeResult) internal {
        CaseRewardSummary storage summary = caseRewards[caseId];
        (uint256 supportVotes, uint256 opposeVotes, , uint256 voterCount, ) = challengeSystem.getChallengeVotingStats(caseId, challengeIndex);
        
        // 这里需要遍历质疑投票者，但由于映射限制，需要在ChallengeSystem中提供获取投票者列表的方法
        // 为了演示，这里省略具体实现
    }

    /**
     * @dev 处理投诉者和企业奖惩
     */
    function _processComplainantAndEnterpriseRewards(uint256 caseId, bool complaintSuccessful) internal {
        CaseRewardSummary storage summary = caseRewards[caseId];
        
        // 这里需要从主合约获取投诉者和企业地址
        // 为了演示，暂时省略具体实现
        // 实际应该根据案件信息获取投诉者和企业地址，然后计算奖惩
    }

    /**
     * @dev 执行奖励分配
     */
    function distributeRewards(uint256 caseId) external onlyOwner nonReentrant {
        CaseRewardSummary storage summary = caseRewards[caseId];
        require(summary.isCompleted, "RewardPunishmentSystem: Rewards not calculated");
        
        for (uint256 i = 0; i < summary.participants.length; i++) {
            address participant = summary.participants[i];
            UserRewardPunishment storage record = summary.userRecords[participant];
            
            if (!record.processed && record.status == IFoodGuard.RewardPunishmentStatus.REWARD) {
                if (record.rewardAmount > 0) {
                    depositManager.distributeReward(participant, record.rewardAmount);
                    record.processed = true;
                    totalRewardsDistributed += record.rewardAmount;
                    
                    emit RewardDistributed(caseId, participant, record.rewardAmount);
                }
            }
        }
    }

    /**
     * @dev 执行惩罚
     */
    function applyPunishments(uint256 caseId) external onlyOwner nonReentrant {
        CaseRewardSummary storage summary = caseRewards[caseId];
        require(summary.isCompleted, "RewardPunishmentSystem: Rewards not calculated");
        
        for (uint256 i = 0; i < summary.participants.length; i++) {
            address participant = summary.participants[i];
            UserRewardPunishment storage record = summary.userRecords[participant];
            
            if (!record.processed && record.status == IFoodGuard.RewardPunishmentStatus.PUNISHMENT) {
                if (record.punishmentAmount > 0) {
                    uint256 slashedAmount = depositManager.slashDeposit(participant, caseId, record.punishmentAmount);
                    record.processed = true;
                    totalPunishmentsApplied += slashedAmount;
                    
                    // 更新信任分数
                    accessControl.updateTrustScore(participant, -int256(slashedAmount / 0.01 ether)); // 每0.01 ETH扣除1分
                    
                    emit PunishmentApplied(caseId, participant, slashedAmount);
                }
            }
        }
    }

    /**
     * @dev 内部函数：计算正确投票的总权重
     */
    function _getTotalCorrectWeight(uint256 caseId, bool correctResult) internal view returns (uint256 totalWeight) {
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        
        for (uint256 i = 0; i < validators.length; i++) {
            (bool hasVoted, bool support, uint256 weight, , ) = votingSystem.getVoteInfo(caseId, validators[i]);
            if (hasVoted && support == correctResult) {
                totalWeight += weight;
            }
        }
        
        return totalWeight;
    }

    // ========== 查询函数 ==========

    /**
     * @dev 获取案件奖惩汇总
     */
    function getCaseRewardSummary(uint256 caseId) external view returns (
        uint256 totalRewardPool,
        uint256 totalPunishmentPool,
        uint256 distributedRewards,
        uint256 platformFees,
        bool isCompleted,
        bool complaintSuccessful
    ) {
        CaseRewardSummary storage summary = caseRewards[caseId];
        return (
            summary.totalRewardPool,
            summary.totalPunishmentPool,
            summary.distributedRewards,
            summary.platformFees,
            summary.isCompleted,
            summary.complaintSuccessful
        );
    }

    /**
     * @dev 获取用户在特定案件中的奖惩记录
     */
    function getUserRewardRecord(uint256 caseId, address user) external view returns (
        IFoodGuard.UserRole role,
        IFoodGuard.IntegrityStatus integrity,
        IFoodGuard.RewardPunishmentStatus status,
        uint256 rewardAmount,
        uint256 punishmentAmount,
        string memory reason,
        bool processed
    ) {
        UserRewardPunishment storage record = caseRewards[caseId].userRecords[user];
        return (
            record.role,
            record.integrity,
            record.status,
            record.rewardAmount,
            record.punishmentAmount,
            record.reason,
            record.processed
        );
    }

    /**
     * @dev 获取系统统计信息
     */
    function getSystemStats() external view returns (
        uint256 totalRewards,
        uint256 totalPunishments,
        uint256 totalFees
    ) {
        return (
            totalRewardsDistributed,
            totalPunishmentsApplied,
            totalPlatformFees
        );
    }

    /**
     * @dev 更新奖惩配置（仅owner）
     */
    function updateRewardConfig(
        uint256 _baseRewardRate,
        uint256 _bonusMultiplier,
        uint256 _punishmentRate,
        uint256 _slashingThreshold,
        uint256 _platformFeeRate
    ) external onlyOwner {
        require(_baseRewardRate <= Utils.PERCENTAGE_BASE, "RewardPunishmentSystem: Invalid base reward rate");
        require(_bonusMultiplier >= 100, "RewardPunishmentSystem: Invalid bonus multiplier");
        require(_punishmentRate <= Utils.PERCENTAGE_BASE, "RewardPunishmentSystem: Invalid punishment rate");
        require(_slashingThreshold <= Utils.PERCENTAGE_BASE, "RewardPunishmentSystem: Invalid slashing threshold");
        require(_platformFeeRate <= 1000, "RewardPunishmentSystem: Platform fee too high"); // 最大10%

        rewardConfig.baseRewardRate = _baseRewardRate;
        rewardConfig.bonusMultiplier = _bonusMultiplier;
        rewardConfig.punishmentRate = _punishmentRate;
        rewardConfig.slashingThreshold = _slashingThreshold;
        rewardConfig.platformFeeRate = _platformFeeRate;

        emit ConfigUpdated(_baseRewardRate, _punishmentRate, _platformFeeRate);
    }

    /**
     * @dev 获取奖惩配置
     */
    function getRewardConfig() external view returns (RewardConfig memory) {
        return rewardConfig;
    }
} 