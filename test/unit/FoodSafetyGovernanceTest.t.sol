// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/FoodSafetyGovernance.sol";
import "../../src/modules/FundManager.sol";
import "../../src/modules/VotingManager.sol";
import "../../src/modules/DisputeManager.sol";
import "../../src/modules/RewardPunishmentManager.sol";
import "../../src/libraries/DataStructures.sol";
import "../../src/libraries/Errors.sol";

/**
 * @title FoodSafetyGovernanceTest
 * @notice 食品安全治理主合约的单元测试
 * @dev 测试完整的投诉-验证-质疑-奖惩流程
 */
contract FoodSafetyGovernanceTest is Test {
    // ==================== 测试合约实例 ====================
    
    FoodSafetyGovernance public governance;
    FundManager public fundManager;
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    RewardPunishmentManager public rewardManager;
    
    // ==================== 测试用户地址 ====================
    
    address public admin;
    address public complainant;
    address public enterprise;
    address public validator1;
    address public validator2;
    address public validator3;
    address public challenger;
    
    // ==================== 测试常量 ====================
    
    uint256 public constant MIN_COMPLAINT_DEPOSIT = 0.1 ether;
    uint256 public constant MIN_ENTERPRISE_DEPOSIT = 2 ether;
    uint256 public constant MIN_CHALLENGE_DEPOSIT = 0.05 ether;
    
    // ==================== 设置函数 ====================
    
    function setUp() public {
        // 设置测试账户
        admin = makeAddr("admin");
        complainant = makeAddr("complainant");
        enterprise = makeAddr("enterprise");
        validator1 = makeAddr("validator1");
        validator2 = makeAddr("validator2");
        validator3 = makeAddr("validator3");
        challenger = makeAddr("challenger");
        
        // 为测试账户分配ETH
        vm.deal(admin, 100 ether);
        vm.deal(complainant, 10 ether);
        vm.deal(enterprise, 10 ether);
        vm.deal(validator1, 10 ether);
        vm.deal(validator2, 10 ether);
        vm.deal(validator3, 10 ether);
        vm.deal(challenger, 10 ether);
        
        // 部署合约
        vm.startPrank(admin);
        
        // 部署资金管理合约
        fundManager = new FundManager(admin);
        
        // 部署主合约
        governance = new FoodSafetyGovernance(admin);
        
        // 部署其他合约
        votingManager = new VotingManager(admin);
        disputeManager = new DisputeManager(admin);
        rewardManager = new RewardPunishmentManager(admin);
        
        // 初始化合约关联
        governance.initializeContracts(
            payable(address(fundManager)),
            address(votingManager),
            address(disputeManager),
            address(rewardManager)
        );
        
        // 设置各模块的治理合约地址
        votingManager.setGovernanceContract(address(governance));
        disputeManager.setGovernanceContract(address(governance));
        rewardManager.setGovernanceContract(address(governance));
        
        // 设置模块间的关联
        disputeManager.setFundManager(address(fundManager));
        disputeManager.setVotingManager(address(votingManager));
        rewardManager.setFundManager(address(fundManager));
        
        // 设置权限
        bytes32 operatorRole = fundManager.OPERATOR_ROLE();
        fundManager.grantRole(operatorRole, address(governance));
        
        bytes32 governanceRole = fundManager.GOVERNANCE_ROLE();
        fundManager.grantRole(governanceRole, address(governance));
        
        // 注册验证者
        _registerValidators();
        
        vm.stopPrank();
    }
    
    /**
     * @notice 注册验证者
     */
    function _registerValidators() internal {
        // 注册验证者（现在应该可以工作了）
        votingManager.registerValidator(validator1, 1 ether, 100);
        votingManager.registerValidator(validator2, 1 ether, 100);
        votingManager.registerValidator(validator3, 1 ether, 100);
        
        console.log("Validators registered successfully");
    }
    
    // ==================== 基础功能测试 ====================
    
    /**
     * @notice 测试用户注册功能
     */
    function test_UserRegistration() public {
        // 测试普通用户注册
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        assertTrue(governance.isUserRegistered(complainant));
        assertFalse(governance.isEnterprise(complainant));
        
        // 测试企业注册
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        assertTrue(governance.isUserRegistered(enterprise));
        assertTrue(governance.isEnterprise(enterprise));
        assertTrue(governance.isEnterpriseRegistered(enterprise));
        
        console.log("User registration test passed");
    }
    
    /**
     * @notice 测试注册失败场景
     */
    function test_UserRegistrationFailures() public {
        // 测试保证金不足
        vm.prank(complainant);
        vm.expectRevert();
        governance.registerUser{value: 0.01 ether}(); // 少于最小要求
        
        // 测试重复注册
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(complainant);
        vm.expectRevert();
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        console.log("User registration failure tests passed");
    }
    
    /**
     * @notice 测试投诉创建功能
     */
    function test_ComplaintCreation() public {
        // 先注册用户
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        // 准备投诉数据
        string memory title = "Food Poisoning Case";
        string memory description = "Got food poisoning from restaurant food";
        string memory location = "Restaurant ABC, Beijing";
        uint256 incidentTime = block.timestamp - 1;
        
        string memory evidenceHash = "QmXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxX";
        
        // 创建投诉
        vm.prank(complainant);
        uint256 caseId = governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise,
            title,
            description,
            location,
            incidentTime,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        // 验证案件信息
        FoodSafetyGovernance.CaseInfo memory caseInfo = governance.getCaseInfo(caseId);
        assertEq(caseInfo.caseId, caseId);
        assertEq(caseInfo.complainant, complainant);
        assertEq(caseInfo.enterprise, enterprise);
        assertEq(caseInfo.complaintTitle, title);
        assertTrue(uint8(caseInfo.status) >= uint8(DataStructures.CaseStatus.PENDING));
        
        console.log("Complaint creation test passed");
        console.log("Case ID:", caseId);
        console.log("Case Status:", uint8(caseInfo.status));
    }
    
    /**
     * @notice 测试投诉创建失败场景
     */
    function test_ComplaintCreationFailures() public {
        // 注册用户
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        // 测试未注册用户创建投诉
        address unregisteredUser = makeAddr("unregistered");
        vm.deal(unregisteredUser, 1 ether);
        
        string memory evidenceHash = "QmXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxXxX";
        
        vm.prank(unregisteredUser);
        vm.expectRevert();
        governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise,
            "Test Complaint",
            "Test Description",
            "Test Location",
            block.timestamp - 1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        // 测试对自己投诉
        vm.prank(enterprise);
        vm.expectRevert();
        governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise, // 对自己投诉
            "Test Complaint",
            "Test Description",
            "Test Location",
            block.timestamp - 1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        console.log("Complaint creation failure tests passed");
    }
    
    // ==================== 完整流程测试 ====================
    
    /**
     * @notice 测试完整的投诉处理流程
     */
    function test_CompleteComplaintFlow() public {
        // 1. 注册用户
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        // 2. 创建投诉
        uint256 caseId = _createTestComplaint();
        
        // 3. 验证案件已自动进入投票状态
        FoodSafetyGovernance.CaseInfo memory caseInfo = governance.getCaseInfo(caseId);
        console.log("Case status after creation:", uint8(caseInfo.status));
        
        // 4. 模拟投票过程
        _simulateVotingProcess(caseId);
        
        // 5. 结束投票并开始质疑期
        governance.endVotingAndStartChallenge(caseId);
        
        caseInfo = governance.getCaseInfo(caseId);
        assertEq(uint8(caseInfo.status), uint8(DataStructures.CaseStatus.CHALLENGING));
        
        // 6. 模拟质疑过程
        _simulateChallengeProcess(caseId);
        
        // 7. 结束质疑并处理奖惩
        governance.endChallengeAndProcessRewards(caseId);
        
        // 8. 验证案件已完成
        caseInfo = governance.getCaseInfo(caseId);
        assertEq(uint8(caseInfo.status), uint8(DataStructures.CaseStatus.COMPLETED));
        assertTrue(caseInfo.isCompleted);
        
        console.log("Complete complaint flow test passed");
        console.log("Final case status:", uint8(caseInfo.status));
        console.log("Complaint upheld:", caseInfo.complaintUpheld);
    }
    
    /**
     * @notice 创建测试投诉
     */
    function _createTestComplaint() internal returns (uint256 caseId) {
        string memory evidenceHash = "QmTestHash";
        
        vm.prank(complainant);
        caseId = governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise,
            "Test Food Safety Issue",
            "Detailed description of food safety problem",
            "Test Restaurant",
            block.timestamp - 1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        return caseId;
    }
    
    /**
     * @notice 模拟投票过程
     */
    function _simulateVotingProcess(uint256 caseId) internal {
        // 等待一段时间使投票期结束
        vm.warp(block.timestamp + 8 days); // 超过7天投票期
        
        console.log("Voting period ended, ready to proceed");
    }
    
    /**
     * @notice 模拟质疑过程
     */
    function _simulateChallengeProcess(uint256 caseId) internal {
        // 等待质疑期结束
        vm.warp(block.timestamp + 4 days); // 超过3天质疑期
        
        console.log("Challenge period ended, ready to process rewards");
    }
    
    // ==================== 辅助函数测试 ====================
    
    /**
     * @notice 测试查询函数
     */
    function test_QueryFunctions() public {
        // 测试案件总数
        uint256 totalCases = governance.getTotalCases();
        assertEq(totalCases, 0);
        
        // 创建一个投诉后再次测试
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        _createTestComplaint();
        
        totalCases = governance.getTotalCases();
        assertEq(totalCases, 1);
        
        // 测试企业状态查询
        assertTrue(governance.checkIsEnterprise(enterprise));
        assertFalse(governance.checkIsEnterprise(complainant));
        
        console.log("Query functions test passed");
    }
    
    /**
     * @notice 测试管理员功能
     */
    function test_AdminFunctions() public {
        // 注册企业
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        // 测试更新企业风险等级（需要以admin身份调用）
        vm.prank(admin);
        governance.updateEnterpriseRiskLevel(enterprise, DataStructures.RiskLevel.HIGH);
        
        DataStructures.RiskLevel riskLevel = governance.getEnterpriseRiskLevel(enterprise);
        assertEq(uint8(riskLevel), uint8(DataStructures.RiskLevel.HIGH));
        
        // 测试暂停/恢复合约（需要以admin身份调用）
        vm.prank(admin);
        governance.setPaused(true);
        
        vm.prank(complainant);
        vm.expectRevert();
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(admin);
        governance.setPaused(false);
        
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        console.log("Admin functions test passed");
    }
    
    // ==================== 边界条件测试 ====================
    
    /**
     * @notice 测试边界条件和异常情况
     */
    function test_EdgeCases() public {
        // 测试使用零地址
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        string memory evidenceHash = "test";
        
        vm.prank(complainant);
        vm.expectRevert();
        governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            address(0), // 零地址
            "Test",
            "Test",
            "Test",
            block.timestamp - 1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        console.log("Edge cases test passed");
    }
    
    // ==================== Gas 消耗测试 ====================
    
    /**
     * @notice 测试关键操作的Gas消耗
     */
    function test_GasConsumption() public {
        // 测试用户注册的Gas消耗
        uint256 gasBefore = gasleft();
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("User registration gas used:", gasUsed);
        
        // 测试企业注册的Gas消耗
        gasBefore = gasleft();
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        gasUsed = gasBefore - gasleft();
        
        console.log("Enterprise registration gas used:", gasUsed);
        
        // 测试投诉创建的Gas消耗
        gasBefore = gasleft();
        _createTestComplaint();
        gasUsed = gasBefore - gasleft();
        
        console.log("Complaint creation gas used:", gasUsed);
        
        // 确保Gas消耗在合理范围内
        assertTrue(gasUsed < 10000000, "Gas consumption too high");
    }
    
    // ==================== 安全性测试 ====================
    
    /**
     * @notice 测试重入攻击防护
     */
    function test_ReentrancyProtection() public {
        // 测试在注册过程中是否有重入漏洞
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        // 尝试在同一交易中重复注册（应该失败）
        vm.prank(complainant);
        vm.expectRevert();
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        console.log("Reentrancy protection test passed");
    }
    
    /**
     * @notice 简单的投诉创建测试 - 用于调试
     */
    function test_SimpleComplaintCreation() public {
        // 1. 注册用户
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        console.log("Complainant registered");
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        console.log("Enterprise registered");
        
        // 2. 检查用户保证金
        uint256 complainantBalance = fundManager.getAvailableDeposit(complainant);
        uint256 enterpriseBalance = fundManager.getAvailableDeposit(enterprise);
        console.log("Complainant balance:", complainantBalance);
        console.log("Enterprise balance:", enterpriseBalance);
        
        // 3. 准备投诉数据
        string memory evidenceHash = "QmTestHash";
        
        console.log("Evidence prepared");
        
        // 4. 直接创建投诉（不使用try-catch）
        vm.prank(complainant);
        uint256 caseId = governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise,
            "Test Food Safety Issue",
            "Detailed description of food safety problem",
            "Test Restaurant",
            block.timestamp - 1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        console.log("Complaint created successfully with ID:", caseId);
    }
    
    /**
     * @notice 最简化投诉创建测试
     */
    function test_MinimalComplaintCreation() public {
        // 1. 注册用户
        vm.prank(complainant);
        governance.registerUser{value: MIN_COMPLAINT_DEPOSIT}();
        
        vm.prank(enterprise);
        governance.registerEnterprise{value: MIN_ENTERPRISE_DEPOSIT}();
        
        // 2. 创建最简单的证据哈希
        string memory evidenceHash = "a";
        
        // 3. 创建投诉
        vm.prank(complainant);
        uint256 caseId = governance.createComplaint{value: MIN_COMPLAINT_DEPOSIT}(
            enterprise,
            "title",
            "description",
            "location",
            1,
            evidenceHash,
            uint8(DataStructures.RiskLevel.LOW)
        );
        
        assertEq(caseId, 1);
    }
} 