// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/FoodSafetyGovernance.sol";
import "../../src/modules/FundManager.sol";
import "../../src/modules/VotingManager.sol";
import "../../src/modules/DisputeManager.sol";
import "../../src/modules/RewardPunishmentManager.sol";
import "../../src/modules/ParticipantPoolManager.sol";
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
    ParticipantPoolManager public poolManager;

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
        poolManager = new ParticipantPoolManager(admin);

        // 初始化合约关联
        governance.initializeContracts(
            payable(address(fundManager)),
            address(votingManager),
            address(disputeManager),
            address(rewardManager),
            address(poolManager)
        );

        // 设置各模块的治理合约地址
        votingManager.setGovernanceContract(address(governance));
        disputeManager.setGovernanceContract(address(governance));
        rewardManager.setGovernanceContract(address(governance));
        poolManager.setGovernanceContract(address(governance));

        // 设置模块间的关联
        disputeManager.setFundManager(address(fundManager));
        disputeManager.setVotingManager(address(votingManager));
        disputeManager.setPoolManager(address(poolManager));
        rewardManager.setFundManager(address(fundManager));

        // 设置权限
        bytes32 operatorRole = fundManager.OPERATOR_ROLE();
        fundManager.grantRole(operatorRole, address(governance));

        bytes32 governanceRole = fundManager.GOVERNANCE_ROLE();
        fundManager.grantRole(governanceRole, address(governance));

        vm.stopPrank();
    }

}
