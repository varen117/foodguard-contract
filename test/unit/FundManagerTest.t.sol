// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/modules/FundManager.sol";
import "../../src/libraries/DataStructures.sol";
import "../helpers/TestHelper.sol";

/**
 * @title FundManagerTest
 * @notice FundManager模块的单元测试
 */
contract FundManagerTest is TestHelper {
    
    FundManager public fundManager;
    address public governance;
    
    event DepositMade(
        address indexed user,
        uint256 amount,
        uint256 totalDeposit,
        uint256 timestamp
    );
    
    event DepositFrozen(
        uint256 indexed caseId,
        address indexed user,
        uint256 amount,
        DataStructures.RiskLevel riskLevel,
        uint256 timestamp
    );
    
    function setUp() public {
        setupTestAccounts();
        governance = ADMIN;
        
        // 部署FundManager合约
        vm.prank(ADMIN);
        fundManager = new FundManager(ADMIN);
        
        // 设置治理合约地址
        vm.prank(ADMIN);
        fundManager.setGovernanceContract(governance);
    }
    
    /**
     * @notice 测试用户保证金存入
     */
    function test_MakeDeposit() public {
        logTestStep("Test Make Deposit");
        
        uint256 depositAmount = DEFAULT_DEPOSIT;
        
        // 验证存入前状态
        assertEq(fundManager.getUserDeposit(COMPLAINANT), 0);
        
        // 执行存入操作
        vm.expectEmit(true, false, false, true);
        emit DepositMade(COMPLAINANT, depositAmount, depositAmount, block.timestamp);
        
        vm.prank(governance);
        fundManager.makeDeposit{value: depositAmount}(COMPLAINANT);
        
        // 验证存入后状态
        assertEq(fundManager.getUserDeposit(COMPLAINANT), depositAmount);
        assertEq(address(fundManager).balance, depositAmount);
    }
    
    /**
     * @notice 测试冻结保证金
     */
    function test_FreezeDeposit() public {
        logTestStep("Test Freeze Deposit");
        
        uint256 depositAmount = DEFAULT_DEPOSIT;
        uint256 caseId = 1;
        DataStructures.RiskLevel riskLevel = DataStructures.RiskLevel.High;
        
        // 先存入保证金
        vm.prank(governance);
        fundManager.makeDeposit{value: depositAmount}(ENTERPRISE);
        
        // 冻结保证金
        vm.expectEmit(true, true, false, true);
        emit DepositFrozen(caseId, ENTERPRISE, depositAmount, riskLevel, block.timestamp);
        
        vm.prank(governance);
        fundManager.freezeDeposit(caseId, ENTERPRISE, depositAmount, riskLevel);
        
        // 验证冻结状态
        assertEq(fundManager.getCaseFrozenDeposit(caseId, ENTERPRISE), depositAmount);
        assertEq(fundManager.getUserDeposit(ENTERPRISE), 0); // 可用保证金减少
    }
    
    /**
     * @notice 测试解冻保证金
     */
    function test_UnfreezeDeposit() public {
        logTestStep("Test Unfreeze Deposit");
        
        uint256 depositAmount = DEFAULT_DEPOSIT;
        uint256 caseId = 1;
        DataStructures.RiskLevel riskLevel = DataStructures.RiskLevel.Medium;
        
        // 先存入并冻结保证金
        vm.startPrank(governance);
        fundManager.makeDeposit{value: depositAmount}(ENTERPRISE);
        fundManager.freezeDeposit(caseId, ENTERPRISE, depositAmount, riskLevel);
        vm.stopPrank();
        
        // 解冻保证金
        vm.prank(governance);
        fundManager.unfreezeDeposit(caseId, ENTERPRISE, depositAmount);
        
        // 验证解冻状态
        assertEq(fundManager.getCaseFrozenDeposit(caseId, ENTERPRISE), 0);
        assertEq(fundManager.getUserDeposit(ENTERPRISE), depositAmount);
    }
    
    /**
     * @notice 测试添加奖励到保证金
     */
    function test_AddRewardToDeposit() public {
        logTestStep("Test Add Reward To Deposit");
        
        uint256 initialDeposit = DEFAULT_DEPOSIT;
        uint256 rewardAmount = 500 ether;
        
        // 先存入初始保证金
        vm.prank(governance);
        fundManager.makeDeposit{value: initialDeposit}(COMPLAINANT);
        
        // 添加奖励到保证金
        vm.prank(governance);
        fundManager.addRewardToDeposit(COMPLAINANT, rewardAmount);
        
        // 验证保证金增加
        assertEq(fundManager.getUserDeposit(COMPLAINANT), initialDeposit + rewardAmount);
    }
    
    /**
     * @notice 测试提取保证金
     */
    function test_WithdrawDeposit() public {
        logTestStep("Test Withdraw Deposit");
        
        uint256 depositAmount = DEFAULT_DEPOSIT;
        uint256 withdrawAmount = 300 ether;
        
        // 先存入保证金
        vm.prank(governance);
        fundManager.makeDeposit{value: depositAmount}(COMPLAINANT);
        
        uint256 initialBalance = COMPLAINANT.balance;
        
        // 提取部分保证金
        vm.prank(governance);
        fundManager.withdrawDeposit(COMPLAINANT, withdrawAmount);
        
        // 验证提取结果
        assertEq(fundManager.getUserDeposit(COMPLAINANT), depositAmount - withdrawAmount);
        assertEq(COMPLAINANT.balance, initialBalance + withdrawAmount);
    }
    
    /**
     * @notice 测试添加资金到基金池
     */
    function test_AddToFundPool() public {
        logTestStep("Test Add To Fund Pool");
        
        uint256 addAmount = 1000 ether;
        string memory source = "Punishment from case 1";
        
        uint256 initialPool = fundManager.getFundPoolBalance();
        
        // 添加资金到基金池
        vm.prank(governance);
        fundManager.addToFundPool(addAmount, source);
        
        // 验证基金池增加
        assertEq(fundManager.getFundPoolBalance(), initialPool + addAmount);
    }
    
    /**
     * @notice 测试从基金池转移资金
     */
    function test_TransferFromFundPool() public {
        logTestStep("Test Transfer From Fund Pool");
        
        uint256 addAmount = 2000 ether;
        uint256 transferAmount = 800 ether;
        string memory purpose = "Reward distribution";
        
        // 先向基金池添加资金
        vm.prank(governance);
        fundManager.addToFundPool(addAmount, "Initial funding");
        
        uint256 initialBalance = DAO_MEMBER1.balance;
        
        // 从基金池转移资金
        vm.prank(governance);
        fundManager.transferFromFundPool(DAO_MEMBER1, transferAmount, purpose);
        
        // 验证转移结果
        assertEq(fundManager.getFundPoolBalance(), addAmount - transferAmount);
        assertEq(DAO_MEMBER1.balance, initialBalance + transferAmount);
    }
    
    /**
     * @notice 测试获取系统配置
     */
    function test_GetSystemConfig() public {
        logTestStep("Test Get System Config");
        
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        
        // 验证默认配置值
        assertEq(config.minDeposit, 100 ether);
        assertEq(config.votingDuration, 7 days);
        assertEq(config.challengeDuration, 3 days);
        assertTrue(config.minValidators > 0);
    }
    
    /**
     * @notice 测试权限控制
     */
    function test_OnlyGovernanceAccess() public {
        logTestStep("Test Only Governance Access");
        
        // 测试非治理合约调用会失败
        vm.expectRevert();
        vm.prank(RANDOM_USER);
        fundManager.makeDeposit{value: DEFAULT_DEPOSIT}(COMPLAINANT);
        
        vm.expectRevert();
        vm.prank(RANDOM_USER);
        fundManager.freezeDeposit(1, ENTERPRISE, DEFAULT_DEPOSIT, DataStructures.RiskLevel.Medium);
    }
    
    /**
     * @notice 测试零值操作的错误处理
     */
    function test_ZeroValueOperations() public {
        logTestStep("Test Zero Value Operations");
        
        // 测试零金额存入
        vm.expectRevert();
        vm.prank(governance);
        fundManager.makeDeposit{value: 0}(COMPLAINANT);
        
        // 测试零金额提取
        vm.prank(governance);
        fundManager.makeDeposit{value: DEFAULT_DEPOSIT}(COMPLAINANT);
        
        vm.expectRevert();
        vm.prank(governance);
        fundManager.withdrawDeposit(COMPLAINANT, 0);
    }
    
    /**
     * @notice 测试保证金不足的情况
     */
    function test_InsufficientDeposit() public {
        logTestStep("Test Insufficient Deposit");
        
        uint256 depositAmount = 500 ether;
        uint256 freezeAmount = 800 ether; // 超过存入金额
        
        // 存入保证金
        vm.prank(governance);
        fundManager.makeDeposit{value: depositAmount}(ENTERPRISE);
        
        // 尝试冻结超额保证金应该失败
        vm.expectRevert();
        vm.prank(governance);
        fundManager.freezeDeposit(1, ENTERPRISE, freezeAmount, DataStructures.RiskLevel.High);
    }
    
    /**
     * @notice 测试多次操作的累积效果
     */
    function test_MultipleOperations() public {
        logTestStep("Test Multiple Operations");
        
        uint256 deposit1 = 500 ether;
        uint256 deposit2 = 300 ether;
        uint256 reward = 200 ether;
        
        // 多次存入
        vm.startPrank(governance);
        fundManager.makeDeposit{value: deposit1}(COMPLAINANT);
        fundManager.makeDeposit{value: deposit2}(COMPLAINANT);
        
        // 添加奖励
        fundManager.addRewardToDeposit(COMPLAINANT, reward);
        vm.stopPrank();
        
        // 验证累计效果
        assertEq(fundManager.getUserDeposit(COMPLAINANT), deposit1 + deposit2 + reward);
    }
} 