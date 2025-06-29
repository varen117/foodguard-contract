// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);
    // 抽奖合约
    Raffle public raffle;
    // 辅助配置合约
    HelperConfig public helperConfig;

    uint256 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2_5;
    LinkToken link;
    // 创建一个新的玩家（链上地址）
    address public PLAYER = makeAddr("player");
    // 玩家的初始余额
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    // chainlink的链link余额
    uint256 public constant LINK_BALANCE = 100 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        // 给玩家一个初始余额
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        automationUpdateInterval = config.automationUpdateInterval;
        raffleEntranceFee = config.raffleEntranceFee; // 参与抽奖的入场费用
        callbackGasLimit = config.callbackGasLimit;
        vrfCoordinatorV2_5 = config.vrfCoordinatorV2_5;
        link = LinkToken(config.link);

        vm.startPrank(msg.sender);
        if (block.chainid == LOCAL_CHAIN_ID) {
            link.mint(msg.sender, LINK_BALANCE);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(subscriptionId, LINK_BALANCE);
        }
        link.approve(vrfCoordinatorV2_5, LINK_BALANCE);
        vm.stopPrank();
    }

    /**
     * 断言开奖状态是否打开
     */
    function  testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /*//////////////////////////////////////////////////////////////
                            ENTER RAFFLE
    //////////////////////////////////////////////////////////////*/
    /**
     * 断言是否支付了足够的入场费
     */
    function testRaffleRevertsWHenYouDontPayEnough() public {
        // Arrange 使用 Foundry 作弊代码将下一个调用的消息发送者设置为 PLAYER
        vm.prank(PLAYER);
        // vm.expectRevert() 期望下一个调用会失败并抛出特定错误
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        // 调用抽奖函数并不支付任何入场费q
        raffle.enterRaffle();
    }

    /**
     * 断言抽奖玩家列表是否被更新
     */
    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: raffleEntranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    /**
     * 测试时间发送函数
     */
    function testEmitsEventOnEntrance() public {
        // Arrange 首先模拟 PLAYER 地址的调用
        vm.prank(PLAYER);
        /*
        设置事件检查预期
        这是一个测试函数，用于验证当玩家成功进入抽奖时是否正确发出了 RaffleEnter 事件，
        前三个参数是代表 indexed 参数是否检查，事件最多只能有3个indexed参数，
        后面一个是非索引参数是否检查，address(raffle)指的是预期发出事件的合约地址
         */
        vm.expectEmit(true, false, false, false, address(raffle));
        // 声明预期事件
        emit RaffleEnter(PLAYER);
        //调用合约方法，合约方法会发出事件会和上面的声明的预期事件比较
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    /**
     * 开奖状态为计算中时，玩家不能进入抽奖
     * 此测试确保了抽奖合约的安全性，防止在计算获胜者期间有新玩家加入，维护了抽奖的公平性。
     */
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // 1. 让玩家参与抽奖
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        // 2. 推进时间
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        // 3. 按区块号推进，使得满足开奖时间间隔
        vm.roll(block.number + 1);
        // 4. 触发开奖操作
        raffle.performUpkeep("");

        // 5. 预期下一次调用会失败并抛出 Raffle__RaffleNotOpen 错误
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        // 6. 尝试让玩家再次参与抽奖
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                            CHECKUPKEEP
    //////////////////////////////////////////////////////////////*/
    /**
     * 验证 Raffle 合约的 checkUpkeep 函数在合约没有余额时是否正确返回 false。
     */
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    /**
     * 测试抽奖活动尚未公开（状态为CALCULATING）则返回false
     */
    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); //参加抽奖并支付入场费
        vm.warp(block.timestamp + automationUpdateInterval + 1); // 推进区块时间
        vm.roll(block.number + 1); //推进区块编号
        // 模拟chinlink自动化调用performUpkeep函数获取随机词，该方法会将开奖状态置为CALCULATING
        raffle.performUpkeep(""); 
        Raffle.RaffleState raffleState = raffle.getRaffleState(); // 获取当前抽奖状态
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep(""); //检查是否满足开奖条件，不满足为false
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    // 测试未满足时间间隔的情况下checkUpkeep返回false
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    // 测试 checkUpkeep 函数在所有条件都满足时是否正确返回 true
    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                            PERFORMUPKEEP
    //////////////////////////////////////////////////////////////*/
    /**
     * 测试 performUpkeep 函数只能在 checkUpkeep 返回 true 时调用是否成功
     */
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        // It doesnt revert
        raffle.performUpkeep("");
    }

    /**
     * 测试 performUpkeep 函数在 checkUpkeep 返回 false 时是否会抛出异常
     */
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    /**
     * 测试 performUpkeep 函数是否会更新抽奖状态并发出请求 ID
     */
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered{
        // Act
        vm.recordLogs(); // 告诉VM开始记录所有发出的事件。要访问它们，请使用getRecordedLogs。
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //跟踪到的事件日志获取
        // topics[0] 通常是事件的哈希值（通过 keccak256 计算事件签名得到）。topics[1]、topics[2] 等是事件中 indexed 参数的值。
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // requestId = raffle.getLastRequestId();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////*/
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    /**
     * 修饰器保证测试只在本地链执行，防止误操作。
     */
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /**
     * 验证 Chainlink VRF 的随机数回调机制的安全性：
     *   1. 测试确保 fulfillRandomWords 不能在没有先调用 performUpkeep 的情况下被调用
     *   2. 防止恶意用户直接调用随机数回调函数
     * 修饰器：
     *   1. raffleEntered  // 修饰器：确保测试前已有玩家参与抽奖
     *   2. skipFork       // 修饰器：确保测试只在本地测试网络运行
     * 测试流程：
     *   1. 尝试直接调用 fulfillRandomWords 而不先调用 performUpkeep
     *   2. 使用两个不同的 requestId (0 和 1) 进行测试
     *   3. 验证每次调用都会失败并抛出 InvalidRequest 错误
     * 目的：这个测试确保了 Chainlink VRF 随机数生成流程的完整性和安全性，防止随机数回调函数被绕过或滥用。
     */
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public raffleEntered skipFork {
        // Arrange
        // 期望调用失败并返回 InvalidRequest 错误
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        // 尝试用 requestId = 0 调用 fulfillRandomWords
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(0, address(raffle));
        // 再次期望调用失败并返回 InvalidRequest 错误
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        //尝试用 requestId = 1 调用 fulfillRandomWords
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(1, address(raffle));
    }

    /**
     * 测试抽奖合约的完整流程
     */
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        // ---1. 测试准备阶段---
        /*
            设置预期获胜者为 address(1)
            为什么可预测？
            1. requestId从 1 开始自增，如果不重新部署requestId 会一直自增加一，但这个测试每次都是重新部署，所以每次都是1，所以它是可预测的
            2. 请求的随机词数量我们是知道的，所以这个也是确定的
            3. mock算法是_words[i] = uint256(keccak256(abi.encode(_requestId, i)));,所以它也是确定的
            4. 我们自己的算法是 _randomWords[0] % players.length;，所以它也是确定的，所以expectedWinner是可以预测的。
         */
        address expectedWinner = address(1);

        // Arrange
        uint256 additionalEntrances = 3; // 额外的参与者数量
        uint256 startingIndex = 1; // 设置起始索引为1（避免使用 address(0)）

        // 2. 模拟多个玩家参与抽奖
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // 给玩家提供测试代币
            raffle.enterRaffle{value: raffleEntranceFee}(); // 玩家参与抽奖
        }

        // 3. 记录初始状态
        uint256 startingTimeStamp = raffle.getLastTimeStamp(); // 上次开奖时间戳
        uint256 startingBalance = expectedWinner.balance; // 预期获胜者的初始余额

        // 4. 执行抽奖流程
        vm.recordLogs();
        raffle.performUpkeep(""); // 触发开奖操作
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console2.logBytes32(entries[1].topics[1]);
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        // 5. 完成随机数回调（模拟 Chainlink VRF 返回随机数）
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = raffleEntranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner); // 验证获胜者
        assert(uint256(raffleState) == 0); // 验证抽奖状态重置为 OPEN
        assert(winnerBalance == startingBalance + prize); // 验证奖金转账
        assert(endingTimeStamp > startingTimeStamp); // 验证时间戳更新
    }
}
