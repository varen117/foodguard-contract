// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RewardPunishmentManager
 * @author Food Safety Governance Team
 * @notice 奖惩管理模块，负责根据投票和质疑结果计算和分配奖励与惩罚
 * @dev 根据流程图逻辑处理复杂的奖惩计算，管理用户诚信状态
 */
contract RewardPunishmentManager is Ownable {
    // ==================== 状态变量 ====================

    /// @notice 治理合约地址
    address public governanceContract;

    /// @notice 资金管理合约地址
    address public fundManager;

    /// @notice 用户状态映射
    mapping(address => DataStructures.UserStatus) public userStatuses;

    /// @notice 案件奖惩记录映射 caseId => RewardPunishmentRecord
    mapping(uint256 => RewardPunishmentRecord) public caseRewards;

    /// @notice 用户总奖励统计
    mapping(address => uint256) public totalUserRewards;

    /// @notice 用户总惩罚统计
    mapping(address => uint256) public totalUserPunishments;

    /// @notice 案件是否已处理奖惩 caseId => processed
    mapping(uint256 => bool) public caseProcessed;

    // ==================== 结构体定义 ====================

    /**
     * @notice 奖惩记录结构体
     */
    struct RewardPunishmentRecord {
        uint256 caseId; // 案件ID
        bool complaintUpheld; // 投诉是否成立
        DataStructures.RiskLevel riskLevel; // 风险等级
        uint256 totalRewardAmount; // 总奖励金额
        uint256 totalPunishmentAmount; // 总惩罚金额
        bool isProcessed; // 是否已处理
        uint256 processTime; // 处理时间
        // 个人奖惩映射
        mapping(address => PersonalReward) personalRewards;
        mapping(address => PersonalPunishment) personalPunishments;
        // 参与者列表
        address[] rewardRecipients;
        address[] punishmentTargets;
    }

    /**
     * @notice 个人奖励记录
     */
    struct PersonalReward {
        uint256 amount; // 奖励金额
        string reason; // 奖励原因
        DataStructures.RewardPunishmentStatus status; // 奖励状态
        bool claimed; // 是否已领取
    }

    /**
     * @notice 个人惩罚记录
     */
    struct PersonalPunishment {
        uint256 amount; // 惩罚金额
        string reason; // 惩罚原因
        DataStructures.RewardPunishmentStatus status; // 惩罚状态
        bool executed; // 是否已执行
    }

    /**
     * @notice 奖惩计算参数
     */
    struct CalculationParams {
        uint256 caseId;
        bool complaintUpheld;
        DataStructures.RiskLevel riskLevel;
        address complainant;
        address enterprise;
        address[] validators;
        address[] challengers;
        mapping(address => DataStructures.VoteInfo) votes;
        mapping(address => bool) challengeResults;
    }

    // ==================== 修饰符 ====================

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
     * @notice 检查案件是否未处理
     */
    modifier caseNotProcessed(uint256 caseId) {
        if (caseProcessed[caseId]) {
            revert Errors.RewardPunishmentAlreadyProcessed(caseId);
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address _admin) Ownable(_admin) {
    }

    // ==================== 核心奖惩处理函数 ====================

    /**
     * @notice 处理案件奖惩（主要入口函数）
     * @param caseId 案件ID
     * @param complaintUpheld 投诉是否成立
     * @param riskLevel 风险等级
     * @param complainant 投诉者地址
     * @param enterprise 企业地址
     * @param validators 验证者地址数组
     * @param validatorChoices 验证者投票选择数组
     * @param challengers 质疑者地址数组
     * @param challengeSuccessful 质疑者是否成功数组
     */
    function processCaseRewardPunishment(
        uint256 caseId,
        bool complaintUpheld,
        DataStructures.RiskLevel riskLevel,
        address complainant,
        address enterprise,
        address[] calldata validators,
        DataStructures.VoteChoice[] calldata validatorChoices,
        address[] calldata challengers,
        bool[] calldata challengeSuccessful
    ) external onlyGovernance caseNotProcessed(caseId) {
        // 验证输入参数
        if (validators.length != validatorChoices.length) {
            revert Errors.InvalidAmount(
                validators.length,
                validatorChoices.length
            );
        }

        if (challengers.length != challengeSuccessful.length) {
            revert Errors.InvalidAmount(
                challengers.length,
                challengeSuccessful.length
            );
        }

        // 创建奖惩记录
        RewardPunishmentRecord storage record = caseRewards[caseId];
        record.caseId = caseId;
        record.complaintUpheld = complaintUpheld;
        record.riskLevel = riskLevel;
        record.isProcessed = false;
        record.processTime = block.timestamp;

        emit Events.RewardPunishmentCalculationStarted(
            caseId,
            complaintUpheld,
            block.timestamp
        );

        // 处理验证者奖惩
        _processValidatorRewards(
            caseId,
            validators,
            validatorChoices,
            complaintUpheld
        );

        // 处理质疑者奖惩
        _processChallengerRewards(caseId, challengers, challengeSuccessful);

        // 处理投诉者和企业奖惩
        _processComplainantEnterpriseRewards(
            caseId,
            complainant,
            enterprise,
            complaintUpheld,
            riskLevel
        );

        // 标记案件已处理
        caseProcessed[caseId] = true;
        record.isProcessed = true;
    }

    /**
     * @notice 处理验证者奖惩
     * @param caseId 案件ID
     * @param validators 验证者数组
     * @param choices 投票选择数组
     * @param complaintUpheld 投诉是否成立
     */
    function _processValidatorRewards(
        uint256 caseId,
        address[] calldata validators,
        DataStructures.VoteChoice[] calldata choices,
        bool complaintUpheld
    ) internal {
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            DataStructures.VoteChoice choice = choices[i];

            // 判断验证者投票是否正确
            bool votedCorrectly = false;
            if (
                complaintUpheld &&
                choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT
            ) {
                votedCorrectly = true;
            } else if (
                !complaintUpheld &&
            choice == DataStructures.VoteChoice.REJECT_COMPLAINT
            ) {
                votedCorrectly = true;
            }

            // 更新验证者诚信状态和奖惩状态
            DataStructures.UserStatus storage status = userStatuses[validator];

            if (votedCorrectly) {
                // 投票正确，诚实，获得奖励
                status.integrity = DataStructures.IntegrityStatus.HONEST;
                status.rewardPunishment = DataStructures
                    .RewardPunishmentStatus
                    .REWARD;

                // 计算奖励金额（基础奖励）
                uint256 rewardAmount = _calculateValidatorReward(validator);

                // 记录个人奖励
                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalRewards[validator] = PersonalReward({
                    amount: rewardAmount,
                    reason: "Correct validation",
                    status: DataStructures.RewardPunishmentStatus.REWARD,
                    claimed: false
                });

                record.rewardRecipients.push(validator);
                record.totalRewardAmount += rewardAmount;
                totalUserRewards[validator] += rewardAmount;

                emit Events.UserIntegrityStatusUpdated(
                    caseId,
                    validator,
                    DataStructures.IntegrityStatus.DISHONEST, // 假设之前状态
                    DataStructures.IntegrityStatus.HONEST,
                    DataStructures.RewardPunishmentStatus.REWARD,
                    block.timestamp
                );
            } else {
                // 投票错误，不诚实，接受惩罚
                status.integrity = DataStructures.IntegrityStatus.DISHONEST;
                status.rewardPunishment = DataStructures
                    .RewardPunishmentStatus
                    .PUNISHMENT;

                // 计算惩罚金额
                uint256 punishmentAmount = _calculateValidatorPunishment(
                    validator
                );

                // 记录个人惩罚
                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalPunishments[validator] = PersonalPunishment({
                    amount: punishmentAmount,
                    reason: "Incorrect validation",
                    status: DataStructures.RewardPunishmentStatus.PUNISHMENT,
                    executed: false
                });

                record.punishmentTargets.push(validator);
                record.totalPunishmentAmount += punishmentAmount;
                totalUserPunishments[validator] += punishmentAmount;

                emit Events.UserIntegrityStatusUpdated(
                    caseId,
                    validator,
                    DataStructures.IntegrityStatus.HONEST, // 假设之前状态
                    DataStructures.IntegrityStatus.DISHONEST,
                    DataStructures.RewardPunishmentStatus.PUNISHMENT,
                    block.timestamp
                );
            }

            // 更新验证者统计
            status.participationCount++;
        }
    }

    /**
     * @notice 处理质疑者奖惩
     * @param caseId 案件ID
     * @param challengers 质疑者数组
     * @param successResults 质疑是否成功数组
     */
    function _processChallengerRewards(
        uint256 caseId,
        address[] calldata challengers,
        bool[] calldata successResults
    ) internal {
        for (uint256 i = 0; i < challengers.length; i++) {
            address challenger = challengers[i];
            bool successful = successResults[i];

            DataStructures.UserStatus storage status = userStatuses[challenger];

            if (successful) {
                // 质疑成功，诚实，获得奖励
                status.integrity = DataStructures.IntegrityStatus.HONEST;
                status.rewardPunishment = DataStructures
                    .RewardPunishmentStatus
                    .REWARD;

                uint256 rewardAmount = _calculateChallengerReward(challenger);

                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalRewards[challenger] = PersonalReward({
                    amount: rewardAmount,
                    reason: "Successful challenge",
                    status: DataStructures.RewardPunishmentStatus.REWARD,
                    claimed: false
                });

                record.rewardRecipients.push(challenger);
                record.totalRewardAmount += rewardAmount;
                totalUserRewards[challenger] += rewardAmount;
            } else {
                // 质疑失败，不诚实，接受惩罚
                status.integrity = DataStructures.IntegrityStatus.DISHONEST;
                status.rewardPunishment = DataStructures
                    .RewardPunishmentStatus
                    .PUNISHMENT;

                uint256 punishmentAmount = _calculateChallengerPunishment(
                    challenger
                );

                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalPunishments[challenger] = PersonalPunishment({
                    amount: punishmentAmount,
                    reason: "Failed challenge",
                    status: DataStructures.RewardPunishmentStatus.PUNISHMENT,
                    executed: false
                });

                record.punishmentTargets.push(challenger);
                record.totalPunishmentAmount += punishmentAmount;
                totalUserPunishments[challenger] += punishmentAmount;
            }

            emit Events.UserIntegrityStatusUpdated(
                caseId,
                challenger,
                DataStructures.IntegrityStatus.HONEST, // 简化处理
                status.integrity,
                status.rewardPunishment,
                block.timestamp
            );
        }
    }

    /**
     * @notice 处理投诉者和企业奖惩
     * @param caseId 案件ID
     * @param complainant 投诉者地址
     * @param enterprise 企业地址
     * @param complaintUpheld 投诉是否成立
     * @param riskLevel 风险等级
     */
    function _processComplainantEnterpriseRewards(
        uint256 caseId,
        address complainant,
        address enterprise,
        bool complaintUpheld,
        DataStructures.RiskLevel riskLevel
    ) internal {
        RewardPunishmentRecord storage record = caseRewards[caseId];

        if (complaintUpheld) {
            // 投诉成立，企业败诉

            // 投诉者获得赔偿
            DataStructures.UserStatus storage complainantStatus = userStatuses[
                        complainant
                ];
            complainantStatus.integrity = DataStructures.IntegrityStatus.HONEST;
            complainantStatus.rewardPunishment = DataStructures
                .RewardPunishmentStatus
                .REWARD;

            uint256 compensationAmount = _calculateCompensation(riskLevel);

            record.personalRewards[complainant] = PersonalReward({
                amount: compensationAmount,
                reason: "Complaint upheld compensation",
                status: DataStructures.RewardPunishmentStatus.REWARD,
                claimed: false
            });

            record.rewardRecipients.push(complainant);
            record.totalRewardAmount += compensationAmount;
            totalUserRewards[complainant] += compensationAmount;

            // 企业接受惩罚
            DataStructures.UserStatus storage enterpriseStatus = userStatuses[
                        enterprise
                ];
            enterpriseStatus.integrity = DataStructures
                .IntegrityStatus
                .DISHONEST;
            enterpriseStatus.rewardPunishment = DataStructures
                .RewardPunishmentStatus
                .PUNISHMENT;

            uint256 enterprisePenalty = _calculateEnterprisePenalty(riskLevel);

            record.personalPunishments[enterprise] = PersonalPunishment({
                amount: enterprisePenalty,
                reason: "Food safety violation",
                status: DataStructures.RewardPunishmentStatus.PUNISHMENT,
                executed: false
            });

            record.punishmentTargets.push(enterprise);
            record.totalPunishmentAmount += enterprisePenalty;
            totalUserPunishments[enterprise] += enterprisePenalty;
        } else {
            // 投诉失败，投诉者败诉

            // 投诉者接受惩罚（虚假投诉）
            DataStructures.UserStatus storage complainantStatus = userStatuses[
                        complainant
                ];
            complainantStatus.integrity = DataStructures
                .IntegrityStatus
                .DISHONEST;
            complainantStatus.rewardPunishment = DataStructures
                .RewardPunishmentStatus
                .PUNISHMENT;

            uint256 falseComplaintPenalty = _calculateFalseComplaintPenalty(
                riskLevel
            );

            record.personalPunishments[complainant] = PersonalPunishment({
                amount: falseComplaintPenalty,
                reason: "False complaint",
                status: DataStructures.RewardPunishmentStatus.PUNISHMENT,
                executed: false
            });

            record.punishmentTargets.push(complainant);
            record.totalPunishmentAmount += falseComplaintPenalty;
            totalUserPunishments[complainant] += falseComplaintPenalty;

            // 企业声誉恢复
            DataStructures.UserStatus storage enterpriseStatus = userStatuses[
                        enterprise
                ];
            enterpriseStatus.integrity = DataStructures.IntegrityStatus.HONEST;
            enterpriseStatus.rewardPunishment = DataStructures
                .RewardPunishmentStatus
                .REWARD;

            // 企业可能获得少量补偿
            uint256 reputationCompensation = _calculateReputationCompensation();

            if (reputationCompensation > 0) {
                record.personalRewards[enterprise] = PersonalReward({
                    amount: reputationCompensation,
                    reason: "Reputation restoration",
                    status: DataStructures.RewardPunishmentStatus.REWARD,
                    claimed: false
                });

                record.rewardRecipients.push(enterprise);
                record.totalRewardAmount += reputationCompensation;
                totalUserRewards[enterprise] += reputationCompensation;
            }
        }
    }

    // ==================== 奖惩计算辅助函数 ====================

    /**
     * @notice 计算验证者奖励
     */
    function _calculateValidatorReward(
        address validator
    ) internal view returns (uint256) {
        DataStructures.UserStatus storage status = userStatuses[validator];

        // 基础奖励
        uint256 baseReward = 0.01 ether;

        // 声誉加成
        uint256 reputationBonus = (status.reputationScore * baseReward) / 1000;

        return baseReward + reputationBonus;
    }

    /**
     * @notice 计算验证者惩罚
     */
    function _calculateValidatorPunishment(
        address validator
    ) internal view returns (uint256) {
        // 基础惩罚
        uint256 basePunishment = 0.005 ether;

        return basePunishment;
    }

    /**
     * @notice 计算质疑者奖励
     */
    function _calculateChallengerReward(
        address challenger
    ) internal pure returns (uint256) {
        return 0.02 ether; // 质疑者奖励相对更高
    }

    /**
     * @notice 计算质疑者惩罚
     */
    function _calculateChallengerPunishment(
        address challenger
    ) internal pure returns (uint256) {
        return 0.01 ether; // 失败质疑的惩罚
    }

    /**
     * @notice 计算赔偿金额
     */
    function _calculateCompensation(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 1 ether;
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 0.5 ether;
        } else {
            return 0.1 ether;
        }
    }

    /**
     * @notice 计算企业惩罚
     */
    function _calculateEnterprisePenalty(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 5 ether;
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 2 ether;
        } else {
            return 0.5 ether;
        }
    }

    /**
     * @notice 计算虚假投诉惩罚
     */
    function _calculateFalseComplaintPenalty(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 0.5 ether;
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 0.2 ether;
        } else {
            return 0.05 ether;
        }
    }

    /**
     * @notice 计算声誉恢复补偿
     */
    function _calculateReputationCompensation()
    internal
    pure
    returns (uint256)
    {
        return 0.05 ether;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取案件奖惩记录
     */
    function getCaseRewardRecord(
        uint256 caseId
    )
    external
    view
    returns (
        uint256, // caseId
        bool, // complaintUpheld
        uint8, // riskLevel
        uint256, // totalRewardAmount
        uint256, // totalPunishmentAmount
        bool, // isProcessed
        uint256 // processTime
    )
    {
        RewardPunishmentRecord storage record = caseRewards[caseId];

        return (
            record.caseId,
            record.complaintUpheld,
            uint8(record.riskLevel),
            record.totalRewardAmount,
            record.totalPunishmentAmount,
            record.isProcessed,
            record.processTime
        );
    }

    /**
     * @notice 获取个人奖励信息
     */
    function getPersonalReward(
        uint256 caseId,
        address user
    ) external view returns (PersonalReward memory) {
        return caseRewards[caseId].personalRewards[user];
    }

    /**
     * @notice 获取个人惩罚信息
     */
    function getPersonalPunishment(
        uint256 caseId,
        address user
    ) external view returns (PersonalPunishment memory) {
        return caseRewards[caseId].personalPunishments[user];
    }

    /**
     * @notice 获取用户状态
     */
    function getUserStatus(
        address user
    ) external view returns (DataStructures.UserStatus memory) {
        return userStatuses[user];
    }

    /**
     * @notice 获取用户总奖励和惩罚统计
     */
    function getUserStats(
        address user
    )
    external
    view
    returns (
        uint256 totalRewards,
        uint256 totalPunishments,
        uint256 participationCount,
        uint256 reputationScore
    )
    {
        DataStructures.UserStatus storage status = userStatuses[user];

        return (
            totalUserRewards[user],
            totalUserPunishments[user],
            status.participationCount,
            status.reputationScore
        );
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyOwner {
        if (_governanceContract == address(0)) {
            revert Errors.ZeroAddress();
        }
        governanceContract = _governanceContract;
    }

    /**
     * @notice 设置资金管理合约地址
     */
    function setFundManager(address _fundManager) external onlyOwner {
        if (_fundManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        fundManager = _fundManager;
    }

    /**
     * @notice 更新用户声誉分数
     */
    function updateUserReputation(
        address user,
        uint256 newScore
    ) external onlyGovernance {
        userStatuses[user].reputationScore = newScore;
        userStatuses[user].lastActiveTime = block.timestamp;
    }
}
