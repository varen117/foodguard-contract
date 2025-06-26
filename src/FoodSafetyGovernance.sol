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

    /// @notice 模块合约地址 - 治理系统的四大核心模块
    /// @dev 模块化设计使系统更易维护和升级
    FundManager public fundManager; // 资金管理模块：处理保证金、奖励池、动态保证金
    VotingManager public votingManager; // 投票管理模块：管理验证者选择和投票过程
    DisputeManager public disputeManager; // 质疑管理模块：处理投票结果的质疑和争议
    RewardPunishmentManager public rewardManager; // 奖惩管理模块：计算和分配奖励惩罚

    /// @notice 案件信息映射 - 存储所有案件的核心信息
    /// @dev 键值对：caseId => CaseInfo，提供案件的完整状态追踪
    mapping(uint256 => CaseInfo) public cases;

    /// @notice 普通用户注册状态 - 记录普通用户的注册状态
    /// @dev 键值对：user => isRegistered，控制用户参与权限
    mapping(address => bool) public isUserRegistered;

    /// @notice 企业注册状态 - 记录企业的注册状态
    /// @dev 键值对：enterprise => isRegistered，企业需要更高保证金
    mapping(address => bool) public isEnterpriseRegistered;

    /// @notice DAO组织注册状态 - 记录DAO成员的注册状态
    /// @dev 键值对：dao => isRegistered，DAO成员可参与验证和质疑
    mapping(address => bool) public isDaoRegistered;

    /// @notice 用户类型映射 - 区分普通用户和企业用户
    /// @dev 键值对：user => isEnterprise，影响保证金要求和权限
    mapping(address => bool) public isEnterprise;

    /// @notice 风险等级评估映射 - 记录企业的风险等级评估
    /// @dev 键值对：enterprise => riskLevel，影响相关案件的保证金和处理优先级
    mapping(address => DataStructures.RiskLevel) public enterpriseRiskLevel;

    // ==================== 结构体定义 ====================

    /**
     * @notice 案件信息结构体（主要状态信息）
     */
    struct CaseInfo {
        uint256 caseId; // 案件ID
        address complainant; // 投诉者
        address enterprise; // 被投诉企业
        string complaintTitle; // 投诉标题
        string complaintDescription; // 投诉描述
        string location; // 事发地点
        uint256 incidentTime; // 事发时间
        uint256 complaintTime; // 投诉时间
        DataStructures.CaseStatus status; // 案件状态
        DataStructures.RiskLevel riskLevel; // 风险等级
        bool complaintUpheld; // 投诉是否成立
        uint256 complainantDeposit; // 投诉者保证金
        uint256 enterpriseDeposit; // 企业保证金
        string complainantEvidenceHash; // 投诉者证据哈希
        bool isCompleted; // 是否已完成
        uint256 completionTime; // 完成时间
    }

    // ==================== 修饰符 ====================
    /**
     * @notice 检查用户是否已注册
     */
    modifier onlyRegisteredUser() {
        if (!isUserRegistered[msg.sender]) {
            revert Errors.InsufficientPermission(msg.sender, "REGISTERED_USER");
        }
        _;
    }

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
     */
    function initializeContracts(
        address payable _fundManager,
        address _votingManager,
        address _disputeManager,
        address _rewardManager
    ) external onlyOwner {
        if (
            _fundManager == address(0) ||
            _votingManager == address(0) ||
            _disputeManager == address(0) ||
            _rewardManager == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        fundManager = FundManager(_fundManager);
        votingManager = VotingManager(_votingManager);
        disputeManager = DisputeManager(_disputeManager);
        rewardManager = RewardPunishmentManager(_rewardManager);

        // 注意：各模块的治理合约地址应该在调用此函数之前由管理员设置
    }

    // ==================== 用户注册函数 ====================

    /**
     * @notice 注册普通用户
     */
    function registerUser() external payable whenNotPaused {
        if (isUserRegistered[msg.sender]) {
            revert Errors.DuplicateOperation(msg.sender, "Registered");
        }

        // 要求最小保证金
        DataStructures.SystemConfig memory config = fundManager
            .getSystemConfig();
        if (msg.value < config.minComplaintDeposit) {
            revert Errors.InsufficientComplaintDeposit(
                msg.value,
                config.minComplaintDeposit
            );
        }

        isUserRegistered[msg.sender] = true;
        isEnterprise[msg.sender] = false;

        // 在资金管理合约中注册用户保证金
        fundManager.registerUserDeposit{value: msg.value}(
            msg.sender,
            msg.value
        );

        emit Events.UserRegistered(
            msg.sender,
            false,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @notice 注册企业用户
     */
    function registerEnterprise() external payable whenNotPaused {
        if (isEnterpriseRegistered[msg.sender]) {
            revert Errors.DuplicateOperation(msg.sender, "Registered");
        }

        // 企业需要更高的保证金
        DataStructures.SystemConfig memory config = fundManager
            .getSystemConfig();
        if (msg.value < config.minEnterpriseDeposit) {
            revert Errors.InsufficientEnterpriseDeposit(
                msg.value,
                config.minEnterpriseDeposit
            );
        }

        isUserRegistered[msg.sender] = true;
        isEnterprise[msg.sender] = true;
        isEnterpriseRegistered[msg.sender] = true;
        enterpriseRiskLevel[msg.sender] = DataStructures.RiskLevel.LOW; // 默认低风险

        // 在资金管理合约中注册企业保证金
        fundManager.registerUserDeposit{value: msg.value}(
            msg.sender,
            msg.value
        );

        emit Events.UserRegistered(
            msg.sender,
            true,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @notice 注册DAO成员
     */
    function registerDaoMember() external payable whenNotPaused {
        if (isUserRegistered[msg.sender]) {
            revert Errors.DuplicateOperation(msg.sender, "Registered");
        }
        DataStructures.SystemConfig memory config = fundManager
            .getSystemConfig();
        if (msg.value < config.minDaoDeposit) {
            revert Errors.InsufficientValidatorDeposit(
                msg.value,
                config.minDaoDeposit
            );
        }

        isUserRegistered[msg.sender] = true;
        isEnterprise[msg.sender] = false;

        // 在资金管理合约中注册DAO保证金
        fundManager.registerUserDeposit{value: msg.value}(
            msg.sender,
            msg.value
        );

        emit Events.UserRegistered(
            msg.sender,
            false,
            msg.value,
            block.timestamp
        );
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
    onlyRegisteredUser
    returns (uint256 caseId)
    {
        // 验证输入参数
        if (enterprise == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (!isEnterpriseRegistered[enterprise]) {
            revert Errors.EnterpriseNotRegistered(enterprise);
        }

        if (msg.sender == enterprise) {
            revert Errors.CannotComplainAgainstSelf(msg.sender, enterprise);
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
            address(this),
            block.timestamp
        );

        // 步骤4：高风险案件特殊处理
        // 高风险案件需要更多关注和更快的处理速度
        if (caseInfo.riskLevel == DataStructures.RiskLevel.HIGH) {
            emit Events.HighRiskCaseProcessed(
                caseId,
                caseInfo.complainantDeposit + caseInfo.enterpriseDeposit, // 总锁定金额
                _getAffectedUsers(caseId), // 受影响的用户列表
                block.timestamp
            );
        }

        // 步骤5：自动启动投票流程
        // 保证金锁定成功后立即进入投票阶段，提高处理效率
        _startVoting(caseId);
    }

    /**
     * @notice 步骤3: 开始投票
     * @param caseId 案件ID
     */
    function _startVoting(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager
            .getSystemConfig();

        // 随机选择验证者并开始投票
        votingManager.startVotingSession(
            caseId,
            config.votingPeriod,
            config.minValidators
        );

        // 更新案件状态
        caseInfo.status = DataStructures.CaseStatus.VOTING;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            DataStructures.CaseStatus.VOTING,
            address(this),
            block.timestamp
        );
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
        // 结束验证阶段
        votingManager.endVotingSession(caseId);

        CaseInfo storage caseInfo = cases[caseId];
        //todo 质疑完成后执行这些状态改变
//        caseInfo.complaintUpheld = votingResult;
        // 计算投票结果：支持票数大于反对票数则投诉成立
//        complaintUpheld = session.supportVotes > session.rejectVotes;
//        session.complaintUpheld = complaintUpheld; // 记录最终结果
//        validators[validator].successfulValidations++;
        // 开启质疑阶段
        caseInfo.status = DataStructures.CaseStatus.CHALLENGING;

        // 开始质疑期
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        disputeManager.startDisputeSession(caseId, config.challengePeriod);

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.VOTING,
            DataStructures.CaseStatus.CHALLENGING,
            msg.sender,
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

        // 结束质疑期
        (bool finalResult, ) = disputeManager
            .endDisputeSession(caseId, caseInfo.complaintUpheld);

        // 更新最终结果
        caseInfo.complaintUpheld = finalResult;
        caseInfo.status = DataStructures.CaseStatus.REWARD_PUNISHMENT;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.CHALLENGING,
            DataStructures.CaseStatus.REWARD_PUNISHMENT,
            msg.sender,
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
     * 3. 分析质疑是否成功改变了投票结果
     * 4. 调用奖惩管理器进行复杂的奖惩计算
     * 5. 自动完成案件处理
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

        // 步骤1：获取投票信息
        // 从投票管理器获取所有参与投票的验证者地址
        (, address[] memory validators, , , , , , , ,) = votingManager
            .getVotingSessionInfo(caseId);

        // 步骤2：构建验证者投票选择数组
        // 收集每个验证者的具体投票选择，用于奖惩计算
        DataStructures.VoteChoice[]
        memory validatorChoices = new DataStructures.VoteChoice[](
            validators.length
        );
        for (uint256 i = 0; i < validators.length; i++) {
            DataStructures.VoteInfo memory vote = votingManager
                .getValidatorVote(caseId, validators[i]);
            validatorChoices[i] = vote.choice; // SUPPORT_COMPLAINT 或 REJECT_COMPLAINT
        }

        // 步骤3：获取质疑者信息
        // 从质疑管理器获取所有质疑信息
        DataStructures.ChallengeInfo[] memory challenges = disputeManager
            .getAllChallenges(caseId);
        address[] memory challengers = new address[](challenges.length);
        bool[] memory challengeResults = new bool[](challenges.length);

        // 步骤4：分析质疑结果
        for (uint256 i = 0; i < challenges.length; i++) {
            challengers[i] = challenges[i].challenger;
            // 质疑成功判断逻辑：
            // 如果质疑者选择OPPOSE_VALIDATOR且最终结果与投票结果不同，则质疑成功
            challengeResults[i] =
                (challenges[i].choice ==
                    DataStructures.ChallengeChoice.OPPOSE_VALIDATOR) ==
                (!caseInfo.complaintUpheld); // 如果反对验证者且结果确实改变了
        }

        // 步骤5：调用奖惩管理器进行综合计算
        // 将所有参与者信息和结果传递给专门的奖惩管理器
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
        // 奖惩分配完成后，案件进入最终完成阶段
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

    /**
     * @notice 检查用户是否为企业
     */
    function checkIsEnterprise(address user) external view returns (bool) {
        return isEnterprise[user];
    }

    /**
     * @notice 获取企业风险等级
     */
    function getEnterpriseRiskLevel(
        address enterprise
    ) external view returns (DataStructures.RiskLevel) {
        return enterpriseRiskLevel[enterprise];
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
        if (!isEnterpriseRegistered[enterprise]) {
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
