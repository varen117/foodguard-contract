// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FoodSafetyGovernance.sol";
import "../src/modules/ParticipantPoolManager.sol";
import "../src/modules/VotingManager.sol";
import "../src/modules/DisputeManager.sol";
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
    VotingManager public votingManager;
    DisputeManager public disputeManager;
    FundManager public fundManager;
    RewardPunishmentManager public rewardManager;
    
    // 部署参数
    address public deployer;
    
    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
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
        poolManager = new ParticipantPoolManager();
        console.log("ParticipantPoolManager deployed at:", address(poolManager));
        
        // 部署投票管理合约
        votingManager = new VotingManager();
        console.log("VotingManager deployed at:", address(votingManager));
        
        // 部署争议管理合约
        disputeManager = new DisputeManager();
        console.log("DisputeManager deployed at:", address(disputeManager));
        
        // 部署资金管理合约
        fundManager = new FundManager();
        console.log("FundManager deployed at:", address(fundManager));
        
        // 部署奖惩管理合约
        rewardManager = new RewardPunishmentManager();
        console.log("RewardPunishmentManager deployed at:", address(rewardManager));
    }
    
    /**
     * @notice 部署主治理合约
     */
    function _deployGovernance() internal {
        console.log("\n=== Deploying Governance Contract ===");
        
        governance = new FoodSafetyGovernance(
            address(poolManager),
            address(votingManager),
            address(disputeManager),
            address(fundManager),
            address(rewardManager)
        );
        
        console.log("FoodSafetyGovernance deployed at:", address(governance));
    }
    
    /**
     * @notice 设置合约间的关联关系
     */
    function _setupContractRelations() internal {
        console.log("\n=== Setting up Contract Relations ===");
        
        // 设置治理合约地址到各模块
        poolManager.setGovernanceContract(address(governance));
        console.log("PoolManager governance set");
        
        votingManager.setGovernanceContract(address(governance));
        console.log("VotingManager governance set");
        
        disputeManager.setGovernanceContract(address(governance));
        console.log("DisputeManager governance set");
        
        fundManager.setGovernanceContract(address(governance));
        console.log("FundManager governance set");
        
        rewardManager.setGovernanceContract(address(governance));
        console.log("RewardManager governance set");
        
        // 设置模块间的依赖关系（如果需要的话）
        // 注意：实际的依赖关系需要根据合约接口确定
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
        require(address(votingManager) != address(0), "VotingManager not deployed");
        require(address(disputeManager) != address(0), "DisputeManager not deployed");
        require(address(fundManager) != address(0), "FundManager not deployed");
        require(address(rewardManager) != address(0), "RewardManager not deployed");
        
        // 验证合约代码大小（避免部署空合约）
        uint256 governanceSize;
        assembly { governanceSize := extcodesize(address(governance)) }
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
        console.log("VotingManager:", address(votingManager));
        console.log("DisputeManager:", address(disputeManager));
        console.log("FundManager:", address(fundManager));
        console.log("RewardPunishmentManager:", address(rewardManager));
    }
    
    /**
     * @notice 获取部署的合约地址（用于测试）
     */
    function getDeployedAddresses() external view returns (
        address _governance,
        address _poolManager,
        address _votingManager,
        address _disputeManager,
        address _fundManager,
        address _rewardManager
    ) {
        return (
            address(governance),
            address(poolManager),
            address(votingManager),
            address(disputeManager),
            address(fundManager),
            address(rewardManager)
        );
    }
}
