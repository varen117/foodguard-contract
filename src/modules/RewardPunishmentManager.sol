// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用最新稳定版本的Solidity

import "../libraries/DataStructures.sol"; // 导入数据结构库
import "../libraries/Errors.sol"; // 导入错误处理库
import "../libraries/Events.sol"; // 导入事件库
import "../libraries/CommonModifiers.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; // 导入所有权控制

/**
 * @title RewardPunishmentManager
 * @author Food Safety Governance Team
 * @notice 奖惩管理模块，负责根据投票和质疑结果计算和分配奖励与惩罚
 * @dev 根据流程图逻辑处理复杂的奖惩计算，管理用户诚信状态
 * 这是食品安全治理系统的奖惩核心，实现了完整的激励机制：
 * 1. 多角色奖惩：处理投诉者、企业、验证者、质疑者的奖惩逻辑
 * 2. 动态计算：根据风险等级、参与表现、历史声誉动态计算奖惩金额
 * 3. 诚信管理：实时更新用户诚信状态，影响后续参与权限
 * 4. 声誉系统：维护长期声誉分数，实现声誉激励
 * 5. 公平机制：确保正确参与者获得奖励，错误参与者承担相应惩罚
 */
contract RewardPunishmentManager is Ownable {
    // ==================== 状态变量 ====================

    /// @notice 治理合约地址 - 唯一有权调用奖惩处理函数的合约
    /// @dev 确保奖惩处理只能由经过验证的治理流程触发
    address public governanceContract;

    /// @notice 资金管理合约地址 - 处理奖励发放和惩罚扣除的合约
    /// @dev 与资金管理模块协作，实现奖惩的实际执行
    address public fundManager;

    /// @notice 用户状态映射 - 记录每个用户的完整状态信息
    /// @dev 包括诚信状态、声誉分数、参与次数等关键信息
    mapping(address => DataStructures.UserStatus) public userStatuses;

    /// @notice 案件奖惩记录映射 - 每个案件的详细奖惩分配记录
    /// @dev 键值对：caseId => RewardPunishmentRecord，记录案件相关的所有奖惩信息
    mapping(uint256 => RewardPunishmentRecord) public caseRewards;

    /// @notice 用户总奖励统计 - 用户历史累计获得的奖励金额
    /// @dev 用于声誉计算和用户激励展示
    mapping(address => uint256) public totalUserRewards;

    /// @notice 用户总惩罚统计 - 用户历史累计承担的惩罚金额
    /// @dev 用于风险评估和用户信用记录
    mapping(address => uint256) public totalUserPunishments;

    /// @notice 案件是否已处理奖惩标记 - 防止重复处理同一案件
    /// @dev 键值对：caseId => processed，确保每个案件只处理一次奖惩
    mapping(uint256 => bool) public caseProcessed;

    // ==================== 结构体定义 ====================

    /**
     * @notice 奖惩记录结构体 - 记录单个案件的完整奖惩信息
     * @dev 这是奖惩系统的核心数据结构，包含案件的所有奖惩细节
     */
    struct RewardPunishmentRecord {
        uint256 caseId; // 案件ID - 唯一标识符
        bool complaintUpheld; // 投诉是否成立 - 决定奖惩方向的关键标志
        DataStructures.RiskLevel riskLevel; // 风险等级 - 影响奖惩金额的重要因素
        uint256 totalRewardAmount; // 总奖励金额 - 该案件发放的奖励总额
        uint256 totalPunishmentAmount; // 总惩罚金额 - 该案件执行的惩罚总额
        bool isProcessed; // 是否已处理 - 避免重复处理的标志位
        uint256 processTime; // 处理时间 - 记录奖惩处理的时间戳
        // 个人奖惩映射 - 记录每个参与者的具体奖惩情况
        mapping(address => PersonalReward) personalRewards; // 个人奖励详情
        mapping(address => PersonalPunishment) personalPunishments; // 个人惩罚详情
        // 参与者列表 - 便于遍历和统计
        address[] rewardRecipients; // 获得奖励的用户列表
        address[] punishmentTargets; // 承担惩罚的用户列表
    }

    /**
     * @notice 个人奖励记录 - 记录单个用户在特定案件中的奖励信息
     */
    struct PersonalReward {
        uint256 amount; // 奖励金额
        string reason; // 奖励原因
        bool claimed; // 是否已领取
    }

    /**
     * @notice 个人惩罚记录 - 记录单个用户在特定案件中的惩罚信息
     */
    struct PersonalPunishment {
        uint256 amount; // 惩罚金额
        string reason; // 惩罚原因
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

        // 边界条件检查
        if (validators.length == 0) {
            emit Events.BusinessProcessAnomaly(
                caseId,
                address(0),
                "Reward Processing",
                "No validators to process",
                "Skip validator rewards",
                block.timestamp
            );
        }

        // 检查是否有重复的验证者地址
        for (uint256 i = 0; i < validators.length; i++) {
            for (uint256 j = i + 1; j < validators.length; j++) {
                if (validators[i] == validators[j]) {
                    emit Events.BusinessProcessAnomaly(
                        caseId,
                        validators[i],
                        "Reward Processing",
                        "Duplicate validator detected",
                        "Continue with warning",
                        block.timestamp
                    );
                }
            }
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
                // Note: Removed integrity and rewardPunishment field access as they don't exist in UserStatus

                // 计算奖励金额（基础奖励）
                uint256 rewardAmount = _calculateValidatorReward(validator);

                // 记录个人奖励
                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalRewards[validator] = PersonalReward({
                    amount: rewardAmount,
                    reason: "Correct validation",
                    claimed: false
                });

                record.rewardRecipients.push(validator);
                
                // 溢出检测：防止奖励金额计算溢出
                if (record.totalRewardAmount + rewardAmount < record.totalRewardAmount) {
                    emit Events.SystemAnomalyWarning(
                        "REWARD_SYSTEM",
                        "Total reward amount overflow detected",
                        4, // 高严重程度
                        address(this),
                        abi.encode(caseId, validator, rewardAmount, record.totalRewardAmount),
                        block.timestamp
                    );
                    // 使用安全加法，限制在最大值
                    record.totalRewardAmount = type(uint256).max;
                } else {
                    record.totalRewardAmount += rewardAmount;
                }
                
                // 用户总奖励溢出检测
                if (totalUserRewards[validator] + rewardAmount < totalUserRewards[validator]) {
                    emit Events.SystemAnomalyWarning(
                        "REWARD_SYSTEM", 
                        "User total rewards overflow detected",
                        4,
                        address(this),
                        abi.encode(validator, rewardAmount, totalUserRewards[validator]),
                        block.timestamp
                    );
                    totalUserRewards[validator] = type(uint256).max;
                } else {
                    totalUserRewards[validator] += rewardAmount;
                }

                emit Events.UserIntegrityStatusUpdated(
                    caseId,
                    validator,
                    uint8(DataStructures.IntegrityStatus.DISHONEST), // 假设之前状态
                    uint8(DataStructures.IntegrityStatus.HONEST),
                    uint8(DataStructures.RewardPunishmentStatus.REWARD),
                    block.timestamp
                );
            } else {
                // 投票错误，不诚实，接受惩罚
                // Note: Removed integrity and rewardPunishment field access as they don't exist in UserStatus

                // 计算惩罚金额
                uint256 punishmentAmount = _calculateValidatorPunishment(
                    validator
                );

                // 记录个人惩罚
                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalPunishments[validator] = PersonalPunishment({
                    amount: punishmentAmount,
                    reason: "Incorrect validation",
                    executed: false
                });

                record.punishmentTargets.push(validator);
                record.totalPunishmentAmount += punishmentAmount;
                totalUserPunishments[validator] += punishmentAmount;

                emit Events.UserIntegrityStatusUpdated(
                    caseId,
                    validator,
                    uint8(DataStructures.IntegrityStatus.HONEST), // 假设之前状态
                    uint8(DataStructures.IntegrityStatus.DISHONEST),
                    uint8(DataStructures.RewardPunishmentStatus.PUNISHMENT),
                    block.timestamp
                );
            }

            // 更新验证者统计
            status.participationCount++;
            status.isActive = true;
            status.lastActiveTime = block.timestamp;
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
                // Note: Tracking integrity status through events instead of struct fields

                uint256 rewardAmount = _calculateChallengerReward(challenger);

                RewardPunishmentRecord storage record = caseRewards[caseId];
                record.personalRewards[challenger] = PersonalReward({
                    amount: rewardAmount,
                    reason: "Successful challenge",
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
                    executed: false
                });

                record.punishmentTargets.push(challenger);
                record.totalPunishmentAmount += punishmentAmount;
                totalUserPunishments[challenger] += punishmentAmount;
            }

            emit Events.UserIntegrityStatusUpdated(
                caseId,
                challenger,
                uint8(DataStructures.IntegrityStatus.HONEST), // 简化处理
                uint8(status.integrity),
                uint8(status.rewardPunishment),
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
     * @dev 验证者奖励算法 - 基础奖励 + 声誉加成
     * 设计原理：
     * 1. 基础奖励：0.01 ETH，保证所有正确参与者都有基本收益
     * 2. 声誉加成：声誉分数/1000 * 基础奖励，激励长期良好表现
     * 例如：声誉800分的验证者奖励 = 0.01 + (800/1000 * 0.01) = 0.018 ETH
     * @param validator 验证者地址
     * @return 计算得出的奖励金额
     */
    function _calculateValidatorReward(
        address validator
    ) internal view returns (uint256) {
        DataStructures.UserStatus storage status = userStatuses[validator];

        // 基础奖励：0.01 ETH
        // 设定原则：足以覆盖参与成本，激励用户积极参与
        uint256 baseReward = 0.01 ether;

        // 声誉加成算法：(声誉分数 / 1000) * 基础奖励
        // 设计目的：奖励历史表现良好的验证者，建立长期激励机制
        // 最高加成：满分1000分可获得100%加成（翻倍奖励）
        uint256 reputationBonus = (status.reputationScore * baseReward) / 1000;

        return baseReward + reputationBonus;
    }

    /**
     * @notice 计算验证者惩罚
     * @dev 验证者惩罚算法 - 固定基础惩罚
     * 设计原理：
     * 1. 固定惩罚0.005 ETH：惩罚金额约为基础奖励的50%
     * 2. 适度惩罚：既要有威慑作用，又不能过于严厉
     * 3. 不考虑声誉：避免对新用户过度惩罚，给予改正机会
     * @param validator 验证者地址（当前版本未使用，为未来扩展预留）
     * @return 固定的惩罚金额
     */
    function _calculateValidatorPunishment(
        address validator
    ) internal view returns (uint256) {
        // 基础惩罚：0.005 ETH
        // 惩罚/奖励比例 = 1:2，保证正确参与仍有净收益
        uint256 basePunishment = 0.005 ether;

        return basePunishment;
    }

    /**
     * @notice 计算质疑者奖励
     * @dev 质疑者奖励算法 - 高于验证者的固定奖励
     * 设计原理：
     * 1. 0.02 ETH奖励：是验证者基础奖励的2倍
     * 2. 高风险高回报：质疑需要承担更大风险，给予更高奖励
     * 3. 激励监督：鼓励用户对投票结果进行质疑和监督
     * @param challenger 质疑者地址（当前版本未使用，为未来扩展预留）
     * @return 固定的质疑者奖励金额
     */
    function _calculateChallengerReward(
        address challenger
    ) internal pure returns (uint256) {
        // 质疑者奖励：0.02 ETH
        // 设计逻辑：质疑行为风险更高，需要更仔细的分析和更大的勇气
        return 0.02 ether;
    }

    /**
     * @notice 计算质疑者惩罚
     * @dev 质疑者惩罚算法 - 适中的固定惩罚
     * 设计原理：
     * 1. 0.01 ETH惩罚：等于验证者基础奖励
     * 2. 平衡设计：既要防止恶意质疑，又要鼓励合理质疑
     * 3. 惩罚/奖励比例 = 1:2，保证成功质疑的净收益
     * @param challenger 质疑者地址（当前版本未使用，为未来扩展预留）
     * @return 固定的质疑者惩罚金额
     */
    function _calculateChallengerPunishment(
        address challenger
    ) internal pure returns (uint256) {
        // 失败质疑的惩罚：0.01 ETH
        // 惩罚理由：恶意或轻率的质疑会浪费系统资源
        return 0.01 ether;
    }

    /**
     * @notice 计算赔偿金额
     * @dev 投诉者赔偿算法 - 根据风险等级分级赔偿
     * 设计原理：
     * 1. 分级赔偿：高风险1 ETH，中风险0.5 ETH，低风险0.1 ETH
     * 2. 风险对应：赔偿金额与食品安全风险等级成正比
     * 3. 激励机制：鼓励用户举报高风险问题
     * @param riskLevel 案件风险等级
     * @return 根据风险等级计算的赔偿金额
     */
    function _calculateCompensation(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 1 ether; // 高风险：1 ETH，涉及严重健康威胁
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 0.5 ether; // 中风险：0.5 ETH，涉及一般健康问题
        } else {
            return 0.1 ether; // 低风险：0.1 ETH，涉及轻微问题
        }
    }

    /**
     * @notice 计算企业惩罚
     * @dev 企业惩罚算法 - 根据风险等级的严厉惩罚
     * 设计原理：
     * 1. 重罚机制：高风险5 ETH，中风险2 ETH，低风险0.5 ETH
     * 2. 威慑作用：企业惩罚远高于个人，体现企业责任
     * 3. 风险比例：企业惩罚是投诉者赔偿的5倍，确保违法成本
     * @param riskLevel 案件风险等级
     * @return 根据风险等级计算的企业惩罚金额
     */
    function _calculateEnterprisePenalty(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 5 ether; // 高风险：5 ETH，严重食品安全问题的重罚
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 2 ether; // 中风险：2 ETH，一般食品安全问题的惩罚
        } else {
            return 0.5 ether; // 低风险：0.5 ETH，轻微问题的处罚
        }
    }

    /**
     * @notice 计算虚假投诉惩罚
     * @dev 虚假投诉惩罚算法 - 根据声称风险等级的适度惩罚
     * 设计原理：
     * 1. 适度惩罚：防止恶意投诉，但不过分严厉
     * 2. 风险关联：声称的风险越高，虚假投诉的惩罚越重
     * 3. 比例合理：约为企业惩罚的10%，体现过错程度差异
     * @param riskLevel 投诉声称的风险等级
     * @return 根据声称风险等级计算的虚假投诉惩罚金额
     */
    function _calculateFalseComplaintPenalty(
        DataStructures.RiskLevel riskLevel
    ) internal pure returns (uint256) {
        if (riskLevel == DataStructures.RiskLevel.HIGH) {
            return 0.5 ether; // 虚假高风险投诉：0.5 ETH
        } else if (riskLevel == DataStructures.RiskLevel.MEDIUM) {
            return 0.2 ether; // 虚假中风险投诉：0.2 ETH
        } else {
            return 0.05 ether; // 虚假低风险投诉：0.05 ETH
        }
    }

    /**
     * @notice 计算声誉恢复补偿
     * @dev 企业声誉恢复补偿算法 - 固定的象征性补偿
     * 设计原理：
     * 1. 象征性补偿：0.05 ETH，主要起到声誉恢复的象征意义
     * 2. 公平原则：企业被错误指控时应得到一定补偿
     * 3. 适度金额：不会造成系统负担，但体现公正性
     * @return 固定的声誉恢复补偿金额
     */
    function _calculateReputationCompensation()
    internal
    pure
    returns (uint256)
    {
        // 声誉恢复补偿：0.05 ETH
        // 目的：对被错误指控企业的象征性补偿
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
