// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Constants} from "../src/libraries/Constants.sol";

/**
 * @title HelperConfig
 * @author FoodGuard Team
 * @notice 配置管理合约，为不同链提供相应的配置参数
 * @dev 参考foundry-raffle的HelperConfig设计模式
 */
contract HelperConfig is Constants, Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        // 基础配置
        uint256 deployerKey;                    // 部署者私钥
        address deployerAddress;                // 部署者地址
        
        // 系统参数配置
        uint256 minDepositAmount;               // 最小保证金
        uint256 maxDepositAmount;               // 最大保证金
        uint256 membershipFee;                  // 成员费用
        uint256 minChallengeDeposit;            // 最小质疑保证金
        
        // 投票配置
        uint256 minValidators;                  // 最小验证者数量
        uint256 maxValidators;                  // 最大验证者数量
        uint256 votingPeriod;                   // 投票期限
        uint256 challengePeriod;                // 质疑期限
        uint256 quorumPercentage;               // 法定人数百分比
        uint256 majorityThreshold;              // 多数票阈值
        
        // 奖惩配置
        uint256 baseRewardRate;                 // 基础奖励率
        uint256 punishmentRate;                 // 惩罚率
        uint256 platformFeeRate;                // 平台费率
        uint256 withdrawalFeeRate;              // 提取费率
        
        // 风险评估配置
        uint256 highRiskThreshold;              // 高风险阈值
        uint256 mediumRiskThreshold;            // 中风险阈值
        
        // 信任分数配置
        uint256 trustScoreBase;                 // 基础信任分数
        uint256 minTrustScore;                  // 最低信任分数
        uint256 maxDaoMembers;                  // 最大DAO成员数
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
        networkConfigs[POLYGON_CHAIN_ID] = getPolygonConfig();
        networkConfigs[BSC_CHAIN_ID] = getBscConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].deployerAddress != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            NETWORK CONFIGS
    //////////////////////////////////////////////////////////////*/
    
    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("MAINNET_PRIVATE_KEY"),
            deployerAddress: vm.envAddress("MAINNET_DEPLOYER_ADDRESS"),
            
            // 主网配置 - 更严格的参数
            minDepositAmount: 0.1 ether,       // 更高的最小保证金
            maxDepositAmount: 1000 ether,      // 更高的最大保证金限制
            membershipFee: 0.5 ether,          // 更高的成员费用
            minChallengeDeposit: 0.2 ether,    // 更高的质疑保证金
            
            minValidators: 7,                  // 更多的验证者
            maxValidators: 21,                 // 更多的最大验证者
            votingPeriod: 5 days,              // 更长的投票期
            challengePeriod: 3 days,           // 更长的质疑期
            quorumPercentage: 6500,            // 65% 法定人数
            majorityThreshold: 5500,           // 55% 多数票
            
            baseRewardRate: 800,               // 8% 基础奖励率
            punishmentRate: 2500,              // 25% 惩罚率
            platformFeeRate: 150,              // 1.5% 平台费
            withdrawalFeeRate: 50,             // 0.5% 提取费
            
            highRiskThreshold: 8500,           // 85% 高风险阈值
            mediumRiskThreshold: 6000,         // 60% 中风险阈值
            
            trustScoreBase: 1000,
            minTrustScore: 600,                // 更高的最低信任分数
            maxDaoMembers: 500                 // 主网限制更多成员
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY"),
            deployerAddress: vm.envAddress("SEPOLIA_DEPLOYER_ADDRESS"),
            
            // 测试网配置
            minDepositAmount: MIN_DEPOSIT_AMOUNT,
            maxDepositAmount: MAX_DEPOSIT_AMOUNT,
            membershipFee: MEMBERSHIP_FEE,
            minChallengeDeposit: MIN_CHALLENGE_DEPOSIT,
            
            minValidators: MIN_VALIDATORS,
            maxValidators: MAX_VALIDATORS,
            votingPeriod: 3 days,
            challengePeriod: CHALLENGE_PERIOD,
            quorumPercentage: DEFAULT_QUORUM,
            majorityThreshold: DEFAULT_MAJORITY,
            
            baseRewardRate: BASE_REWARD_RATE,
            punishmentRate: PUNISHMENT_RATE,
            platformFeeRate: PLATFORM_FEE_RATE,
            withdrawalFeeRate: WITHDRAWAL_FEE_RATE,
            
            highRiskThreshold: HIGH_RISK_THRESHOLD,
            mediumRiskThreshold: MEDIUM_RISK_THRESHOLD,
            
            trustScoreBase: TRUST_SCORE_BASE,
            minTrustScore: MIN_TRUST_SCORE,
            maxDaoMembers: MAX_DAO_MEMBERS
        });
    }

    function getPolygonConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("POLYGON_PRIVATE_KEY"),
            deployerAddress: vm.envAddress("POLYGON_DEPLOYER_ADDRESS"),
            
            // Polygon 配置 - 考虑到更低的gas费
            minDepositAmount: 0.001 ether,     // 更低的保证金（考虑MATIC价格）
            maxDepositAmount: 10000 ether,     // 相应调整
            membershipFee: 0.01 ether,
            minChallengeDeposit: 0.005 ether,
            
            minValidators: MIN_VALIDATORS,
            maxValidators: MAX_VALIDATORS,
            votingPeriod: 2 days,              // 更快的处理
            challengePeriod: 1 days,
            quorumPercentage: DEFAULT_QUORUM,
            majorityThreshold: DEFAULT_MAJORITY,
            
            baseRewardRate: BASE_REWARD_RATE,
            punishmentRate: PUNISHMENT_RATE,
            platformFeeRate: PLATFORM_FEE_RATE,
            withdrawalFeeRate: WITHDRAWAL_FEE_RATE,
            
            highRiskThreshold: HIGH_RISK_THRESHOLD,
            mediumRiskThreshold: MEDIUM_RISK_THRESHOLD,
            
            trustScoreBase: TRUST_SCORE_BASE,
            minTrustScore: MIN_TRUST_SCORE,
            maxDaoMembers: MAX_DAO_MEMBERS
        });
    }

    function getBscConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("BSC_PRIVATE_KEY"),
            deployerAddress: vm.envAddress("BSC_DEPLOYER_ADDRESS"),
            
            // BSC 配置
            minDepositAmount: 0.001 ether,
            maxDepositAmount: 5000 ether,
            membershipFee: 0.01 ether,
            minChallengeDeposit: 0.005 ether,
            
            minValidators: MIN_VALIDATORS,
            maxValidators: MAX_VALIDATORS,
            votingPeriod: 2 days,
            challengePeriod: 1 days,
            quorumPercentage: DEFAULT_QUORUM,
            majorityThreshold: DEFAULT_MAJORITY,
            
            baseRewardRate: BASE_REWARD_RATE,
            punishmentRate: PUNISHMENT_RATE,
            platformFeeRate: PLATFORM_FEE_RATE,
            withdrawalFeeRate: WITHDRAWAL_FEE_RATE,
            
            highRiskThreshold: HIGH_RISK_THRESHOLD,
            mediumRiskThreshold: MEDIUM_RISK_THRESHOLD,
            
            trustScoreBase: TRUST_SCORE_BASE,
            minTrustScore: MIN_TRUST_SCORE,
            maxDaoMembers: MAX_DAO_MEMBERS
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // 检查是否已经设置了本地网络配置
        if (localNetworkConfig.deployerAddress != address(0)) {
            return localNetworkConfig;
        }

        console2.log(unicode"⚠️ You have deployed to a local network!");
        console2.log("Make sure this was intentional");

        // 本地网络配置
        localNetworkConfig = NetworkConfig({
            deployerKey: vm.envOr("ANVIL_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)),
            deployerAddress: FOUNDRY_DEFAULT_SENDER,
            
            // 本地测试配置 - 快速测试参数
            minDepositAmount: 0.001 ether,     // 更低的测试保证金
            maxDepositAmount: 100 ether,
            membershipFee: 0.01 ether,
            minChallengeDeposit: 0.005 ether,
            
            minValidators: 3,                  // 更少的验证者便于测试
            maxValidators: 10,
            votingPeriod: 1 hours,             // 更短的时间便于测试
            challengePeriod: 30 minutes,
            quorumPercentage: 5000,            // 50% 更容易达到法定人数
            majorityThreshold: 5000,           // 50% 简单多数
            
            baseRewardRate: BASE_REWARD_RATE,
            punishmentRate: PUNISHMENT_RATE,
            platformFeeRate: PLATFORM_FEE_RATE,
            withdrawalFeeRate: WITHDRAWAL_FEE_RATE,
            
            highRiskThreshold: HIGH_RISK_THRESHOLD,
            mediumRiskThreshold: MEDIUM_RISK_THRESHOLD,
            
            trustScoreBase: TRUST_SCORE_BASE,
            minTrustScore: MIN_TRUST_SCORE,
            maxDaoMembers: 100                 // 测试环境限制成员数
        });

        // 为本地测试提供初始资金
        vm.deal(localNetworkConfig.deployerAddress, 1000 ether);
        
        return localNetworkConfig;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev 获取当前网络的简化配置（仅包含关键参数）
     */
    function getSimpleConfig() public returns (
        uint256 minDeposit,
        uint256 membershipFee,
        uint256 votingPeriod,
        uint256 challengePeriod,
        address deployer
    ) {
        NetworkConfig memory config = getConfig();
        return (
            config.minDepositAmount,
            config.membershipFee,
            config.votingPeriod,
            config.challengePeriod,
            config.deployerAddress
        );
    }

    /**
     * @dev 检查当前是否为本地测试环境
     */
    function isLocalNetwork() public view returns (bool) {
        return block.chainid == LOCAL_CHAIN_ID;
    }

    /**
     * @dev 检查当前是否为测试网络
     */
    function isTestNetwork() public view returns (bool) {
        return block.chainid == ETH_SEPOLIA_CHAIN_ID;
    }

    /**
     * @dev 检查当前是否为主网络
     */
    function isMainNetwork() public view returns (bool) {
        return block.chainid == ETH_MAINNET_CHAIN_ID;
    }
} 