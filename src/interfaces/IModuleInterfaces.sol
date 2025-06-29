// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";

/**
 * @notice 资金管理合约接口
 * @dev 定义合约需要调用的资金管理合约函数
 */
interface IFundManager {
    function freezeDeposit(
        uint256 caseId, // 案件ID
        address user, // 用户地址
        DataStructures.RiskLevel riskLevel, // 风险等级
        uint256 baseAmount // 基础金额
    ) external;

    function unfreezeDeposit(uint256 caseId, address user) external; // 案件ID, 用户地址

    function getCaseFrozenDeposit(uint256 caseId, address user) external view returns (uint256);

    function addRewardToDeposit(address user, uint256 amount) external;

    function decreaseRewardToDeposit(address user, uint256 amount) external;

    function getSystemConfig() external view returns (DataStructures.SystemConfig memory);

    function addToFundPool(uint256 amount, string memory source) external;
}

/**
 * @notice 参与者池管理合约接口
 * @dev 定义合约需要调用的参与者池管理函数
 */
interface IParticipantPoolManager {
    function canParticipateInCase(
        uint256 caseId, // 案件ID
        address user, // 用户地址
        DataStructures.UserRole requiredRole // 所需角色
    ) external view returns (bool);

    function isValidatorsCheckedVoting(uint256 caseId) external view returns (bool);
}

/**
 * @notice 投票质疑管理合约接口
 * @dev 定义合约需要调用的投票质疑管理函数
 */
interface IVotingDisputeManager {
    function isVotingPeriodEnded(uint256 caseId) external view returns (bool);
    function isChallengePeriodEnded(uint256 caseId) external view returns (bool);
    function areAllValidatorsVoted(uint256 caseId) external view returns (bool);
}
