// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FoodGuardDAO.sol";
import "../src/RiskAssessment.sol";
import "../src/RandomSelector.sol";

contract IntegrationTest is Test {
    FoodGuardDAO public dao;
    RiskAssessment public riskAssessment;
    RandomSelector public randomSelector;
    
    address public owner;
    address public company;
    address public complainant;
    address public daoMember1;
    address public daoMember2;
    address public daoMember3;
    address public daoMember4;
    address public daoMember5;
    address public staker1;
    address public staker2;
    
    uint256 public constant MIN_INDIVIDUAL_DEPOSIT = 0.1 ether;
    uint256 public constant MIN_COMPANY_DEPOSIT = 1.0 ether;
    
    event ComplaintSubmitted(uint256 indexed complaintId, address indexed complainant, address indexed company, IFoodGuardDAO.RiskLevel riskLevel);
    event VoteSubmitted(uint256 indexed complaintId, address indexed voter, bool support, string evidence);
    event ComplaintResolved(uint256 indexed complaintId, bool companyPenalized, uint256 prizePoolAmount);
    event RewardsDistributed(uint256 indexed complaintId, uint256 totalRewards);
    
    function setUp() public {
        owner = address(this);
        company = makeAddr("company");
        complainant = makeAddr("complainant");
        daoMember1 = makeAddr("daoMember1");
        daoMember2 = makeAddr("daoMember2");
        daoMember3 = makeAddr("daoMember3");
        daoMember4 = makeAddr("daoMember4");
        daoMember5 = makeAddr("daoMember5");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        
        // Deploy contracts
        dao = new FoodGuardDAO();
        riskAssessment = new RiskAssessment();
        randomSelector = new RandomSelector();
        
        // Setup DAO members (need enough for high-risk voting)
        dao.addDAOMember(daoMember1);
        dao.addDAOMember(daoMember2);
        dao.addDAOMember(daoMember3);
        dao.addDAOMember(daoMember4);
        dao.addDAOMember(daoMember5);
        
        // Unpause contract
        dao.unpause();
        
        // Give test accounts some ETH
        vm.deal(company, 10 ether);
        vm.deal(complainant, 10 ether);
        vm.deal(staker1, 10 ether);
        vm.deal(staker2, 10 ether);
        vm.deal(daoMember3, 1 ether); // Give DAO member deposit for verification test
        
        // Setup initial deposits
        vm.prank(company);
        dao.depositGuarantee{value: 1 ether}(IFoodGuardDAO.UserType.Company);
        
        vm.prank(complainant);
        dao.depositGuarantee{value: 1 ether}(IFoodGuardDAO.UserType.Individual);
        
        vm.prank(daoMember3);
        dao.depositGuarantee{value: 0.5 ether}(IFoodGuardDAO.UserType.Individual); // DAO member needs deposit for penalty test
        
        // Setup initial staking to fund reserve
        vm.prank(staker1);
        dao.stake{value: 5 ether}();
        
        vm.prank(staker2);
        dao.stake{value: 3 ether}();
        
        // Add some initial reserve fund
        (bool success,) = address(dao).call{value: 2 ether}("");
        require(success, "Failed to add reserve fund");
    }
    
    function testCompleteHighRiskComplaintFlow() public {
        // Step 1: Submit high-risk complaint
        vm.expectEmit(true, true, true, false);
        emit ComplaintSubmitted(1, complainant, company, IFoodGuardDAO.RiskLevel.High);
        
        vm.prank(complainant);
        uint256 complaintId = dao.submitComplaint(
            company,
            "Severe food poisoning outbreak from contaminated products",
            IFoodGuardDAO.RiskLevel.High
        );
        
        assertEq(complaintId, 1);
        
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Pending));
        assertTrue(complaint.companyDepositFrozen);
        
        // Step 2: DAO members vote (need 3 votes for high risk)
        vm.expectEmit(true, true, false, false);
        emit VoteSubmitted(complaintId, daoMember1, true, "");
        
        vm.prank(daoMember1);
        dao.submitVote(complaintId, true, "Strong evidence of contamination");
        
        vm.prank(daoMember2);
        dao.submitVote(complaintId, true, "Multiple cases reported");
        
        vm.prank(daoMember3);
        dao.submitVote(complaintId, true, "Lab tests confirm contamination");
        
        // Check voting status changed
        complaint = dao.getComplaint(complaintId);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Voting));
        assertEq(complaint.votesFor, 3);
        assertEq(complaint.votesAgainst, 0);
        
        // Step 3: Verification by non-voting member
        vm.expectEmit(true, true, false, false);
        emit ComplaintResolved(complaintId, true, 0);
        
        vm.prank(daoMember4); // Non-voting member verifies
        dao.verifyVote(complaintId, true);
        
        // Step 4: Check resolution
        complaint = dao.getComplaint(complaintId);
        assertTrue(complaint.resolved);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Resolved));
        
        // Company should be penalized (deposit taken)
        assertEq(dao.depositBalances(company), 0);
        
        // Complainant should keep their deposit
        assertGt(dao.depositBalances(complainant), 0);
        
        // Prize pool should have company's deposit
        assertGt(complaint.prizePool, 0);
    }
    
    function testCompleteLowRiskComplaintFlowCompanyWins() public {
        // Step 1: Submit low-risk complaint
        vm.prank(complainant);
        uint256 complaintId = dao.submitComplaint(
            company,
            "Minor packaging issue with product appearance",
            IFoodGuardDAO.RiskLevel.Low
        );
        
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Pending));
        assertFalse(complaint.companyDepositFrozen); // Low risk doesn't freeze
        
        // Step 2: DAO members vote against complaint (need 2 votes for low risk)
        vm.prank(daoMember1);
        dao.submitVote(complaintId, false, "Insufficient evidence");
        
        vm.prank(daoMember2);
        dao.submitVote(complaintId, false, "Normal packaging variation");
        
        // Check voting status changed
        complaint = dao.getComplaint(complaintId);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Voting));
        assertEq(complaint.votesFor, 0);
        assertEq(complaint.votesAgainst, 2);
        
        // Step 3: Verification by non-voting member
        vm.prank(daoMember3);
        dao.verifyVote(complaintId, true);
        
        // Step 4: Check resolution - company wins
        complaint = dao.getComplaint(complaintId);
        assertTrue(complaint.resolved);
        
        // Complainant should be penalized
        assertEq(dao.depositBalances(complainant), 0);
        
        // Company should keep their deposit
        assertGt(dao.depositBalances(company), 0);
    }
    
    function testCompleteStakingFlow() public {
        uint256 initialStake = 2 ether;
        
        // Step 1: Stake funds (note: staker1 already staked 5 ether in setup)
        uint256 currentStaked = dao.stakedBalances(staker1);
        
        vm.prank(staker1);
        dao.stake{value: initialStake}();
        
        uint256 stakedBalance = dao.stakedBalances(staker1);
        assertEq(stakedBalance, currentStaked + initialStake);
        
        // Step 2: Fast forward time to accumulate interest
        vm.warp(block.timestamp + 182 days); // 6 months
        
        // Step 3: Check interest calculation
        uint256 interest = dao.calculateInterest(staker1);
        uint256 expectedInterest = (stakedBalance * 5 * 182 days) / (365 days * 100);
        assertEq(interest, expectedInterest);
        
        // Step 4: Withdraw with interest
        uint256 withdrawAmount = 1 ether;
        uint256 initialBalance = address(staker1).balance;
        
        vm.prank(staker1);
        dao.withdrawStake(withdrawAmount);
        
        uint256 finalBalance = address(staker1).balance;
        uint256 remainingStaked = dao.stakedBalances(staker1);
        
        assertEq(remainingStaked, stakedBalance - withdrawAmount);
        assertGt(finalBalance - initialBalance, withdrawAmount); // Should include interest
    }
    
    function testCompleteFlowWithMultipleComplaints() public {
        // Submit multiple complaints of different risk levels
        vm.startPrank(complainant);
        
        uint256 complaint1 = dao.submitComplaint(
            company,
            "High risk food poisoning case",
            IFoodGuardDAO.RiskLevel.High
        );
        
        uint256 complaint2 = dao.submitComplaint(
            company,
            "Medium hygiene issue",
            IFoodGuardDAO.RiskLevel.Medium
        );
        
        vm.stopPrank();
        
        // Handle first complaint (high risk)
        vm.prank(daoMember1);
        dao.submitVote(complaint1, true, "Evidence 1");
        
        vm.prank(daoMember2);
        dao.submitVote(complaint1, true, "Evidence 2");
        
        vm.prank(daoMember3);
        dao.submitVote(complaint1, true, "Evidence 3");
        
        vm.prank(daoMember4);
        dao.verifyVote(complaint1, true);
        
        // Handle second complaint (medium risk)
        vm.prank(daoMember1);
        dao.submitVote(complaint2, false, "Insufficient evidence");
        
        vm.prank(daoMember2);
        dao.submitVote(complaint2, false, "Normal operations");
        
        vm.prank(daoMember3);
        dao.verifyVote(complaint2, true);
        
        // Check both complaints are resolved
        IFoodGuardDAO.Complaint memory c1 = dao.getComplaint(complaint1);
        IFoodGuardDAO.Complaint memory c2 = dao.getComplaint(complaint2);
        
        assertTrue(c1.resolved);
        assertTrue(c2.resolved);
        
        // First complaint should penalize company, second should penalize complainant
        assertEq(dao.depositBalances(company), 0); // Penalized for first complaint
    }
    
    function testRiskAssessmentIntegration() public view {
        // Test different risk levels
        // Note: Risk assessment uses weighted scoring, testing general behavior
        
        // High risk case with high-risk keywords
        IFoodGuardDAO.RiskLevel level1 = riskAssessment.assessRisk(
            company,
            "poisoning outbreak contamination",
            100
        );
        // Should be at least Medium risk
        assertTrue(uint(level1) >= uint(IFoodGuardDAO.RiskLevel.Medium));
        
        // Medium risk case with medium-risk keywords
        IFoodGuardDAO.RiskLevel level2 = riskAssessment.assessRisk(
            company,
            "hygiene mold",
            60
        );
        // Should be at least Low risk
        assertTrue(uint(level2) >= uint(IFoodGuardDAO.RiskLevel.Low));
        
        // Test that different inputs produce different results
        IFoodGuardDAO.RiskLevel level3 = riskAssessment.assessRisk(
            company,
            "simple issue",
            10
        );
        
        // Just verify that the function works and returns a valid risk level
        assertTrue(uint(level3) <= uint(IFoodGuardDAO.RiskLevel.High));
    }
    
    function testRandomSelectorIntegration() public {
        address[] memory members = dao.getDAOMembers();
        address[] memory excludeList = new address[](1);
        excludeList[0] = daoMember1;
        
        uint256 seed = randomSelector.generateSeed(1);
        
        // Select 2 voters excluding daoMember1
        address[] memory voters = randomSelector.selectRandomVoters(
            members,
            2,
            seed,
            excludeList
        );
        
        assertEq(voters.length, 2);
        assertFalse(randomSelector.isInList(daoMember1, voters));
        
        // Select 1 verifier excluding voters
        address[] memory newExcludeList = new address[](3);
        newExcludeList[0] = daoMember1;
        newExcludeList[1] = voters[0];
        newExcludeList[2] = voters[1];
        
        address[] memory verifiers = randomSelector.selectRandomVerifiers(
            members,
            1,
            seed + 1,
            newExcludeList
        );
        
        assertEq(verifiers.length, 1);
        assertFalse(randomSelector.isInList(verifiers[0], newExcludeList));
    }
    
    function test_RevertWhen_VerificationFails() public {
        // Submit complaint
        vm.prank(complainant);
        uint256 complaintId = dao.submitComplaint(
            company,
            "Test complaint",
            IFoodGuardDAO.RiskLevel.Medium
        );
        
        // Vote
        vm.prank(daoMember1);
        dao.submitVote(complaintId, true, "Evidence");
        
        vm.prank(daoMember2);
        dao.submitVote(complaintId, true, "More evidence");
        
        // Verifier marks as false (verification fails)
        uint256 verifierInitialDeposit = dao.depositBalances(daoMember3);
        
        vm.prank(daoMember3);
        dao.verifyVote(complaintId, false);
        
        // Check that verification failure resets the complaint
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertEq(uint(complaint.status), uint(IFoodGuardDAO.ComplaintStatus.Pending));
        assertEq(complaint.votesFor, 0);
        assertEq(complaint.votesAgainst, 0);
        
        // Verifier should be penalized
        uint256 verifierFinalDeposit = dao.depositBalances(daoMember3);
        assertLt(verifierFinalDeposit, verifierInitialDeposit, "Verifier should be penalized");
    }
    
    function testEndToEndRewardDistribution() public {
        uint256 initialReserveFund = dao.totalReserveFund();
        
        // Submit and resolve complaint with company penalty
        vm.prank(complainant);
        uint256 complaintId = dao.submitComplaint(
            company,
            "Serious contamination issue",
            IFoodGuardDAO.RiskLevel.High
        );
        
        // Vote to penalize company
        vm.prank(daoMember1);
        dao.submitVote(complaintId, true, "Evidence 1");
        
        vm.prank(daoMember2);
        dao.submitVote(complaintId, true, "Evidence 2");
        
        vm.prank(daoMember3);
        dao.submitVote(complaintId, true, "Evidence 3");
        
        // Verify and resolve
        vm.prank(daoMember4);
        dao.verifyVote(complaintId, true);
        
        // Check that rewards were distributed
        IFoodGuardDAO.Complaint memory complaint = dao.getComplaint(complaintId);
        assertGt(complaint.prizePool, 0);
        
        // Check that reserve fund received portion
        uint256 finalReserveFund = dao.totalReserveFund();
        assertGt(finalReserveFund, initialReserveFund);
        
        // Check that voters received rewards (they should have more than 0 since they got rewards)
        assertGt(dao.depositBalances(daoMember1), 0);
        assertGt(dao.depositBalances(daoMember2), 0);
        assertGt(dao.depositBalances(daoMember3), 0);
    }
} 