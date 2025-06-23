// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IFoodGuard.sol";

/**
 * @title Utils
 * @dev 食品安全治理系统的工具库
 */
library Utils {
    // 常量定义
    uint256 public constant PERCENTAGE_BASE = 10000; // 百分比基数 (100% = 10000)
    uint256 public constant MIN_VOTING_PERIOD = 1 days; // 最小投票期
    uint256 public constant MAX_VOTING_PERIOD = 7 days; // 最大投票期
    uint256 public constant CHALLENGE_PERIOD = 2 days; // 质疑期
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.01 ether; // 最小保证金
    
    // 风险等级判定阈值
    uint256 public constant HIGH_RISK_THRESHOLD = 8000; // 80%
    uint256 public constant MEDIUM_RISK_THRESHOLD = 5000; // 50%
    
    /**
     * @dev 计算投票权重（基于保证金数额）
     * @param depositAmount 保证金数额
     * @return weight 投票权重
     */
    function calculateVotingWeight(uint256 depositAmount) internal pure returns (uint256 weight) {
        if (depositAmount >= 10 ether) {
            return 5; // 高额保证金用户权重为5
        } else if (depositAmount >= 1 ether) {
            return 3; // 中等保证金用户权重为3
        } else if (depositAmount >= MIN_DEPOSIT_AMOUNT) {
            return 1; // 基础保证金用户权重为1
        } else {
            return 0; // 保证金不足，无投票权
        }
    }

    /**
     * @dev 评估风险等级
     * @param description 案件描述
     * @param evidenceCount 证据数量
     * @return riskLevel 风险等级
     */
    function assessRiskLevel(
        string memory description,
        uint256 evidenceCount
    ) internal pure returns (IFoodGuard.RiskLevel riskLevel) {
        // 基于描述关键词和证据数量评估风险
        bytes memory descBytes = bytes(description);
        uint256 riskScore = 0;
        
        // 检查高风险关键词
        if (containsKeyword(description, unicode"死亡") || 
            containsKeyword(description, unicode"中毒") ||
            containsKeyword(description, unicode"致癌")) {
            riskScore += 4000;
        }
        
        // 检查中风险关键词  
        if (containsKeyword(description, unicode"过期") ||
            containsKeyword(description, unicode"变质") ||
            containsKeyword(description, unicode"腹泻")) {
            riskScore += 2000;
        }
        
        // 基于证据数量调整风险分数
        if (evidenceCount >= 5) {
            riskScore += 1000;
        } else if (evidenceCount >= 3) {
            riskScore += 500;
        }
        
        // 基于描述长度调整
        if (descBytes.length > 500) {
            riskScore += 500;
        }
        
        // 确定风险等级
        if (riskScore >= HIGH_RISK_THRESHOLD) {
            return IFoodGuard.RiskLevel.HIGH;
        } else if (riskScore >= MEDIUM_RISK_THRESHOLD) {
            return IFoodGuard.RiskLevel.MEDIUM;
        } else {
            return IFoodGuard.RiskLevel.LOW;
        }
    }

    /**
     * @dev 检查字符串是否包含特定关键词
     * @param source 源字符串
     * @param keyword 关键词
     * @return contains 是否包含
     */
    function containsKeyword(
        string memory source,
        string memory keyword
    ) internal pure returns (bool contains) {
        bytes memory sourceBytes = bytes(source);
        bytes memory keywordBytes = bytes(keyword);
        
        if (keywordBytes.length > sourceBytes.length) {
            return false;
        }
        
        for (uint256 i = 0; i <= sourceBytes.length - keywordBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < keywordBytes.length; j++) {
                if (sourceBytes[i + j] != keywordBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev 计算投票截止时间
     * @param riskLevel 风险等级
     * @param startTime 开始时间
     * @return deadline 截止时间
     */
    function calculateVotingDeadline(
        IFoodGuard.RiskLevel riskLevel,
        uint256 startTime
    ) internal pure returns (uint256 deadline) {
        if (riskLevel == IFoodGuard.RiskLevel.HIGH) {
            return startTime + MIN_VOTING_PERIOD; // 高风险案件快速处理
        } else if (riskLevel == IFoodGuard.RiskLevel.MEDIUM) {
            return startTime + 3 days; // 中风险案件中等时间
        } else {
            return startTime + MAX_VOTING_PERIOD; // 低风险案件充分讨论
        }
    }

    /**
     * @dev 验证证据哈希格式
     * @param fileHashes 文件哈希数组
     * @return valid 是否有效
     */
    function validateEvidenceHashes(
        string[] memory fileHashes
    ) internal pure returns (bool valid) {
        if (fileHashes.length == 0) {
            return false;
        }
        
        for (uint256 i = 0; i < fileHashes.length; i++) {
            bytes memory hashBytes = bytes(fileHashes[i]);
            // 检查哈希长度（假设使用SHA256，64个字符）
            if (hashBytes.length != 64) {
                return false;
            }
            
            // 检查是否为有效的十六进制字符
            for (uint256 j = 0; j < hashBytes.length; j++) {
                bytes1 char = hashBytes[j];
                if (!(char >= '0' && char <= '9') && 
                    !(char >= 'a' && char <= 'f') &&
                    !(char >= 'A' && char <= 'F')) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @dev 计算奖励分配比例
     * @param totalReward 总奖励
     * @param userWeight 用户权重
     * @param totalWeight 总权重
     * @return userReward 用户应得奖励
     */
    function calculateRewardShare(
        uint256 totalReward,
        uint256 userWeight,
        uint256 totalWeight
    ) internal pure returns (uint256 userReward) {
        if (totalWeight == 0) {
            return 0;
        }
        return (totalReward * userWeight) / totalWeight;
    }

    /**
     * @dev 检查是否超时
     * @param deadline 截止时间
     * @return expired 是否已超时
     */
    function isExpired(uint256 deadline) internal view returns (bool expired) {
        return block.timestamp > deadline;
    }

    /**
     * @dev 安全的百分比计算
     * @param amount 基数
     * @param percentage 百分比（基于PERCENTAGE_BASE）
     * @return result 计算结果
     */
    function calculatePercentage(
        uint256 amount,
        uint256 percentage
    ) internal pure returns (uint256 result) {
        return (amount * percentage) / PERCENTAGE_BASE;
    }

    /**
     * @dev 获取随机种子（用于随机选择验证者）
     * @param caseId 案件ID
     * @param blockNumber 区块号
     * @return seed 随机种子
     */
    function getRandomSeed(
        uint256 caseId,
        uint256 blockNumber
    ) internal view returns (uint256 seed) {
        return uint256(keccak256(abi.encodePacked(
            caseId,
            blockNumber,
            block.timestamp,
            block.difficulty
        )));
    }
} 