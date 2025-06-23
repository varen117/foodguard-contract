// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFoodGuard.sol";
import "./libraries/Utils.sol";
import "./libraries/Constants.sol";
import "./core/AccessControl.sol";
import "./core/DepositManager.sol";
import "./core/VotingSystem.sol";
import "./core/ChallengeSystem.sol";
import "./core/RewardPunishmentSystem.sol";

/**
 * @title FoodGuardGovernance
 * @author FoodGuard Team
 * @notice 食品安全治理主合约 - 完整的食品安全投诉和治理流程
 * @dev 严格按照流程图实现的治理系统
 * 
 * 流程步骤：
 * 1. 存入保证金 -> 2. 投诉 -> 3. 风险等级判定
 * 4. 高风险冻结保证金 / 中低风险随机选择验证者
 * 5. 提交证据并投票 -> 6. 质疑阶段 -> 7. 质疑投票
 * 8. 结果确定（可能取反）-> 9. 奖惩计算 -> 10. 资金分配 -> 11. 公布消息
 */
contract FoodGuardGovernance is IFoodGuard, Constants, Ownable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error FoodGuardGovernance__SystemPaused();
    error FoodGuardGovernance__CaseNotExists();
    error FoodGuardGovernance__InvalidEnterprise();
    error FoodGuardGovernance__NotAuthorizedToComplain();
    error FoodGuardGovernance__EnterpriseCannotBeComplained();
    error FoodGuardGovernance__InvalidLocation();
    error FoodGuardGovernance__InvalidDescription();
    error FoodGuardGovernance__InvalidEvidenceFormat();
    error FoodGuardGovernance__VotingNotInProgress();
    error FoodGuardGovernance__ChallengePhaseNotActive();
    error FoodGuardGovernance__CaseNotInChallengePhase();
    error FoodGuardGovernance__CaseAlreadyCompleted();
    error FoodGuardGovernance__InsufficientChallengeDeposit();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // 引用子系统合约
    AccessControl public immutable i_accessControl;
    DepositManager public immutable i_depositManager;
    VotingSystem public immutable i_votingSystem;
    ChallengeSystem public immutable i_challengeSystem;
    RewardPunishmentSystem public immutable i_rewardPunishmentSystem;
    
    // 案件存储
    mapping(uint256 => Case) private cases;
    uint256 public nextCaseId = 1;
    
    // 案件状态统计
    uint256 public totalCases;
    uint256 public completedCases;
    uint256 public successfulComplaints;
    
    // 系统配置
    bool public systemPaused = false;
    
    // 额外事件（补充接口中的事件）
    event SystemInitialized(address accessControl, address depositManager, address votingSystem, address challengeSystem, address rewardSystem);
    event SystemPaused(bool paused);
    event RiskAssessmentCompleted(uint256 indexed caseId, RiskLevel riskLevel);
    event CaseProgressUpdate(uint256 indexed caseId, CaseStatus fromStatus, CaseStatus toStatus);

    /**
     * @dev 构造函数 - 初始化所有子系统
     */
    constructor() Ownable(msg.sender) {
        // 部署并初始化子系统
        i_accessControl = new AccessControl();
        i_depositManager = new DepositManager();
        i_votingSystem = new VotingSystem(address(i_accessControl), address(i_depositManager));
        i_challengeSystem = new ChallengeSystem(address(i_accessControl), address(i_votingSystem), address(i_depositManager));
        i_rewardPunishmentSystem = new RewardPunishmentSystem(
            address(i_accessControl),
            address(i_depositManager),
            address(i_votingSystem),
            address(i_challengeSystem)
        );
        
        emit SystemInitialized(
            address(i_accessControl),
            address(i_depositManager),
            address(i_votingSystem),
            address(i_challengeSystem),
            address(i_rewardPunishmentSystem)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    // 修饰符：检查系统是否暂停
    modifier whenNotPaused() {
        if (systemPaused) {
            revert FoodGuardGovernance__SystemPaused();
        }
        _;
    }

    // 修饰符：检查案件是否存在
    modifier caseExists(uint256 caseId) {
        if (caseId == 0 || caseId >= nextCaseId) {
            revert FoodGuardGovernance__CaseNotExists();
        }
        _;
    }

    /**
     * @dev 存入保证金
     */
    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function submitDeposit(uint256 caseId) external payable override nonReentrant whenNotPaused {
        if (caseId == 0) {
            // 通用保证金存入
            i_depositManager.depositFunds{value: msg.value}();
        } else {
            // 为特定案件存入保证金
            if (caseId >= nextCaseId) {
                revert FoodGuardGovernance__CaseNotExists();
            }
            i_depositManager.depositForCase{value: msg.value}(caseId);
        }
        
        emit DepositSubmitted(caseId, msg.sender, msg.value);
    }

    /**
     * @dev 创建投诉案件
     */
    function createComplaint(
        address enterprise,
        string memory location,
        string memory description,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external override nonReentrant whenNotPaused returns (uint256 caseId) {
        // 验证输入参数
        require(enterprise != address(0), "FoodGuardGovernance: Invalid enterprise address");
        require(bytes(location).length > 0, "FoodGuardGovernance: Location cannot be empty");
        require(bytes(description).length > 0, "FoodGuardGovernance: Description cannot be empty");
        require(Utils.validateEvidenceHashes(evidenceFiles), "FoodGuardGovernance: Invalid evidence format");
        
        // 检查权限
        require(i_accessControl.canComplain(msg.sender), "FoodGuardGovernance: Not authorized to complain");
        require(i_accessControl.canBeComplained(enterprise), "FoodGuardGovernance: Enterprise cannot be complained against");
        
        // 创建案件
        caseId = nextCaseId++;
        Case storage newCase = cases[caseId];
        
        newCase.caseId = caseId;
        newCase.complainant = msg.sender;
        newCase.enterprise = enterprise;
        newCase.location = location;
        newCase.description = description;
        newCase.createTime = block.timestamp;
        newCase.status = CaseStatus.COMPLAINT_SUBMITTED;
        
        // 创建投诉证据
        newCase.complaintEvidence = Evidence({
            description: evidenceDescription,
            fileHashes: evidenceFiles,
            timestamp: block.timestamp,
            submitter: msg.sender
        });
        
        // 添加参与者信息
        newCase.participants[msg.sender] = UserInfo({
            userAddress: msg.sender,
            role: UserRole.COMPLAINANT,
            integrity: IntegrityStatus.PENDING,
            rpStatus: RewardPunishmentStatus.NEUTRAL,
            depositAmount: 0,
            isActive: true
        });
        
        newCase.participants[enterprise] = UserInfo({
            userAddress: enterprise,
            role: UserRole.ENTERPRISE,
            integrity: IntegrityStatus.PENDING,
            rpStatus: RewardPunishmentStatus.NEUTRAL,
            depositAmount: 0,
            isActive: true
        });
        
        totalCases++;
        
        emit CaseCreated(caseId, msg.sender, enterprise);
        
        // 自动进行风险评估
        _assessRiskAndStartVoting(caseId);
        
        return caseId;
    }

    /**
     * @dev 内部函数：风险评估并开始投票
     */
    function _assessRiskAndStartVoting(uint256 caseId) internal {
        Case storage caseData = cases[caseId];
        
        // 评估风险等级
        RiskLevel riskLevel = Utils.assessRiskLevel(
            caseData.description,
            caseData.complaintEvidence.fileHashes.length
        );
        
        caseData.riskLevel = riskLevel;
        caseData.status = CaseStatus.RISK_ASSESSED;
        
        emit RiskAssessmentCompleted(caseId, riskLevel);
        emit CaseProgressUpdate(caseId, CaseStatus.COMPLAINT_SUBMITTED, CaseStatus.RISK_ASSESSED);
        
        // 如果是高风险，立即冻结相关保证金
        if (riskLevel == RiskLevel.HIGH) {
            _freezeHighRiskDeposits(caseId);
        }
        
        // 开始投票流程
        address[] memory validators = i_votingSystem.startVoting(
            caseId,
            riskLevel,
            caseData.description,
            caseData.complaintEvidence.fileHashes.length
        );
        
        // 更新案件状态
        caseData.status = CaseStatus.VOTING_IN_PROGRESS;
        caseData.deadline = Utils.calculateVotingDeadline(riskLevel, block.timestamp);
        
        // 添加验证者到参与者列表
        for (uint256 i = 0; i < validators.length; i++) {
            caseData.participants[validators[i]] = UserInfo({
                userAddress: validators[i],
                role: UserRole.VALIDATOR,
                integrity: IntegrityStatus.PENDING,
                rpStatus: RewardPunishmentStatus.NEUTRAL,
                depositAmount: 0,
                isActive: true
            });
        }
        
        emit CaseProgressUpdate(caseId, CaseStatus.RISK_ASSESSED, CaseStatus.VOTING_IN_PROGRESS);
    }

    /**
     * @dev 内部函数：冻结高风险案件的保证金
     */
    function _freezeHighRiskDeposits(uint256 caseId) internal {
        Case storage caseData = cases[caseId];
        
        // 冻结投诉者保证金
        (uint256 complainantDeposit, , , , bool complainantActive) = i_depositManager.getUserDeposit(caseData.complainant);
        if (complainantActive && complainantDeposit > 0) {
            i_depositManager.freezeDeposit(caseData.complainant, caseId, complainantDeposit);
        }
        
        // 冻结企业保证金
        (uint256 enterpriseDeposit, , , , bool enterpriseActive) = i_depositManager.getUserDeposit(caseData.enterprise);
        if (enterpriseActive && enterpriseDeposit > 0) {
            i_depositManager.freezeDeposit(caseData.enterprise, caseId, enterpriseDeposit);
        }
    }

    /**
     * @dev 提交投票
     */
    function submitVote(
        uint256 caseId,
        bool support,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external override nonReentrant whenNotPaused caseExists(caseId) {
        require(cases[caseId].status == CaseStatus.VOTING_IN_PROGRESS, "FoodGuardGovernance: Voting not in progress");
        
        // 调用投票系统
        i_votingSystem.submitVote(caseId, support, evidenceDescription, evidenceFiles);
        
        emit VoteSubmitted(caseId, msg.sender, support);
        
        // 检查投票是否完成
        _checkVotingCompletion(caseId);
    }

    /**
     * @dev 检查投票是否完成，如果完成则进入质疑阶段
     */
    function _checkVotingCompletion(uint256 caseId) internal {
        (, , , , , bool isActive, bool isCompleted, bool result) = i_votingSystem.getCaseVotingInfo(caseId);
        
        if (!isActive && isCompleted) {
            Case storage caseData = cases[caseId];
            caseData.status = CaseStatus.CHALLENGE_PHASE;
            caseData.complaintSuccessful = result;
            
            // 开始质疑阶段
            i_challengeSystem.startChallengePhase(caseId);
            
            emit CaseProgressUpdate(caseId, CaseStatus.VOTING_IN_PROGRESS, CaseStatus.CHALLENGE_PHASE);
        }
    }

    /**
     * @dev 提交质疑
     */
    function submitChallenge(
        uint256 caseId,
        address targetValidator,
        bool challengeResult,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external override nonReentrant whenNotPaused caseExists(caseId) {
        require(cases[caseId].status == CaseStatus.CHALLENGE_PHASE, "FoodGuardGovernance: Challenge phase not active");
        
        // 调用质疑系统（注意：需要先存入保证金）
        i_challengeSystem.submitChallenge(caseId, targetValidator, challengeResult, evidenceDescription, evidenceFiles);
        
        // 添加质疑者到参与者列表
        cases[caseId].participants[msg.sender] = UserInfo({
            userAddress: msg.sender,
            role: UserRole.CHALLENGER,
            integrity: IntegrityStatus.PENDING,
            rpStatus: RewardPunishmentStatus.NEUTRAL,
            depositAmount: 0,
            isActive: true
        });
        
        emit ChallengeSubmitted(caseId, msg.sender, challengeResult);
    }

    /**
     * @dev 对质疑进行投票
     */
    function submitChallengeVote(
        uint256 caseId,
        uint256 challengeIndex,
        bool support,
        string memory evidenceDescription,
        string[] memory evidenceFiles
    ) external override nonReentrant whenNotPaused caseExists(caseId) {
        // 调用质疑系统
        i_challengeSystem.voteOnChallenge(caseId, challengeIndex, support, evidenceDescription, evidenceFiles);
        
        emit ChallengeVoteSubmitted(caseId, challengeIndex, msg.sender, support);
    }

    /**
     * @dev 完成案件处理（管理员调用）
     */
    function completeCase(uint256 caseId) external onlyOwner nonReentrant caseExists(caseId) {
        Case storage caseData = cases[caseId];
        require(caseData.status == CaseStatus.CHALLENGE_PHASE, "FoodGuardGovernance: Case not in challenge phase");
        
        // 结束质疑阶段
        bool originalResultChanged = i_challengeSystem.endChallengePhase(caseId);
        
        // 更新最终结果
        if (originalResultChanged) {
            caseData.complaintSuccessful = !caseData.complaintSuccessful;
        }
        
        // 进入奖励计算阶段
        caseData.status = CaseStatus.REWARD_CALCULATION;
        emit CaseProgressUpdate(caseId, CaseStatus.CHALLENGE_PHASE, CaseStatus.REWARD_CALCULATION);
        
        // 计算奖惩
        i_rewardPunishmentSystem.calculateRewards(caseId);
        
        // 分配奖励和执行惩罚
        i_rewardPunishmentSystem.distributeRewards(caseId);
        i_rewardPunishmentSystem.applyPunishments(caseId);
        
        // 标记案件完成
        caseData.status = CaseStatus.COMPLETED;
        completedCases++;
        
        if (caseData.complaintSuccessful) {
            successfulComplaints++;
        }
        
        emit CaseCompleted(caseId, caseData.complaintSuccessful);
        emit CaseProgressUpdate(caseId, CaseStatus.REWARD_CALCULATION, CaseStatus.COMPLETED);
    }

    // ========== 查询函数 ==========

    /**
     * @dev 获取案件基本信息
     */
    function getCaseInfo(uint256 caseId) external view override caseExists(caseId) returns (
        address complainant,
        address enterprise,
        string memory location,
        string memory description,
        RiskLevel riskLevel,
        CaseStatus status,
        uint256 createTime,
        bool complaintSuccessful
    ) {
        Case storage caseData = cases[caseId];
        return (
            caseData.complainant,
            caseData.enterprise,
            caseData.location,
            caseData.description,
            caseData.riskLevel,
            caseData.status,
            caseData.createTime,
            caseData.complaintSuccessful
        );
    }

    /**
     * @dev 获取投票统计
     */
    function getVoteCount(uint256 caseId) external view override caseExists(caseId) returns (uint256 support, uint256 oppose) {
        (, support, oppose, , , , , ) = i_votingSystem.getCaseVotingInfo(caseId);
    }

    /**
     * @dev 获取质疑数量
     */
    function getChallengeCount(uint256 caseId) external view override caseExists(caseId) returns (uint256) {
        return i_challengeSystem.getChallengeCount(caseId);
    }

    /**
     * @dev 获取用户信息
     */
    function getUserInfo(uint256 caseId, address user) external view override caseExists(caseId) returns (UserInfo memory) {
        return cases[caseId].participants[user];
    }

    /**
     * @dev 获取案件详细信息
     */
    function getCaseDetails(uint256 caseId) external view caseExists(caseId) returns (
        uint256 id,
        address complainant,
        address enterprise,
        string memory location,
        string memory description,
        RiskLevel riskLevel,
        CaseStatus status,
        uint256 createTime,
        uint256 supportVotes,
        uint256 opposeVotes,
        uint256 challengeCount,
        bool votingCompleted,
        bool challengePhaseActive
    ) {
        Case storage caseData = cases[caseId];
        id = caseData.caseId;
        complainant = caseData.complainant;
        enterprise = caseData.enterprise;
        location = caseData.location;
        description = caseData.description;
        riskLevel = caseData.riskLevel;
        status = caseData.status;
        createTime = caseData.createTime;
        
        (,supportVotes, opposeVotes, , , , votingCompleted, ) = i_votingSystem.getCaseVotingInfo(caseId);
        challengeCount = i_challengeSystem.getChallengeCount(caseId);
        challengePhaseActive = i_challengeSystem.caseInChallengePhase(caseId);
    }

    /**
     * @dev 获取系统统计信息
     */
    function getSystemStats() external view returns (
        uint256 total,
        uint256 completed,
        uint256 successful,
        uint256 successRate
    ) {
        total = totalCases;
        completed = completedCases;
        successful = successfulComplaints;
        successRate = completed > 0 ? (successful * 10000) / completed : 0; // 以基点表示的成功率
    }

    // ========== 管理函数 ==========

    /**
     * @dev 暂停/恢复系统
     */
    function pauseSystem(bool paused) external onlyOwner {
        systemPaused = paused;
        emit SystemPaused(paused);
    }

    /**
     * @dev 获取子系统合约地址
     */
    function getSystemAddresses() external view returns (
        address accessControlAddr,
        address depositManagerAddr,
        address votingSystemAddr,
        address challengeSystemAddr,
        address rewardSystemAddr
    ) {
        return (
            address(i_accessControl),
            address(i_depositManager),
            address(i_votingSystem),
            address(i_challengeSystem),
            address(i_rewardPunishmentSystem)
        );
    }

    /**
     * @dev 紧急情况下取消案件
     */
    function emergencyCancelCase(uint256 caseId) external onlyOwner caseExists(caseId) {
        Case storage caseData = cases[caseId];
        require(caseData.status != CaseStatus.COMPLETED, "FoodGuardGovernance: Case already completed");
        
        caseData.status = CaseStatus.CANCELLED;
        emit CaseStatusChanged(caseId, CaseStatus.CANCELLED);
    }
} 