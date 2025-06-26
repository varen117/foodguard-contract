// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FoodSafetyGovernance.sol";
import "../src/modules/FundManager.sol";
import "../src/modules/VotingManager.sol";
import "../src/modules/DisputeManager.sol";
import "../src/modules/RewardPunishmentManager.sol";

/**
 * @title DeployFoodSafetyGovernance
 * @notice 食品安全治理系统部署脚本
 * @dev 按照正确顺序部署所有合约并设置权限
 */
contract DeployFoodSafetyGovernance is Script {

    // ==================== 部署的合约实例 ====================

    FoodSafetyGovernance public governance;
    FundManager public fundManager;
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    RewardPunishmentManager public rewardManager;

    // ==================== 部署配置 ====================

    address public deployer;

    // ==================== 主部署函数 ====================

    function run() external {
        // 获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Food Safety Governance System...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 第一步：部署所有合约
        _deployContracts();

        // 第二步：初始化合约关联
        _initializeContracts();

        // 第三步：设置权限
        _setupPermissions();

        // 第四步：验证部署
        _verifyDeployment();

        vm.stopBroadcast();

        // 第五步：输出部署信息
        _outputDeploymentInfo();
    }

    /**
     * @notice 第一步：部署所有合约
     */
    function _deployContracts() internal {
        console.log("Step 1: Deploying contracts...");
        
        // 部署资金管理合约
        fundManager = new FundManager(deployer);
        console.log("FundManager deployed at:", address(fundManager));
        
        // 部署治理主合约
        governance = new FoodSafetyGovernance(deployer);
        console.log("FoodSafetyGovernance deployed at:", address(governance));
        
        // 部署投票管理合约
        votingManager = new VotingManager(deployer);
        console.log("VotingManager deployed at:", address(votingManager));
        
        // 部署质疑管理合约
        disputeManager = new DisputeManager(deployer);
        console.log("DisputeManager deployed at:", address(disputeManager));
        
        // 部署奖惩管理合约
        rewardManager = new RewardPunishmentManager(deployer);
        console.log("RewardPunishmentManager deployed at:", address(rewardManager));
        
        console.log("All contracts deployed successfully!");
    }

    /**
     * @notice 第二步：初始化合约关联
     */
    function _initializeContracts() internal {
        console.log("\n=== Step 2: Initializing Contract Associations ===");

        // 在主合约中设置模块地址
        governance.initializeContracts(
            payable(address(fundManager)),
            address(votingManager),
            address(disputeManager),
            address(rewardManager)
        );
        console.log("Main contract initialized with module addresses");

        // 设置各模块的治理合约地址
        votingManager.setGovernanceContract(address(governance));
        console.log("VotingManager governance contract set");

        disputeManager.setGovernanceContract(address(governance));
        console.log("DisputeManager governance contract set");

        rewardManager.setGovernanceContract(address(governance));
        console.log("RewardManager governance contract set");

        // 设置模块间的关联
        disputeManager.setFundManager(address(fundManager));
        disputeManager.setVotingManager(address(votingManager));
        console.log("DisputeManager dependencies set");

        rewardManager.setFundManager(address(fundManager));
        console.log("RewardManager dependencies set");

        console.log("Contract associations initialized successfully!");
    }

    /**
     * @notice 第三步：设置权限
     */
    function _setupPermissions() internal {
        console.log("\n=== Step 3: Setting Up Permissions ===");

        // 为主合约授予资金管理器的操作权限
        bytes32 operatorRole = fundManager.OPERATOR_ROLE();
        fundManager.grantRole(operatorRole, address(governance));
        console.log("Governance contract granted OPERATOR_ROLE for FundManager");

        // 为主合约授予资金管理器的治理权限
        bytes32 governanceRole = fundManager.GOVERNANCE_ROLE();
        fundManager.grantRole(governanceRole, address(governance));
        console.log("Governance contract granted GOVERNANCE_ROLE for FundManager");

        console.log("Permissions set up successfully!");
    }

    /**
     * @notice 第四步：验证部署
     */
    function _verifyDeployment() internal view {
        console.log("\n=== Step 4: Verifying Deployment ===");

        // 验证主合约
        require(address(governance) != address(0), "Governance contract not deployed");
        require(governance.owner() == deployer, "Governance admin not set correctly");
        console.log("Governance contract verified");

        // 验证资金管理合约
        require(address(fundManager) != address(0), "FundManager not deployed");
        require(fundManager.hasRole(fundManager.DEFAULT_ADMIN_ROLE(), deployer), "FundManager admin not set");
        console.log("FundManager verified");

        // 验证投票管理合约
        require(address(votingManager) != address(0), "VotingManager not deployed");
        require(votingManager.owner() == deployer, "VotingManager admin not set");
        require(votingManager.governanceContract() == address(governance), "VotingManager governance not set");
        console.log("VotingManager verified");

        // 验证质疑管理合约
        require(address(disputeManager) != address(0), "DisputeManager not deployed");
        require(disputeManager.owner() == deployer, "DisputeManager admin not set");
        require(disputeManager.governanceContract() == address(governance), "DisputeManager governance not set");
        console.log("DisputeManager verified");

        // 验证奖惩管理合约
        require(address(rewardManager) != address(0), "RewardManager not deployed");
        require(rewardManager.owner() == deployer, "RewardManager admin not set");
        require(rewardManager.governanceContract() == address(governance), "RewardManager governance not set");
        console.log("RewardManager verified");

        console.log("All contracts verified successfully!");
    }

    /**
     * @notice 第五步：输出部署信息
     */
    function _outputDeploymentInfo() internal view {
        console.log("\n=== System Configuration ===");
        DataStructures.SystemConfig memory config = fundManager.getSystemConfig();
        console.log("Min Complaint Deposit:", config.minComplaintDeposit);
        console.log("Min Enterprise Deposit:", config.minEnterpriseDeposit);
        console.log("Min DAO Deposit:", config.minDaoDeposit);
        console.log("Voting Period (seconds):", config.votingPeriod);
        console.log("Challenge Period (seconds):", config.challengePeriod);
        console.log("Min Validators:", config.minValidators);
        console.log("Max Validators:", config.maxValidators);

        console.log("\n=== Dynamic Deposit Configuration ===");
        DataStructures.DynamicDepositConfig memory dynamicConfig = fundManager.getDynamicConfig();
        console.log("Warning Threshold:", dynamicConfig.warningThreshold, "%");
        console.log("Restriction Threshold:", dynamicConfig.restrictionThreshold, "%");
        console.log("Liquidation Threshold:", dynamicConfig.liquidationThreshold, "%");
        console.log("High Risk Multiplier:", dynamicConfig.highRiskMultiplier, "%");
        console.log("Medium Risk Multiplier:", dynamicConfig.mediumRiskMultiplier, "%");
        console.log("Low Risk Multiplier:", dynamicConfig.lowRiskMultiplier, "%");

        console.log("\n=== Fund Pool Status ===");
        DataStructures.FundPool memory poolStatus = fundManager.getFundPool();
        console.log("Total Balance:", poolStatus.totalBalance);
        console.log("Reward Pool:", poolStatus.rewardPool);
        console.log("Operational Fund:", poolStatus.operationalFund);

        console.log("\n=== Next Steps ===");
        console.log("1. Register users with: governance.registerUser{value: 0.05 ether}()");
        console.log("2. Register enterprises with: governance.registerEnterprise{value: 1 ether}()");
        console.log("3. Create complaints and test dynamic deposit management");
        console.log("4. Monitor user deposit status with: fundManager.getUserDepositStatus(user)");
        console.log("\n=== Advanced Features ===");
        console.log("- Dynamic deposit calculation based on risk level and reputation");
        console.log("- Automatic status management (Warning -> Restriction -> Liquidation)");
        console.log("- Simple and direct deposit freeze mechanism");
        console.log("- Reputation-based deposit discounts/penalties");

        console.log("\n=== Management Functions ===");
        console.log("- Update dynamic config: fundManager.updateDynamicConfig()");
        console.log("- Batch status check: fundManager.batchCheckUserStatus()");
        console.log("- Update reputation: fundManager.updateUserReputation()");
        console.log("- Check participation eligibility: fundManager.canParticipateInCase()");

        console.log("\n=== Deployment Summary ===");
        console.log("[SUCCESS] All contracts deployed successfully");
        console.log("[SUCCESS] Dynamic deposit management enabled");
        console.log("[SUCCESS] Simple deposit freeze mechanism active");
        console.log("[SUCCESS] Liquidation system active");
        console.log("[SUCCESS] Reputation-based discounts configured");

        console.log("\nFood Safety Governance with Simple Dynamic Deposits is ready!");
    }

    // ==================== 辅助部署函数 ====================

    /**
     * @notice 仅部署主合约（用于测试）
     */
    function deployGovernanceOnly() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        governance = new FoodSafetyGovernance(deployer);
        console.log("FoodSafetyGovernance deployed at:", address(governance));

        vm.stopBroadcast();
    }

    /**
     * @notice 部署并注册初始验证者
     */
    function deployWithValidators() external {
        // 获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Food Safety Governance System with Validators...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 执行完整部署流程
        _deployContracts();
        _initializeContracts();
        _setupPermissions();
        _verifyDeployment();

        // 注册一些初始验证者（需要手动设置验证者地址）
        address[] memory initialValidators = new address[](3);

        // 尝试从环境变量获取验证者地址，如果不存在则使用默认地址
        try vm.envAddress("VALIDATOR_1") returns (address addr1) {
            initialValidators[0] = addr1;
        } catch {
            initialValidators[0] = address(0);
        }

        try vm.envAddress("VALIDATOR_2") returns (address addr2) {
            initialValidators[1] = addr2;
        } catch {
            initialValidators[1] = address(0);
        }

        try vm.envAddress("VALIDATOR_3") returns (address addr3) {
            initialValidators[2] = addr3;
        } catch {
            initialValidators[2] = address(0);
        }

        for (uint256 i = 0; i < initialValidators.length; i++) {
            if (initialValidators[i] != address(0)) {
                votingManager.registerValidator(
                    initialValidators[i],
                    1 ether, // 初始质押
                    100     // 初始声誉分数
                );
                console.log("Validator registered:", initialValidators[i]);
            }
        }

        vm.stopBroadcast();

        // 输出部署信息
        _outputDeploymentInfo();

        console.log("Initial validators registered successfully!");
    }

    /**
     * @notice 升级部署（用于升级现有合约）
     */
    function upgrade() external {
        console.log("Upgrade functionality not implemented yet");
        console.log("This would require proxy contracts for upgradeability");
    }
}
