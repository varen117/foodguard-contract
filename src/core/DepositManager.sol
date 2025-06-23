// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFoodGuard.sol";
import "../libraries/Utils.sol";

/**
 * @title DepositManager
 * @dev 保证金管理合约
 * 负责处理所有与保证金相关的操作：存入、冻结、扣除、退还
 */
contract DepositManager is Ownable, ReentrancyGuard {
    
    // 保证金记录结构体
    struct DepositRecord {
        uint256 amount;                 // 保证金数额
        uint256 frozenAmount;           // 冻结金额
        uint256 lockedUntil;            // 锁定至什么时候
        bool isActive;                  // 是否活跃
        uint256 lastDepositTime;        // 最后存入时间
    }

    // 用户保证金映射
    mapping(address => DepositRecord) public userDeposits;
    
    // 案件相关的保证金冻结
    mapping(uint256 => mapping(address => uint256)) public caseDeposits; // caseId => user => amount
    mapping(uint256 => uint256) public totalCaseDeposits; // caseId => total amount
    
    // 系统参数
    uint256 public constant MIN_DEPOSIT = 0.01 ether;           // 最小保证金
    uint256 public constant MAX_DEPOSIT = 100 ether;            // 最大保证金
    uint256 public constant LOCK_PERIOD = 7 days;               // 锁定期
    uint256 public constant WITHDRAWAL_FEE_RATE = 100;          // 提取费率 1%
    
    // 保证金池
    uint256 public totalDeposits;                               // 总保证金
    uint256 public totalFrozenDeposits;                         // 总冻结保证金
    uint256 public systemReserve;                               // 系统储备金

    // 事件定义
    event DepositAdded(address indexed user, uint256 amount, uint256 timestamp);
    event DepositFrozen(address indexed user, uint256 caseId, uint256 amount, uint256 timestamp);
    event DepositUnfrozen(address indexed user, uint256 caseId, uint256 amount, uint256 timestamp);
    event DepositSlashed(address indexed user, uint256 caseId, uint256 amount, uint256 timestamp);
    event DepositWithdrawn(address indexed user, uint256 amount, uint256 fee, uint256 timestamp);
    event SystemReserveUpdated(uint256 oldAmount, uint256 newAmount);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev 存入保证金
     */
    function depositFunds() external payable nonReentrant {
        require(msg.value >= MIN_DEPOSIT, "DepositManager: Amount below minimum");
        require(msg.value <= MAX_DEPOSIT, "DepositManager: Amount exceeds maximum");

        DepositRecord storage record = userDeposits[msg.sender];
        
        // 检查总保证金是否超过限制
        require(record.amount + msg.value <= MAX_DEPOSIT, "DepositManager: Total deposit exceeds maximum");

        record.amount += msg.value;
        record.lastDepositTime = block.timestamp;
        record.lockedUntil = block.timestamp + LOCK_PERIOD;
        record.isActive = true;

        totalDeposits += msg.value;

        emit DepositAdded(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev 为特定案件存入保证金
     */
    function depositForCase(uint256 caseId) external payable nonReentrant {
        require(msg.value >= MIN_DEPOSIT, "DepositManager: Amount below minimum");
        require(caseId > 0, "DepositManager: Invalid case ID");

        // 先存入个人保证金
        DepositRecord storage record = userDeposits[msg.sender];
        record.amount += msg.value;
        record.lastDepositTime = block.timestamp;
        record.isActive = true;

        // 记录案件相关保证金
        caseDeposits[caseId][msg.sender] += msg.value;
        totalCaseDeposits[caseId] += msg.value;
        totalDeposits += msg.value;

        emit DepositAdded(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev 内部函数：冻结保证金
     */
    function _freezeDeposit(
        address user, 
        uint256 caseId, 
        uint256 amount
    ) internal {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        
        DepositRecord storage record = userDeposits[user];
        require(record.isActive, "DepositManager: User deposit not active");
        require(record.amount >= record.frozenAmount + amount, "DepositManager: Insufficient available balance");

        record.frozenAmount += amount;
        totalFrozenDeposits += amount;

        // 记录案件冻结
        caseDeposits[caseId][user] += amount;

        emit DepositFrozen(user, caseId, amount, block.timestamp);
    }

    /**
     * @dev 冻结保证金（用于案件处理期间）
     */
    function freezeDeposit(
        address user, 
        uint256 caseId, 
        uint256 amount
    ) external onlyOwner {
        _freezeDeposit(user, caseId, amount);
    }

    /**
     * @dev 批量冻结保证金
     */
    function batchFreezeDeposits(
        address[] memory users,
        uint256 caseId,
        uint256[] memory amounts
    ) external onlyOwner {
        require(users.length == amounts.length, "DepositManager: Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            _freezeDeposit(users[i], caseId, amounts[i]);
        }
    }

    /**
     * @dev 解冻保证金
     */
    function unfreezeDeposit(
        address user,
        uint256 caseId,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        
        DepositRecord storage record = userDeposits[user];
        require(record.frozenAmount >= amount, "DepositManager: Insufficient frozen amount");
        require(caseDeposits[caseId][user] >= amount, "DepositManager: Insufficient case deposit");

        record.frozenAmount -= amount;
        totalFrozenDeposits -= amount;
        caseDeposits[caseId][user] -= amount;

        emit DepositUnfrozen(user, caseId, amount, block.timestamp);
    }

    /**
     * @dev 内部函数：扣除保证金
     */
    function _slashDeposit(
        address user,
        uint256 caseId,
        uint256 amount
    ) internal returns (uint256 slashedAmount) {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        
        DepositRecord storage record = userDeposits[user];
        
        // 计算实际可扣除金额
        slashedAmount = amount;
        if (slashedAmount > record.amount) {
            slashedAmount = record.amount;
        }

        // 扣除保证金
        record.amount -= slashedAmount;
        totalDeposits -= slashedAmount;

        // 如果有冻结金额，相应减少
        if (record.frozenAmount > 0) {
            uint256 unfreezeAmount = slashedAmount;
            if (unfreezeAmount > record.frozenAmount) {
                unfreezeAmount = record.frozenAmount;
            }
            record.frozenAmount -= unfreezeAmount;
            totalFrozenDeposits -= unfreezeAmount;
        }

        // 添加到系统储备金
        systemReserve += slashedAmount;

        // 更新案件保证金记录
        if (caseDeposits[caseId][user] > 0) {
            uint256 caseDeductAmount = slashedAmount;
            if (caseDeductAmount > caseDeposits[caseId][user]) {
                caseDeductAmount = caseDeposits[caseId][user];
            }
            caseDeposits[caseId][user] -= caseDeductAmount;
            totalCaseDeposits[caseId] -= caseDeductAmount;
        }

        emit DepositSlashed(user, caseId, slashedAmount, block.timestamp);
        return slashedAmount;
    }

    /**
     * @dev 扣除保证金（作为惩罚）
     */
    function slashDeposit(
        address user,
        uint256 caseId,
        uint256 amount
    ) external onlyOwner returns (uint256 slashedAmount) {
        return _slashDeposit(user, caseId, amount);
    }

    /**
     * @dev 批量扣除保证金
     */
    function batchSlashDeposits(
        address[] memory users,
        uint256 caseId,
        uint256[] memory amounts
    ) external onlyOwner returns (uint256 totalSlashed) {
        require(users.length == amounts.length, "DepositManager: Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            totalSlashed += _slashDeposit(users[i], caseId, amounts[i]);
        }
    }

    /**
     * @dev 用户提取保证金
     */
    function withdrawDeposit(uint256 amount) external nonReentrant {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        
        DepositRecord storage record = userDeposits[msg.sender];
        require(record.isActive, "DepositManager: Deposit not active");
        require(block.timestamp >= record.lockedUntil, "DepositManager: Deposit still locked");
        
        uint256 availableAmount = record.amount - record.frozenAmount;
        require(availableAmount >= amount, "DepositManager: Insufficient available balance");

        // 计算提取费用
        uint256 fee = Utils.calculatePercentage(amount, WITHDRAWAL_FEE_RATE);
        uint256 withdrawAmount = amount - fee;

        // 更新记录
        record.amount -= amount;
        totalDeposits -= amount;
        systemReserve += fee;

        // 如果保证金为0，标记为非活跃
        if (record.amount == 0) {
            record.isActive = false;
        }

        // 转账
        payable(msg.sender).transfer(withdrawAmount);

        emit DepositWithdrawn(msg.sender, withdrawAmount, fee, block.timestamp);
    }

    /**
     * @dev 紧急提取（仅owner，用于特殊情况）
     */
    function emergencyWithdraw(address user, uint256 amount) external onlyOwner {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        
        DepositRecord storage record = userDeposits[user];
        require(record.amount >= amount, "DepositManager: Insufficient balance");

        record.amount -= amount;
        totalDeposits -= amount;

        payable(user).transfer(amount);
        
        emit DepositWithdrawn(user, amount, 0, block.timestamp);
    }

    /**
     * @dev 分配奖励（从系统储备金中）
     */
    function distributeReward(address recipient, uint256 amount) external onlyOwner {
        require(amount > 0, "DepositManager: Amount must be greater than 0");
        require(amount <= systemReserve, "DepositManager: Insufficient system reserve");
        require(recipient != address(0), "DepositManager: Invalid recipient");

        systemReserve -= amount;
        payable(recipient).transfer(amount);
    }

    /**
     * @dev 批量分配奖励
     */
    function batchDistributeRewards(
        address[] memory recipients,
        uint256[] memory amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "DepositManager: Array length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(totalAmount <= systemReserve, "DepositManager: Insufficient system reserve");

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0 && recipients[i] != address(0)) {
                systemReserve -= amounts[i];
                payable(recipients[i]).transfer(amounts[i]);
            }
        }
    }

    /**
     * @dev 增加系统储备金
     */
    function addSystemReserve() external payable onlyOwner {
        require(msg.value > 0, "DepositManager: Amount must be greater than 0");
        
        uint256 oldReserve = systemReserve;
        systemReserve += msg.value;
        
        emit SystemReserveUpdated(oldReserve, systemReserve);
    }

    // ========== 查询函数 ==========

    /**
     * @dev 获取用户保证金信息
     */
    function getUserDeposit(address user) external view returns (
        uint256 totalAmount,
        uint256 availableAmount,
        uint256 frozenAmount,
        uint256 lockedUntil,
        bool isActive
    ) {
        DepositRecord memory record = userDeposits[user];
        return (
            record.amount,
            record.amount - record.frozenAmount,
            record.frozenAmount,
            record.lockedUntil,
            record.isActive
        );
    }

    /**
     * @dev 获取案件保证金信息
     */
    function getCaseDepositInfo(uint256 caseId, address user) external view returns (
        uint256 userCaseDeposit,
        uint256 totalCaseDeposit
    ) {
        return (
            caseDeposits[caseId][user],
            totalCaseDeposits[caseId]
        );
    }

    /**
     * @dev 检查用户是否有足够的可用保证金
     */
    function hasEnoughBalance(address user, uint256 amount) external view returns (bool) {
        DepositRecord memory record = userDeposits[user];
        return record.isActive && (record.amount - record.frozenAmount >= amount);
    }

    /**
     * @dev 获取系统统计信息
     */
    function getSystemStats() external view returns (
        uint256 totalDepositsAmount,
        uint256 totalFrozenAmount,
        uint256 systemReserveAmount,
        uint256 contractBalance
    ) {
        return (
            totalDeposits,
            totalFrozenDeposits,
            systemReserve,
            address(this).balance
        );
    }
} 