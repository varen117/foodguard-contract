// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LinkToken} from "../test/mocks/LinkToken.sol";
import {Script, console2} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
/**
 * @title 辅助配置信息
 * @author jay
 * @notice 为了了方便在不同的链上进行部署，我们需要一个配置文件来存储各个链的配置
 */
abstract contract CodeConstants {
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // 模拟需要支付的chainlinkgas费用
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; // 模拟gas公共link链接
    // LINK / ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15; // 1 LINK 的价格为0.004 ETH
    // 默认发送人（每当foundry需要某个地址发送某些东西时都会用这个默认地址），只在本地链（如 Anvil）有意义，私钥是公开的，适合开发测试。
    address public constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        uint256 subscriptionId;// VRF服务订阅的唯一标识符（用于跟踪和管理随机数请求的付款）
        bytes32 gasLane;// 定义随机数生成的gas价格上限（不同的gasLane对应不同的确认时间和成本）
        uint256 automationUpdateInterval;// 定义两次抽奖之间的最小时间间隔（防止抽奖过于频繁，确保公平性）
        uint256 raffleEntranceFee;// 参与抽奖需要支付的费用（用于奖池accumulation）
        uint32 callbackGasLimit;// VRF回调函数的gas限制（确保随机数生成回调能够成功执行）
        address vrfCoordinatorV2_5;// VRF协调器合约地址（负责处理随机数请求和响应）
        address link;// LINK代币合约地址（用于支付Chainlink VRF服务费用）
        address account;// 部署者账户地址（用于管理合约部署和交互）
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
        // Note: We skip doing the local config
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    // 利用链ID获取相应配置
    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinatorV2_5 != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            subscriptionId: 0, // If left as 0, our scripts will create one!
            gasLane: 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805,
            automationUpdateInterval: 20, // 30 seconds
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 500,000 gas
            vrfCoordinatorV2_5: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909,
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            account: 0x643315C9Be056cDEA171F4e7b2222a4ddaB9F88D
        });
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            // Chainlink VRF 订阅ID，唯一标识一个 VRF 服务订阅，管理随机数请求和费用结算。作用：请求随机数时需要提供，费用从该订阅扣除。
            subscriptionId: 35953992749011469347670286683980262947405339699573753149657221682241756426716,
            // 说明：Chainlink VRF 的 keyHash，代表最大可接受的 gas 价格。作用：影响 VRF 节点响应速度和费用。
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            // 说明：自动化任务（如抽奖开奖）之间的最小时间间隔，单位为秒。防止过于频繁地开奖，保证公平性和可控性。
            automationUpdateInterval: 20,
            // 说明：参与抽奖需要支付的 ETH 数量（单位：wei）。作用：累积到奖池，最终由获胜者领取。
            raffleEntranceFee: 0.01 ether,
            // 说明：Chainlink VRF 回调函数（如 fulfillRandomWords）的最大 gas 限制。作用：确保回调逻辑能顺利完成，避免因 gas 不足导致失败。
            callbackGasLimit: 500000,
            // 说明：Chainlink VRF Coordinator 合约地址。作用：负责接收随机数请求、分发随机数、管理订阅等。
            vrfCoordinatorV2_5: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            // LINK 代币合约地址。作用：支付 Chainlink VRF 服务费用。（测试link领取：https://docs.chain.link/resources/link-token-contracts）
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            // 部署或操作合约的账户地址（你的钱包地址）。作用：用于合约部署、订阅创建、充值等链上操作。
            account: 0xC871425db776da225212A8295250cc7f02Fe6D03
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // 检查是否设置了活动网络配置
        if (localNetworkConfig.vrfCoordinatorV2_5 != address(0)) {
            return localNetworkConfig;
        }

        //部署一个模拟的链上VRF协调器合约
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock =
            new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);
        // 部署一个模拟的LINK代币合约
        LinkToken link = new LinkToken();
        // 创建订阅并返回订阅ID
        uint256 subscriptionId = vrfCoordinatorV2_5Mock.createSubscription();
        vm.stopBroadcast();
        // 填充本地网络配置
        localNetworkConfig = NetworkConfig({
            subscriptionId: subscriptionId,
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // doesn't really matter
            automationUpdateInterval: 20, // 30 seconds
            raffleEntranceFee: 0.01 ether,
            callbackGasLimit: 500000, // 500,000 gas
            vrfCoordinatorV2_5: address(vrfCoordinatorV2_5Mock),
            link: address(link),
            account: FOUNDRY_DEFAULT_SENDER
        });
        //
        vm.deal(localNetworkConfig.account, 100 ether);
        return localNetworkConfig;
    }
}
