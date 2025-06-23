// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";

/**
 * @title FundManager
 * @author Food Safety Governance Team
 * @notice 资金管理模块，负责处理保证金、奖励池和资金分配
 * @dev 处理所有资金相关操作，包括保证金存取、冻结解冻、奖励分配等
 */
contract FundManager is AccessControl, ReentrancyGuard, Pausable {
    // ==================== 角色定义 ====================
    
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ==================== 状态变量 ====================
    
    /// @notice 系统资金池
    DataStructures.FundPool public fundPool;
    
    /// @notice 用户保证金映射 user => total deposit
    mapping(address => uint256) public userDeposits;
    
    /// @notice 用户冻结保证金映射 user => frozen amount
    mapping(address => uint256) public frozenDeposits;
    
    /// @notice 案件相关冻结保证金映射 caseId => user => amount
    mapping(uint256 => mapping(address => uint256)) public caseFrozenDeposits;
    
    /// @notice 用户待领取奖励映射 user => pending rewards
    mapping(address => uint256) public pendingRewards;
    
    /// @notice 系统配置
    DataStructures.SystemConfig public systemConfig;
    
    /// @notice 最小保证金要求
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    
    /// @notice 最大保证金限制
    uint256 public constant MAX_DEPOSIT = 100 ether;
    
    // ==================== 修饰符 ====================
    
    /**
     * @notice 检查用户是否有足够的可用保证金
     */
    modifier hasAvailableDeposit(address user, uint256 amount) {
        uint256 totalDeposit = userDeposits[user];
        uint256 frozen = frozenDeposits[user];
        
        // 防止下溢：如果冻结金额大于总存款，说明状态异常
        if (frozen > totalDeposit) {
            revert Errors.InsufficientBalance(user, amount, 0);
        }
        
        uint256 available = totalDeposit - frozen;
        if (available < amount) {
            revert Errors.InsufficientBalance(user, amount, available);
        }
        _;
    }
    
    /**
     * @notice 检查地址是否为零地址
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }
    
    // ==================== 构造函数 ====================
    
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
        
        // 初始化系统配置
        systemConfig = DataStructures.SystemConfig({
            minComplaintDeposit: 0.1 ether,
            minEnterpriseDeposit: 1 ether,
            minChallengeDeposit: 0.05 ether,
            votingPeriod: 7 days,
            challengePeriod: 3 days,
            minValidators: 3,
            maxValidators: 15,
            rewardPoolPercentage: 70, // 70%
            operationalFeePercentage: 10 // 10%
        });
    }
    
    // ==================== 保证金管理函数 ====================
    
    /**
     * @notice 存入保证金
     * @dev 用户可以存入ETH作为保证金参与治理
     */
    function depositFunds() external payable whenNotPaused nonReentrant {
        if (msg.value < MIN_DEPOSIT) {
            revert Errors.InvalidAmount(msg.value, MIN_DEPOSIT);
        }
        
        if (userDeposits[msg.sender] + msg.value > MAX_DEPOSIT) {
            revert Errors.InvalidAmount(
                userDeposits[msg.sender] + msg.value, 
                MAX_DEPOSIT
            );
        }
        
        userDeposits[msg.sender] += msg.value;
        
        emit Events.DepositMade(
            msg.sender,
            msg.value,
            userDeposits[msg.sender],
            block.timestamp
        );
    }
    
    /**
     * @notice 提取可用保证金
     * @param amount 提取金额
     */
    function withdrawFunds(uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        hasAvailableDeposit(msg.sender, amount)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount, 1);
        }
        
        userDeposits[msg.sender] -= amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert Errors.TransferFailed(msg.sender, amount);
        }
        
        emit Events.FundsTransferredFromPool(
            msg.sender,
            amount,
            "Withdrawal",
            block.timestamp
        );
    }
    
    /**
     * @notice 冻结用户保证金（用于案件处理）
     * @param caseId 案件ID
     * @param user 用户地址
     * @param amount 冻结金额
     */
    function freezeDeposit(
        uint256 caseId,
        address user,
        uint256 amount
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        notZeroAddress(user)
        hasAvailableDeposit(user, amount)
    {
        frozenDeposits[user] += amount;
        caseFrozenDeposits[caseId][user] = amount;
        
        emit Events.DepositFrozen(
            caseId,
            user,
            amount,
            "Case processing",
            block.timestamp
        );
    }
    
    /**
     * @notice 解冻用户保证金
     * @param caseId 案件ID
     * @param user 用户地址
     */
    function unfreezeDeposit(
        uint256 caseId,
        address user
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        notZeroAddress(user)
    {
        uint256 frozenAmount = caseFrozenDeposits[caseId][user];
        if (frozenAmount == 0) {
            revert Errors.InvalidAmount(frozenAmount, 1);
        }
        
        frozenDeposits[user] -= frozenAmount;
        caseFrozenDeposits[caseId][user] = 0;
        
        emit Events.DepositUnfrozen(
            caseId,
            user,
            frozenAmount,
            block.timestamp
        );
    }
    
    /**
     * @notice 扣除用户保证金（作为惩罚）
     * @param caseId 案件ID
     * @param user 用户地址
     * @param amount 扣除金额
     * @param reason 扣除原因
     */
    function deductDeposit(
        uint256 caseId,
        address user,
        uint256 amount,
        string calldata reason
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        notZeroAddress(user)
    {
        uint256 frozenAmount = caseFrozenDeposits[caseId][user];
        if (amount > frozenAmount) {
            revert Errors.PunishmentExceedsDeposit(amount, frozenAmount);
        }
        
        userDeposits[user] -= amount;
        frozenDeposits[user] -= amount;
        caseFrozenDeposits[caseId][user] -= amount;
        
        // 将扣除的资金转入基金池
        _addToFundPool(amount, "Punishment");
        
        emit Events.DepositDeducted(
            caseId,
            user,
            amount,
            reason,
            block.timestamp
        );
    }
    
    // ==================== 奖励管理函数 ====================
    
    /**
     * @notice 添加用户待领取奖励
     * @param user 用户地址
     * @param amount 奖励金额
     */
    function addPendingReward(
        address user,
        uint256 amount
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        notZeroAddress(user)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount, 1);
        }
        
        if (fundPool.rewardPool < amount) {
            revert Errors.InsufficientFundPool(amount, fundPool.rewardPool);
        }
        
        pendingRewards[user] += amount;
        fundPool.rewardPool -= amount;
        
        emit Events.RewardDistributed(
            0, // 通用奖励，无特定案件ID
            user,
            amount,
            "Performance reward",
            block.timestamp
        );
    }
    
    /**
     * @notice 用户领取奖励
     */
    function claimRewards() external whenNotPaused nonReentrant {
        uint256 rewardAmount = pendingRewards[msg.sender];
        if (rewardAmount == 0) {
            revert Errors.InvalidAmount(rewardAmount, 1);
        }
        
        pendingRewards[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: rewardAmount}("");
        if (!success) {
            revert Errors.TransferFailed(msg.sender, rewardAmount);
        }
        
        emit Events.FundsTransferredFromPool(
            msg.sender,
            rewardAmount,
            "Reward claim",
            block.timestamp
        );
    }
    
    /**
     * @notice 批量分配奖励
     * @param caseId 案件ID
     * @param recipients 接收者地址数组
     * @param amounts 奖励金额数组
     */
    function batchDistributeRewards(
        uint256 caseId,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
    {
        if (recipients.length != amounts.length) {
            revert Errors.InvalidAmount(recipients.length, amounts.length);
        }
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        if (fundPool.rewardPool < totalAmount) {
            revert Errors.InsufficientFundPool(totalAmount, fundPool.rewardPool);
        }
        
        fundPool.rewardPool -= totalAmount;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) {
                revert Errors.ZeroAddress();
            }
            
            pendingRewards[recipients[i]] += amounts[i];
            
            emit Events.RewardDistributed(
                caseId,
                recipients[i],
                amounts[i],
                "Case participation reward",
                block.timestamp
            );
        }
    }
    
    // ==================== 资金池管理函数 ====================
    
    /**
     * @notice 向资金池添加资金
     * @param amount 金额
     * @param source 资金来源
     */
    function _addToFundPool(uint256 amount, string memory source) internal {
        uint256 rewardPoolShare = (amount * systemConfig.rewardPoolPercentage) / 100;
        uint256 operationalShare = (amount * systemConfig.operationalFeePercentage) / 100;
        uint256 reserveShare = amount - rewardPoolShare - operationalShare;
        
        fundPool.totalBalance += amount;
        fundPool.rewardPool += rewardPoolShare;
        fundPool.operationalFund += operationalShare;
        fundPool.reserveBalance += reserveShare;
        
        emit Events.FundsTransferredToPool(
            0, // 通用转入
            amount,
            source,
            block.timestamp
        );
        
        emit Events.FundPoolUpdated(
            fundPool.totalBalance,
            fundPool.rewardPool,
            fundPool.operationalFund,
            fundPool.emergencyFund,
            block.timestamp
        );
    }
    
    /**
     * @notice 紧急提取资金（仅管理员）
     * @param amount 提取金额
     * @param recipient 接收者地址
     * @param reason 提取原因
     */
    function emergencyWithdraw(
        uint256 amount,
        address recipient,
        string calldata reason
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        notZeroAddress(recipient)
    {
        if (fundPool.emergencyFund < amount) {
            revert Errors.InsufficientFundPool(amount, fundPool.emergencyFund);
        }
        
        fundPool.emergencyFund -= amount;
        fundPool.totalBalance -= amount;
        
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Errors.TransferFailed(recipient, amount);
        }
        
        emit Events.FundsTransferredFromPool(
            recipient,
            amount,
            reason,
            block.timestamp
        );
    }
    
    // ==================== 系统配置函数 ====================
    
    /**
     * @notice 更新系统配置
     * @param newConfig 新配置
     */
    function updateSystemConfig(
        DataStructures.SystemConfig calldata newConfig
    ) external onlyRole(GOVERNANCE_ROLE) {
        // 验证配置参数的合理性
        if (newConfig.minComplaintDeposit < MIN_DEPOSIT || 
            newConfig.minEnterpriseDeposit < MIN_DEPOSIT ||
            newConfig.minChallengeDeposit < MIN_DEPOSIT) {
            revert Errors.InvalidConfiguration("deposit", 0);
        }
        
        if (newConfig.votingPeriod < 1 days || newConfig.votingPeriod > 30 days) {
            revert Errors.ConfigurationOutOfRange(
                "votingPeriod", 
                newConfig.votingPeriod, 
                1 days, 
                30 days
            );
        }
        
        if (newConfig.minValidators == 0 || 
            newConfig.minValidators > newConfig.maxValidators) {
            revert Errors.InvalidConfiguration("validators", 0);
        }
        
        if (newConfig.rewardPoolPercentage + newConfig.operationalFeePercentage > 100) {
            revert Errors.InvalidConfiguration("percentage", 100);
        }
        
        systemConfig = newConfig;
        
        emit Events.SystemConfigUpdated(
            "SystemConfig",
            0,
            1,
            msg.sender,
            block.timestamp
        );
    }
    
    // ==================== 查询函数 ====================
    
    /**
     * @notice 获取用户可用保证金
     * @param user 用户地址
     * @return 可用保证金数量
     */
    function getAvailableDeposit(address user) external view returns (uint256) {
        uint256 totalDeposit = userDeposits[user];
        uint256 frozen = frozenDeposits[user];
        
        // 防止下溢：如果冻结金额大于总存款，返回0
        if (frozen > totalDeposit) {
            return 0;
        }
        
        return totalDeposit - frozen;
    }
    
    /**
     * @notice 获取案件相关冻结保证金
     * @param caseId 案件ID
     * @param user 用户地址
     * @return 冻结保证金数量
     */
    function getCaseFrozenDeposit(
        uint256 caseId, 
        address user
    ) external view returns (uint256) {
        return caseFrozenDeposits[caseId][user];
    }
    
    /**
     * @notice 获取资金池状态
     * @return 资金池详细信息
     */
    function getFundPoolStatus() external view returns (DataStructures.FundPool memory) {
        return fundPool;
    }
    
    /**
     * @notice 获取系统配置
     * @return 系统配置详细信息
     */
    function getSystemConfig() external view returns (DataStructures.SystemConfig memory) {
        return systemConfig;
    }
    
    // ==================== 管理函数 ====================
    
    /**
     * @notice 暂停合约
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        
        emit Events.SystemPauseStatusChanged(
            true,
            msg.sender,
            block.timestamp
        );
    }
    
    /**
     * @notice 恢复合约
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        
        emit Events.SystemPauseStatusChanged(
            false,
            msg.sender,
            block.timestamp
        );
    }
    
    /**
     * @notice 接收ETH
     */
    receive() external payable {
        _addToFundPool(msg.value, "Direct deposit");
    }
    
    /**
     * @notice 处理用户注册时的保证金存入
     * @param user 用户地址
     * @param amount 保证金金额
     */
    function registerUserDeposit(address user, uint256 amount) 
        external 
        payable 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        notZeroAddress(user)
    {
        if (msg.value != amount) {
            revert Errors.InvalidAmount(msg.value, amount);
        }
        
        if (amount < MIN_DEPOSIT) {
            revert Errors.InvalidAmount(amount, MIN_DEPOSIT);
        }
        
        if (userDeposits[user] + amount > MAX_DEPOSIT) {
            revert Errors.InvalidAmount(
                userDeposits[user] + amount, 
                MAX_DEPOSIT
            );
        }
        
        userDeposits[user] += amount;
        
        emit Events.DepositMade(
            user,
            amount,
            userDeposits[user],
            block.timestamp
        );
    }
} 