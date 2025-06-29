// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用最新稳定版本，支持优化和安全特性

// 导入系统基础库
import "./libraries/DataStructures.sol"; // 核心数据结构定义
import "./libraries/Errors.sol"; // 标准化错误处理
import "./libraries/Events.sol"; // 标准化事件定义

// 导入功能模块合约
import "./modules/FundManager.sol"; // 资金和保证金管理模块
import "./modules/VotingDisputeManager.sol"; // 投票和质疑管理模块
import "./modules/RewardPunishmentManager.sol"; // 奖惩计算和分配模块
import "./modules/ParticipantPoolManager.sol"; // 参与者池管理模块

// 导入OpenZeppelin安全组件
import "@openzeppelin/contracts/utils/Pausable.sol"; // 暂停功能，用于紧急情况
import "@openzeppelin/contracts/access/Ownable.sol"; // 所有权管理

// 导入chainlink模块
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

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
contract FoodSafetyGovernance is Pausable, VRFConsumerBaseV2Plus, AutomationCompatibleInterface {

    address private _admin;

    modifier onlyAdmin() {
        require(msg.sender == _admin, "Not the admin");
        _;
    }

    function admin() public view returns (address) {
        return _admin;
    }

    function transferAdmin(address newAdmin) public onlyAdmin {
        require(newAdmin != address(0), "New admin is the zero address");
        _admin = newAdmin;
    }
    // ==================== 状态变量VRF =================
    // vrf,也可以用构造函数初始化它们
    uint256 private s_subscriptionId;
    address private vrfCoordinator;
    bytes32 private s_keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 private callbackGasLimit = 40000;
    uint16 private requestConfirmations = 3;

    /// @notice VRF配置是否已初始化
    bool public vrfConfigured = false;

    // ==================== 状态变量 ====================

    /// @notice 案件计数器 - 系统中创建的案件总数，也用作新案件的唯一ID
    /// @dev 从0开始递增，确保每个案件都有唯一标识符
    uint256 public caseCounter; // 案件总数计数器

    /// @notice 核心模块合约地址
    FundManager public fundManager; // 资金管理合约实例
    VotingDisputeManager public votingDisputeManager; // 投票和质疑管理合约实例
    RewardPunishmentManager public rewardManager; // 奖惩管理合约实例
    ParticipantPoolManager public poolManager; // 参与者池管理合约实例

    /// @notice 案件信息映射 - 存储所有案件的核心信息
    /// @dev 键值对：caseId => CaseInfo，提供案件的完整状态追踪
    mapping(uint256 => CaseInfo) public cases; // 案件ID到案件信息的映射

    /// @notice 活跃案件列表 - 存储所有未完成案件的ID，用于优化自动触发逻辑
    /// @dev 只包含状态为PENDING, DEPOSIT_LOCKED, VOTING, CHALLENGING, REWARD_PUNISHMENT的案件
    uint256[] public activeCases;

    /// @notice 活跃案件索引映射 - 快速查找案件在活跃列表中的位置
    /// @dev 键值对：caseId => index，其中index是案件在activeCases数组中的索引
    mapping(uint256 => uint256) public activeCaseIndex;

    /// @notice 案件是否活跃标记 - 快速判断案件是否还在活跃状态
    /// @dev 键值对：caseId => isActive，避免线性搜索activeCases数组
    mapping(uint256 => bool) public isCaseActive;

    /// @notice 将请求ID与案件ID关联 Chainlink requestId => caseId
    mapping(uint256 => uint256) public caseRequestIds;

    // ==================== 结构体定义 ====================

    /**
     * @notice 案件信息结构体
     */
    struct CaseInfo {
        uint256 caseId; // 案件唯一标识符
        address complainant; // 投诉者地址
        address enterprise; // 被投诉企业地址
        string complaintTitle; // 投诉标题
        string complaintDescription; // 投诉详细描述
        string location; // 事发地点
        uint256 incidentTime; // 事发时间(Unix时间戳)
        uint256 complaintTime; // 投诉提交时间(Unix时间戳)
        DataStructures.CaseStatus status; // 案件当前状态
        DataStructures.RiskLevel riskLevel; // 案件风险等级
        bool complaintUpheld; // 投诉是否成立
        uint256 complainantDeposit; // 投诉者实际冻结保证金数额
        uint256 enterpriseDeposit; // 企业实际冻结保证金数额
        string complainantEvidenceHash; // 投诉者提供的证据哈希
        bool isCompleted; // 案件是否已完成
        uint256 completionTime; // 案件完成时间(Unix时间戳)
    }

    // ==================== 修饰符 ====================
    /**
     * @notice 检查案件是否存在
     */
    modifier caseExists(uint256 caseId) { // 案件ID
        if (cases[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    /**
     * @notice 检查案件状态
     */
    modifier inStatus(
        uint256 caseId, // 案件ID
        DataStructures.CaseStatus requiredStatus // 要求的案件状态
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

    constructor(address initialOwner) VRFConsumerBaseV2Plus(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) { // 初始所有者地址
        if (initialOwner == address(0)) {
            revert Errors.ZeroAddress();
        }
        _admin = initialOwner;
        caseCounter = 0;
        // 对于本地测试，使用第一个Anvil测试账户作为模拟VRF协调器
        vrfCoordinator = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }

    // ==================== 初始化函数 ====================

    /**
     * @notice 初始化模块合约地址
     * @param _fundManager 资金管理合约地址
     * @param _votingDisputeManager 投票和质疑管理合约地址
     * @param _rewardManager 奖惩管理合约地址
     * @param _poolManager 参与者池管理合约地址
     */
    function initializeContracts(
        address payable _fundManager, // 资金管理合约地址
        address _votingDisputeManager, // 投票和质疑管理合约地址
        address _rewardManager, // 奖惩管理合约地址
        address _poolManager // 参与者池管理合约地址
    ) external onlyAdmin {
        if (
            _fundManager == address(0) ||
            _votingDisputeManager == address(0) ||
            _rewardManager == address(0) ||
            _poolManager == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        fundManager = FundManager(_fundManager);
        votingDisputeManager = VotingDisputeManager(_votingDisputeManager);
        rewardManager = RewardPunishmentManager(_rewardManager);
        poolManager = ParticipantPoolManager(_poolManager);
    }

    /**
     * @notice 初始化VRF配置
     * @param _subscriptionId Chainlink VRF订阅ID
     * @param _vrfCoordinator VRF协调器地址
     * @param _keyHash VRF密钥哈希
     * @param _callbackGasLimit 回调Gas限制
     * @param _requestConfirmations 请求确认数
     */
    function initializeVRF(
        uint256 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyAdmin {
        require(_subscriptionId > 0, "Invalid subscription ID");
        require(_vrfCoordinator != address(0), "Invalid VRF coordinator address");
        require(_keyHash != bytes32(0), "Invalid key hash");
        require(_callbackGasLimit >= 20000, "Gas limit too low");
        require(_requestConfirmations >= 1, "Invalid confirmation count");

        s_subscriptionId = _subscriptionId;
        s_vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        s_keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        vrfConfigured = true;

        emit Events.SystemConfigUpdated("VRF", "VRF configuration updated");
    }



    /**
     * @notice 验证系统配置完整性
     * @return isValid 配置是否有效
     * @return issues 配置问题列表
     */
    function validateConfiguration() external view returns (bool isValid, string[] memory issues) {
        string[] memory problems = new string[](10);
        uint256 count = 0;

        // 检查VRF配置
        if (s_subscriptionId == 0) {
            problems[count++] = "VRF subscription ID not set";
        }
        
        if (vrfCoordinator == address(0)) {
            problems[count++] = "VRF coordinator not set";
        }
        
        if (!vrfConfigured) {
            problems[count++] = "VRF not configured";
        }

        // 检查模块合约
        if (address(fundManager) == address(0)) {
            problems[count++] = "Fund manager not set";
        }
        
        if (address(votingDisputeManager) == address(0)) {
            problems[count++] = "Voting dispute manager not set";
        }
        
        if (address(rewardManager) == address(0)) {
            problems[count++] = "Reward manager not set";
        }
        
        if (address(poolManager) == address(0)) {
            problems[count++] = "Pool manager not set";
        }

        // 创建实际大小的数组
        string[] memory actualIssues = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            actualIssues[i] = problems[i];
        }

        return (count == 0, actualIssues);
    }

    // ==================== 核心流程函数 ====================

    /**
     * @notice 注册用户
     * @param user 用户地址
     * @param userRole 用户角色
     */
    function registerUser(address user, uint8 userRole) external {
        // 检查是否超出枚举范围
        if (userRole > uint8(DataStructures.UserRole.DAO_MEMBER)) {
            revert Errors.UserRoleIncorrect(user, userRole, "Incorrect user role registration");
        }

        // 调用池管理合约注册用户
        poolManager.registerUser(user, DataStructures.UserRole(userRole));
    }

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
        address enterprise, // 被投诉企业地址
        string calldata complaintTitle, // 投诉标题
        string calldata complaintDescription, // 投诉详细描述
        string calldata location, // 事发地点
        uint256 incidentTime, // 事发时间(Unix时间戳)
        string calldata evidenceHash, // 证据材料哈希
        uint8 riskLevel // 风险等级数值(0-2)
    )
    external
    whenNotPaused
    returns (uint256 caseId) // 返回新案件ID
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
        (bool complainantRegistered, DataStructures.UserRole complainantRole, bool complainantActive,) = poolManager.getUserInfo(msg.sender); // 投诉者注册状态, 用户角色, 激活状态, 其他信息
        if (!complainantRegistered || !complainantActive || complainantRole != DataStructures.UserRole.COMPLAINANT) {
            revert Errors.InvalidUserRole(
                msg.sender,
                uint8(complainantRole),
                uint8(DataStructures.UserRole.COMPLAINANT)
            );
        }

        // 验证企业角色权限
        (bool enterpriseRegistered, DataStructures.UserRole enterpriseRole, bool enterpriseActive,) = poolManager.getUserInfo(enterprise); // 企业注册状态, 用户角色, 激活状态, 其他信息
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

        DataStructures.RiskLevel riskLevelEnum = DataStructures.RiskLevel(riskLevel); // 风险等级枚举值

        // 检查用户是否可以参与新案件（基于动态保证金系统）
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig(); // 系统配置参数
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
        caseId = ++caseCounter; // 递增案件计数器并赋值给新案件ID

        // 创建案件信息
        CaseInfo storage newCase = cases[caseId]; // 新案件信息存储引用
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

        // 将新案件添加到活跃案件列表，用于优化自动触发逻辑
        _addToActiveCases(caseId);

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
    function _lockDeposits(uint256 caseId) internal { // 案件ID
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig(); // 系统配置参数

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
    function _startVoting(uint256 caseId) internal { // 案件ID
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig(); // 系统配置参数

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
        uint256 validatorCount = config.minValidators; // 验证者数量
//        if (caseInfo.riskLevel == DataStructures.RiskLevel.HIGH) {
//            validatorCount = config.maxValidators > 7 ? 7 : config.maxValidators; // 高风险案件更多验证者
//        } else if (caseInfo.riskLevel == DataStructures.RiskLevel.MEDIUM) {
//            validatorCount = config.minValidators + 2; // 中风险案件适中验证者
//        }
        validatorCount = 3; // // todo 便于测试统一设置成3，后续delete
        // 确保验证者数量为奇数
        if (validatorCount % 2 == 0) {
            validatorCount += 1;
        }

        uint256 requestId = this.sendRandomWordsRequest(uint32(validatorCount)); // 发送请求获取随机数
        caseRequestIds[requestId] = caseId; // 将请求ID与案件ID关联
    }

    // VRF获取随机数
    function sendRandomWordsRequest(uint32 _numWords) external returns (uint256) {
        // 检查VRF配置是否已初始化
        require(vrfConfigured, "VRF not configured");
        require(s_subscriptionId > 0, "Invalid subscription ID");
        
        // 获取随机数（组装请求参数）
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: s_keyHash,//chainlink中VRF创建的订阅 keyhash
            subId: s_subscriptionId, // VRF订阅ID
            requestConfirmations: requestConfirmations, // 请求确认数
            callbackGasLimit: callbackGasLimit, // 回调gas限制
            numWords: _numWords, //获取的随机数个数
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false}) // 将nativePayment设置为true，使用Sepolia ETH而不是LINK来支付VRF请求
            )
        });
        // 向 Chainlink VRF 协调器请求随机数，返回一个唯一的 requestId 用于追踪这次随机数请求
        return s_vrfCoordinator.requestRandomWords(request);
    }

    // 选择随机验证者并开启投票
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 caseId = caseRequestIds[requestId]; // 获取与请求ID关联的案件ID
        // 使用ParticipantPoolManager随机选择验证者
        address[] memory selectedValidators = poolManager.selectValidators(caseId, randomWords); // 选中的验证者地址数组
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig(); // 系统配置参数
        // 将选中的验证者传递给VotingDisputeManager开启投票
        votingDisputeManager.startVotingSessionWithValidators(
            caseId,
            selectedValidators,
            config.votingPeriod
        );

        // 更新案件状态
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用
        caseInfo.status = DataStructures.CaseStatus.VOTING;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.DEPOSIT_LOCKED,
            DataStructures.CaseStatus.VOTING,
            block.timestamp
        );

        // 发出验证者选择事件
        emit Events.VoteStart(caseId, selectedValidators, block.timestamp, block.timestamp + config.votingPeriod, block.timestamp);
    }

    // ==================== 结束投票并开启质疑阶段 ====================
    function checkUpkeep(bytes memory /* checkData */)
    public
    view
    override
    returns (bool upkeepNeeded, bytes memory performData)
    {
        // 只检查活跃案件列表，避免遍历所有历史案件，显著提升性能
        uint256 activeCaseCount = activeCases.length;
        uint256[] memory casesToProcess = new uint256[](activeCaseCount);
        uint256[] memory actionTypes = new uint256[](activeCaseCount); // 0: endVoting, 1: endChallenge
        uint256 count = 0;

        // 历活跃案件列表
        for (uint256 i = 0; i < activeCaseCount; i++) {
            uint256 caseId = activeCases[i];
            CaseInfo storage caseInfo = cases[caseId];

            // 检查投票阶段
            if (caseInfo.status == DataStructures.CaseStatus.VOTING) {
                // 投票期结束时自动更新为投票结束状态
                if (votingDisputeManager.isVotingPeriodEnded(caseId)) {
                    casesToProcess[count] = caseId;
                    actionTypes[count] = uint256(DataStructures.ActionType.updateToVotingStatus); // updateToVotingStatus
                    count++;
                    upkeepNeeded = true;
                }
                // 条件2：全员提前完成投票时自动更新为投票结束状态
                else if (votingDisputeManager.areAllValidatorsVoted(caseId)) {
                    casesToProcess[count] = caseId;
                    actionTypes[count] = uint256(DataStructures.ActionType.updateToVotingStatus); // updateToVotingStatus
                    count++;
                    upkeepNeeded = true;
                }
            }
            // 检查投票结束阶段
            else if (caseInfo.status == DataStructures.CaseStatus.VOTING_ENDED) {
                // 投票结束后自动进入质疑阶段
                casesToProcess[count] = caseId;
                actionTypes[count] = uint256(DataStructures.ActionType.endVoting); // endVoting
                count++;
                upkeepNeeded = true;
            }
            // 检查质疑阶段
            else if (caseInfo.status == DataStructures.CaseStatus.CHALLENGING) {
                // 条件3：质疑期结束时自动调用endChallengeAndProcessRewards
                if (votingDisputeManager.isChallengePeriodEnded(caseId)) {
                    casesToProcess[count] = caseId;
                    actionTypes[count] = uint256(DataStructures.ActionType.endChallenge); // endChallenge
                    count++;
                    upkeepNeeded = true;
                }
            }
        }

        // 如果有需要处理的案件，编码为performData
        if (upkeepNeeded) {
            // 调整数组大小到实际需要的长度
            uint256[] memory finalCases = new uint256[](count);
            uint256[] memory finalActions = new uint256[](count);
            for (uint256 i = 0; i < count; i++) {
                finalCases[i] = casesToProcess[i];
                finalActions[i] = actionTypes[i];
            }
            performData = abi.encode(finalCases, finalActions);
        }

        return (upkeepNeeded, performData);
    }

    /**
     * @notice 该函数由 Chainlink Automation 调用，用于执行自动触发动作
     * @param performData 传递给函数的数据，包含需要处理的案件ID和动作类型
     */
    function performUpkeep(bytes calldata performData) external override {
        // 解码performData
        (uint256[] memory casesToProcess, uint256[] memory actionTypes) = abi.decode(performData, (uint256[], uint256[]));

        require(casesToProcess.length == actionTypes.length, "Data length mismatch");

        uint256 successfulCases = 0;
        uint256 failedCases = 0;

        // 循环处理所有需要的案件
        for (uint256 i = 0; i < casesToProcess.length; i++) {
            if (_executeActionWithErrorHandling(casesToProcess[i], actionTypes[i])) {
                successfulCases++;
            } else {
                failedCases++;
            }
        }

        // 发送批次处理结果事件
        if (casesToProcess.length > 0) {
            emit Events.AutoExecutionBatchProcessed(
                casesToProcess.length,
                successfulCases,
                failedCases,
                block.timestamp
            );
        }
    }

    /**
     * @notice 执行单个案件动作并处理错误
     * @param caseId 案件ID
     * @param actionType 动作类型
     * @return success 执行是否成功
     */
    function _executeActionWithErrorHandling(uint256 caseId, uint256 actionType) internal returns (bool success) {
        try this.executeCaseAction(caseId, actionType) {
            // 成功执行，发送成功事件
            emit Events.AutoExecutionSuccess(
                caseId,
                actionType,
                actionType == 0 ? "endVoting" : actionType == 1 ? "endChallenge" : "updateToVotingEnded",
                block.timestamp
            );
            return true;
        } catch {
            // 统一错误处理，避免复杂的字符串操作
            emit Events.AutoExecutionFailed(
                caseId,
                actionType,
                actionType == 0 ? "endVoting" : actionType == 1 ? "endChallenge" : "updateToVotingEnded",
                "Execution failed",
                block.timestamp
            );
            return false;
        }
    }

    /**
     * @notice 执行特定案件的动作
     * @param caseId 案件ID
     * @param actionType 动作类型 (0: endVoting, 1: endChallenge, 2: updateToVotingEnded)
     */
    function executeCaseAction(uint256 caseId, uint256 actionType) external {
        require(msg.sender == address(this), "Only self can call");
        DataStructures.ActionType actionTypeEnum = DataStructures.ActionType(actionType); // 将动作类型转换为枚举
        if (DataStructures.ActionType.endVoting ==  actionTypeEnum) {
            // 结束投票并开始质疑期
            this.endVotingAndStartChallenge(caseId);
        } else if (actionTypeEnum == DataStructures.ActionType.endChallenge) {
            // 结束质疑期并进入奖惩阶段
            this.endChallengeAndProcessRewards(caseId);
        } else if (actionTypeEnum == DataStructures.ActionType.updateToVotingStatus) {
            // 更新案件状态为投票结束
            this.updateCaseToVotingEnded(caseId);
        }
    }

    /**
     * @notice 更新案件状态为投票结束
     * @param caseId 案件ID
     */
    function updateCaseToVotingEnded(
        uint256 caseId // 案件ID
    )
    external
    whenNotPaused
    caseExists(caseId)
    inStatus(caseId, DataStructures.CaseStatus.VOTING)
    {
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        // 更新案件状态为投票结束
        caseInfo.status = DataStructures.CaseStatus.VOTING_ENDED;

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.VOTING,
            DataStructures.CaseStatus.VOTING_ENDED,
            block.timestamp
        );
    }

    /**
     * @notice 步骤4: 结束投票并开始质疑期
     * @param caseId 案件ID

     */
    function endVotingAndStartChallenge(
        uint256 caseId // 案件ID
    )
    external
    whenNotPaused
    caseExists(caseId)
    inStatus(caseId, DataStructures.CaseStatus.VOTING_ENDED)
    {
        // 结束验证阶段并获取投票结果
        votingDisputeManager.endVotingSession(caseId);

        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        // 开启质疑阶段
        caseInfo.status = DataStructures.CaseStatus.CHALLENGING;

        // 开始质疑期
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig(); // 系统配置参数
        votingDisputeManager.startDisputeSession(caseId, config.challengePeriod);

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.VOTING_ENDED,
            DataStructures.CaseStatus.CHALLENGING,
            block.timestamp
        );
    }

    /**
     * @notice 步骤5: 结束质疑期并进入奖惩阶段
     * @param caseId 案件ID
     */
    function endChallengeAndProcessRewards(
        uint256 caseId // 案件ID
    )
    external
    whenNotPaused
    caseExists(caseId)
    inStatus(caseId, DataStructures.CaseStatus.CHALLENGING)
    {
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        // 结束质疑期并获取质疑者详细信息
        bool finalResult = votingDisputeManager.endDisputeSession( // 最终投诉结果
            caseId,
            caseInfo.complainant,
            caseInfo.enterprise
        );

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
     *
     * 奖惩分配原则：
     * - 验证者：投票正确获得奖励，错误承担惩罚
     * - 质疑者：成功质疑获得奖励，失败质疑承担惩罚
     * - 投诉者：投诉成立获得赔偿，虚假投诉承担惩罚
     * - 企业：败诉承担重罚，胜诉获得声誉恢复补偿
     *
     * @param caseId 案件ID
     */
    function _processRewardsPunishments(uint256 caseId) internal { // 案件ID
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        // 获取各角色的奖励和惩罚成员列表
        address[] memory complainantRewards = votingDisputeManager.getRewardMembers(caseId, DataStructures.UserRole.COMPLAINANT);
        address[] memory enterpriseRewards = votingDisputeManager.getRewardMembers(caseId, DataStructures.UserRole.ENTERPRISE);
        address[] memory daoRewards = votingDisputeManager.getRewardMembers(caseId, DataStructures.UserRole.DAO_MEMBER);

        address[] memory complainantPunishments = votingDisputeManager.getPunishMembers(caseId, DataStructures.UserRole.COMPLAINANT);
        address[] memory enterprisePunishments = votingDisputeManager.getPunishMembers(caseId, DataStructures.UserRole.ENTERPRISE);
        address[] memory daoPunishments = votingDisputeManager.getPunishMembers(caseId, DataStructures.UserRole.DAO_MEMBER);

        // 步骤5：调用奖惩管理器进行奖惩分配
        rewardManager.processCaseRewardPunishment(
            caseId,
            complainantRewards.length > 0 ? complainantRewards[0] : address(0),
            enterpriseRewards.length > 0 ? enterpriseRewards[0] : address(0),
            daoRewards,
            complainantPunishments.length > 0 ? complainantPunishments[0] : address(0),
            enterprisePunishments.length > 0 ? enterprisePunishments[0] : address(0),
            daoPunishments,
            caseInfo.complaintUpheld,
            caseInfo.riskLevel);

        // 步骤6：完成案件处理
        _completeCase(caseId);
    }

    /**
     * @notice 步骤7: 完成案件
     * @param caseId 案件ID
     */
    function _completeCase(uint256 caseId) internal { // 案件ID
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        caseInfo.status = DataStructures.CaseStatus.COMPLETED;
        caseInfo.isCompleted = true;
        caseInfo.completionTime = block.timestamp;

        // 从活跃案件列表中移除该案件，优化后续自动触发逻辑的性能
        _removeFromActiveCases(caseId);

        // 解冻剩余保证金
        fundManager.unfreezeDeposit(caseId, caseInfo.complainant);
        fundManager.unfreezeDeposit(caseId, caseInfo.enterprise);

        emit Events.CaseCompleted(
            caseId,
            caseInfo.complaintUpheld,
            0, // 总奖励金额 - 需要从奖惩管理器获取
            0, // 总惩罚金额 - 需要从奖惩管理器获取
            block.timestamp
        );

        emit Events.CaseStatusUpdated(
            caseId,
            DataStructures.CaseStatus.REWARD_PUNISHMENT,
            DataStructures.CaseStatus.COMPLETED,
            block.timestamp
        );
    }

    // ==================== 辅助函数 ====================

    /**
     * @notice 获取受影响的用户列表
     */
    function _getAffectedUsers(
        uint256 caseId // 案件ID
    ) internal view returns (address[] memory) {
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用
        address[] memory affected = new address[](2); // 受影响用户地址数组
        affected[0] = caseInfo.complainant;
        affected[1] = caseInfo.enterprise;
        return affected;
    }

    /**
     * @notice 添加案件到活跃案件列表
     * @dev 在案件创建时调用，将新案件添加到活跃列表以便自动触发逻辑可以高效处理
     * @param caseId 要添加的案件ID
     */
    function _addToActiveCases(uint256 caseId) internal {
        if (!isCaseActive[caseId]) {
            activeCaseIndex[caseId] = activeCases.length;
            activeCases.push(caseId);
            isCaseActive[caseId] = true;
        }
    }

    /**
     * @notice 从活跃案件列表中移除案件
     * @dev 在案件完成或取消时调用，从活跃列表中移除案件以优化后续遍历性能
     * 使用swap-and-pop技术保持数组紧凑，避免gas浪费
     * @param caseId 要移除的案件ID
     */
    function _removeFromActiveCases(uint256 caseId) internal {
        if (isCaseActive[caseId]) {
            uint256 indexToRemove = activeCaseIndex[caseId];
            uint256 lastIndex = activeCases.length - 1;

            // 如果要删除的不是最后一个元素，用最后一个元素替换它
            if (indexToRemove != lastIndex) {
                uint256 lastCaseId = activeCases[lastIndex];
                activeCases[indexToRemove] = lastCaseId;
                activeCaseIndex[lastCaseId] = indexToRemove;
            }

            // 删除最后一个元素
            activeCases.pop();
            delete activeCaseIndex[caseId];
            isCaseActive[caseId] = false;
        }
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取案件信息
     */
    function getCaseInfo(
        uint256 caseId // 案件ID
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
     * @notice 获取活跃案件数量
     * @dev 返回当前正在处理中的案件数量，不包括已完成或已取消的案件
     * @return 活跃案件数量
     */
    function getActiveCaseCount() external view returns (uint256) {
        return activeCases.length;
    }

    /**
     * @notice 获取活跃案件列表
     * @dev 返回所有正在处理中的案件ID列表，用于外部监控和分析
     * @return 活跃案件ID数组
     */
    function getActiveCases() external view returns (uint256[] memory) {
        return activeCases;
    }

    /**
     * @notice 检查案件是否活跃
     * @param caseId 案件ID
     * @return 如果案件正在处理中返回true，否则返回false
     */
    function isCaseActiveStatus(uint256 caseId) external view returns (bool) {
        return isCaseActive[caseId];
    }

    /**
     * @notice 获取活跃案件的详细信息
     * @dev 批量获取所有活跃案件的详细信息，用于管理面板展示
     * @return activeCaseInfos 活跃案件信息数组
     */
    function getActiveCaseInfos() external view returns (CaseInfo[] memory activeCaseInfos) {
        uint256 count = activeCases.length;
        activeCaseInfos = new CaseInfo[](count);

        for (uint256 i = 0; i < count; i++) {
            activeCaseInfos[i] = cases[activeCases[i]];
        }

        return activeCaseInfos;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 暂停/恢复合约
     */
    function setPaused(bool _paused) external onlyAdmin { // 是否暂停标志
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }

    }

    /**
     * @notice 紧急取消案件
     */
    function emergencyCancelCase(
        uint256 caseId, // 案件ID
        string calldata reason // 取消原因
    ) external onlyAdmin caseExists(caseId) {
        CaseInfo storage caseInfo = cases[caseId]; // 案件信息存储引用

        if (caseInfo.isCompleted) {
            revert Errors.CaseAlreadyCompleted(caseId);
        }

        caseInfo.status = DataStructures.CaseStatus.CANCELLED;
        caseInfo.isCompleted = true;
        caseInfo.completionTime = block.timestamp;

        // 从活跃案件列表中移除该案件，优化后续自动触发逻辑的性能
        _removeFromActiveCases(caseId);

        // 解冻保证金
        fundManager.unfreezeDeposit(caseId, caseInfo.complainant);
        fundManager.unfreezeDeposit(caseId, caseInfo.enterprise);

        emit Events.CaseCancelled(caseId, reason, msg.sender, block.timestamp);
    }

    /**
     * @notice 清理活跃案件列表
     * @dev 管理员函数，用于处理数据不一致情况，移除已完成但仍在活跃列表中的案件
     * 这是一个维护函数，正常情况下不应该需要调用
     */
    function cleanupActiveCases() external onlyAdmin {
        uint256 i = 0;
        while (i < activeCases.length) {
            uint256 caseId = activeCases[i];
            CaseInfo storage caseInfo = cases[caseId];

            // 检查案件是否已完成或已取消
            if (caseInfo.isCompleted ||
                caseInfo.status == DataStructures.CaseStatus.COMPLETED ||
                caseInfo.status == DataStructures.CaseStatus.CANCELLED) {

                // 移除已完成的案件（这会改变数组，所以不增加i）
                _removeFromActiveCases(caseId);
            } else {
                // 只有案件仍然活跃时才增加索引
                i++;
            }
        }
    }
}
