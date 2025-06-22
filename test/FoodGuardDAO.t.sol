// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FoodGuardDAO.sol";
import "../src/RiskAssessment.sol";
import "../src/RandomSelector.sol";

contract FoodGuardDAOTest is Test {
    FoodGuardDAO public dao;
    RiskAssessment public riskAssessment;
    RandomSelector public randomSelector;
    
    address public owner;
    address public company1;
    address public company2;
    address public complainant1;
    address public complainant2;
    address public daoMember1;
    address public daoMember2;
    address public daoMember3;
    address public staker1;
    address public staker2;
    
    uint256 public constant MIN_INDIVIDUAL_DEPOSIT = 0.1 ether;
    uint256 public constant MIN_COMPANY_DEPOSIT = 1.0 ether;
    
    function setUp() public {
        owner = address(this);
        company1 = makeAddr("company1");
        company2 = makeAddr("company2");
        complainant1 = makeAddr("complainant1");
        complainant2 = makeAddr("complainant2");
        daoMember1 = makeAddr("daoMember1");
        daoMember2 = makeAddr("daoMember2");
        daoMember3 = makeAddr("daoMember3");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        
        // Deploy contracts
        dao = new FoodGuardDAO();
        riskAssessment = new RiskAssessment();
        randomSelector = new RandomSelector();
        
        // Setup DAO members
        dao.addDAOMember(daoMember1);
        dao.addDAOMember(daoMember2);
        dao.addDAOMember(daoMember3);
        
        // Unpause contract
        dao.unpause();
        
        // Give test accounts some ETH
        vm.deal(company1, 10 ether);
        vm.deal(company2, 10 ether);
        vm.deal(complainant1, 10 ether);
        vm.deal(complainant2, 10 ether);
        vm.deal(staker1, 10 ether);
        vm.deal(staker2, 10 ether);
    }
    
    function testDepositGuarantee() public {
        vm.startPrank(company1);
        
        uint256 initialBalance = dao.depositBalances(company1);
        assertEq(initialBalance, 0);
        
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT}(IFoodGuardDAO.UserType.Company);
        
        uint256 finalBalance = dao.depositBalances(company1);
        assertEq(finalBalance, MIN_COMPANY_DEPOSIT);
        
        vm.stopPrank();
    }
    
    function testDepositGuaranteeInsufficientAmount() public {
        vm.startPrank(company1);
        
        vm.expectRevert("Insufficient deposit amount for user type");
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT - 1}(IFoodGuardDAO.UserType.Company);
        
        vm.stopPrank();
    }
    
    function testSubmitComplaint() public {
        // Company deposits guarantee
        vm.prank(company1);
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT}(IFoodGuardDAO.UserType.Company);
        
        // Complainant deposits guarantee
        vm.prank(complainant1);
        dao.depositGuarantee{value: MIN_INDIVIDUAL_DEPOSIT}(IFoodGuardDAO.UserType.Individual);
        
        vm.startPrank(complainant1);
        
        uint256 complaintId = dao.submitComplaint(
            company1,
            "Food poisoning from contaminated product",
            IFoodGuardDAO.RiskLevel.High
        );
        
        assertEq(complaintId, 1);
        
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertEq(complaint.complainant, complainant1);
        assertEq(complaint.company, company1);
        assertEq(uint(complaint.riskLevel), uint(IFoodGuardDAO.RiskLevel.High));
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Pending));
        assertTrue(complaint.companyDepositFrozen);
        
        vm.stopPrank();
    }
    
    function testSubmitComplaintInsufficientDeposit() public {
        vm.startPrank(complainant1);
        
        vm.expectRevert("Insufficient deposit");
        dao.submitComplaint(
            company1,
            "Food poisoning",
            IFoodGuardDAO.RiskLevel.High
        );
        
        vm.stopPrank();
    }
    
    function testSubmitVote() public {
        // Setup complaint
        vm.prank(company1);
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT}(IFoodGuardDAO.UserType.Company);
        
        vm.prank(complainant1);
        dao.depositGuarantee{value: MIN_INDIVIDUAL_DEPOSIT}(IFoodGuardDAO.UserType.Individual);
        
        vm.prank(complainant1);
        uint256 complaintId = dao.submitComplaint(
            company1,
            "Food contamination issue",
            IFoodGuardDAO.RiskLevel.Medium
        );
        
        // DAO member votes
        vm.prank(daoMember1);
        dao.submitVote(complaintId, true, "Evidence supports the complaint");
        
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertEq(complaint.votesFor, 1);
        assertEq(complaint.votesAgainst, 0);
    }
    
    function testSubmitVoteAlreadyVoted() public {
        // Setup complaint
        vm.prank(company1);
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT}(IFoodGuardDAO.UserType.Company);
        
        vm.prank(complainant1);
        dao.depositGuarantee{value: MIN_INDIVIDUAL_DEPOSIT}(IFoodGuardDAO.UserType.Individual);
        
        vm.prank(complainant1);
        uint256 complaintId = dao.submitComplaint(
            company1,
            "Food issue",
            IFoodGuardDAO.RiskLevel.Low
        );
        
        vm.startPrank(daoMember1);
        dao.submitVote(complaintId, true, "First vote");
        
        vm.expectRevert("Already voted");
        dao.submitVote(complaintId, false, "Second vote");
        
        vm.stopPrank();
    }
    
    function testStaking() public {
        uint256 stakeAmount = 1 ether;
        
        vm.startPrank(staker1);
        
        uint256 initialBalance = dao.stakedBalances(staker1);
        assertEq(initialBalance, 0);
        
        dao.stake{value: stakeAmount}();
        
        uint256 finalBalance = dao.stakedBalances(staker1);
        assertEq(finalBalance, stakeAmount);
        
        vm.stopPrank();
    }
    
    function testWithdrawStake() public {
        uint256 stakeAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        
        vm.startPrank(staker1);
        
        dao.stake{value: stakeAmount}();
        
        // Fast forward time to accumulate interest
        vm.warp(block.timestamp + 365 days);
        
        uint256 initialBalance = address(staker1).balance;
        
        dao.withdrawStake(withdrawAmount);
        
        uint256 finalBalance = address(staker1).balance;
        uint256 remainingStaked = dao.stakedBalances(staker1);
        
        assertEq(remainingStaked, stakeAmount - withdrawAmount);
        assertTrue(finalBalance > initialBalance); // Should include interest
        
        vm.stopPrank();
    }
    
    function testCalculateInterest() public {
        uint256 stakeAmount = 1 ether;
        
        vm.prank(staker1);
        dao.stake{value: stakeAmount}();
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        uint256 interest = dao.calculateInterest(staker1);
        uint256 expectedInterest = (stakeAmount * 5) / 100; // 5% annual rate
        
        assertEq(interest, expectedInterest);
    }
    
    function testWithdrawDeposit() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        
        vm.startPrank(company1);
        
        dao.depositGuarantee{value: depositAmount}(IFoodGuardDAO.UserType.Company);
        
        uint256 initialBalance = address(company1).balance;
        
        dao.withdrawDeposit(withdrawAmount);
        
        uint256 finalBalance = address(company1).balance;
        uint256 remainingDeposit = dao.depositBalances(company1);
        
        assertEq(finalBalance - initialBalance, withdrawAmount);
        assertEq(remainingDeposit, depositAmount - withdrawAmount);
        
        vm.stopPrank();
    }
    
    function testGetDAOMembers() public {
        address[] memory members = dao.getDAOMembers();
        assertEq(members.length, 3);
        assertEq(members[0], daoMember1);
        assertEq(members[1], daoMember2);
        assertEq(members[2], daoMember3);
    }
    
    function testGetStakerInfo() public {
        uint256 stakeAmount = 1 ether;
        
        vm.prank(staker1);
        dao.stake{value: stakeAmount}();
        
        (uint256 balance, uint256 interest, uint256 lastStake) = dao.getStakerInfo(staker1);
        
        assertEq(balance, stakeAmount);
        assertEq(interest, 0); // No time passed yet
        assertEq(lastStake, block.timestamp);
    }
    
    function testOnlyOwnerFunctions() public {
        address unauthorizedUser = makeAddr("unauthorized");
        
        vm.startPrank(unauthorizedUser);
        
        vm.expectRevert();
        dao.addDAOMember(makeAddr("newMember"));
        
        vm.expectRevert();
        dao.removeDAOMember(daoMember1);
        
        vm.expectRevert();
        dao.pause();
        
        vm.stopPrank();
    }
    
    function testOnlyDAOMemberFunctions() public {
        // Setup complaint first
        vm.prank(company1);
        dao.depositGuarantee{value: MIN_COMPANY_DEPOSIT}(IFoodGuardDAO.UserType.Company);
        
        vm.prank(complainant1);
        dao.depositGuarantee{value: MIN_INDIVIDUAL_DEPOSIT}(IFoodGuardDAO.UserType.Individual);
        
        vm.prank(complainant1);
        uint256 complaintId = dao.submitComplaint(
            company1,
            "Test complaint",
            IFoodGuardDAO.RiskLevel.Low
        );
        
        address unauthorizedUser = makeAddr("unauthorized");
        
        vm.startPrank(unauthorizedUser);
        
        vm.expectRevert("Not a DAO member");
        dao.submitVote(complaintId, true, "Test evidence");
        
        vm.stopPrank();
    }
    
    function testReceiveFunction() public {
        uint256 amount = 1 ether;
        uint256 initialReserveFund = dao.totalReserveFund();
        
        // Send ETH directly to contract
        (bool success,) = address(dao).call{value: amount}("");
        assertTrue(success);
        
        uint256 finalReserveFund = dao.totalReserveFund();
        assertEq(finalReserveFund - initialReserveFund, amount);
    }
} 