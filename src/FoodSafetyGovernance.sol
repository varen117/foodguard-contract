// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用最新稳定版本，支持优化和安全特性

// 导入系统基础库
import "./libraries/DataStructures.sol"; // 核心数据结构定义
import "./libraries/Errors.sol"; // 标准化错误处理
import "./libraries/Events.sol"; // 标准化事件定义

// 导入功能模块合约
import "./modules/FundManager.sol"; // 资金和保证金管理模块
import "./modules/VotingManager.sol"; // 投票和验证者管理模块
import "./modules/DisputeManager.sol"; // 质疑和争议处理模块
import "./modules/RewardPunishmentManager.sol"; // 奖惩计算和分配模块
import "./modules/ParticipantPoolManager.sol"; // 参与者池管理模块

// 导入OpenZeppelin安全组件
import "@openzeppelin/contracts/utils/Pausable.sol"; // 暂停功能，用于紧急情况
import "@openzeppelin/contracts/access/Ownable.sol"; // 所有权管理

/**
 * @title FoodSafetyGovernance
 * @author Food Safety Governance Team
 * @notice 食品安全治理主合约，整合投诉、验证、质疑、奖惩等完整流程
 * @dev 严格按照Mermaid流程图实现的去中心化食品安全治理系统
 *
 * 系统核心特性：
 * 1. 完整的案件生命周期管理：从投诉创建到最终完成的7个关键步骤
 * 2. 模块化架构：将不同功能分离到专门的模块合约中，提高可维护性
 * 3. 动态保证金系统：根据风险等级、用户声誉、并发案件数量动态调整保证金要求
 * 4. 多层验证机制：投票验证 + 质疑机制，确保决策的公正性和准确性
 * 5. 智能奖惩系统：根据参与表现和结果准确性进行奖励和惩罚分配
 * 6. 风险分级管理：高、中、低三级风险分类，差异化处理不同严重程度的问题
 * 7. 声誉激励机制：长期表现良好的用户享受更多权益和优惠
 *
 * 案件处理流程：
 * 步骤1：创建投诉 → 步骤2：锁定保证金 → 步骤3：开始投票 →
 * 步骤4：结束投票并开始质疑 → 步骤5：结束质疑并进入奖惩 →
 * 步骤6：处理奖惩 → 步骤7：完成案件
 */
