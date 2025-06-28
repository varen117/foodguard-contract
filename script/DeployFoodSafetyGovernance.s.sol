// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FoodSafetyGovernance.sol";
import "../src/modules/ParticipantPoolManager.sol";
import "../src/modules/VotingDisputeManager.sol";
import "../src/modules/FundManager.sol";
import "../src/modules/RewardPunishmentManager.sol";

/**
 * @title DeployFoodSafetyGovernance
 * @notice 部署食品安全治理系统的完整脚本
 * @dev 按照正确的依赖顺序部署所有合约并建立关联
 */
contract DeployFoodSafetyGovernance is Script {
    
    // 部署的合约实例
    FoodSafetyGovernance public governance;
    ParticipantPoolManager public poolManager;
    VotingDisputeManager public votingDisputeManager;
    FundManager public fundManager;
    RewardPunishmentManager public rewardManager;
    
    // 部署参数
    address public deployer;
    
    function setUp() public {
        // 使用默认的 Anvil 账户地址
        deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }
    
    function run() public {
        // 使用默认的 Anvil 私钥
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Starting deployment of Food Safety Governance System...");
        console.log("Deployer address:", deployer);
        
        // 第一阶段：部署核心模块合约
        _deployModules();
        
        // 第二阶段：部署主治理合约
        _deployGovernance();
        
        // 第三阶段：设置合约间关联
        _setupContractRelations();
        
        // 第四阶段：初始化权限和配置
        _initializePermissions();
        
        // 第五阶段：验证部署
        _verifyDeployment();
        
        vm.stopBroadcast();
        
        console.log("Food Safety Governance System deployed successfully!");
        _logContractAddresses();
    }
    
    /**
     * @notice 部署所有模块合约
     */
    function _deployModules() internal {
        console.log("\n=== Deploying Module Contracts ===");
        
        // 部署参与者池管理合约
        poolManager = new ParticipantPoolManager(deployer);
        console.log("ParticipantPoolManager deployed at:", address(poolManager));
        
        // 部署投票和质疑管理合约（合并版）
        votingDisputeManager = new VotingDisputeManager(deployer);
        console.log("VotingDisputeManager deployed at:", address(votingDisputeManager));
        
        // 部署资金管理合约
        fundManager = new FundManager(deployer);
        console.log("FundManager deployed at:", address(fundManager));
        
        // 部署奖惩管理合约
        rewardManager = new RewardPunishmentManager(deployer);
        console.log("RewardPunishmentManager deployed at:", address(rewardManager));
    }
    
    /**
     * @notice 部署主治理合约
     */
    function _deployGovernance() internal {
        console.log("\n=== Deploying Governance Contract ===");
        
        governance = new FoodSafetyGovernance(deployer);
        
        console.log("FoodSafetyGovernance deployed at:", address(governance));
    }
    
    /**
     * @notice 设置合约间的关联关系
     */
    function _setupContractRelations() internal {
        console.log("\n=== Setting up Contract Relations ===");
        
        // 初始化治理合约的模块地址
        governance.initializeContracts(
            payable(address(fundManager)),
            address(votingDisputeManager),
            address(rewardManager),
            address(poolManager)
        );
        console.log("Governance contract initialized with module addresses");
        
        // 设置治理合约地址到各模块
        poolManager.setGovernanceContract(address(governance));
        console.log("PoolManager governance set");
        
        votingDisputeManager.setGovernanceContract(address(governance));
        console.log("VotingDisputeManager governance set");
        
        fundManager.setGovernanceContract(address(governance));
        console.log("FundManager governance set");
        
        rewardManager.setGovernanceContract(address(governance));
        console.log("RewardManager governance set");
        
        // 设置合并管理器的依赖关系
        votingDisputeManager.setFundManager(address(fundManager));
        votingDisputeManager.setPoolManager(address(poolManager));
        console.log("VotingDisputeManager dependencies set");
        
        console.log("Contract relations established");
    }
    
    /**
     * @notice 初始化权限和配置
     */
    function _initializePermissions() internal {
        console.log("\n=== Initializing Permissions ===");
        
        // 这里可以设置初始的管理员权限、系统参数等
        // 具体的权限设置需要根据合约的实际实现来确定
        
        console.log("Permissions initialized");
    }
    
    /**
     * @notice 验证部署是否成功
     */
    function _verifyDeployment() internal view {
        console.log("\n=== Verifying Deployment ===");
        
        // 验证所有合约都已部署
        require(address(governance) != address(0), "Governance not deployed");
        require(address(poolManager) != address(0), "PoolManager not deployed");
        require(address(votingDisputeManager) != address(0), "VotingDisputeManager not deployed");
        require(address(fundManager) != address(0), "FundManager not deployed");
        require(address(rewardManager) != address(0), "RewardManager not deployed");
        
        // 验证合约代码大小（避免部署空合约）
        uint256 governanceSize;
        address governanceAddr = address(governance);
        assembly { governanceSize := extcodesize(governanceAddr) }
        require(governanceSize > 0, "Governance contract has no code");
        
        console.log("All contracts verified successfully");
    }
    
    /**
     * @notice 输出所有合约地址
     */
    function _logContractAddresses() internal view {
        console.log("\n=== Contract Addresses ===");
        console.log("FoodSafetyGovernance:", address(governance));
        console.log("ParticipantPoolManager:", address(poolManager));
        console.log("VotingDisputeManager:", address(votingDisputeManager));
        console.log("FundManager:", address(fundManager));
        console.log("RewardPunishmentManager:", address(rewardManager));
    }
    
    /**
     * @notice 获取部署的合约地址（用于测试）
     */
    function getDeployedAddresses() external view returns (
        address _governance,
        address _poolManager,
        address _votingDisputeManager,
        address _fundManager,
        address _rewardManager
    ) {
        return (
            address(governance),
            address(poolManager),
            address(votingDisputeManager),
            address(fundManager),
            address(rewardManager)
        );
    }
}
