// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FoodGuardGovernance} from "../src/FoodGuardGovernance.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployFoodGuard
 * @author FoodGuard Team
 * @notice 食品安全治理系统部署脚本
 * @dev 参考foundry-raffle的部署模式
 */
contract DeployFoodGuard is Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error DeployFoodGuard__InvalidNetwork();

    /*//////////////////////////////////////////////////////////////
                            DEPLOY FUNCTION
    //////////////////////////////////////////////////////////////*/
    
    function run() external returns (FoodGuardGovernance, HelperConfig) {
        // 获取网络配置
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // 验证配置
        if (config.deployerAddress == address(0)) {
            revert DeployFoodGuard__InvalidNetwork();
        }

        console2.log("Deploying FoodGuard Governance System...");
        console2.log("Network: Chain ID", block.chainid);
        console2.log("Deployer:", config.deployerAddress);
        console2.log("Min Deposit:", config.minDepositAmount);
        console2.log("Membership Fee:", config.membershipFee);

        // 开始广播交易
        vm.startBroadcast(config.deployerKey);

        // 部署主合约（会自动部署所有子系统）
        FoodGuardGovernance governance = new FoodGuardGovernance();

        vm.stopBroadcast();

        // 获取子系统地址并记录
        (
            address accessControl,
            address depositManager,
            address votingSystem,
            address challengeSystem,
            address rewardSystem
        ) = governance.getSystemAddresses();

        // 输出部署信息
        console2.log("\n=== FoodGuard Governance System Deployed ===");
        console2.log("Main Governance Contract:", address(governance));
        console2.log("Access Control Contract:", accessControl);
        console2.log("Deposit Manager Contract:", depositManager);
        console2.log("Voting System Contract:", votingSystem);
        console2.log("Challenge System Contract:", challengeSystem);
        console2.log("Reward System Contract:", rewardSystem);
        console2.log("==========================================\n");

        // 验证部署
        _verifyDeployment(governance);

        return (governance, helperConfig);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 验证部署是否成功
     */
    function _verifyDeployment(FoodGuardGovernance governance) internal view {
        // 检查主合约
        require(address(governance) != address(0), "Main contract deployment failed");
        
        // 检查子系统
        (
            address accessControl,
            address depositManager,
            address votingSystem,
            address challengeSystem,
            address rewardSystem
        ) = governance.getSystemAddresses();
        
        require(accessControl != address(0), "AccessControl deployment failed");
        require(depositManager != address(0), "DepositManager deployment failed");
        require(votingSystem != address(0), "VotingSystem deployment failed");
        require(challengeSystem != address(0), "ChallengeSystem deployment failed");
        require(rewardSystem != address(0), "RewardSystem deployment failed");
        
        console2.log("All contracts deployed successfully!");
    }
} 