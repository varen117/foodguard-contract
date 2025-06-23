// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/DataStructures.sol";
import "./libraries/Errors.sol";
import "./libraries/Events.sol";
import "./modules/FundManager.sol";
import "./modules/VotingManager.sol";
import "./modules/DisputeManager.sol";
import "./modules/RewardPunishmentManager.sol";

/**
 * @title FoodSafetyGovernance
 * @author Food Safety Governance Team
 * @notice 食品安全治理主合约，整合投诉、验证、质疑、奖惩等完整流程
 * @dev 严格按照Mermaid流程图实现的去中心化食品安全治理系统
 */
contract FoodSafetyGovernance {
    // ==================== 状态变量 ====================
    
    /// @notice 管理员地址
    address public admin;
    
    /// @notice 合约是否暂停
    bool public isPaused;
    
    /// @notice 案件计数器
    uint256 public caseCounter;
    
    /// @notice 模块合约地址
    FundManager public fundManager;
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    RewardPunishmentManager public rewardManager;
    
    /// @notice 案件信息映射 caseId => CaseInfo
    mapping(uint256 => CaseInfo) public cases;
    
    /// @notice 用户注册状态 user => isRegistered
    mapping(address => bool) public isUserRegistered;
    
    /// @notice 企业注册状态 enterprise => isRegistered
    mapping(address => bool) public isEnterpriseRegistered;
    
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
        uint256 caseId;                        // 案件ID
        address complainant;                   // 投诉者
        address enterprise;                    // 被投诉企业
        string complaintTitle;                 // 投诉标题
        string complaintDescription;           // 投诉描述
        string location;                       // 事发地点
        uint256 incidentTime;                  // 事发时间
        uint256 complaintTime;                 // 投诉时间
        DataStructures.CaseStatus status;     // 案件状态
        DataStructures.RiskLevel riskLevel;   // 风险等级
        bool complaintUpheld;                  // 投诉是否成立
        uint256 complainantDeposit;            // 投诉者保证金
        uint256 enterpriseDeposit;             // 企业保证金
        bool isCompleted;                      // 是否已完成
        uint256 completionTime;                // 完成时间
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
     * @notice 合约未暂停时可调用
     */
    modifier whenNotPaused() {
        if (isPaused) {
            revert Errors.SystemPaused();
        }
        _;
    }
    
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
    modifier inStatus(uint256 caseId, DataStructures.CaseStatus requiredStatus) {
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
    
    constructor() {
        admin = msg.sender;
        caseCounter = 0;
        isPaused = false;
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
    ) external onlyAdmin {
        if (_fundManager == address(0) || _votingManager == address(0) || 
            _disputeManager == address(0) || _rewardManager == address(0)) {
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
            revert Errors.DuplicateOperation(msg.sender, "register");
        }
        
        // 要求最小保证金
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        if (msg.value < config.minComplaintDeposit) {
            revert Errors.InsufficientComplaintDeposit(msg.value, config.minComplaintDeposit);
        }
        
        isUserRegistered[msg.sender] = true;
        isEnterprise[msg.sender] = false;
        
        // 在资金管理合约中注册用户保证金
        fundManager.registerUserDeposit{value: msg.value}(msg.sender, msg.value);
        
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
        if (isUserRegistered[msg.sender]) {
            revert Errors.DuplicateOperation(msg.sender, "register");
        }
        
        // 企业需要更高的保证金
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        if (msg.value < config.minEnterpriseDeposit) {
            revert Errors.InsufficientEnterpriseDeposit(msg.value, config.minEnterpriseDeposit);
        }
        
        isUserRegistered[msg.sender] = true;
        isEnterprise[msg.sender] = true;
        isEnterpriseRegistered[msg.sender] = true;
        enterpriseRiskLevel[msg.sender] = DataStructures.RiskLevel.LOW; // 默认低风险
        
        // 在资金管理合约中注册企业保证金
        fundManager.registerUserDeposit{value: msg.value}(msg.sender, msg.value);
        
        emit Events.UserRegistered(
            msg.sender,
            true,
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
     * @param evidenceTypes 证据类型数组
     * @param evidenceDescriptions 证据描述数组
     */
    function createComplaint(
        address enterprise,
        string calldata complaintTitle,
        string calldata complaintDescription,
        string calldata location,
        uint256 incidentTime,
        string[] calldata evidenceHashes,
        string[] calldata evidenceTypes,
        string[] calldata evidenceDescriptions
    ) external payable whenNotPaused onlyRegisteredUser returns (uint256 caseId) {
        
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
        
        if (bytes(complaintTitle).length == 0 || bytes(complaintDescription).length == 0) {
            revert Errors.EmptyComplaintContent();
        }
        
        if (incidentTime > block.timestamp) {
            revert Errors.InvalidTimestamp(incidentTime, block.timestamp);
        }
        
        if (evidenceHashes.length == 0) {
            revert Errors.InsufficientEvidence(0, 1);
        }
        
        // 验证保证金
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        if (msg.value < config.minComplaintDeposit) {
            revert Errors.InsufficientComplaintDeposit(msg.value, config.minComplaintDeposit);
        }
        
        // 创建新案件
        caseId = ++caseCounter;
        
        // 评估风险等级
        DataStructures.RiskLevel riskLevel = _assessRiskLevel(enterprise, complaintDescription);
        
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
        newCase.riskLevel = riskLevel;
        newCase.complainantDeposit = msg.value;
        newCase.isCompleted = false;
        
        // 注意：投诉保证金已经在 msg.value 中提供，将直接进入锁定流程
        
        emit Events.ComplaintCreated(
            caseId,
            msg.sender,
            enterprise,
            complaintTitle,
            riskLevel,
            block.timestamp
        );
        
        // 立即进入下一步骤：锁定保证金
        _lockDeposits(caseId);
        
        return caseId;
    }
    
    /**
     * @notice 步骤2: 锁定保证金
     * @param caseId 案件ID
     */
    function _lockDeposits(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        
        // 先将投诉保证金存入用户账户，然后冻结
        fundManager.registerUserDeposit{value: caseInfo.complainantDeposit}(
            caseInfo.complainant, 
            caseInfo.complainantDeposit
        );
        
        // 冻结投诉者保证金
        fundManager.freezeDeposit(caseId, caseInfo.complainant, caseInfo.complainantDeposit);
        
        // 获取企业保证金要求
        uint256 enterpriseDepositRequired = config.minEnterpriseDeposit;
        
        // 高风险案件直接冻结所有保证金
        if (caseInfo.riskLevel == DataStructures.RiskLevel.HIGH) {
            // 冻结企业所有可用保证金
            uint256 availableDeposit = fundManager.getAvailableDeposit(caseInfo.enterprise);
            if (availableDeposit > 0) {
                fundManager.freezeDeposit(caseId, caseInfo.enterprise, availableDeposit);
                caseInfo.enterpriseDeposit = availableDeposit;
                
                emit Events.HighRiskCaseProcessed(
                    caseId,
                    caseInfo.complainantDeposit + availableDeposit,
                    _getAffectedUsers(caseId),
                    block.timestamp
                );
            }
        } else {
            // 中低风险案件冻结要求的保证金
            if (fundManager.getAvailableDeposit(caseInfo.enterprise) >= enterpriseDepositRequired) {
                fundManager.freezeDeposit(caseId, caseInfo.enterprise, enterpriseDepositRequired);
                caseInfo.enterpriseDeposit = enterpriseDepositRequired;
            }
        }
        
        // 更新案件状态
        caseInfo.status = DataStructures.CaseStatus.DEPOSIT_LOCKED;
        
        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.PENDING,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            address(this),
            block.timestamp
        );
        
        // 立即开始投票
        _startVoting(caseId);
    }
    
    /**
     * @notice 步骤3: 开始投票
     * @param caseId 案件ID
     */
    function _startVoting(uint256 caseId) internal {
        CaseInfo storage caseInfo = cases[caseId];
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        
        // 随机选择验证者并开始投票
        address[] memory selectedValidators = votingManager.startVotingSession(
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
    function endVotingAndStartChallenge(uint256 caseId) 
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
    function endChallengeAndProcessRewards(uint256 caseId) 
        external 
        whenNotPaused 
        caseExists(caseId) 
        inStatus(caseId, DataStructures.CaseStatus.CHALLENGING) 
    {
        CaseInfo storage caseInfo = cases[caseId];
        
        // 结束质疑期
        (bool finalResult, bool resultChanged) = disputeManager.endDisputeSession(
            caseId, 
            caseInfo.complaintUpheld
        );
        
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
        (
            ,
            address[] memory validators,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            
        ) = votingManager.getVotingSessionInfo(caseId);
        
        // 构建验证者投票选择数组
        DataStructures.VoteChoice[] memory validatorChoices = new DataStructures.VoteChoice[](validators.length);
        for (uint256 i = 0; i < validators.length; i++) {
            DataStructures.VoteInfo memory vote = votingManager.getValidatorVote(caseId, validators[i]);
            validatorChoices[i] = vote.choice;
        }
        
        // 获取质疑者信息
        DataStructures.ChallengeInfo[] memory challenges = disputeManager.getAllChallenges(caseId);
        address[] memory challengers = new address[](challenges.length);
        bool[] memory challengeResults = new bool[](challenges.length);
        
        for (uint256 i = 0; i < challenges.length; i++) {
            challengers[i] = challenges[i].challenger;
            // 简化质疑结果判断
            challengeResults[i] = (challenges[i].choice == DataStructures.ChallengeChoice.OPPOSE_VALIDATOR) == 
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
     * @notice 评估风险等级
     * @param enterprise 企业地址
     * @param description 投诉描述
     * @return 风险等级
     */
    function _assessRiskLevel(
        address enterprise, 
        string calldata description
    ) internal view returns (DataStructures.RiskLevel) {
        // 基于企业历史风险等级
        DataStructures.RiskLevel baseRisk = enterpriseRiskLevel[enterprise];
        
        // 基于投诉内容的关键词判断（简化实现）
        bytes memory desc = bytes(description);
        
        // 检查高风险关键词
        if (_containsHighRiskKeywords(desc)) {
            return DataStructures.RiskLevel.HIGH;
        }
        
        // 检查中风险关键词
        if (_containsMediumRiskKeywords(desc)) {
            return baseRisk == DataStructures.RiskLevel.HIGH ? 
                   DataStructures.RiskLevel.HIGH : 
                   DataStructures.RiskLevel.MEDIUM;
        }
        
        return baseRisk;
    }
    
    /**
     * @notice 检查是否包含高风险关键词
     */
    function _containsHighRiskKeywords(bytes memory description) internal pure returns (bool) {
        // 简化实现：检查是否包含"poisoning"、"death"等关键词
        // 实际实现中可以使用更复杂的NLP算法
        return description.length > 100; // 简化为描述长度判断
    }
    
    /**
     * @notice 检查是否包含中风险关键词
     */
    function _containsMediumRiskKeywords(bytes memory description) internal pure returns (bool) {
        return description.length > 50;
    }
    
    /**
     * @notice 获取受影响的用户列表
     */
    function _getAffectedUsers(uint256 caseId) internal view returns (address[] memory) {
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
    function getCaseInfo(uint256 caseId) external view returns (CaseInfo memory) {
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
    function getEnterpriseRiskLevel(address enterprise) external view returns (DataStructures.RiskLevel) {
        return enterpriseRiskLevel[enterprise];
    }
    
    // ==================== 管理函数 ====================
    
    /**
     * @notice 暂停/恢复合约
     */
    function setPaused(bool _paused) external onlyAdmin {
        isPaused = _paused;
        
        emit Events.SystemPauseStatusChanged(
            _paused,
            msg.sender,
            block.timestamp
        );
    }
    
    /**
     * @notice 更新企业风险等级
     */
    function updateEnterpriseRiskLevel(
        address enterprise, 
        DataStructures.RiskLevel newLevel
    ) external onlyAdmin {
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
    function emergencyCancelCase(uint256 caseId, string calldata reason) external onlyAdmin caseExists(caseId) {
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
        
        emit Events.CaseCancelled(
            caseId,
            reason,
            msg.sender,
            block.timestamp
        );
    }
} 