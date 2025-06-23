// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Constants
 * @dev 食品安全治理系统的常量定义
 * 参考foundry-raffle的CodeConstants模式
 */
abstract contract Constants {
    /*//////////////////////////////////////////////////////////////
                            CHAIN IDs
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant POLYGON_CHAIN_ID = 137;
    uint256 public constant BSC_CHAIN_ID = 56;

    /*//////////////////////////////////////////////////////////////
                        FOUNDRY CONSTANTS
    //////////////////////////////////////////////////////////////*/
    address public constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    /*//////////////////////////////////////////////////////////////
                        SYSTEM CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant PERCENTAGE_BASE = 10000; // 100% = 10000 基点
    
    /*//////////////////////////////////////////////////////////////
                        TIME CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_VOTING_PERIOD = 1 days;
    uint256 public constant MAX_VOTING_PERIOD = 7 days;
    uint256 public constant CHALLENGE_PERIOD = 2 days;
    uint256 public constant LOCK_PERIOD = 7 days;

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.01 ether;
    uint256 public constant MAX_DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant MIN_CHALLENGE_DEPOSIT = 0.05 ether;
    uint256 public constant MEMBERSHIP_FEE = 0.1 ether;

    /*//////////////////////////////////////////////////////////////
                        VOTING CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_VALIDATORS = 5;
    uint256 public constant MAX_VALIDATORS = 15;
    uint256 public constant DEFAULT_QUORUM = 6000; // 60%
    uint256 public constant DEFAULT_MAJORITY = 5000; // 50%

    /*//////////////////////////////////////////////////////////////
                        REWARD/PUNISHMENT CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant BASE_REWARD_RATE = 1000; // 10%
    uint256 public constant PUNISHMENT_RATE = 2000; // 20%
    uint256 public constant PLATFORM_FEE_RATE = 200; // 2%
    uint256 public constant WITHDRAWAL_FEE_RATE = 100; // 1%
    uint256 public constant CHALLENGER_REWARD_RATE = 500; // 5%

    /*//////////////////////////////////////////////////////////////
                        RISK ASSESSMENT CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant HIGH_RISK_THRESHOLD = 8000; // 80%
    uint256 public constant MEDIUM_RISK_THRESHOLD = 5000; // 50%

    /*//////////////////////////////////////////////////////////////
                        TRUST SCORE CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant TRUST_SCORE_BASE = 1000;
    uint256 public constant MIN_TRUST_SCORE = 500;
    uint256 public constant MAX_DAO_MEMBERS = 1000;

    /*//////////////////////////////////////////////////////////////
                        EVIDENCE CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MAX_EVIDENCE_FILES = 10;
    uint256 public constant EVIDENCE_HASH_LENGTH = 64; // SHA256 hex length
} 