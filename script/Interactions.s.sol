// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FoodSafetyGovernance} from "../src/FoodSafetyGovernance.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol"; //dev 第一步导入
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {CodeConstants} from "./HelperConfig.s.sol";
/**
 * 线上测试环境的VRF合约交互
 * @title 第一步：创建VRF订阅
 * @author jay
 * @notice 用于创建VRF订阅的脚本
 */
contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        // 获取当前链的配置
        HelperConfig helperConfig = new HelperConfig();
        // 获取VRF协调器地址和账户地址
        address vrfCoordinatorV2_5 = helperConfig
            .getConfigByChainId(block.chainid)
            .vrfCoordinatorV2_5;
        address account = helperConfig
            .getConfigByChainId(block.chainid)
            .account;
        return createSubscription(vrfCoordinatorV2_5, account);
    }

    /**
     * @notice 创建VRF订阅
     * @param vrfCoordinatorV2_5 VRF协调器地址
     * @param account 账户地址,本地链 anvil 默认账户地址
     * @return subId 订阅ID
     * @return vrfCoordinatorV2_5 VRF协调器地址
     */
    function createSubscription(
        address vrfCoordinatorV2_5,
        address account
    ) public returns (uint256, address) {
        console.log("Creating subscription on chainId: ", block.chainid);
        /*
            vm.startBroadcast(account);
            这行代码告诉 Foundry 脚本环境：后续所有链上交易都由 account 这个地址发起，即这些交易的 msg.sender 就是 account。
            这样可以模拟用指定账户（比如你本地的默认账户或你配置的部署账户）来执行合约操作。
            为什么要这样做？
            权限控制：有些合约操作（如 VRF 订阅、充值、添加消费者）只能由订阅创建者或特定账户执行。
            资金来源：充值等操作需要账户有余额，指定账户可以确保有足够的测试币或 LINK。
            部署一致性：在多环境部署时，确保所有操作都由同一个账户完成，便于管理和追踪。
         */
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your subscription Id is: ", subId);
        console.log("Please update the subscriptionId in HelperConfig.s.sol");
        return (subId, vrfCoordinatorV2_5);
    }

    function run() external returns (uint256, address) {
        return createSubscriptionUsingConfig();
    }
}

/**
 * @title 为订阅充值 LINK 代币（基金认购）
 * @author jay
 * @notice 给新创建好的订阅充值
 * @dev 充值的LINK代币会被锁定在订阅中，直到订阅被取消或到期
 */
contract FundSubscription is CodeConstants, Script {
    //定义每次充值的固定金额为 3 LINK（这里的 ether 单位实际表示 LINK）
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        // 从配置中获取必要的参数
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId; // 订阅ID
        address vrfCoordinatorV2_5 = helperConfig
            .getConfig()
            .vrfCoordinatorV2_5; // VRF协调器地址
        address link = helperConfig.getConfig().link; // linkToken代币地址
        address account = helperConfig.getConfig().account; // 部署者账户地址
        //如果没有订阅ID，则创建一个新的订阅
        if (subId == 0) {
            CreateSubscription createSub = new CreateSubscription();
            (uint256 updatedSubId, address updatedVRFv2) = createSub.run();
            subId = updatedSubId;
            vrfCoordinatorV2_5 = updatedVRFv2;
            console.log(
                "New SubId Created! ",
                subId,
                "VRF Address: ",
                vrfCoordinatorV2_5
            );
        }

        fundSubscription(vrfCoordinatorV2_5, subId, link, account);
    }
    /**
     *
     * @notice 第二步：为订阅充值 LINK 代币
     * @param vrfCoordinatorV2_5 VRF协调器地址
     * @param subId 订阅ID
     * @param link LINK代币地址
     * @param account 部署者账户地址
     */
    function fundSubscription(
        address vrfCoordinatorV2_5,
        uint256 subId,
        address link,
        address account
    ) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinatorV2_5);
        console.log("On ChainID: ", block.chainid);
        if (block.chainid == LOCAL_CHAIN_ID) {
            // 如果是本地链
            vm.startBroadcast(account);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            // 实际网络逻辑
            console.log(LinkToken(link).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(link).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(account);
            LinkToken(link).transferAndCall(
                vrfCoordinatorV2_5,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

/**
 * @title 第三步：为订阅添加消费者
 * @author jay
 * @notice 消费者就是使用VRF服务的合约的地址
 */
contract AddConsumer is Script {
    function addConsumer(
        address contractToAddToVrf,
        address vrfCoordinator,
        uint256 subId,
        address account
    ) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On ChainID: ", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(
            subId,
            contractToAddToVrf
        );
        vm.stopBroadcast();
    }

    /**
     * 添加配置
     * @param mostRecentlyDeployed 最近刚部署的合约地址
     */
    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinatorV2_5 = helperConfig
            .getConfig()
            .vrfCoordinatorV2_5;
        address account = helperConfig.getConfig().account;

        addConsumer(mostRecentlyDeployed, vrfCoordinatorV2_5, subId, account);
    }

    /**
     * 执行添加消费者操作
     */
    function run() external {
        // 获取当前链的最近刚部署的合约地址（参考文档：github.com/Cyfrin/foundry-devops）
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "FoodSafetyGovernance",
            block.chainid
        );
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}
