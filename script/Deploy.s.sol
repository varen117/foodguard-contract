// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FoodGuardGovernance.sol";

/**
 * @title Deploy
 * @dev 食品安全治理系统部署脚本
 */
contract Deploy is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署主合约（会自动部署所有子系统）
        FoodGuardGovernance governance = new FoodGuardGovernance();
        
        // 获取子系统地址
        (
            address accessControl,
            address depositManager,
            address votingSystem,
            address challengeSystem,
            address rewardSystem
        ) = governance.getSystemAddresses();
        
        vm.stopBroadcast();
        
        // 输出部署信息
        console.log("=== FoodGuard Governance System Deployed ===");
        console.log("Main Governance Contract:", address(governance));
        console.log("Access Control Contract:", accessControl);
        console.log("Deposit Manager Contract:", depositManager);
        console.log("Voting System Contract:", votingSystem);
        console.log("Challenge System Contract:", challengeSystem);
        console.log("Reward System Contract:", rewardSystem);
        console.log("==========================================");
    }
} 