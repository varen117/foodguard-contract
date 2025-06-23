// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IFoodGuard.sol";

/**
 * @title AccessControl
 * @dev 食品安全治理系统的访问控制合约
 * 管理系统中的角色权限和准入机制
 */
contract AccessControl is Ownable, ReentrancyGuard {

    // 角色管理
    mapping(address => bool) public isDAOMember;        // DAO成员映射
    mapping(address => bool) public isRegisteredEnterprise; // 注册企业映射
    mapping(address => bool) public isBlacklisted;     // 黑名单映射
    mapping(address => uint256) public memberJoinTime; // 成员加入时间
    mapping(address => uint256) public trustScore;     // 信任分数

    // 系统参数
    uint256 public constant MAX_DAO_MEMBERS = 1000;    // DAO成员上限
    uint256 public constant MIN_TRUST_SCORE = 500;     // 最低信任分数
    uint256 public constant TRUST_SCORE_BASE = 1000;   // 信任分数基数
    uint256 public daoMemberCount;                      // 当前DAO成员数量
    uint256 public membershipFee = 0.1 ether;          // 成员费用

    // 企业注册信息
    struct EnterpriseInfo {
        string name;                // 企业名称
        string registrationNumber;  // 注册号
        string businessLicense;     // 营业执照哈希
        uint256 registrationTime;   // 注册时间
        bool isActive;              // 是否活跃
    }
    mapping(address => EnterpriseInfo) public enterpriseInfo;

    // 事件定义
    event DAOMemberAdded(address indexed member, uint256 timestamp);
    event DAOMemberRemoved(address indexed member, uint256 timestamp);
    event EnterpriseRegistered(address indexed enterprise, string name, uint256 timestamp);
    event EnterpriseDeactivated(address indexed enterprise, uint256 timestamp);
    event TrustScoreUpdated(address indexed user, uint256 oldScore, uint256 newScore);
    event BlacklistUpdated(address indexed user, bool blacklisted);

    constructor() Ownable(msg.sender) {
        // 将部署者设为初始DAO成员
        _addDAOMember(msg.sender);
    }

    // 修饰符：只有DAO成员可以调用
    modifier onlyDAOMember() {
        require(isDAOMember[msg.sender], "AccessControl: Not a DAO member");
        require(!isBlacklisted[msg.sender], "AccessControl: User is blacklisted");
        _;
    }

    // 修饰符：只有注册企业可以调用
    modifier onlyRegisteredEnterprise() {
        require(isRegisteredEnterprise[msg.sender], "AccessControl: Not a registered enterprise");
        require(enterpriseInfo[msg.sender].isActive, "AccessControl: Enterprise is not active");
        require(!isBlacklisted[msg.sender], "AccessControl: Enterprise is blacklisted");
        _;
    }

    // 修饰符：检查用户是否被拉黑
    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "AccessControl: User is blacklisted");
        _;
    }

    // 修饰符：检查最低信任分数
    modifier hasMinTrustScore() {
        require(trustScore[msg.sender] >= MIN_TRUST_SCORE, "AccessControl: Trust score too low");
        _;
    }

    /**
     * @dev 申请成为DAO成员
     */
    function applyForDAOMembership() external payable nonReentrant notBlacklisted {
        require(msg.value >= membershipFee, "AccessControl: Insufficient membership fee");
        require(!isDAOMember[msg.sender], "AccessControl: Already a DAO member");
        require(daoMemberCount < MAX_DAO_MEMBERS, "AccessControl: DAO member limit reached");

        // 初始化信任分数
        if (trustScore[msg.sender] == 0) {
            trustScore[msg.sender] = TRUST_SCORE_BASE;
        }

        _addDAOMember(msg.sender);
        
        emit DAOMemberAdded(msg.sender, block.timestamp);
    }

    /**
     * @dev 内部函数：添加DAO成员
     */
    function _addDAOMember(address member) internal {
        isDAOMember[member] = true;
        memberJoinTime[member] = block.timestamp;
        daoMemberCount++;
    }

    /**
     * @dev 移除DAO成员（只有owner可以调用）
     */
    function removeDAOMember(address member) external onlyOwner {
        require(isDAOMember[member], "AccessControl: Not a DAO member");
        require(member != owner(), "AccessControl: Cannot remove owner");

        isDAOMember[member] = false;
        daoMemberCount--;
        
        emit DAOMemberRemoved(member, block.timestamp);
    }

    /**
     * @dev 企业注册
     */
    function registerEnterprise(
        string memory name,
        string memory registrationNumber,
        string memory businessLicense
    ) external payable nonReentrant notBlacklisted {
        require(msg.value >= membershipFee, "AccessControl: Insufficient registration fee");
        require(!isRegisteredEnterprise[msg.sender], "AccessControl: Already registered");
        require(bytes(name).length > 0, "AccessControl: Name cannot be empty");
        require(bytes(registrationNumber).length > 0, "AccessControl: Registration number cannot be empty");

        // 初始化信任分数
        if (trustScore[msg.sender] == 0) {
            trustScore[msg.sender] = TRUST_SCORE_BASE;
        }

        isRegisteredEnterprise[msg.sender] = true;
        enterpriseInfo[msg.sender] = EnterpriseInfo({
            name: name,
            registrationNumber: registrationNumber,
            businessLicense: businessLicense,
            registrationTime: block.timestamp,
            isActive: true
        });

        emit EnterpriseRegistered(msg.sender, name, block.timestamp);
    }

    /**
     * @dev 停用企业（只有owner可以调用）
     */
    function deactivateEnterprise(address enterprise) external onlyOwner {
        require(isRegisteredEnterprise[enterprise], "AccessControl: Not a registered enterprise");
        require(enterpriseInfo[enterprise].isActive, "AccessControl: Enterprise already inactive");

        enterpriseInfo[enterprise].isActive = false;
        
        emit EnterpriseDeactivated(enterprise, block.timestamp);
    }

    /**
     * @dev 内部函数：更新信任分数
     */
    function _updateTrustScore(address user, int256 delta) internal {
        uint256 oldScore = trustScore[user];
        
        if (delta > 0) {
            trustScore[user] += uint256(delta);
        } else if (delta < 0) {
            uint256 decrease = uint256(-delta);
            if (decrease >= trustScore[user]) {
                trustScore[user] = 0;
            } else {
                trustScore[user] -= decrease;
            }
        }

        emit TrustScoreUpdated(user, oldScore, trustScore[user]);
    }

    /**
     * @dev 更新信任分数
     */
    function updateTrustScore(address user, int256 delta) external onlyOwner {
        _updateTrustScore(user, delta);
    }

    /**
     * @dev 批量更新信任分数
     */
    function batchUpdateTrustScore(
        address[] memory users,
        int256[] memory deltas
    ) external onlyOwner {
        require(users.length == deltas.length, "AccessControl: Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            _updateTrustScore(users[i], deltas[i]);
        }
    }

    /**
     * @dev 添加/移除黑名单
     */
    function setBlacklist(address user, bool blacklisted) external onlyOwner {
        isBlacklisted[user] = blacklisted;
        
        if (blacklisted && isDAOMember[user]) {
            // 如果被拉黑的是DAO成员，自动移除
            isDAOMember[user] = false;
            daoMemberCount--;
        }

        emit BlacklistUpdated(user, blacklisted);
    }

    /**
     * @dev 检查用户是否有投票权限
     */
    function canVote(address user) external view returns (bool) {
        return (isDAOMember[user] && 
                !isBlacklisted[user] && 
                trustScore[user] >= MIN_TRUST_SCORE);
    }

    /**
     * @dev 检查用户是否可以提起投诉
     */
    function canComplain(address user) external view returns (bool) {
        return (!isBlacklisted[user] && trustScore[user] >= MIN_TRUST_SCORE);
    }

    /**
     * @dev 检查企业是否可以被投诉
     */
    function canBeComplained(address enterprise) external view returns (bool) {
        return (isRegisteredEnterprise[enterprise] && 
                enterpriseInfo[enterprise].isActive &&
                !isBlacklisted[enterprise]);
    }

    /**
     * @dev 获取随机DAO成员进行投票（简化版，实际应用中需要更复杂的随机选择机制）
     */
    function getRandomValidators(uint256 count, uint256 seed) 
        external 
        view 
        returns (address[] memory validators) 
    {
        require(count > 0, "AccessControl: Count must be greater than 0");
        require(count <= daoMemberCount, "AccessControl: Not enough DAO members");

        // 创建有效验证者数组
        address[] memory allValidators = new address[](daoMemberCount);
        uint256 validatorCount = 0;

        // 这里需要遍历所有地址，实际应用中应该维护一个活跃成员列表
        // 为了演示，这里使用简化逻辑
        validators = new address[](count);
        
        // 实际实现中应该有更好的随机选择算法
        return validators;
    }

    /**
     * @dev 设置成员费用（只有owner可以调用）
     */
    function setMembershipFee(uint256 newFee) external onlyOwner {
        membershipFee = newFee;
    }

    /**
     * @dev 提取合约中的资金（只有owner可以调用）
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "AccessControl: No funds to withdraw");
        
        payable(owner()).transfer(balance);
    }

    /**
     * @dev 获取企业信息
     */
    function getEnterpriseInfo(address enterprise) 
        external 
        view 
        returns (EnterpriseInfo memory) 
    {
        return enterpriseInfo[enterprise];
    }
} 