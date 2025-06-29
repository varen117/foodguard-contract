// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Errors.sol";
import "./Events.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CommonModifiers
 * @author Food Safety Governance Team
 * @notice 公共修饰符库，统一管理系统中重复使用的修饰符和验证逻辑
 * @dev 通过继承此合约，其他合约可以使用统一的修饰符，减少代码重复
 * 使用基于角色的权限控制系统，更加安全和灵活
 */
abstract contract CommonModifiers is AccessControl {

    // ==================== 角色定义 ====================

    /// @notice 治理角色 - 拥有系统治理权限的角色
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ==================== 事件定义 ====================

    /// @notice 治理合约设置事件
    event GovernanceContractSet(address indexed governanceContract, address indexed module, uint256 timestamp);

    // ==================== 修饰符 ====================

    /**
     * @notice 只有治理角色可以调用
     * @dev 统一的治理权限检查修饰符，使用基于角色的权限控制
     */
    modifier onlyGovernance() {
        _checkRole(GOVERNANCE_ROLE);
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

    // ==================== 治理管理函数 ====================

    /**
     * @notice 统一的治理合约设置函数
     * @dev 所有模块都可以使用这个函数来设置治理权限，避免代码重复
     * @param _governanceContract 治理合约地址
     * @param moduleName 模块名称，用于事件记录
     */
    function _setGovernanceRole(address _governanceContract, string memory moduleName) internal notZeroAddress(_governanceContract) {
        // 授予治理合约治理权限
        _grantRole(GOVERNANCE_ROLE, _governanceContract);
        
        // 发出统一的事件
        emit GovernanceContractSet(_governanceContract, address(this), block.timestamp);
        
        // 发出业务处理异常事件（保持向后兼容）
        emit Events.BusinessProcessAnomaly(
            0,
            _governanceContract,
            "Governance Setup",
            string(abi.encodePacked(moduleName, " governance contract updated")),
            "New governance contract granted GOVERNANCE_ROLE",
            block.timestamp
        );
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
}
