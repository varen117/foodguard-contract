// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/FoodSafetyGovernance.sol";
import "../../src/modules/FundManager.sol";
import "../../src/modules/VotingDisputeManager.sol";
import "../../src/modules/RewardPunishmentManager.sol";
import "../../src/modules/ParticipantPoolManager.sol";
import "../../src/libraries/DataStructures.sol";
import "../helpers/TestHelper.sol";

/**
 * @title SystemIntegrationTest
 * @notice 食品安全治理系统的完整集成测试
 * @dev 测试从投诉提交到案件结案的完整流程
 */
contract SystemIntegrationTest is TestHelper {
    
    // 合约实例
    FoodSafetyGovernance public governance;
    FundManager public fundManager;
    VotingDisputeManager public votingManager;
    RewardPunishmentManager public rewardManager;
    ParticipantPoolManager public poolManager;
    
    // 测试状态追踪
    uint256 public testCaseId;
    uint256 public initialComplainantBalance;
    uint256 public initialEnterpriseBalance;
    
    function setUp() public {
        logTestStep("Setting up Integration Test Environment");
        
        setupTestAccounts();
        
        // 部署所有合约
        _deployContracts();
        
        // 建立合约关联
        _setupContractRelations();
        
        // 注册测试参与者
        registerTestParticipants(governance);
        
        // 记录初始余额
        initialComplainantBalance = COMPLAINANT.balance;
        initialEnterpriseBalance = ENTERPRISE.balance;
        
        console.log("Integration test environment setup completed");
    }
    
    /**
     * @notice 测试完整的投诉成立流程
     * @dev 模拟一个投诉案件从提交到结案的完整过程，投诉成立
     */
    function test_CompleteComplaintUpheldFlow() public {
        logTestStep("Starting Complete Complaint Upheld Flow Test");
        
        // 第一阶段：提交投诉
        _submitComplaint();
        
        // 第二阶段：DAO投票（支持投诉）
        _executeVoting(true); // true = 支持投诉
        
        // 第三阶段：结束投票期
        _endVotingPhase();
        
        // 第四阶段：质疑期（无质疑）
        _skipChallengePhase();
        
        // 第五阶段：执行奖惩
        _executeRewardPunishment(true); // true = 投诉成立
        
        // 第六阶段：验证最终结果
        _verifyComplaintUpheldResults();
        
        console.log("Complete complaint upheld flow test passed");
    }
    
    /**
     * @notice 测试完整的投诉不成立流程
     */
    function test_CompleteComplaintRejectedFlow() public {
        logTestStep("Starting Complete Complaint Rejected Flow Test");
        
        // 第一阶段：提交投诉
        _submitComplaint();
        
        // 第二阶段：DAO投票（拒绝投诉）
        _executeVoting(false); // false = 拒绝投诉
        
        // 第三阶段：结束投票期
        _endVotingPhase();
        
        // 第四阶段：质疑期（无质疑）
        _skipChallengePhase();
        
        // 第五阶段：执行奖惩
        _executeRewardPunishment(false); // false = 投诉不成立
        
        // 第六阶段：验证最终结果
        _verifyComplaintRejectedResults();
        
        console.log("Complete complaint rejected flow test passed");
    }
    
    /**
     * @notice 测试投票后有质疑的流程
     */
    function test_ComplaintWithChallengeFlow() public {
        logTestStep("Starting Complaint With Challenge Flow Test");
        
        // 提交投诉并投票（支持）
        _submitComplaint();
        _executeVoting(true);
        _endVotingPhase();
        
        // 提交质疑
        vm.startPrank(ENTERPRISE);
        governance.submitChallenge{value: DEFAULT_DEPOSIT}(
            testCaseId,
            DAO_MEMBER1, // 质疑目标
            DataStructures.ChallengeChoice.ChangeToReject,
            "Challenge reason: insufficient evidence"
        );
        vm.stopPrank();
        
        // 验证质疑提交成功
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.InChallenge);
        
        // 结束质疑期
        skipToChallengeEnd();
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        // 验证进入奖惩阶段
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.PendingRewardPunishment);
        
        console.log("Complaint with challenge flow test passed");
    }
    
    /**
     * @notice 测试风险等级对奖惩的影响
     */
    function test_RiskLevelImpactOnRewardPunishment() public {
        logTestStep("Testing Risk Level Impact on Reward Punishment");
        
        // 测试高风险案件
        _testRiskLevelCase(DataStructures.RiskLevel.High);
        
        // 测试中风险案件
        _testRiskLevelCase(DataStructures.RiskLevel.Medium);
        
        // 测试低风险案件
        _testRiskLevelCase(DataStructures.RiskLevel.Low);
        
        console.log("Risk level impact test passed");
    }
    
    /**
     * @notice 测试自动执行功能
     */
    function test_AutoExecutionFlow() public {
        logTestStep("Testing Auto Execution Flow");
        
        _submitComplaint();
        _executeVoting(true);
        
        // 等待投票期结束
        skipToVotingEnd();
        
        // 触发自动执行
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        // 验证投票自动结束
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.InChallenge);
        
        // 等待质疑期结束
        skipToChallengeEnd();
        
        // 再次触发自动执行
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        // 验证质疑期自动结束
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.PendingRewardPunishment);
        
        console.log("Auto execution flow test passed");
    }
    
    /**
     * @notice 测试系统在极端情况下的表现
     */
    function test_SystemEdgeCases() public {
        logTestStep("Testing System Edge Cases");
        
        // 测试最小保证金边界
        _testMinimumDepositBoundary();
        
        // 测试同时处理多个案件
        _testMultipleCasesHandling();
        
        // 测试参与者保证金不足的情况
        _testInsufficientDepositScenario();
        
        console.log("System edge cases test passed");
    }
    
    // ==================== 内部辅助函数 ====================
    
    function _deployContracts() internal {
        vm.startPrank(ADMIN);
        
        // 部署模块合约
        fundManager = new FundManager(ADMIN);
        votingManager = new VotingDisputeManager(ADMIN);
        rewardManager = new RewardPunishmentManager(ADMIN);
        poolManager = new ParticipantPoolManager(ADMIN);
        
        // 部署主治理合约
        governance = new FoodSafetyGovernance(ADMIN);
        
        vm.stopPrank();
        
        console.log("All contracts deployed successfully");
    }
    
    function _setupContractRelations() internal {
        vm.startPrank(ADMIN);
        
        // 初始化治理合约的模块地址
        governance.initializeContracts(
            payable(address(fundManager)),
            address(votingManager),
            address(rewardManager),
            address(poolManager)
        );
        
        // 设置治理合约地址到各模块
        fundManager.setGovernanceContract(address(governance));
        votingManager.setGovernanceContract(address(governance));
        rewardManager.setGovernanceContract(address(governance));
        poolManager.setGovernanceContract(address(governance));
        
        // 设置模块间依赖
        votingManager.setFundManager(address(fundManager));
        votingManager.setPoolManager(address(poolManager));
        
        vm.stopPrank();
        
        console.log("Contract relations established");
    }
    
    function _submitComplaint() internal {
        logTestStep("Submitting Complaint");
        
        vm.startPrank(COMPLAINANT);
        testCaseId = governance.submitComplaint{value: DEFAULT_DEPOSIT}(
            ENTERPRISE,
            TEST_CASE_DESCRIPTION,
            TEST_EVIDENCE
        );
        vm.stopPrank();
        
        // 验证投诉提交成功
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.UnderReview);
        console.log("Complaint submitted with case ID:", testCaseId);
    }
    
    function _executeVoting(bool support) internal {
        logTestStep(support ? "Executing Voting (Support)" : "Executing Voting (Reject)");
        
        executeTestVoting(governance, testCaseId, support);
        
        console.log("Voting completed with support:", support);
    }
    
    function _endVotingPhase() internal {
        logTestStep("Ending Voting Phase");
        
        skipToVotingEnd();
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.InChallenge);
        console.log("Voting phase ended");
    }
    
    function _skipChallengePhase() internal {
        logTestStep("Skipping Challenge Phase");
        
        skipToChallengeEnd();
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.PendingRewardPunishment);
        console.log("Challenge phase skipped");
    }
    
    function _executeRewardPunishment(bool complaintUpheld) internal {
        logTestStep("Executing Reward Punishment");
        
        address[] memory daoRewards = new address[](3);
        daoRewards[0] = DAO_MEMBER1;
        daoRewards[1] = DAO_MEMBER2;
        daoRewards[2] = DAO_MEMBER3;
        
        vm.prank(ADMIN);
        governance.processCaseRewardPunishment(
            testCaseId,
            complaintUpheld ? COMPLAINANT : address(0), // 投诉者奖励
            complaintUpheld ? address(0) : COMPLAINANT, // 投诉者惩罚
            complaintUpheld ? address(0) : ENTERPRISE,  // 企业奖励
            complaintUpheld ? ENTERPRISE : address(0),  // 企业惩罚
            daoRewards,                                 // DAO成员奖励
            new address[](0),                          // DAO成员惩罚
            complaintUpheld,
            DataStructures.RiskLevel.Medium
        );
        
        assertCaseStatus(governance, testCaseId, DataStructures.CaseStatus.Completed);
        console.log("Reward punishment executed");
    }
    
    function _verifyComplaintUpheldResults() internal {
        logTestStep("Verifying Complaint Upheld Results");
        
        // 验证案件状态
        DataStructures.ComplaintCase memory complaintCase = governance.getComplaintCase(testCaseId);
        assertTrue(complaintCase.complaintUpheld);
        assertEq(uint256(complaintCase.status), uint256(DataStructures.CaseStatus.Completed));
        
        // 验证余额变化（投诉者应该获得奖励）
        assertTrue(COMPLAINANT.balance > initialComplainantBalance);
        assertTrue(ENTERPRISE.balance < initialEnterpriseBalance);
        
        console.log("Complaint upheld results verified");
    }
    
    function _verifyComplaintRejectedResults() internal {
        logTestStep("Verifying Complaint Rejected Results");
        
        // 验证案件状态
        DataStructures.ComplaintCase memory complaintCase = governance.getComplaintCase(testCaseId);
        assertFalse(complaintCase.complaintUpheld);
        assertEq(uint256(complaintCase.status), uint256(DataStructures.CaseStatus.Completed));
        
        // 验证余额变化（企业应该获得奖励）
        assertTrue(ENTERPRISE.balance > initialEnterpriseBalance);
        assertTrue(COMPLAINANT.balance < initialComplainantBalance);
        
        console.log("Complaint rejected results verified");
    }
    
    function _testRiskLevelCase(DataStructures.RiskLevel riskLevel) internal {
        // 提交不同风险等级的投诉并完成流程
        uint256 initialFundPool = fundManager.getFundPoolBalance();
        
        vm.startPrank(COMPLAINANT);
        uint256 caseId = governance.submitComplaint{value: DEFAULT_DEPOSIT}(
            ENTERPRISE,
            string.concat("Risk level test: ", _riskLevelToString(riskLevel)),
            TEST_EVIDENCE
        );
        vm.stopPrank();
        
        // 完成投票和质疑阶段
        executeTestVoting(governance, caseId, true);
        skipToVotingEnd();
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        skipToChallengeEnd();
        vm.prank(ADMIN);
        governance.triggerAutoExecution();
        
        // 执行奖惩
        address[] memory daoRewards = new address[](1);
        daoRewards[0] = DAO_MEMBER1;
        
        vm.prank(ADMIN);
        governance.processCaseRewardPunishment(
            caseId,
            COMPLAINANT,     // 投诉者奖励
            address(0),      // 投诉者惩罚
            address(0),      // 企业奖励
            ENTERPRISE,      // 企业惩罚
            daoRewards,      // DAO成员奖励
            new address[](0), // DAO成员惩罚
            true,            // 投诉成立
            riskLevel
        );
        
        // 验证基金池增长（不同风险等级应有不同的影响）
        uint256 finalFundPool = fundManager.getFundPoolBalance();
        assertTrue(finalFundPool > initialFundPool);
        
        console.log("Risk level", _riskLevelToString(riskLevel), "test completed");
    }
    
    function _testMinimumDepositBoundary() internal {
        uint256 minDeposit = fundManager.getSystemConfig().minDeposit;
        
        // 测试刚好满足最小保证金
        vm.startPrank(RANDOM_USER);
        governance.registerParticipant{value: minDeposit}(
            DataStructures.UserRole.Complainant,
            "Minimum Deposit User"
        );
        vm.stopPrank();
        
        assertUserRole(governance, RANDOM_USER, DataStructures.UserRole.Complainant);
    }
    
    function _testMultipleCasesHandling() internal {
        // 同时提交多个投诉案件
        uint256[] memory caseIds = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(COMPLAINANT);
            caseIds[i] = governance.submitComplaint{value: DEFAULT_DEPOSIT}(
                ENTERPRISE,
                string.concat("Multiple case test ", vm.toString(i)),
                TEST_EVIDENCE
            );
            vm.stopPrank();
        }
        
        // 验证所有案件都在审核中
        for (uint i = 0; i < 3; i++) {
            assertCaseStatus(governance, caseIds[i], DataStructures.CaseStatus.UnderReview);
        }
    }
    
    function _testInsufficientDepositScenario() internal {
        // 消耗用户的保证金
        vm.startPrank(ADMIN);
        fundManager.withdrawDeposit(COMPLAINANT, fundManager.getUserDeposit(COMPLAINANT) - 1 ether);
        vm.stopPrank();
        
        // 尝试提交需要更多保证金的投诉应该失败
        vm.expectRevert();
        vm.startPrank(COMPLAINANT);
        governance.submitComplaint{value: DEFAULT_DEPOSIT}(
            ENTERPRISE,
            "Insufficient deposit test",
            TEST_EVIDENCE
        );
        vm.stopPrank();
    }
    
    function _riskLevelToString(DataStructures.RiskLevel level) internal pure returns (string memory) {
        if (level == DataStructures.RiskLevel.Low) return "Low";
        if (level == DataStructures.RiskLevel.Medium) return "Medium";
        if (level == DataStructures.RiskLevel.High) return "High";
        return "Unknown";
    }
} 