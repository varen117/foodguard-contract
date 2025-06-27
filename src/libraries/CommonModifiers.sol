// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Errors.sol";

/**
 * @title CommonModifiers
 * @author Food Safety Governance Team
 * @notice 公共修饰符库，统一管理系统中重复使用的修饰符和验证逻辑
 * @dev 通过继承此合约，其他合约可以使用统一的修饰符，减少代码重复
 */
abstract contract CommonModifiers {
    
    // ==================== 状态变量 ====================
    
    /// @notice 治理合约地址
    address public governanceContract;
    
    // ==================== 修饰符 ====================
    
    /**
     * @notice 只有治理合约可以调用
     * @dev 统一的治理权限检查修饰符
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }
    
    /**
     * @notice 检查地址是否为零地址
     * @dev 统一的零地址检查修饰符
     */
    modifier notZeroAddress(address account) {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }
    
    /**
     * @notice 检查字符串是否为空
     * @dev 统一的字符串非空检查修饰符
     */
    modifier notEmptyString(string calldata str) {
        if (bytes(str).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }
        _;
    }
    
    /**
     * @notice 检查时间戳是否有效
     * @dev 统一的时间戳验证修饰符
     */
    modifier validTimestamp(uint256 timestamp) {
        if (timestamp > block.timestamp) {
            revert Errors.InvalidTimestamp(timestamp, block.timestamp);
        }
        _;
    }
    
    // ==================== 内部验证函数 ====================
    
    /**
     * @notice 验证地址不为零
     * @dev 内部函数，用于在复杂验证逻辑中调用
     */
    function _requireNotZeroAddress(address account) internal pure {
        if (account == address(0)) {
            revert Errors.ZeroAddress();
        }
    }
    
    /**
     * @notice 验证字符串不为空
     * @dev 内部函数，用于在复杂验证逻辑中调用
     */
    function _requireNotEmptyString(string memory str) internal pure {
        if (bytes(str).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }
    }
    
    /**
     * @notice 验证多个字符串都不为空
     * @dev 内部函数，批量验证多个字符串
     */
    function _requireNotEmptyStrings(string memory str1, string memory str2) internal pure {
        _requireNotEmptyString(str1);
        _requireNotEmptyString(str2);
    }
    
    /**
     * @notice 验证时间戳有效性
     * @dev 内部函数，验证时间戳不超过当前时间
     */
    function _requireValidTimestamp(uint256 timestamp) internal view {
        if (timestamp > block.timestamp) {
            revert Errors.InvalidTimestamp(timestamp, block.timestamp);
        }
    }
    
    // ==================== 管理函数 ====================
    
    /**
     * @notice 设置治理合约地址
     * @dev 受保护的函数，只能由合约所有者调用
     */
    function _setGovernanceContract(address _governanceContract) internal {
        _requireNotZeroAddress(_governanceContract);
        governanceContract = _governanceContract;
    }
} 