contract FoodSafetyGovernance is Pausable, Ownable {
    // ==================== 状态变量 ====================

    /// @notice 案件计数器 - 系统中创建的案件总数，也用作新案件的唯一ID
    /// @dev 从0开始递增，确保每个案件都有唯一标识符
    uint256 public caseCounter;

    /// @notice 核心模块合约地址
    FundManager public fundManager;
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    RewardPunishmentManager public rewardManager;
    ParticipantPoolManager public poolManager;

    /// @notice 案件信息映射 - 存储所有案件的核心信息
    /// @dev 键值对：caseId => CaseInfo，提供案件的完整状态追踪
    mapping(uint256 => CaseInfo) public cases;

    /// @notice 企业风险等级映射（保留，用于案件风险评估）
    mapping(address => DataStructures.RiskLevel) public enterpriseRiskLevel;

    // ==================== 结构体定义 ====================

    /**
     * @notice 案件信息结构体
     */
    struct CaseInfo {
        uint256 caseId;
        address complainant;
        address enterprise;
        string complaintTitle;
        string complaintDescription;
        string location;
        uint256 incidentTime;
        uint256 complaintTime;
        DataStructures.CaseStatus status;
        DataStructures.RiskLevel riskLevel;
        bool complaintUpheld;
        uint256 complainantDeposit;
        uint256 enterpriseDeposit;
        string complainantEvidenceHash;
        bool isCompleted;
        uint256 completionTime;
    }

    // ==================== 修饰符 ====================
    /**
     * @notice 检查案件是否存在
     */
    modifier caseExists(uint256 caseId) {
        if (cases[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    /**
     * @notice 检查案件状态
     */
    modifier inStatus(
        uint256 caseId,
        DataStructures.CaseStatus requiredStatus
    ) {
        if (cases[caseId].status != requiredStatus) {
            revert Errors.InvalidCaseStatus(
                caseId,
                uint8(cases[caseId].status),
                uint8(requiredStatus)
            );
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address initialOwner) Ownable(initialOwner) {
        caseCounter = 0;
    }

    // ==================== 初始化函数 ====================

    /**
     * @notice 初始化模块合约地址
     * @param _fundManager 资金管理合约地址
     * @param _votingManager 投票管理合约地址
     * @param _disputeManager 质疑管理合约地址
     * @param _rewardManager 奖惩管理合约地址
     * @param _poolManager 参与者池管理合约地址
     */
    function initializeContracts(
        address payable _fundManager,
        address _votingManager,
        address _disputeManager,
        address _rewardManager,
        address _poolManager
    ) external onlyOwner {
        if (
            _fundManager == address(0) ||
            _votingManager == address(0) ||
            _disputeManager == address(0) ||
            _rewardManager == address(0) ||
            _poolManager == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        fundManager = FundManager(_fundManager);
        votingManager = VotingManager(_votingManager);
        disputeManager = DisputeManager(_disputeManager);
        rewardManager = RewardPunishmentManager(_rewardManager);
        poolManager = ParticipantPoolManager(_poolManager);

        // 注意：各模块的治理合约地址应该在调用此函数之前由管理员设置
    }

    // ==================== 核心流程函数 ====================

    /**
     * @notice 步骤1: 创建投诉 - 启动食品安全治理流程的入口函数
     * @dev 完整的投诉创建流程，包含严格的参数验证和自动化后续步骤
     * 功能流程：
     * 1. 验证所有输入参数的有效性和合规性
     * 2. 检查投诉者和企业的保证金充足性（基于动态保证金系统）
     * 3. 创建新案件并记录基本信息
     * 4. 自动触发保证金锁定流程
     * 5. 自动启动投票流程
     *
     * 安全机制：
     * - 防止自我投诉：用户不能投诉自己
     * - 注册验证：只有注册用户可以创建投诉
     * - 企业验证：被投诉方必须是已注册企业
     * - 保证金检查：确保双方都有足够保证金参与案件
     * - 证据要求：必须提供至少一个证据哈希
     * - 时间验证：事发时间不能晚于当前时间
     *
     * @param enterprise 被投诉的企业地址（必须是已注册企业）
     * @param complaintTitle 投诉标题（不能为空）
     * @param complaintDescription 投诉详细描述（不能为空）
     * @param location 事发地点（食品安全问题发生的具体位置）
     * @param incidentTime 事发时间（Unix时间戳，不能晚于当前时间）
     * @param evidenceHash IPFS证据哈希（证据材料的存储位置）
     * @param riskLevel 风险等级（0=LOW, 1=MEDIUM, 2=HIGH）
     * @return caseId 新创建案件的唯一ID
     */
    function createComplaint(
        address enterprise,
        string calldata complaintTitle,
        string calldata complaintDescription,
        string calldata location,
        uint256 incidentTime,
        string calldata evidenceHash,
        uint8 riskLevel
    )
    external
    payable
    whenNotPaused
    returns (uint256 caseId)
    {
        // 验证输入参数
        if (enterprise == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (!poolManager.isEnterpriseRegistered(enterprise)) {
            revert Errors.EnterpriseNotRegistered(enterprise);
        }

        if (msg.sender == enterprise) {
            revert Errors.CannotComplainAgainstSelf(msg.sender, enterprise);
        }

        // 验证投诉者角色权限
        (bool complainantRegistered, DataStructures.UserRole complainantRole, bool complainantActive,) = poolManager.getUserInfo(msg.sender);
        if (!complainantRegistered || !complainantActive || complainantRole != DataStructures.UserRole.COMPLAINANT) {
            revert Errors.InvalidUserRole(
                msg.sender,
                uint8(complainantRole),
                uint8(DataStructures.UserRole.COMPLAINANT)
            );
        }

        // 验证企业角色权限
        (bool enterpriseRegistered, DataStructures.UserRole enterpriseRole, bool enterpriseActive,) = poolManager.getUserInfo(enterprise);
        if (!enterpriseRegistered || !enterpriseActive || enterpriseRole != DataStructures.UserRole.ENTERPRISE) {
            revert Errors.InvalidUserRole(
                enterprise,
                uint8(enterpriseRole),
                uint8(DataStructures.UserRole.ENTERPRISE)
            );
        }

        if (
            bytes(complaintTitle).length == 0 ||
            bytes(complaintDescription).length == 0
        ) {
            revert Errors.EmptyComplaintContent();
        }

        if (incidentTime > block.timestamp) {
            revert Errors.InvalidTimestamp(incidentTime, block.timestamp);
        }

        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }

        if (riskLevel > uint8(DataStructures.RiskLevel.HIGH)) {
            revert Errors.InvalidRiskLevel(riskLevel);
        }

        // 用户发送了额外的ETH，存入保证金
        if (msg.value > 0) {
            fundManager.registerUserDeposit{value: msg.value}(
                msg.sender,
                msg.value
            );
        }

        DataStructures.RiskLevel riskLevelEnum = DataStructures.RiskLevel(riskLevel);

        // 检查用户是否可以参与新案件（基于动态保证金系统）
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        if (!fundManager.canParticipateInCase(msg.sender, riskLevelEnum, config.minComplaintDeposit)) {
            revert Errors.InsufficientDynamicDeposit(
                msg.sender,
                config.minComplaintDeposit,
                fundManager.getAvailableDeposit(msg.sender)
            );
        }

        // 检查企业是否可以参与新案件
        if (!fundManager.canParticipateInCase(enterprise, riskLevelEnum, config.minEnterpriseDeposit)) {
            revert Errors.InsufficientDynamicDeposit(
                enterprise,
                config.minEnterpriseDeposit,
                fundManager.getAvailableDeposit(enterprise)
            );
        }

        // 创建新案件
        caseId = ++caseCounter;

        // 创建案件信息
        CaseInfo storage newCase = cases[caseId];
        newCase.caseId = caseId;
        newCase.complainant = msg.sender;
        newCase.enterprise = enterprise;
        newCase.complaintTitle = complaintTitle;
        newCase.complaintDescription = complaintDescription;
        newCase.location = location;
        newCase.incidentTime = incidentTime;
        newCase.complaintTime = block.timestamp;
        newCase.status = DataStructures.CaseStatus.PENDING;
        newCase.riskLevel = riskLevelEnum;
        newCase.complainantDeposit = 0; // 将在锁定时确定
        newCase.complainantEvidenceHash = evidenceHash; // 存储投诉者证据哈希
        newCase.isCompleted = false;

        emit Events.ComplaintCreated(
            caseId,
            msg.sender,
            enterprise,
            complaintTitle,
            riskLevelEnum,
            block.timestamp
        );

        // 立即进入下一步骤：锁定保证金
        _lockDeposits(caseId);

        return caseId;
    }

    /**
     * @notice 步骤2: 锁定保证金（使用智能动态冻结）
     * @dev 智能保证金锁定机制，实现动态风险管理
     * 锁定流程：
     * 1. 根据案件风险等级和用户状态动态计算所需保证金
     * 2. 使用智能冻结算法，在保证金不足时尝试互助池支持
     * 3. 记录实际冻结金额，可能低于理想金额但仍允许案件进行
     * 4. 更新案件状态为DEPOSIT_LOCKED
     * 5. 高风险案件触发特殊监控事件
     * 6. 自动启动投票流程
     *
     * 智能冻结特性：
     * - 动态计算：基于风险等级、用户声誉、并发案件数量
     * - 互助池支持：保证金不足时自动尝试使用互助池资金
     * - 部分冻结：即使保证金不足也允许参与，但影响用户状态
     * - 风险监控：高风险案件获得特殊关注和快速处理
     *
     * @param caseId 案件ID
     */
    function _lockDeposits(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();

        // 步骤1：冻结投诉者保证金
        // 冻结考虑用户的风险等级、声誉分数、并发案件等因素
        fundManager.freezeDeposit(
            caseId,
            caseInfo.complainant,
            caseInfo.riskLevel,
            config.minComplaintDeposit
        );

        // 记录实际冻结的投诉者保证金
        caseInfo.complainantDeposit = fundManager.getCaseFrozenDeposit(caseId, caseInfo.complainant);

        // 步骤2：冻结企业保证金
        // 企业通常需要更高的保证金，体现更大的责任
        fundManager.freezeDeposit(
            caseId,
            caseInfo.enterprise,
            caseInfo.riskLevel,
            config.minEnterpriseDeposit
        );

        // 记录实际冻结的企业保证金
        caseInfo.enterpriseDeposit = fundManager.getCaseFrozenDeposit(caseId, caseInfo.enterprise);

        // 步骤3：更新案件状态为保证金已锁定
        caseInfo.status = DataStructures.CaseStatus.DEPOSIT_LOCKED;

        // 发出状态更新事件，记录状态变迁
        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.PENDING,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            block.timestamp
        );

        // 步骤5：自动启动投票流程
        // 保证金锁定成功后立即进入投票阶段，提高处理效率
        _startVoting(caseId);
    }

    /**
     * @notice 步骤3: 开始投票 - 随机选择验证者并启动投票流程
     * @dev 使用ParticipantPoolManager随机选择验证者，确保公平性和随机性
     * 流程：
     * 1. 验证投诉者和企业的角色权限
     * 2. 使用ParticipantPoolManager随机选择验证者（奇数个）
     * 3. 将选中的验证者传递给VotingManager开始投票
     * 4. 更新案件状态为VOTING
     *
     * 选择规则：
     * - 验证者必须是DAO_MEMBER角色
     * - 验证者不能是投诉者或被投诉企业
     * - 验证者不能已经参与此案件
     * - 验证者数量必须为奇数（避免平票）
     *
     * @param caseId 案件ID
     */
    function _startVoting(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();

        // 验证投诉者角色权限
        if (!poolManager.canParticipateInCase(caseId, caseInfo.complainant, DataStructures.UserRole.COMPLAINANT)) {
            revert Errors.InvalidUserRole(
                caseInfo.complainant,
                uint8(DataStructures.UserRole.COMPLAINANT),
                uint8(DataStructures.UserRole.COMPLAINANT)
            );
        }

        // 验证企业角色权限
        if (!poolManager.canParticipateInCase(caseId, caseInfo.enterprise, DataStructures.UserRole.ENTERPRISE)) {
            revert Errors.InvalidUserRole(
                caseInfo.enterprise,
                uint8(DataStructures.UserRole.ENTERPRISE),
                uint8(DataStructures.UserRole.ENTERPRISE)
            );
        }

        // 确定验证者数量（基于风险等级动态调整）
        uint256 validatorCount = config.minValidators;
        if (caseInfo.riskLevel == DataStructures.RiskLevel.HIGH) {
            validatorCount = config.maxValidators > 7 ? 7 : config.maxValidators; // 高风险案件更多验证者
        } else if (caseInfo.riskLevel == DataStructures.RiskLevel.MEDIUM) {
            validatorCount = config.minValidators + 2; // 中风险案件适中验证者
        }

        // 确保验证者数量为奇数
        if (validatorCount % 2 == 0) {
            validatorCount += 1;
        }

        // 使用ParticipantPoolManager随机选择验证者
        address[] memory selectedValidators = poolManager.selectValidators(caseId, validatorCount);

        // 将选中的验证者传递给VotingManager开始投票
        votingManager.startVotingSessionWithValidators(
            caseId,
            selectedValidators,
            config.votingPeriod
        );

        // 更新案件状态
        caseInfo.status = DataStructures.CaseStatus.VOTING;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            DataStructures.CaseStatus.VOTING,
            block.timestamp
        );

        // 发出验证者选择事件
        emit Events.ValidatorsSelected(caseId, selectedValidators, block.timestamp);
    }


    /**
     * @notice 步骤4: 结束投票并开始质疑期
     * @param caseId 案件ID
     */
    function endVotingAndStartChallenge(
        uint256 caseId
    )
    external
    whenNotPaused
    caseExists(caseId)
    inStatus(caseId, DataStructures.CaseStatus.VOTING)
    {
        // 结束验证阶段并获取投票结果
        (bool complaintUpheld, , ) = votingManager.endVotingSession(caseId);

        CaseInfo storage caseInfo = cases[caseId];
        caseInfo.complaintUpheld = complaintUpheld; // 记录投票结果

        // 开启质疑阶段
        caseInfo.status = DataStructures.CaseStatus.CHALLENGING;

        // 开始质疑期
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        disputeManager.startDisputeSession(caseId, config.challengePeriod);

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.VOTING,
            DataStructures.CaseStatus.CHALLENGING,
            block.timestamp
        );
    }

    /**
     * @notice 步骤5: 结束质疑期并进入奖惩阶段
     * @param caseId 案件ID
     */
    function endChallengeAndProcessRewards(
        uint256 caseId
    )
    external
    whenNotPaused
    caseExists(caseId)
    inStatus(caseId, DataStructures.CaseStatus.CHALLENGING)
    {
        CaseInfo storage caseInfo = cases[caseId];

        // 结束质疑期并获取质疑者详细信息
        (bool finalResult, , , ) = disputeManager.endDisputeSession(caseId);

        // 更新最终结果
        caseInfo.complaintUpheld = finalResult;
        caseInfo.status = DataStructures.CaseStatus.REWARD_PUNISHMENT;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.CHALLENGING,
            DataStructures.CaseStatus.REWARD_PUNISHMENT,
            block.timestamp
        );

        // 处理奖惩
        _processRewardsPunishments(caseId);
    }

    /**
     * @notice 步骤6: 处理奖惩 - 根据案件结果计算和分配奖惩
     * @dev 复杂的奖惩处理流程，整合投票和质疑结果进行公平分配
     * 处理流程：
     * 1. 收集所有验证者的投票信息和选择
     * 2. 收集所有质疑者的质疑信息和结果
     * 3. 调用奖惩管理器进行复杂的奖惩计算
     * 4. 自动完成案件处理
     *
     * 奖惩分配原则：
     * - 验证者：投票正确获得奖励，错误承担惩罚
     * - 质疑者：成功质疑获得奖励，失败质疑承担惩罚
     * - 投诉者：投诉成立获得赔偿，虚假投诉承担惩罚
     * - 企业：败诉承担重罚，胜诉获得声誉恢复补偿
     *
     * @param caseId 案件ID
     */
    function _processRewardsPunishments(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];

        // 步骤1：获取投票结果信息
        DataStructures.VotingSession votingSession = votingManager.getVotingSessionInfo(caseId);

        // 步骤2：构建验证者投票选择数组
        DataStructures.VoteChoice[] memory validatorChoices = new DataStructures.VoteChoice[](votingSession.validators.length);
        for (uint256 i = 0; i < validators.length; i++) {
            DataStructures.VoteInfo memory vote = votingManager.getValidatorVote(caseId, validators[i]);
            if (vote.hasVoted) {
                validatorChoices[i] = vote.choice;
            } else {
                // 未投票视为反对投诉
                validatorChoices[i] = DataStructures.VoteChoice.REJECT_COMPLAINT;
            }
        }

        // 步骤3：获取质疑者信息
        DataStructures.ChallengeInfo[] memory challenges = disputeManager.getAllChallenges(caseId);
        address[] memory challengers = new address[](challenges.length);
        bool[] memory challengeResults = new bool[](challenges.length);

        // 获取质疑会话信息以确定结果是否改变
        (
            uint256 caseIdDispute,
            bool disputeIsActive,
            bool disputeIsCompleted,
            uint256 disputeStartTime,
            uint256 disputeEndTime,
            uint256 totalChallenges,
            bool resultChanged
        ) = disputeManager.getDisputeSessionInfo(caseId);

        // 步骤4：分析质疑结果
        for (uint256 i = 0; i < challenges.length; i++) {
            challengers[i] = challenges[i].challenger;

            // 判断质疑是否成功
            if (resultChanged) {
                // 如果结果改变了，说明反对验证者的质疑成功
                challengeResults[i] = (challenges[i].choice == DataStructures.ChallengeChoice.OPPOSE_VALIDATOR);
            } else {
                // 如果结果没改变，说明支持验证者的质疑成功
                challengeResults[i] = (challenges[i].choice == DataStructures.ChallengeChoice.SUPPORT_VALIDATOR);
            }
        }

        // 步骤5：调用奖惩管理器进行综合计算
        rewardManager.processCaseRewardPunishment(
            caseId,
            caseInfo.complaintUpheld, // 最终的案件结果
            caseInfo.riskLevel, // 风险等级影响奖惩金额
            caseInfo.complainant, // 投诉者
            caseInfo.enterprise, // 被投诉企业
            validators, // 参与投票的验证者列表
            validatorChoices, // 验证者的投票选择
            challengers, // 参与质疑的质疑者列表
            challengeResults // 质疑者的成功/失败结果
        );

        // 步骤6：完成案件处理
        _completeCase(caseId);
    }

    /**
     * @notice 步骤7: 完成案件
     * @param caseId 案件ID
     */
    function _completeCase(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];

        caseInfo.status = DataStructures.CaseStatus.COMPLETED;
        caseInfo.isCompleted = true;
        caseInfo.completionTime = block.timestamp;

        // 解冻剩余保证金
        fundManager.unfreezeDeposit(caseId, caseInfo.complainant);
        fundManager.unfreezeDeposit(caseId, caseInfo.enterprise);

        emit Events.CaseCompleted(
            caseId,
            caseInfo.complaintUpheld,
            0, // 总奖励金额 - 需要从奖惩管理器获取
            0, // 总惩罚金额 - 需要从奖惩管理器获取
            "Case processing completed",
            block.timestamp
        );

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.REWARD_PUNISHMENT,
            DataStructures.CaseStatus.COMPLETED,
            address(this),
            block.timestamp
        );
    }

    // ==================== 辅助函数 ====================

    /**
     * @notice 获取受影响的用户列表
     */
    function _getAffectedUsers(
        uint256 caseId
    ) internal view returns (address[] memory) {
        CaseInfo storage caseInfo = cases[caseId];
        address[] memory affected = new address[](2);
        affected[0] = caseInfo.complainant;
        affected[1] = caseInfo.enterprise;
        return affected;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取案件信息
     */
    function getCaseInfo(
        uint256 caseId
    ) external view returns (CaseInfo memory) {
        return cases[caseId];
    }

    /**
     * @notice 获取案件总数
     */
    function getTotalCases() external view returns (uint256) {
        return caseCounter;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 暂停/恢复合约
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }

    }

    /**
     * @notice 更新企业风险等级
     */
    function updateEnterpriseRiskLevel(
        address enterprise,
        DataStructures.RiskLevel newLevel
    ) external onlyOwner {
        if (!poolManager.isEnterpriseRegistered(enterprise)) {
            revert Errors.EnterpriseNotRegistered(enterprise);
        }

        enterpriseRiskLevel[enterprise] = newLevel;

        emit Events.RiskWarningPublished(
            enterprise,
            newLevel,
            "Risk level updated by admin",
            0,
            block.timestamp
        );
    }

    /**
     * @notice 紧急取消案件
     */
    function emergencyCancelCase(
        uint256 caseId,
        string calldata reason
    ) external onlyOwner caseExists(caseId) {
        CaseInfo storage caseInfo = cases[caseId];

        if (caseInfo.isCompleted) {
            revert Errors.CaseAlreadyCompleted(caseId);
        }

        caseInfo.status = DataStructures.CaseStatus.CANCELLED;
        caseInfo.isCompleted = true;
        caseInfo.completionTime = block.timestamp;

        // 解冻保证金
        fundManager.unfreezeDeposit(caseId, caseInfo.complainant);
        fundManager.unfreezeDeposit(caseId, caseInfo.enterprise);

        emit Events.CaseCancelled(caseId, reason, msg.sender, block.timestamp);
    }
}
