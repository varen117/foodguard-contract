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
        address[] complainantRewardRecipients; // 获得补偿的投诉用户列表
        address[] complainantPunishmentTargets; // 获得惩罚的投诉用户列表
        address[] enterpriseRewardRecipients; // 获得奖励的企业用户列表
        address[] enterprisePunishmentTargets; // 获得惩罚的企业用户列表
        address[] daoRewardRecipients; // 获得奖励的dao用户列表
        address[] daoRewardPunishmentTargets;//获得惩罚的dao用户列表
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
     */
    function processCaseRewardPunishment(
        uint256 caseId,
        address[] memory complainantRewards,
        address[] memory enterpriseRewards,
        address[] memory daoRewards,
        address[] memory complainantPunishments,
        address[] memory enterprisePunishments,
        address[] memory daoPunishments,
        bool complaintUpheld,
        DataStructures.RiskLevel riskLevel
    ) external onlyGovernance caseNotProcessed(caseId) {
        RewardPunishmentRecord storage record = caseRewards[caseId];
        if (record.isProcessed) {
            revert Errors.RewardPunishmentAlreadyProcessed(caseId);
        }
        if (complainantRewards.length == 0 &&
        enterpriseRewards.length == 0 &&
        daoRewards.length == 0 &&
        complainantPunishments.length == 0 &&
        enterprisePunishments.length == 0 &&
            daoPunishments.length == 0) {
            revert Errors.NoRewardOrPunishmentMembers("No Reward or Punishment Members");
        }

        // 检查重复地址
        _validateNoDuplicateAddresses(
            complainantRewards, enterpriseRewards, daoRewards,
            complainantPunishments, enterprisePunishments, daoPunishments
        );

        // 创建奖惩记录
        record.caseId = caseId;
        record.complainantRewardRecipients = complainantRewards;
        record.complainantPunishmentTargets = complainantPunishments;
        record.enterpriseRewardRecipients = enterpriseRewards;
        record.enterprisePunishmentTargets = enterprisePunishments;
        record.daoRewardRecipients = daoRewards;
        record.daoRewardPunishmentTargets = daoPunishments;
        // 投诉是否成立
        record.complaintUpheld = complaintUpheld;
        // 风险等级
        record.riskLevel = riskLevel;
        //处理时间
        record.processTime = block.timestamp;
        record.isProcessed = false;

        // 计算总奖励金额和总惩罚金额




        emit Events.RewardPunishmentCalculationStarted(
            caseId,
            complaintUpheld,
            block.timestamp
        );




        // 标记案件已处理
        caseProcessed[caseId] = true;
        record.isProcessed = true;
    }

    /**
     * @notice 验证地址数组中是否有重复地址
     */
    function _validateNoDuplicateAddresses(
        address[] memory complainantRewards,
        address[] memory enterpriseRewards,
        address[] memory daoRewards,
        address[] memory complainantPunishments,
        address[] memory enterprisePunishments,
        address[] memory daoPunishments
    ) internal pure {
        // 检查各个数组内部是否有重复
        _checkArrayDuplicates(complainantRewards, "complainant rewards");
        _checkArrayDuplicates(enterpriseRewards, "enterprise rewards");
        _checkArrayDuplicates(daoRewards, "dao rewards");
        _checkArrayDuplicates(complainantPunishments, "complainant punishments");
        _checkArrayDuplicates(enterprisePunishments, "enterprise punishments");
        _checkArrayDuplicates(daoPunishments, "dao punishments");
        
        // 检查跨数组的重复
        _checkCrossArrayDuplicates(
            complainantRewards, enterpriseRewards, daoRewards,
            complainantPunishments, enterprisePunishments, daoPunishments
        );
    }
    
    /**
     * @notice 检查单个数组内是否有重复地址
     */
    function _checkArrayDuplicates(address[] memory addresses, string memory arrayName) internal pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                if (addresses[i] == addresses[j] && addresses[i] != address(0)) {
                    revert Errors.DuplicateOperation(addresses[i], arrayName);
                }
            }
        }
    }
    
    /**
     * @notice 检查跨数组的重复地址
     */
    function _checkCrossArrayDuplicates(
        address[] memory complainantRewards,
        address[] memory enterpriseRewards,
        address[] memory daoRewards,
        address[] memory complainantPunishments,
        address[] memory enterprisePunishments,
        address[] memory daoPunishments
    ) internal pure {
        address[][] memory allArrays = new address[][](6);
        allArrays[0] = complainantRewards;
        allArrays[1] = enterpriseRewards;
        allArrays[2] = daoRewards;
        allArrays[3] = complainantPunishments;
        allArrays[4] = enterprisePunishments;
        allArrays[5] = daoPunishments;
        
        for (uint256 i = 0; i < allArrays.length; i++) {
            for (uint256 j = i + 1; j < allArrays.length; j++) {
                for (uint256 k = 0; k < allArrays[i].length; k++) {
                    for (uint256 l = 0; l < allArrays[j].length; l++) {
                        if (allArrays[i][k] == allArrays[j][l] && allArrays[i][k] != address(0)) {
                            revert Errors.DuplicateOperation(allArrays[i][k], "cross-array duplicate");
                        }
                    }
                }
            }
        }
    }

    // ==================== 奖惩计算辅助函数 ====================

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
