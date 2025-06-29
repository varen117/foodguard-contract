// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FundManager} from "../src/modules/FundManager.sol";
import {ParticipantPoolManager} from "../src/modules/ParticipantPoolManager.sol";
import {RewardPunishmentManager} from "../src/modules/RewardPunishmentManager.sol";
import {VotingDisputeManager} from "../src/modules/VotingDisputeManager.sol";
import {FoodSafetyGovernance} from "../src/FoodSafetyGovernance.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";
/**
 * @title Foodguard 合约部署脚本
 * @author jay
 * @notice 合约部署脚本
 */
contract DeployFoodguard is Script {
    function run() external returns (Raffle, HelperConfig) {
        // 获取当前链的配置
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
        AddConsumer addConsumer = new AddConsumer();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        // 1. 在用chainlink的VRF获取随即词时需要先创建一个订阅
        if (config.subscriptionId == 0) { //检查是否已有订阅ID，如果 subscriptionId 为 0，表示需要创建新的订阅
            // 实例化 CreateSubscription 合约
            CreateSubscription createSubscription = new CreateSubscription();
            // 调用 createSubscription 函数创建新的 VRF 订阅。返回新创建的订阅ID和 VRF 协调器地址
            (config.subscriptionId, config.vrfCoordinatorV2_5) =
                createSubscription.createSubscription(config.vrfCoordinatorV2_5, config.account);
            // 订阅充值
            FundSubscription fundSubscription = new FundSubscription();
            // 为新创建的订阅充值 LINK 代币
            fundSubscription.fundSubscription(
                config.vrfCoordinatorV2_5, config.subscriptionId, config.link, config.account
            );

            helperConfig.setConfig(block.chainid, config);
        }

        vm.startBroadcast(config.account);
        // todo 部署合约
        vm.stopBroadcast();

        // We already have a broadcast in here
        addConsumer.addConsumer(address(raffle), config.vrfCoordinatorV2_5, config.subscriptionId, config.account);
        return (raffle, helperConfig);
    }
}
