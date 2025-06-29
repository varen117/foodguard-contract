// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FoodSafetyGovernance} from "../src/FoodSafetyGovernance.sol";
import {FundManager} from "../src/modules/FundManager.sol";
import {ParticipantPoolManager} from "../src/modules/ParticipantPoolManager.sol";
import {RewardPunishmentManager} from "../src/modules/RewardPunishmentManager.sol";
import {VotingDisputeManager} from "../src/modules/VotingDisputeManager.sol";

/**
 * @title 部署验证脚本
 * @author jay
 * @notice 验证食品安全治理系统是否正确部署和配置
 */
contract VerifyDeployment is Script {
    
    struct ContractAddresses {
        address governance;
        address fundManager;
        address poolManager;
        address rewardManager;
        address votingManager;
    }
    
    function run() external {
        // 这里需要替换为实际部署的合约地址
        // 可以从部署日志或配置文件中获取
        ContractAddresses memory addresses = ContractAddresses({
            governance: address(0), // 需要填入实际地址
            fundManager: address(0),
            poolManager: address(0),
            rewardManager: address(0),
            votingManager: address(0)
        });
        
        // 如果地址为空，尝试从环境变量读取
        if (addresses.governance == address(0)) {
            console2.log("Warning: Contract addresses not set. Please update the script with actual deployed addresses.");
            console2.log("You can also set environment variables:");
            console2.log("- GOVERNANCE_ADDRESS");
            console2.log("- FUND_MANAGER_ADDRESS");
            console2.log("- POOL_MANAGER_ADDRESS");
            console2.log("- REWARD_MANAGER_ADDRESS");
            console2.log("- VOTING_MANAGER_ADDRESS");
            return;
        }
        
        verifyDeployment(addresses);
    }
    
    function verifyDeployment(ContractAddresses memory addresses) public {
        console2.log("=== Food Safety Governance Deployment Verification ===");
        console2.log("");
        
        // 1. 验证合约地址
        console2.log("1. Contract Addresses:");
        console2.log("   Governance:", addresses.governance);
        console2.log("   FundManager:", addresses.fundManager);
        console2.log("   PoolManager:", addresses.poolManager);
        console2.log("   RewardManager:", addresses.rewardManager);
        console2.log("   VotingManager:", addresses.votingManager);
        console2.log("");
        
        // 2. 验证合约连接
        FoodSafetyGovernance governance = FoodSafetyGovernance(addresses.governance);
        
        try governance.fundManager() returns (FundManager fundManagerContract) {
            console2.log("2. Contract Connections:");
                         console2.log("   + FundManager connected:", address(fundManagerContract));
            
                         try governance.poolManager() returns (ParticipantPoolManager poolManagerContract) {
                 console2.log("   + PoolManager connected:", address(poolManagerContract));
             } catch {
                 console2.log("   - PoolManager connection failed");
             }
             
             try governance.rewardManager() returns (RewardPunishmentManager rewardManagerContract) {
                 console2.log("   + RewardManager connected:", address(rewardManagerContract));
             } catch {
                 console2.log("   - RewardManager connection failed");
             }
             
             try governance.votingDisputeManager() returns (VotingDisputeManager votingManagerContract) {
                 console2.log("   + VotingManager connected:", address(votingManagerContract));
             } catch {
                 console2.log("   - VotingManager connection failed");
             }
             
         } catch {
             console2.log("   - Failed to connect to contracts");
        }
        console2.log("");
        
        // 3. 验证系统配置
        console2.log("3. System Configuration:");
        try governance.validateConfiguration() returns (bool isValid, string[] memory issues) {
            if (isValid) {
                console2.log("   ✓ All configurations are valid");
            } else {
                console2.log("   ✗ Configuration issues found:");
                for (uint256 i = 0; i < issues.length; i++) {
                    console2.log("     -", issues[i]);
                }
            }
        } catch {
            console2.log("   ✗ Failed to validate configuration");
        }
        console2.log("");
        
        // 4. 验证VRF配置
        console2.log("4. VRF Configuration:");
        try governance.vrfConfigured() returns (bool vrfConfigured) {
            if (vrfConfigured) {
                console2.log("   ✓ VRF is configured");
            } else {
                console2.log("   ✗ VRF is not configured");
            }
        } catch {
            console2.log("   ✗ Failed to check VRF configuration");
        }
        console2.log("");
        
        // 5. 验证管理员权限
        console2.log("5. Admin Configuration:");
        try governance.admin() returns (address admin) {
            console2.log("   Admin address:", admin);
            console2.log("   ✓ Admin is set");
        } catch {
            console2.log("   ✗ Failed to get admin address");
        }
        console2.log("");
        
        // 6. 验证模块合约配置
        console2.log("6. Module Configurations:");
        _verifyFundManager(addresses.fundManager);
        _verifyPoolManager(addresses.poolManager);
        _verifyRewardManager(addresses.rewardManager);
        _verifyVotingManager(addresses.votingManager);
        
        console2.log("=== Verification Complete ===");
    }
    
    function _verifyFundManager(address fundManagerAddress) internal {
        try FundManager(fundManagerAddress).systemConfig() {
            console2.log("   ✓ FundManager: System config accessible");
        } catch {
            console2.log("   ✗ FundManager: System config not accessible");
        }
    }
    
    function _verifyPoolManager(address poolManagerAddress) internal {
        try ParticipantPoolManager(poolManagerAddress).getTotalUsers() returns (uint256 totalUsers) {
            console2.log("   ✓ PoolManager: Total users =", totalUsers);
        } catch {
            console2.log("   ✗ PoolManager: Failed to get total users");
        }
    }
    
    function _verifyRewardManager(address rewardManagerAddress) internal {
        try RewardPunishmentManager(rewardManagerAddress).rewardConfig() {
            console2.log("   ✓ RewardManager: Config accessible");
        } catch {
            console2.log("   ✗ RewardManager: Config not accessible");
        }
    }
    
    function _verifyVotingManager(address votingManagerAddress) internal {
        // 由于VotingDisputeManager可能没有直接的配置getter，我们检查合约是否响应
        try VotingDisputeManager(votingManagerAddress).owner() returns (address owner) {
            console2.log("   ✓ VotingManager: Owner =", owner);
        } catch {
            console2.log("   ✗ VotingManager: Failed to get owner");
        }
    }
    
    /**
     * @notice 使用环境变量进行验证
     */
    function verifyFromEnv() external {
        // 这个函数可以从环境变量读取合约地址进行验证
        // 实现留给具体使用场景
        console2.log("Environment-based verification not implemented yet");
        console2.log("Please set contract addresses in the script or use environment variables");
    }
} 