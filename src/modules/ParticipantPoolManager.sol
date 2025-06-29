// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../libraries/CommonModifiers.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ParticipantPoolManager
 * @author Food Safety Governance Team
 * @notice 统一的参与者池管理合约
 * @dev 管理所有用户的角色分类和参与状态，支持Chainlink VRF随机选择
 *
 * 核心功能：
 * 1. 角色管理：COMPLAINANT、ENTERPRISE、DAO_MEMBER三种角色
 * 2. 统一池管理：所有参与者在同一个池中按角色分类
 * 3. 随机选择：使用Chainlink VRF进行真正的随机选择
 * 4. 参与控制：每个案件中用户只能选择一个角色参与
 * 5. 权限验证：根据角色控制功能访问权限
 */
contract ParticipantPoolManager is Ownable, CommonModifiers {
    // ==================== 状态变量 ====================

    /// @notice 用户角色映射 user => role
    mapping(address => DataStructures.UserRole) public userRoles;

    /// @notice 用户是否已注册
    mapping(address => bool) public isRegistered;

    /// @notice 按角色分类的用户池
    mapping(DataStructures.UserRole => address[]) public rolePools;

    /// @notice 用户在角色池中的索引 role => user => index
    mapping(DataStructures.UserRole => mapping(address => uint256)) public userPoolIndex;

    /// @notice 用户在角色池中是否存在 role => user => exists
    mapping(DataStructures.UserRole => mapping(address => bool)) public isInRolePool;

    /// @notice 案件参与记录 caseId => user => hasParticipated
    mapping(uint256 => mapping(address => bool)) public caseParticipation;

    /// @notice 案件中用户的角色 caseId => user => role
    mapping(uint256 => mapping(address => DataStructures.UserRole)) public caseUserRole;

    /// @notice 用户活跃状态 user => isActive
    mapping(address => bool) public isUserActive;

    /// @notice 用户声誉分数 user => reputation
    mapping(address => uint256) public userReputation;


    // ==================== 配置参数 ====================

    /// @notice 验证者选择配置
    struct ValidatorConfig {
        uint256 minValidators;    // 最少验证者数量（必须为奇数）
        uint256 maxValidators;    // 最多验证者数量
        uint256 defaultValidators; // 默认验证者数量
    }

    /// @notice 质疑者选择配置
    struct ChallengerConfig {
        uint256 maxChallengersPerValidator; // 每个验证者最多质疑者数量（偶数）
        uint256 minChallengerReputation;    // 质疑者最低声誉要求
    }

    ValidatorConfig public validatorConfig;
    ChallengerConfig public challengerConfig;

    // ==================== 事件定义 ====================

    event UserRegistered(address indexed user, DataStructures.UserRole role, uint256 timestamp);
    event UserRoleUpdated(address indexed user, DataStructures.UserRole oldRole, DataStructures.UserRole newRole);
    event ValidatorsSelected(uint256 indexed caseId, address[] validators);
    event ChallengersSelected(uint256 indexed caseId, address targetValidator, address[] challengers);

    // ==================== 修饰符 ====================


    // ==================== 构造函数 ====================

    constructor(address _admin) Ownable(_admin) {
        // 初始化验证者配置
        validatorConfig = ValidatorConfig({
            minValidators: 3,      // 最少3个验证者（奇数）
            maxValidators: 15,     // 最多15个验证者
            defaultValidators: 5   // 默认5个验证者
        });

        // 初始化质疑者配置
        challengerConfig = ChallengerConfig({
            maxChallengersPerValidator: 4, // 每个验证者最多4个质疑者（偶数）
            minChallengerReputation: 500   // 质疑者最低声誉500分
        });

    }

    // ==================== 用户注册和角色管理 ====================

    /**
     * @notice 注册用户并分配角色
     * @param user 用户地址
     * @param role 用户角色
     */
    function registerUser(address user, DataStructures.UserRole role) external onlyGovernance {
        require(user != address(0), "Invalid user address");
        require(!isRegistered[user], "User already registered");

        // 注册用户
        isRegistered[user] = true;
        userRoles[user] = role;
        isUserActive[user] = true;
        userReputation[user] = 1000; // 初始声誉1000分

        // 添加到对应角色池
        _addToRolePool(user, role);

        emit UserRegistered(user, role, block.timestamp);
    }

    /**
     * @notice 更新用户角色
     * @param user 用户地址
     * @param newRole 新角色
     */
    function updateUserRole(address user, DataStructures.UserRole newRole) external onlyGovernance {
        require(isRegistered[user], "User not registered");
        DataStructures.UserRole oldRole = userRoles[user];
        require(oldRole != newRole, "Same role");

        // 从旧角色池移除
        _removeFromRolePool(user, oldRole);

        // 添加到新角色池
        userRoles[user] = newRole;
        _addToRolePool(user, newRole);

        emit UserRoleUpdated(user, oldRole, newRole);
    }

    /**
     * @notice 更新用户活跃状态
     * @param user 用户地址
     * @param active 是否活跃
     */
    function setUserActive(address user, bool active) external onlyGovernance {
        require(isRegistered[user], "User not registered");
        isUserActive[user] = active;
    }

    /**
     * @notice 更新用户声誉分数
     * @param user 用户地址
     * @param reputation 新声誉分数
     */
    function updateUserReputation(address user, uint256 reputation) external onlyGovernance {
        require(isRegistered[user], "User not registered");
        userReputation[user] = reputation;
    }

    // ==================== 随机选择功能 ====================

    /**
     * @notice 为案件随机选择验证者
     * @param caseId 案件ID
     * @return validators 选中的验证者地址数组
     */
    function selectValidators(uint256 caseId, uint256[] calldata randomWords)
    external
    onlyGovernance
    returns (address[] memory validators)
    {
        // 验证参数
        require(randomWords.length > 0, "Random words cannot be empty");

        // 获取可用的DAO成员作为验证者（排除已参与此案件的用户）
        address[] memory availableValidators = _getAvailableParticipants(caseId,
            DataStructures.UserRole.DAO_MEMBER, randomWords);
        if (availableValidators.length < validatorConfig.minValidators) {
            revert Errors.InsufficientAvailableParticipants( caseId);
        }
        // 发送验证者已选定事件
        emit ValidatorsSelected(caseId, availableValidators);
        return validators;
    }

    // ==================== 内部函数 ====================

    /**
     * @notice 添加用户到角色池
     */
    function _addToRolePool(address user, DataStructures.UserRole role) internal {
        if (!isInRolePool[role][user]) {
            rolePools[role].push(user);
            userPoolIndex[role][user] = rolePools[role].length - 1;
            isInRolePool[role][user] = true;
        }
    }

    /**
     * @notice 从角色池移除用户
     */
    function _removeFromRolePool(address user, DataStructures.UserRole role) internal {
        if (isInRolePool[role][user]) {
            uint256 index = userPoolIndex[role][user];
            uint256 lastIndex = rolePools[role].length - 1;

            if (index != lastIndex) {
                address lastUser = rolePools[role][lastIndex];
                rolePools[role][index] = lastUser;
                userPoolIndex[role][lastUser] = index;
            }

            rolePools[role].pop();
            delete userPoolIndex[role][user];
            isInRolePool[role][user] = false;
        }
    }

    /**
     * @notice 获取可用参与者（排除已参与案件的用户）
     */
    function _getAvailableParticipants(
        uint256 caseId,
        DataStructures.UserRole role,
        uint256[] calldata randomWords
    )
    internal
    returns (address[] memory available)
    {
        address[] memory rolePool = rolePools[role];
        uint256 availableCount = 0;
        address[] memory temporaryAvailable;
        address[] memory availableParticipants;
        // 第一次遍历：计算可用用户数量
        for (uint256 i = 0; i < rolePool.length; i++) {
            address user = rolePool[i];
            if (isUserActive[user] && !caseParticipation[caseId][user]) {
                availableCount++;
                temporaryAvailable[i] = user;
            }
        }

        for(uint i=0; i < randomWords.length; i++) {
            address user = temporaryAvailable[randomWords[i] % availableCount];
            availableParticipants[i] = user;
            // 记录参与状态：这些DAO成员在此案件中担任验证者角色
            caseParticipation[caseId][user] = true;
            caseUserRole[caseId][user] = role;
        }
        return availableParticipants;
    }

    /**
     * @notice 获取可用的质疑者（额外检查声誉要求）
     */
    function _getAvailableChallengersForValidator(uint256 caseId, address targetValidator)
    internal
    view
    returns (address[] memory available)
    {
        address[] memory daoMembers = rolePools[DataStructures.UserRole.DAO_MEMBER];
        uint256 availableCount = 0;

        // 第一次遍历：计算可用质疑者数量
        for (uint256 i = 0; i < daoMembers.length; i++) {
            address user = daoMembers[i];
            if (isUserActive[user] &&
                !caseParticipation[caseId][user] &&
                user != targetValidator &&
                userReputation[user] >= challengerConfig.minChallengerReputation) {
                availableCount++;
            }
        }

        // 第二次遍历：填充可用质疑者数组
        available = new address[](availableCount);
        uint256 index = 0;
        for (uint256 i = 0; i < daoMembers.length; i++) {
            address user = daoMembers[i];
            if (isUserActive[user] &&
                !caseParticipation[caseId][user] &&
                user != targetValidator &&
                userReputation[user] >= challengerConfig.minChallengerReputation) {
                available[index++] = user;
            }
        }

        return available;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 检查用户是否可以参与案件
     */
    function canParticipateInCase(uint256 caseId, address user, DataStructures.UserRole requiredRole)
    external
    view
    returns (bool)
    {
        return isRegistered[user] &&
        isUserActive[user] &&
        userRoles[user] == requiredRole &&
            !caseParticipation[caseId][user];
    }

    /**
     * @notice 获取角色池大小
     */
    function getRolePoolSize(DataStructures.UserRole role) external view returns (uint256) {
        return rolePools[role].length;
    }

    /**
     * @notice 获取角色池中的用户
     */
    function getRolePoolUsers(DataStructures.UserRole role) external view returns (address[] memory) {
        return rolePools[role];
    }

    /**
     * @notice 获取用户详细信息
     */
    function getUserInfo(address user) external view returns (
        bool registered,
        DataStructures.UserRole role,
        bool active,
        uint256 reputation
    ) {
        return (
            isRegistered[user],
            userRoles[user],
            isUserActive[user],
            userReputation[user]
        );
    }

    /**
     * @notice 检查用户在案件中的参与状态
     */
    function getUserCaseParticipation(uint256 caseId, address user) external view returns (
        bool hasParticipated,
        DataStructures.UserRole participationRole
    ) {
        return (
            caseParticipation[caseId][user],
            caseUserRole[caseId][user]
        );
    }

    /**
     * @notice 检查企业是否已注册
     */
    function isEnterpriseRegistered(address enterprise) external view returns (bool) {
        return isRegistered[enterprise] && userRoles[enterprise] == DataStructures.UserRole.ENTERPRISE;
    }

    /**
     * @notice 获取用户总数
     */
    function getTotalUsers() external view returns (uint256) {
        return rolePools[DataStructures.UserRole.COMPLAINANT].length +
        rolePools[DataStructures.UserRole.ENTERPRISE].length +
            rolePools[DataStructures.UserRole.DAO_MEMBER].length;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址并授予治理权限
     * @dev 使用统一的治理设置方法，保证一致性
     */
    function setGovernanceContract(address _governanceContract) external onlyOwner {
        _setGovernanceRole(_governanceContract, "ParticipantPoolManager");
    }

    /**
     * @notice 更新验证者配置
     */
    function updateValidatorConfig(ValidatorConfig calldata newConfig) external onlyOwner {
        require(newConfig.minValidators % 2 == 1, "Min validators must be odd");
        require(newConfig.defaultValidators % 2 == 1, "Default validators must be odd");
        require(newConfig.minValidators <= newConfig.defaultValidators, "Invalid config");
        require(newConfig.defaultValidators <= newConfig.maxValidators, "Invalid config");

        validatorConfig = newConfig;
    }

    /**
     * @notice 更新质疑者配置
     */
    function updateChallengerConfig(ChallengerConfig calldata newConfig) external onlyOwner {
        require(newConfig.maxChallengersPerValidator % 2 == 0, "Max challengers must be even");
        challengerConfig = newConfig;
    }

    /**
     * @notice 批量更新用户声誉
     */
    function batchUpdateReputation(address[] calldata users, uint256[] calldata reputations) external onlyGovernance {
        require(users.length == reputations.length, "Array length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            if (isRegistered[users[i]]) {
                userReputation[users[i]] = reputations[i];
            }
        }
    }

    /**
     * @notice 重置案件参与状态（紧急情况使用）
     */
    function resetCaseParticipation(uint256 caseId, address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            caseParticipation[caseId][users[i]] = false;
            delete caseUserRole[caseId][users[i]];
        }
    }
}
