// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 随机选择器
 * @dev 公平随机选择DAO成员进行投票和验证的核心合约
 * 
 * 🎲 随机选择机制：
 * 1. 投票者选择：从所有DAO成员中随机选择指定数量的投票者
 * 2. 验证者选择：从未参与投票的DAO成员中随机选择验证者
 * 3. 防重复机制：确保同一投诉中不会重复选择相同成员
 * 4. 排除机制：支持排除特定地址（如已投票的成员）
 * 
 * 🔐 随机性保证：
 * - 使用区块时间戳、随机数、投诉ID等多重熵源
 * - 防止操控：基于区块链固有的不可预测性
 * - 最大尝试次数限制，防止无限循环
 */
contract RandomSelector is Ownable {
    
    // ==================== 事件定义 ====================
    
    /// @dev 投票者选择完成事件
    /// @param complaintId 投诉ID
    /// @param voters 被选中的投票者地址数组
    event VotersSelected(uint256 indexed complaintId, address[] voters);
    
    /// @dev 验证者选择完成事件
    /// @param complaintId 投诉ID
    /// @param verifiers 被选中的验证者地址数组
    event VerifiersSelected(uint256 indexed complaintId, address[] verifiers);
    
    /// @dev 构造函数
    /// 初始化随机选择器
    constructor() Ownable(msg.sender) {}
    
    // ==================== 核心随机选择功能 ====================
    
    /**
     * @dev 随机选择投票者
     * 🔥 流程图中"随机选择DAO组织成员进行投票"的核心实现
     * 
     * 选择机制：
     * - 高风险投诉：需要选择3个投票者
     * - 中低风险投诉：需要选择2个投票者
     * - 防重复：同一投诉中不会选择相同的成员
     * - 排除机制：可以排除特定成员（如有利益冲突的成员）
     * 
     * @param _members 所有合格DAO成员地址数组
     * @param _count 需要选择的投票者数量
     * @param _seed 随机种子（用于保证随机性）
     * @param _excludeList 需要排除的地址列表
     * @return 被选中的投票者地址数组
     */
    function selectRandomVoters(
        address[] memory _members,
        uint256 _count,
        uint256 _seed,
        address[] memory _excludeList
    ) external pure returns (address[] memory) {
        require(_members.length > 0, "No members available");
        require(_count > 0, "Count must be positive");
        
        // 🔍 过滤掉需要排除的成员
        address[] memory eligibleMembers = _filterExcluded(_members, _excludeList);
        require(eligibleMembers.length >= _count, "Not enough eligible members");
        
        // 初始化选择结果数组和已使用索引追踪
        address[] memory selectedVoters = new address[](_count);
        uint256[] memory usedIndices = new uint256[](eligibleMembers.length);
        uint256 usedCount = 0;
        
        // 🎲 逐个随机选择投票者
        for (uint256 i = 0; i < _count; i++) {
            uint256 randomIndex;
            bool validIndex = false;
            uint256 attempts = 0;
            
            // 寻找一个未被使用的有效随机索引
            while (!validIndex && attempts < 100) {
                randomIndex = uint256(keccak256(abi.encodePacked(_seed, i, attempts))) % eligibleMembers.length;
                validIndex = true;
                
                // 检查这个索引是否已经被使用过
                for (uint256 j = 0; j < usedCount; j++) {
                    if (usedIndices[j] == randomIndex) {
                        validIndex = false;
                        break;
                    }
                }
                attempts++;
            }
            
            require(validIndex, "Failed to find unique random index");
            
            // 记录选中的投票者和已使用的索引
            selectedVoters[i] = eligibleMembers[randomIndex];
            usedIndices[usedCount] = randomIndex;
            usedCount++;
        }
        
        return selectedVoters;
    }
    
    /**
     * @dev 随机选择验证者（排除已投票的成员）
     * 🔥 流程图中"随机分配未参与过本次投票的DAO成员对其证据材料和投票结果进行验证"的核心实现
     * 
     * 验证者选择规则：
     * - 必须是未参与本次投票的DAO成员
     * - 通常选择1个验证者进行验证
     * - 验证失败时会重新选择其他未参与的成员
     * - 确保验证过程的独立性和公正性
     * 
     * @param _members 所有合格DAO成员地址数组
     * @param _count 需要选择的验证者数量
     * @param _seed 随机种子
     * @param _excludeList 需要排除的地址列表（包含已投票的成员）
     * @return 被选中的验证者地址数组
     */
    function selectRandomVerifiers(
        address[] memory _members,
        uint256 _count,
        uint256 _seed,
        address[] memory _excludeList
    ) external view returns (address[] memory) {
        require(_members.length > 0, "No members available");
        require(_count > 0, "Count must be positive");
        
        // 🚫 过滤掉排除成员（包括已投票的成员）
        address[] memory eligibleMembers = _filterExcluded(_members, _excludeList);
        require(eligibleMembers.length >= _count, "Not enough eligible verifiers");
        
        return _selectRandom(eligibleMembers, _count, _seed);
    }
    
    // ==================== 内部辅助函数 ====================
    
    /**
     * @dev 内部随机选择函数
     * 使用增强的随机性（包含区块时间戳）进行选择
     * 
     * @param _members 候选成员数组
     * @param _count 选择数量
     * @param _seed 随机种子
     * @return 选择结果数组
     */
    function _selectRandom(
        address[] memory _members,
        uint256 _count,
        uint256 _seed
    ) internal view returns (address[] memory) {
        address[] memory selected = new address[](_count);
        uint256[] memory usedIndices = new uint256[](_members.length);
        uint256 usedCount = 0;
        
        for (uint256 i = 0; i < _count; i++) {
            uint256 randomIndex;
            bool validIndex = false;
            uint256 attempts = 0;
            
            while (!validIndex && attempts < 100) {
                randomIndex = uint256(keccak256(abi.encodePacked(_seed, i, attempts, block.timestamp))) % _members.length;
                validIndex = true;
                
                for (uint256 j = 0; j < usedCount; j++) {
                    if (usedIndices[j] == randomIndex) {
                        validIndex = false;
                        break;
                    }
                }
                attempts++;
            }
            
            require(validIndex, "Failed to find unique random index");
            
            selected[i] = _members[randomIndex];
            usedIndices[usedCount] = randomIndex;
            usedCount++;
        }
        
        return selected;
    }
    
    /**
     * @dev 从成员列表中过滤掉需要排除的地址
     * 用于排除已投票成员、有利益冲突的成员等
     * 
     * @param _members 原始成员地址数组
     * @param _excludeList 需要排除的地址数组
     * @return 过滤后的合格成员数组
     */
    function _filterExcluded(
        address[] memory _members,
        address[] memory _excludeList
    ) internal pure returns (address[] memory) {
        // 如果没有排除列表，直接返回原数组
        if (_excludeList.length == 0) {
            return _members;
        }
        
        // 创建临时数组存储过滤结果
        address[] memory temp = new address[](_members.length);
        uint256 count = 0;
        
        // 遍历所有成员，检查是否需要排除
        for (uint256 i = 0; i < _members.length; i++) {
            bool excluded = false;
            
            // 检查当前成员是否在排除列表中
            for (uint256 j = 0; j < _excludeList.length; j++) {
                if (_members[i] == _excludeList[j]) {
                    excluded = true;
                    break;
                }
            }
            
            // 如果未被排除，加入结果数组
            if (!excluded) {
                temp[count] = _members[i];
                count++;
            }
        }
        
        // 创建正确大小的最终数组
        address[] memory filtered = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            filtered[i] = temp[i];
        }
        
        return filtered;
    }
    
    // ==================== 工具函数 ====================
    
    /**
     * @dev 生成伪随机种子
     * 结合多种区块链不可预测的数据源生成随机种子
     * 
     * 熵源包括：
     * - block.timestamp：区块时间戳
     * - block.prevrandao：前一个区块的随机数
     * - _complaintId：投诉ID（业务相关）
     * - msg.sender：调用者地址
     * 
     * @param _complaintId 投诉ID
     * @return 生成的随机种子
     */
    function generateSeed(uint256 _complaintId) external view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.timestamp,    // 区块时间戳
            block.prevrandao,   // 区块随机数
            _complaintId,       // 投诉ID
            msg.sender          // 调用者地址
        )));
    }
    
    /**
     * @dev 检查地址是否在列表中
     * 用于验证某个地址是否已经被选中或排除
     * 
     * @param _target 要检查的目标地址
     * @param _list 地址列表
     * @return 是否在列表中
     */
    function isInList(address _target, address[] memory _list) external pure returns (bool) {
        for (uint256 i = 0; i < _list.length; i++) {
            if (_list[i] == _target) {
                return true;
            }
        }
        return false;
    }
} 