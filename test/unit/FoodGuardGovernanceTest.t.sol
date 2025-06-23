// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployFoodGuard} from "../../script/DeployFoodGuard.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {FoodGuardGovernance} from "../../src/FoodGuardGovernance.sol";
import {AccessControl} from "../../src/core/AccessControl.sol";
import {DepositManager} from "../../src/core/DepositManager.sol";
import {VotingSystem} from "../../src/core/VotingSystem.sol";
import {ChallengeSystem} from "../../src/core/ChallengeSystem.sol";
import {RewardPunishmentSystem} from "../../src/core/RewardPunishmentSystem.sol";
import {IFoodGuard} from "../../src/interfaces/IFoodGuard.sol";
import {Constants} from "../../src/libraries/Constants.sol";

/**
 * @title FoodGuardGovernanceTest
 * @author FoodGuard Team
 * @notice 完整的食品安全治理系统测试
 * @dev 验证流程图中的每个步骤都能正确执行
 */
contract FoodGuardGovernanceTest is Test, Constants {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CaseCreated(uint256 indexed caseId, address indexed complainant, address indexed enterprise);
    event DepositSubmitted(uint256 indexed caseId, address indexed user, uint256 amount);
    event VoteSubmitted(uint256 indexed caseId, address indexed voter, bool support);
    event ChallengeSubmitted(uint256 indexed caseId, address indexed challenger, bool challengeResult);
    event CaseCompleted(uint256 indexed caseId, bool complaintSuccessful);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    FoodGuardGovernance public governance;
    HelperConfig public helperConfig;
    AccessControl public accessControl;
    DepositManager public depositManager;
    VotingSystem public votingSystem;
    ChallengeSystem public challengeSystem;
    RewardPunishmentSystem public rewardSystem;

    // 测试用户
    address public COMPLAINANT = makeAddr("complainant");
    address public ENTERPRISE = makeAddr("enterprise");
    address public DAO_MEMBER1 = makeAddr("dao_member1");
    address public DAO_MEMBER2 = makeAddr("dao_member2");
    address public DAO_MEMBER3 = makeAddr("dao_member3");
    address public CHALLENGER = makeAddr("challenger");

    // 测试常量
    uint256 public constant STARTING_BALANCE = 100 ether;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 public constant CHALLENGE_DEPOSIT = 0.1 ether;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() external {
        // 部署系统
        DeployFoodGuard deployer = new DeployFoodGuard();
        (governance, helperConfig) = deployer.run();
        
        // 获取子系统地址
        (
            address accessControlAddr,
            address depositManagerAddr,
            address votingSystemAddr,
            address challengeSystemAddr,
            address rewardSystemAddr
        ) = governance.getSystemAddresses();
        
        accessControl = AccessControl(accessControlAddr);
        depositManager = DepositManager(depositManagerAddr);
        votingSystem = VotingSystem(votingSystemAddr);
        challengeSystem = ChallengeSystem(challengeSystemAddr);
        rewardSystem = RewardPunishmentSystem(rewardSystemAddr);

        // 为测试用户提供资金
        vm.deal(COMPLAINANT, STARTING_BALANCE);
        vm.deal(ENTERPRISE, STARTING_BALANCE);
        vm.deal(DAO_MEMBER1, STARTING_BALANCE);
        vm.deal(DAO_MEMBER2, STARTING_BALANCE);
        vm.deal(DAO_MEMBER3, STARTING_BALANCE);
        vm.deal(CHALLENGER, STARTING_BALANCE);

        // 设置用户角色
        _setupUsers();
    }

    function _setupUsers() internal {
        // 注册DAO成员
        vm.prank(DAO_MEMBER1);
        accessControl.applyForDAOMembership{value: MEMBERSHIP_FEE}();
        
        vm.prank(DAO_MEMBER2);
        accessControl.applyForDAOMembership{value: MEMBERSHIP_FEE}();
        
        vm.prank(DAO_MEMBER3);
        accessControl.applyForDAOMembership{value: MEMBERSHIP_FEE}();

        // 注册企业
        vm.prank(ENTERPRISE);
        accessControl.registerEnterprise{value: MEMBERSHIP_FEE}(
            "Test Enterprise",
            "TEST123456",
            "0x1234567890abcdef"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            STEP 1-2: 存入保证金 & 投诉
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试步骤1-2：存入保证金并提交投诉
     * 对应流程图：流程开始 -> 存入保证金 -> 投诉
     */
    function testStep1And2_DepositAndComplaint() public {
        // Step 1: 存入保证金
        vm.prank(COMPLAINANT);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);
        
        vm.prank(ENTERPRISE);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);

        // 验证保证金已存入
        (uint256 complainantBalance, , , , bool complainantActive) = depositManager.getUserDeposit(COMPLAINANT);
        (uint256 enterpriseBalance, , , , bool enterpriseActive) = depositManager.getUserDeposit(ENTERPRISE);
        
        assertEq(complainantBalance, DEPOSIT_AMOUNT);
        assertEq(enterpriseBalance, DEPOSIT_AMOUNT);
        assertTrue(complainantActive);
        assertTrue(enterpriseActive);

        // Step 2: 提交投诉
        string[] memory evidenceFiles = new string[](2);
        evidenceFiles[0] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        evidenceFiles[1] = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";

        vm.expectEmit(true, true, true, false);
        emit CaseCreated(1, COMPLAINANT, ENTERPRISE);

        vm.prank(COMPLAINANT);
        uint256 caseId = governance.createComplaint(
            ENTERPRISE,
            "Test Restaurant, Beijing",
            "Found expired food with mold contamination",
            "Photo evidence of moldy food",
            evidenceFiles
        );

        assertEq(caseId, 1);
        
        // 验证案件信息
        (
            address complainant,
            address enterprise,
            string memory location,
            string memory description,
            IFoodGuard.RiskLevel riskLevel,
            IFoodGuard.CaseStatus status,
            uint256 createTime,
            bool complaintSuccessful
        ) = governance.getCaseInfo(caseId);

        assertEq(complainant, COMPLAINANT);
        assertEq(enterprise, ENTERPRISE);
        assertEq(location, "Test Restaurant, Beijing");
        assertTrue(status >= IFoodGuard.CaseStatus.COMPLAINT_SUBMITTED);
        assertGt(createTime, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            STEP 3: 风险等级判定
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试步骤3：风险等级判定
     * 对应流程图：投诉 -> 风险等级判定
     */
    function testStep3_RiskAssessment() public {
        // 创建高风险案件
        string[] memory highRiskEvidence = new string[](5);
        for (uint i = 0; i < 5; i++) {
            highRiskEvidence[i] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        }

        vm.prank(COMPLAINANT);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);
        
        vm.prank(ENTERPRISE);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);

        vm.prank(COMPLAINANT);
        uint256 caseId = governance.createComplaint(
            ENTERPRISE,
            "Test Restaurant",
            "Customer died from food poisoning with toxic contamination", // 高风险关键词
            "Medical reports and toxicology evidence",
            highRiskEvidence
        );

        // 验证风险等级
        (, , , , IFoodGuard.RiskLevel riskLevel, , , ) = governance.getCaseInfo(caseId);
        
        // 应该被评估为高风险
        assertEq(uint256(riskLevel), uint256(IFoodGuard.RiskLevel.HIGH));
    }

    /*//////////////////////////////////////////////////////////////
                        STEP 4-5: 验证者选择与投票
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试步骤4-5：验证者选择和投票
     * 对应流程图：随机选择DAO组织成员进行投票 -> 提交证据材料并投票
     */
    function testStep4And5_ValidatorSelectionAndVoting() public {
        // 创建案件
        uint256 caseId = _createTestCase();
        
        // 检查投票状态
        (
            address[] memory validators,
            uint256 supportVotes,
            uint256 opposeVotes,
            ,
            ,
            bool isActive,
            bool isCompleted,
            
        ) = votingSystem.getCaseVotingInfo(caseId);

        assertTrue(isActive);
        assertFalse(isCompleted);
        assertGt(validators.length, 0);

        // 模拟验证者投票
        string[] memory voteEvidence = new string[](1);
        voteEvidence[0] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        // 假设第一个验证者支持投诉
        if (validators.length > 0) {
            vm.prank(validators[0]);
            governance.submitVote(
                caseId,
                true, // 支持投诉
                "Evidence supports the complaint",
                voteEvidence
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STEP 6-7: 质疑阶段
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试步骤6-7：质疑阶段
     * 对应流程图：质疑 -> 质疑投票
     */
    function testStep6And7_ChallengePhase() public {
        uint256 caseId = _createTestCase();
        
        // 等待投票完成（需要根据具体实现调整）
        _completeVotingPhase(caseId);
        
        // 检查是否进入质疑阶段
        assertTrue(challengeSystem.caseInChallengePhase(caseId));
        
        // 获取验证者列表
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        require(validators.length > 0, "No validators found");
        
        // 提交质疑
        string[] memory challengeEvidence = new string[](1);
        challengeEvidence[0] = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";

        vm.expectEmit(true, true, false, false);
        emit ChallengeSubmitted(caseId, CHALLENGER, true);

        vm.prank(CHALLENGER);
        governance.submitChallenge(
            caseId,
            validators[0], // 质疑第一个验证者
            true, // 质疑原结果
            "Evidence shows voting was incorrect",
            challengeEvidence
        );

        // 验证质疑已提交
        uint256 challengeCount = challengeSystem.getChallengeCount(caseId);
        assertGt(challengeCount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        STEP 8-11: 结果确定与奖惩
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试步骤8-11：结果确定、奖惩计算、资金分配、消息公布
     * 对应流程图：结果确定 -> 奖惩计算 -> 资金分配 -> 公布消息
     */
    function testStep8To11_FinalResultAndRewards() public {
        uint256 caseId = _createTestCase();
        
        // 完成投票和质疑阶段
        _completeVotingPhase(caseId);
        _completeChallengePhase(caseId);
        
        // 获取案件完成前的状态
        (, , , , , IFoodGuard.CaseStatus statusBefore, , bool resultBefore) = governance.getCaseInfo(caseId);
        
        // 完成案件处理
        vm.prank(governance.owner());
        governance.completeCase(caseId);
        
        // 验证案件已完成
        (, , , , , IFoodGuard.CaseStatus statusAfter, , bool resultAfter) = governance.getCaseInfo(caseId);
        assertEq(uint256(statusAfter), uint256(IFoodGuard.CaseStatus.COMPLETED));
        
        // 验证系统统计已更新
        (uint256 total, uint256 completed, uint256 successful, uint256 successRate) = governance.getSystemStats();
        assertGt(total, 0);
        assertGt(completed, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE WORKFLOW TEST
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试完整工作流程
     * 验证流程图中的所有步骤都能正确执行
     */
    function testCompleteWorkflow() public {
        // Step 1-2: 存入保证金并投诉
        testStep1And2_DepositAndComplaint();
        
        // Step 3: 风险评估
        testStep3_RiskAssessment();
        
        // Step 4-5: 验证者选择和投票
        testStep4And5_ValidatorSelectionAndVoting();
        
        // Step 6-7: 质疑阶段
        testStep6And7_ChallengePhase();
        
        // Step 8-11: 最终结果和奖惩
        testStep8To11_FinalResultAndRewards();
        
        console2.log("Complete workflow test passed!");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createTestCase() internal returns (uint256 caseId) {
        // 存入保证金
        vm.prank(COMPLAINANT);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);
        
        vm.prank(ENTERPRISE);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);

        // 创建投诉
        string[] memory evidenceFiles = new string[](2);
        evidenceFiles[0] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        evidenceFiles[1] = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";

        vm.prank(COMPLAINANT);
        caseId = governance.createComplaint(
            ENTERPRISE,
            "Test Location",
            "Test complaint description",
            "Test evidence",
            evidenceFiles
        );
        
        return caseId;
    }
    
    function _completeVotingPhase(uint256 caseId) internal {
        // 获取验证者并完成投票
        (address[] memory validators, , , , , , , ) = votingSystem.getCaseVotingInfo(caseId);
        
        string[] memory voteEvidence = new string[](1);
        voteEvidence[0] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        
        // 所有验证者投票
        for (uint i = 0; i < validators.length; i++) {
            vm.prank(validators[i]);
            governance.submitVote(caseId, true, "Vote evidence", voteEvidence);
        }
        
        // 完成投票
        votingSystem.completeVoting(caseId);
    }
    
    function _completeChallengePhase(uint256 caseId) internal {
        // 等待质疑期结束
        vm.warp(block.timestamp + CHALLENGE_PERIOD + 1);
        
        // 结束质疑阶段
        vm.prank(governance.owner());
        challengeSystem.endChallengePhase(caseId);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES & SECURITY
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 测试系统暂停功能
     */
    function testSystemPause() public {
        vm.prank(governance.owner());
        governance.pauseSystem(true);
        
        vm.expectRevert(FoodGuardGovernance.FoodGuardGovernance__SystemPaused.selector);
        vm.prank(COMPLAINANT);
        governance.submitDeposit{value: DEPOSIT_AMOUNT}(0);
    }
    
    /**
     * @dev 测试无效案件ID
     */
    function testInvalidCaseId() public {
        vm.expectRevert(FoodGuardGovernance.FoodGuardGovernance__CaseNotExists.selector);
        governance.getCaseInfo(999);
    }
    
    /**
     * @dev 测试未授权投诉
     */
    function testUnauthorizedComplaint() public {
        string[] memory evidenceFiles = new string[](1);
        evidenceFiles[0] = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        
        vm.expectRevert(FoodGuardGovernance.FoodGuardGovernance__NotAuthorizedToComplain.selector);
        vm.prank(makeAddr("unauthorized"));
        governance.createComplaint(
            ENTERPRISE,
            "Location",
            "Description",
            "Evidence",
            evidenceFiles
        );
    }
} 