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
 * @notice 食品安全治理系统完整部署脚本
 * @dev 部署所有模块合约和主合约，并完成初始化配置
 */
contract DeployFoodguard is Script {
    // 部署后的合约实例
    struct DeployedContracts {
        FoodSafetyGovernance governance;
        FundManager fundManager;
        ParticipantPoolManager poolManager;
        RewardPunishmentManager rewardManager;
        VotingDisputeManager votingManager;
    }

    function run() external returns (DeployedContracts memory, HelperConfig) {
        // 获取当前链的配置
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // 1. 处理Chainlink VRF订阅（如果需要）
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (
                config.subscriptionId,
                config.vrfCoordinatorV2_5
            ) = createSubscription.createSubscription(
                config.vrfCoordinatorV2_5,
                config.account
            );

            // 订阅充值
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinatorV2_5,
                config.subscriptionId,
                config.link,
                config.account
            );

            helperConfig.setConfig(block.chainid, config);
        }

        vm.startBroadcast(config.account);

        // 2. 部署所有模块合约
        DeployedContracts memory contracts = _deployAllContracts(
            config.account
        );

        // 3. 初始化主合约的模块地址
        contracts.governance.initializeContracts(
            payable(address(contracts.fundManager)),
            address(contracts.votingManager),
            address(contracts.rewardManager),
            address(contracts.poolManager)
        );

        // 4. 初始化VRF配置
        contracts.governance.initializeVRF(
            config.subscriptionId,
            config.vrfCoordinatorV2_5,
            config.gasLane,
            config.callbackGasLimit,
            3 // requestConfirmations
        );

        // 5. 为各模块设置治理合约地址
        contracts.fundManager.setGovernanceContract(
            address(contracts.governance)
        );
        contracts.poolManager.setGovernanceContract(
            address(contracts.governance)
        );
        contracts.rewardManager.setGovernanceContract(
            address(contracts.governance)
        );
        contracts.votingManager.setGovernanceContract(
            address(contracts.governance)
        );

        // 6. 设置模块间的依赖关系
        contracts.votingManager.setFundManager(address(contracts.fundManager));
        contracts.votingManager.setPoolManager(address(contracts.poolManager));
        contracts.rewardManager.setFundManager(address(contracts.fundManager));

        // 7. 注册一些初始用户（可选，用于测试）
        _registerInitialUsers(contracts);

        vm.stopBroadcast();

        // 8. 添加消费者到VRF订阅
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(contracts.governance),
            config.vrfCoordinatorV2_5,
            config.subscriptionId,
            config.account
        );

        return (contracts, helperConfig);
    }

    /**
     * @notice 部署所有合约
     * @param admin 管理员地址
     * @return contracts 部署的合约实例
     */
    function _deployAllContracts(
        address admin
    ) internal returns (DeployedContracts memory contracts) {
        // 部署模块合约
        contracts.fundManager = new FundManager(admin);
        contracts.poolManager = new ParticipantPoolManager(admin);
        contracts.rewardManager = new RewardPunishmentManager(admin);
        contracts.votingManager = new VotingDisputeManager(admin);

        // 部署主合约
        contracts.governance = new FoodSafetyGovernance(admin);

        return contracts;
    }

    /**
     * @notice 注册初始用户（用于测试和演示）
     * @param contracts 已部署的合约
     */
    function _registerInitialUsers(
        DeployedContracts memory contracts
    ) internal {
        // 这里可以注册一些测试用户
        // 注意：在生产环境中应该删除或修改这部分代码
        // 示例：注册部署者为DAO成员
        // contracts.governance.registerUser(msg.sender, uint8(DataStructures.UserRole.DAO_MEMBER));
        // TODO: 根据需要添加更多初始用户注册逻辑
        // 或者可以创建单独的脚本来处理用户注册
    }

    /**
     * @notice 验证部署结果
     * @param contracts 部署的合约
     * @return success 是否部署成功
     * @return issues 部署问题列表
     */
    function verifyDeployment(
        DeployedContracts memory contracts
    ) external view returns (bool success, string[] memory issues) {
        return contracts.governance.validateConfiguration();
    }
}
