// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployFoodguard} from "../script/DeployFoodguard.s.sol";
import {FoodSafetyGovernance} from "../src/FoodSafetyGovernance.sol";
import {FundManager} from "../src/modules/FundManager.sol";
import {ParticipantPoolManager} from "../src/modules/ParticipantPoolManager.sol";
import {RewardPunishmentManager} from "../src/modules/RewardPunishmentManager.sol";
import {VotingDisputeManager} from "../src/modules/VotingDisputeManager.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DataStructures} from "../src/libraries/DataStructures.sol";
import {Events} from "../src/libraries/Events.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {CodeConstants} from "../script/HelperConfig.s.sol";

contract FoodguardTest is Test, CodeConstants {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event ComplaintCreated(
        uint256 indexed caseId,
        address indexed complainant,
        address indexed enterprise,
        string complaintTitle,
        DataStructures.RiskLevel riskLevel,
        uint256 timestamp
    );

    event UserRegistered(
        address indexed user,
        DataStructures.UserRole role,
        uint256 timestamp
    );

    event VoteSubmitted(
        uint256 indexed caseId,
        address indexed voter,
        DataStructures.VoteChoice choice,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    DeployFoodguard.DeployedContracts public contracts;
    HelperConfig public helperConfig;

    FoodSafetyGovernance public governance;
    FundManager public fundManager;
    ParticipantPoolManager public poolManager;
    RewardPunishmentManager public rewardManager;
    VotingDisputeManager public votingManager;

    // Network config
    uint256 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2_5;
    LinkToken link;

    // Test addresses
    address public COMPLAINANT = makeAddr("complainant");
    address public ENTERPRISE = makeAddr("enterprise");
    address public DAO_MEMBER_1 = makeAddr("dao_member_1");
    address public DAO_MEMBER_2 = makeAddr("dao_member_2");
    address public DAO_MEMBER_3 = makeAddr("dao_member_3");
    address public ADMIN = makeAddr("admin");

    // Constants
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant LINK_BALANCE = 100 ether;
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    uint256 public constant ENTERPRISE_DEPOSIT = 0.1 ether;
    uint256 public constant DAO_DEPOSIT = 0.05 ether;

    function setUp() external {
        // Set a reasonable timestamp to simulate system running for a while
        // This prevents underflow when using expressions like block.timestamp - 1 hours
        vm.warp(1000000); // Set to a large timestamp (around 11 days after Unix epoch)

        // Deploy contracts
        DeployFoodguard deployer = new DeployFoodguard();
        (contracts, helperConfig) = deployer.run();

        // Set contract references
        governance = contracts.governance;
        fundManager = contracts.fundManager;
        poolManager = contracts.poolManager;
        rewardManager = contracts.rewardManager;
        votingManager = contracts.votingManager;

        // Get network config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        automationUpdateInterval = config.automationUpdateInterval;
        raffleEntranceFee = config.raffleEntranceFee;
        callbackGasLimit = config.callbackGasLimit;
        vrfCoordinatorV2_5 = config.vrfCoordinatorV2_5;
        link = LinkToken(config.link);

        // Setup test users with initial balances
        vm.deal(COMPLAINANT, STARTING_USER_BALANCE);
        vm.deal(ENTERPRISE, STARTING_USER_BALANCE);
        vm.deal(DAO_MEMBER_1, STARTING_USER_BALANCE);
        vm.deal(DAO_MEMBER_2, STARTING_USER_BALANCE);
        vm.deal(DAO_MEMBER_3, STARTING_USER_BALANCE);
        vm.deal(ADMIN, STARTING_USER_BALANCE);

        // Setup LINK funding for local testing
        vm.startPrank(config.account);
        if (block.chainid == LOCAL_CHAIN_ID) {
            link.mint(config.account, LINK_BALANCE);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(
                subscriptionId,
                LINK_BALANCE
            );
        }
        link.approve(vrfCoordinatorV2_5, LINK_BALANCE);
        vm.stopPrank();

        // Register initial users
        _registerInitialUsers();

        // Deposit initial funds for users
        _depositInitialFunds();
    }

    function _registerInitialUsers() internal {
        vm.startPrank(governance.admin());
        governance.registerUser(
            COMPLAINANT,
            uint8(DataStructures.UserRole.COMPLAINANT)
        );
        governance.registerUser(
            ENTERPRISE,
            uint8(DataStructures.UserRole.ENTERPRISE)
        );
        governance.registerUser(
            DAO_MEMBER_1,
            uint8(DataStructures.UserRole.DAO_MEMBER)
        );
        governance.registerUser(
            DAO_MEMBER_2,
            uint8(DataStructures.UserRole.DAO_MEMBER)
        );
        governance.registerUser(
            DAO_MEMBER_3,
            uint8(DataStructures.UserRole.DAO_MEMBER)
        );
        vm.stopPrank();
    }

    function _depositInitialFunds() internal {
        // Complainant deposits
        vm.prank(COMPLAINANT);
        fundManager.depositFunds{value: MIN_DEPOSIT * 5}();

        // Enterprise deposits
        vm.prank(ENTERPRISE);
        fundManager.depositFunds{value: ENTERPRISE_DEPOSIT * 5}();

        // DAO members deposit
        vm.prank(DAO_MEMBER_1);
        fundManager.depositFunds{value: DAO_DEPOSIT * 3}();

        vm.prank(DAO_MEMBER_2);
        fundManager.depositFunds{value: DAO_DEPOSIT * 3}();

        vm.prank(DAO_MEMBER_3);
        fundManager.depositFunds{value: DAO_DEPOSIT * 3}();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT VERIFICATION
    //////////////////////////////////////////////////////////////*/
    function testDeploymentInitializesCorrectly() public view {
        // Test governance contract
        assert(address(governance) != address(0));
        assert(governance.admin() != address(0));
        assert(governance.vrfConfigured() == true);

        // Test module contracts
        assert(address(fundManager) != address(0));
        assert(address(poolManager) != address(0));
        assert(address(rewardManager) != address(0));
        assert(address(votingManager) != address(0));

        // Test contract connections
        assert(address(governance.fundManager()) == address(fundManager));
        assert(address(governance.poolManager()) == address(poolManager));
        assert(address(governance.rewardManager()) == address(rewardManager));
        assert(
            address(governance.votingDisputeManager()) == address(votingManager)
        );
    }

    function testSystemConfigurationIsValid() public {
        (bool isValid, string[] memory issues) = governance
            .validateConfiguration();
        assert(isValid);
        assert(issues.length == 0);
    }

    /*//////////////////////////////////////////////////////////////
                            USER REGISTRATION
    //////////////////////////////////////////////////////////////*/
    function testUserRegistrationWorks() public {
        address newUser = makeAddr("new_user");

        vm.prank(governance.admin());
        governance.registerUser(
            newUser,
            uint8(DataStructures.UserRole.COMPLAINANT)
        );

        (
            bool registered,
            DataStructures.UserRole role,
            bool active,
            uint256 reputation
        ) = poolManager.getUserInfo(newUser);

        assert(registered == true);
        assert(role == DataStructures.UserRole.COMPLAINANT);
        assert(active == true);
        assert(reputation == 1000); // Initial reputation
    }

    function testUserRegistrationRevertsWithInvalidRole() public {
        address newUser = makeAddr("invalid_user");

        vm.prank(governance.admin());
        vm.expectRevert();
        governance.registerUser(newUser, 99); // Invalid role
    }

    function testAnyoneCanRegisterUsers() public {
        address newUser = makeAddr("any_user");

        // 任何人都可以注册用户，不应该revert
        vm.prank(COMPLAINANT);
        governance.registerUser(
            newUser,
            uint8(DataStructures.UserRole.COMPLAINANT)
        );

        (
            bool registered,
            DataStructures.UserRole role,
            bool active,
            uint256 reputation
        ) = poolManager.getUserInfo(newUser);

        assert(registered == true);
        assert(role == DataStructures.UserRole.COMPLAINANT);
        assert(active == true);
        assert(reputation == 1000); // Initial reputation
    }

    /*//////////////////////////////////////////////////////////////
                            FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function testDepositFundsWorks() public {
        address newUser = makeAddr("deposit_user");
        vm.deal(newUser, 1 ether);

        vm.prank(newUser);
        fundManager.depositFunds{value: MIN_DEPOSIT}();

        // Check deposit using individual field access instead of destructuring
        (uint256 totalDeposit, , , , , , ) = fundManager.userProfiles(newUser);
        assert(totalDeposit == MIN_DEPOSIT);
    }

    function testDepositRevertsWithInsufficientAmount() public {
        vm.prank(COMPLAINANT);
        vm.expectRevert();
        fundManager.depositFunds{value: MIN_DEPOSIT - 1}();
    }

    function testWithdrawFundsWorks() public {
        uint256 withdrawAmount = MIN_DEPOSIT;
        uint256 initialBalance = COMPLAINANT.balance;

        vm.prank(COMPLAINANT);
        fundManager.withdrawFunds(withdrawAmount);

        assert(COMPLAINANT.balance == initialBalance + withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLAINT CREATION
    //////////////////////////////////////////////////////////////*/
    modifier usersRegisteredAndFunded() {
        // Users are already registered and funded in setUp
        _;
    }

    function testCreateComplaintWorks() public usersRegisteredAndFunded {
        string memory title = "Contaminated Food";
        string memory description = "Found foreign objects in food";
        string memory location = "Restaurant ABC";
        string memory evidence = "QmHashOfEvidence";

        vm.prank(COMPLAINANT);
        uint256 caseId = governance.createComplaint(
            ENTERPRISE,
            title,
            description,
            location,
            block.timestamp - 1 hours, // Now safe to use hours
            evidence,
            uint8(DataStructures.RiskLevel.MEDIUM)
        );

        assert(caseId == 1);
        vm.prank(COMPLAINANT);
        uint256 caseId2 = governance.createComplaint(
            ENTERPRISE,
            title,
            description,
            location,
            block.timestamp - 1 hours, // Now safe to use hours
            evidence,
            uint8(DataStructures.RiskLevel.MEDIUM)
        );

        assert(caseId2 == 2);

        // Verify case info by checking individual fields
        (
            uint256 storedCaseId,
            address complainant,
            address enterprise,
            string memory storedTitle,
            ,
            ,
            ,
            ,
            DataStructures.CaseStatus status,
            DataStructures.RiskLevel riskLevel,
            bool complaintUpheld,
            uint256 complainantDeposit,
            uint256 enterpriseDeposit,
            ,
            ,

        ) = governance.cases(caseId);

        assert(storedCaseId == caseId);
        assert(complainant == COMPLAINANT);
        assert(enterprise == ENTERPRISE);
        assert(keccak256(bytes(storedTitle)) == keccak256(bytes(title)));
        // Status should be DEPOSIT_LOCKED after creation, before VRF callback
        assert(status == DataStructures.CaseStatus.DEPOSIT_LOCKED);
        assert(riskLevel == DataStructures.RiskLevel.MEDIUM);
        assert(complainantDeposit > 0);
        assert(enterpriseDeposit > 0);
    }

    function testCreateComplaintRevertsWithInvalidEnterprise()
        public
        usersRegisteredAndFunded
    {
        vm.prank(COMPLAINANT);
        vm.expectRevert();
        governance.createComplaint(
            makeAddr("unregistered_enterprise"),
            "Bad Food",
            "Description",
            "Location",
            1000, // Use a safe timestamp
            "Evidence",
            uint8(DataStructures.RiskLevel.LOW)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    function testCompleteWorkflowBasic()
        public
        usersRegisteredAndFunded
        skipFork
    {
        // 1. Create complaint
        vm.prank(COMPLAINANT);
        uint256 caseId = governance.createComplaint(
            ENTERPRISE,
            "Food Safety Issue",
            "Detailed description",
            "Restaurant Location",
            block.timestamp - 2 hours,
            "Evidence",
            uint8(DataStructures.RiskLevel.HIGH)
        );

        // 2. Verify case was created
        assert(caseId == 1);
        assert(governance.isCaseActive(caseId) == true);

        // 3. Verify case status
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            DataStructures.CaseStatus status,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = governance.cases(caseId);
        // Status should be DEPOSIT_LOCKED after creation, before VRF callback
        assert(status == DataStructures.CaseStatus.DEPOSIT_LOCKED);
    }

    function testSystemHandlesMultipleCases()
        public
        usersRegisteredAndFunded
        skipFork
    {
        // Create multiple complaints
        vm.prank(COMPLAINANT);
        uint256 caseId1 = governance.createComplaint(
            ENTERPRISE,
            "First Complaint",
            "First Description",
            "Location 1",
            block.timestamp - 1 hours,
            "Evidence1",
            uint8(DataStructures.RiskLevel.LOW)
        );

        vm.prank(COMPLAINANT);
        uint256 caseId2 = governance.createComplaint(
            ENTERPRISE,
            "Second Complaint",
            "Second Description",
            "Location 2",
            block.timestamp - 2 hours,
            "Evidence2",
            uint8(DataStructures.RiskLevel.HIGH)
        );

        assert(caseId1 == 1);
        assert(caseId2 == 2);

        // Verify both cases are active
        assert(governance.isCaseActive(caseId1) == true);
        assert(governance.isCaseActive(caseId2) == true);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }
}
