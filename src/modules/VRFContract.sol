// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";


contract VRFContract is VRFConsumerBaseV2Plus {
    // vrf,也可以用构造函数初始化它们
    uint256 private s_subscriptionId;
    address private vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 private s_keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 private callbackGasLimit = 40000;
    uint16 private requestConfirmations = 3;
    // address vrfCoordinatorV2  //vrf协调器合约的地址
    // 订阅ID和请求确认数
    constructor(uint256 _subscriptionId) VRFConsumerBaseV2Plus(vrfCoordinator) {
        s_subscriptionId = _subscriptionId;
    }

    // 发送获取随机数请求，调用完这个函数之后会开始进行随机数计算，计算好了之后会自动回调下面的fulfillRandomWords函数
    function sendRandomWordsRequest(uint32 _numWords) external returns (uint256) {
        // 获取随机数（组装请求参数）
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: s_keyHash,//chainlink中VRF创建的订阅 keyhash
            subId: s_subscriptionId, // VRF订阅ID
            requestConfirmations: requestConfirmations, // 请求确认数
            callbackGasLimit: callbackGasLimit, // 回调gas限制
            numWords: _numWords, //获取的随机数个数
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false}) // 将nativePayment设置为true，使用Sepolia ETH而不是LINK来支付VRF请求
            )
        });
        // 向 Chainlink VRF 协调器请求随机数，返回一个唯一的 requestId 用于追踪这次随机数请求
        return s_vrfCoordinator.requestRandomWords(request);
    }

    // 随机数回调函数
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        //通过随机数randomWords执行自己逻辑
        uint256 randomNumber = randomWords[0];
        if (randomNumber % 3 == 0) {
            //执行逻辑
//            emit RandomNumberModulo(requestId, randomNumber, randomNumber % 3);
        } else {
            //执行逻辑
//            emit RandomNumberModulo(requestId, randomNumber, randomNumber % 3);
        }
    }
}
