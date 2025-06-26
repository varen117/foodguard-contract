// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/DataStructures.sol";
import "./libraries/Errors.sol";
import "./libraries/Events.sol";
import "./modules/FundManager.sol";
import "./modules/VotingManager.sol";
import "./modules/DisputeManager.sol";
import "./modules/RewardPunishmentManager.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FoodSafetyGovernance
 * @author Food Safety Governance Team
 * @notice 食品安全治理主合约，整合投诉、验证、质疑、奖惩等完整流程
 * @dev 严格按照Mermaid流程图实现的去中心化食品安全治理系统
 */
contract FoodSafetyGovernance is Pausable, Ownable {
    // ==================== 状态变量 ====================

    /// @notice 案件计数器
    uint256 public caseCounter;

    /// @notice 模块合约地址
    FundManager public fundManager;
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    RewardPunishmentManager public rewardManager;

    /// @notice 案件信息映射 caseId => CaseInfo
    mapping(uint256 => CaseInfo) public cases;

    /// @notice 普通用户注册状态 user => isRegistered
    mapping(address => bool) public isUserRegistered;

    /// @notice 企业注册状态 enterprise => isRegistered
    mapping(address => bool) public isEnterpriseRegistered;

    /// @notice DAO组织注册状态 enterprise => isRegistered
    mapping(address => bool) public isDaoRegistered;

    /// @notice 用户类型映射 user => isEnterprise
    mapping(address => bool) public isEnterprise;

    /// @notice 风险等级评估映射 enterprise => riskLevel
    mapping(address => DataStructures.RiskLevel) public enterpriseRiskLevel;

    // ==================== 结构体定义 ====================

    /**
     * @notice 案件信息结构体（主要状态信息）
     * @dev 精简版案件信息，避免栈深度过深
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
     * @notice 步骤1: 创建投诉
     * @param enterprise 被投诉的企业地址
     * @param complaintTitle 投诉标题
     * @param complaintDescription 投诉详细描述
     * @param location 事发地点
     * @param incidentTime 事发时间
     * @param evidenceHashes IPFS证据哈希数组
     */
    function createComplaint(
        address enterprise,
        string calldata complaintTitle,
        string calldata complaintDescription,
        string calldata location,
        uint256 incidentTime,
        string[] calldata evidenceHashes,
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

        if (evidenceHashes.length == 0) {
            revert Errors.InsufficientEvidence(0, 1);
        }

        if (riskLevel > uint8(DataStructures.RiskLevel.HIGH)) {
            revert Errors.InvalidRiskLevel(riskLevel);
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

        // 如果用户发送了额外的ETH，存入保证金
        if (msg.value > 0) {
            fundManager.registerUserDeposit{value: msg.value}(
                msg.sender,
                msg.value
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
     * @param caseId 案件ID
     */
    function _lockDeposits(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();

        // 使用智能冻结投诉者保证金
        fundManager.smartFreezeDeposit(
            caseId,
            caseInfo.complainant,
            caseInfo.riskLevel,
            config.minComplaintDeposit
        );

        // 记录实际冻结的投诉者保证金
        caseInfo.complainantDeposit = fundManager.getCaseFrozenDeposit(caseId, caseInfo.complainant);

        // 使用智能冻结企业保证金
        fundManager.smartFreezeDeposit(
            caseId,
            caseInfo.enterprise,
            caseInfo.riskLevel,
            config.minEnterpriseDeposit
        );

        // 记录实际冻结的企业保证金
        caseInfo.enterpriseDeposit = fundManager.getCaseFrozenDeposit(caseId, caseInfo.enterprise);

        // 更新案件状态
        caseInfo.status = DataStructures.CaseStatus.DEPOSIT_LOCKED;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.PENDING,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            address(this),
            block.timestamp
        );

        // 如果是高风险案件，发出特殊事件
        if (caseInfo.riskLevel == DataStructures.RiskLevel.HIGH) {
            emit Events.HighRiskCaseProcessed(
                caseId,
                caseInfo.complainantDeposit + caseInfo.enterpriseDeposit,
                _getAffectedUsers(caseId),
                block.timestamp
            );
        }

        // 立即开始投票
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
        // 结束投票会话
        bool votingResult = votingManager.endVotingSession(caseId);

        CaseInfo storage caseInfo = cases[caseId];
        caseInfo.complaintUpheld = votingResult;
        caseInfo.status = DataStructures.CaseStatus.CHALLENGING;

        // 开始质疑期
        DataStructures.SystemConfig memory config = fundManager
            .getSystemConfig();
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
     * @notice 步骤6: 处理奖惩
     * @param caseId 案件ID
     */
    function _processRewardsPunishments(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];

        // 获取投票信息
        (, address[] memory validators, , , , , , , ,) = votingManager
            .getVotingSessionInfo(caseId);

        // 构建验证者投票选择数组
        DataStructures.VoteChoice[]
        memory validatorChoices = new DataStructures.VoteChoice[](
            validators.length
        );
        for (uint256 i = 0; i < validators.length; i++) {
            DataStructures.VoteInfo memory vote = votingManager
                .getValidatorVote(caseId, validators[i]);
            validatorChoices[i] = vote.choice;
        }

        // 获取质疑者信息
        DataStructures.ChallengeInfo[] memory challenges = disputeManager
            .getAllChallenges(caseId);
        address[] memory challengers = new address[](challenges.length);
        bool[] memory challengeResults = new bool[](challenges.length);

        for (uint256 i = 0; i < challenges.length; i++) {
            challengers[i] = challenges[i].challenger;
            // 简化质疑结果判断
            challengeResults[i] =
                (challenges[i].choice ==
                    DataStructures.ChallengeChoice.OPPOSE_VALIDATOR) ==
                (!caseInfo.complaintUpheld); // 如果反对验证者且结果确实改变了
        }

        // 调用奖惩管理器处理
        rewardManager.processCaseRewardPunishment(
            caseId,
            caseInfo.complaintUpheld,
            caseInfo.riskLevel,
            caseInfo.complainant,
            caseInfo.enterprise,
            validators,
            validatorChoices,
            challengers,
            challengeResults
        );

        // 完成案件
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
