// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/FoodSafetyGovernance.sol";
import "../../src/libraries/DataStructures.sol";
import "../../src/libraries/Events.sol";

/**
 * @title TestHelper
 * @notice 测试辅助工具合约，提供通用的测试功能
 */
contract TestHelper is Test {
    
    // 测试账户
    address public constant ADMIN = address(0x1);
    address public constant COMPLAINANT = address(0x2);
    address public constant ENTERPRISE = address(0x3);
    address public constant DAO_MEMBER1 = address(0x4);
    address public constant DAO_MEMBER2 = address(0x5);
    address public constant DAO_MEMBER3 = address(0x6);
    address public constant RANDOM_USER = address(0x7);
    
    // 测试数据
    uint256 public constant DEFAULT_DEPOSIT = 1000 ether;
    uint256 public constant MIN_DEPOSIT = 100 ether;
    string public constant TEST_CASE_DESCRIPTION = "Test food safety violation";
    string public constant TEST_EVIDENCE = "Evidence hash: QmTestHash";
    
    /**
     * @notice 设置测试账户的初始余额
     */
    function setupTestAccounts() public {
        vm.deal(ADMIN, 10000 ether);
        vm.deal(COMPLAINANT, 5000 ether);
        vm.deal(ENTERPRISE, 5000 ether);
        vm.deal(DAO_MEMBER1, 5000 ether);
        vm.deal(DAO_MEMBER2, 5000 ether);
        vm.deal(DAO_MEMBER3, 5000 ether);
        vm.deal(RANDOM_USER, 5000 ether);
    }
    
    /**
     * @notice 创建测试用的投诉案件
     */
    function createTestComplaint(FoodSafetyGovernance governance) public returns (uint256 caseId) {
        vm.startPrank(COMPLAINANT);
        caseId = governance.submitComplaint{value: DEFAULT_DEPOSIT}(
            ENTERPRISE,
            TEST_CASE_DESCRIPTION,
            TEST_EVIDENCE
        );
        vm.stopPrank();
    }
    
    /**
     * @notice 注册测试用的参与者
     */
    function registerTestParticipants(FoodSafetyGovernance governance) public {
        // 注册投诉者
        vm.startPrank(COMPLAINANT);
        governance.registerParticipant{value: DEFAULT_DEPOSIT}(
            DataStructures.UserRole.Complainant,
            "Test Complainant"
        );
        vm.stopPrank();
        
        // 注册企业
        vm.startPrank(ENTERPRISE);
        governance.registerParticipant{value: DEFAULT_DEPOSIT}(
            DataStructures.UserRole.Enterprise,
            "Test Enterprise"
        );
        vm.stopPrank();
        
        // 注册DAO成员
        vm.startPrank(DAO_MEMBER1);
        governance.registerParticipant{value: DEFAULT_DEPOSIT}(
            DataStructures.UserRole.DAOMember,
            "DAO Member 1"
        );
        vm.stopPrank();
        
        vm.startPrank(DAO_MEMBER2);
        governance.registerParticipant{value: DEFAULT_DEPOSIT}(
            DataStructures.UserRole.DAOMember,
            "DAO Member 2"
        );
        vm.stopPrank();
        
        vm.startPrank(DAO_MEMBER3);
        governance.registerParticipant{value: DEFAULT_DEPOSIT}(
            DataStructures.UserRole.DAOMember,
            "DAO Member 3"
        );
        vm.stopPrank();
    }
    
    /**
     * @notice 执行测试投票
     */
    function executeTestVoting(FoodSafetyGovernance governance, uint256 caseId, bool support) public {
        vm.startPrank(DAO_MEMBER1);
        governance.vote(caseId, support);
        vm.stopPrank();
        
        vm.startPrank(DAO_MEMBER2);
        governance.vote(caseId, support);
        vm.stopPrank();
        
        vm.startPrank(DAO_MEMBER3);
        governance.vote(caseId, support);
        vm.stopPrank();
    }
    
    /**
     * @notice 快进时间到投票结束
     */
    function skipToVotingEnd() public {
        vm.warp(block.timestamp + 8 days); // 7天投票期 + 1天缓冲
    }
    
    /**
     * @notice 快进时间到质疑期结束
     */
    function skipToChallengeEnd() public {
        vm.warp(block.timestamp + 4 days); // 3天质疑期 + 1天缓冲
    }
    
    /**
     * @notice 验证案件状态
     */
    function assertCaseStatus(
        FoodSafetyGovernance governance,
        uint256 caseId,
        DataStructures.CaseStatus expectedStatus
    ) public {
        DataStructures.ComplaintCase memory complaintCase = governance.getComplaintCase(caseId);
        assertEq(uint256(complaintCase.status), uint256(expectedStatus));
    }
    
    /**
     * @notice 验证用户角色
     */
    function assertUserRole(
        FoodSafetyGovernance governance,
        address user,
        DataStructures.UserRole expectedRole
    ) public {
        DataStructures.Participant memory participant = governance.getParticipant(user);
        assertEq(uint256(participant.role), uint256(expectedRole));
    }
    
    /**
     * @notice 获取测试用的风险等级数组
     */
    function getRiskLevels() public pure returns (DataStructures.RiskLevel[] memory) {
        DataStructures.RiskLevel[] memory levels = new DataStructures.RiskLevel[](3);
        levels[0] = DataStructures.RiskLevel.Low;
        levels[1] = DataStructures.RiskLevel.Medium;
        levels[2] = DataStructures.RiskLevel.High;
        return levels;
    }
    
    /**
     * @notice 创建测试用的地址数组
     */
    function createAddressArray(address addr1, address addr2) public pure returns (address[] memory) {
        address[] memory array = new address[](2);
        array[0] = addr1;
        array[1] = addr2;
        return array;
    }
    
    /**
     * @notice 创建单个地址的数组
     */
    function createSingleAddressArray(address addr) public pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = addr;
        return array;
    }
    
    /**
     * @notice 验证合约余额变化
     */
    function assertBalanceChange(
        address account,
        uint256 initialBalance,
        int256 expectedChange
    ) public {
        uint256 currentBalance = account.balance;
        if (expectedChange >= 0) {
            assertEq(currentBalance, initialBalance + uint256(expectedChange));
        } else {
            assertEq(currentBalance, initialBalance - uint256(-expectedChange));
        }
    }
    
    /**
     * @notice 记录测试日志
     */
    function logTestStep(string memory step) public {
        console.log(string.concat("=== ", step, " ==="));
    }
    
    /**
     * @notice 验证合约部署状态
     */
    function assertContractDeployed(address contractAddr) public {
        uint256 codeSize;
        assembly { codeSize := extcodesize(contractAddr) }
        assertGt(codeSize, 0, "Contract not deployed");
    }
} 