// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFoodGuardDAO
 * @dev 食品安全DAO治理系统接口
 * 
 * 这个接口定义了去中心化食品安全投诉治理系统的核心数据结构和事件。
 * 系统通过DAO投票机制处理食品安全投诉，确保公正透明的治理流程。
 * 
 * 主要流程：
 * 1. 存入保证金 → 提交投诉
 * 2. 风险等级判定（高/中/低风险）
 * 3. 高风险：冻结企业保证金 → DAO投票 → 验证 → 奖惩
 * 4. 中低风险：直接DAO投票 → 验证 → 奖惩
 * 5. 奖金分配：90%给诚实投票者，10%进入备用基金
 * 6. 质押系统：用户质押获得年化收益
 */
interface IFoodGuardDAO {
    
    /// @dev 用户类型枚举
    /// 区分个人用户和企业用户，用于不同的保证金要求
    enum UserType {
        Individual,  // 个人用户：投诉者、DAO成员等个人参与者
        Company      // 企业用户：被投诉的企业或商户
    }
    
    /// @dev 投诉风险等级枚举
    /// 根据投诉内容、企业历史记录等因素自动评估
    enum RiskLevel {
        Low,     // 低风险：一般性问题，如包装、外观等
        Medium,  // 中风险：卫生问题、过期等
        High     // 高风险：食物中毒、污染爆发等严重问题
    }
    
    /// @dev 投诉状态枚举
    /// 描述投诉在处理流程中的当前阶段
    enum ComplaintStatus {
        Pending,  // 待处理：等待DAO成员投票
        Voting,   // 投票中：已收集足够投票，等待验证
        Resolved  // 已解决：投票验证完成，奖惩已执行
    }
    
    /// @dev 投诉信息结构体
    /// 包含投诉的完整信息和处理状态
    struct Complaint {
        uint256 id;                    // 投诉ID，唯一标识符
        address complainant;           // 投诉者地址
        address company;               // 被投诉企业地址
        string description;            // 投诉描述，包含证据材料
        RiskLevel riskLevel;           // 风险等级（低/中/高）
        ComplaintStatus status;        // 当前处理状态
        uint256 votesFor;              // 支持投诉的票数
        uint256 votesAgainst;          // 反对投诉的票数
        uint256 prizePool;             // 本投诉的奖金池总额
        bool resolved;                 // 是否已完成处理
        bool companyDepositFrozen;     // 企业保证金是否被冻结（仅高风险投诉）
    }
    
    // ==================== 事件定义 ====================
    
    /// @dev DAO成员被添加事件
    /// @param member 新添加的DAO成员地址
    event DAOMemberAdded(address indexed member);
    
    /// @dev DAO成员被移除事件  
    /// @param member 被移除的DAO成员地址
    event DAOMemberRemoved(address indexed member);
    
    /// @dev 保证金存入事件
    /// @param depositor 存入者地址
    /// @param amount 存入金额
    event DepositMade(address indexed depositor, uint256 amount);
    
    /// @dev 保证金提取事件
    /// @param depositor 提取者地址
    /// @param amount 提取金额
    event DepositWithdrawn(address indexed depositor, uint256 amount);
    
    /// @dev 投诉提交事件（流程开始）
    /// @param complaintId 投诉ID
    /// @param complainant 投诉者地址
    /// @param company 被投诉企业地址
    /// @param riskLevel 风险等级判定结果
    event ComplaintSubmitted(uint256 indexed complaintId, address indexed complainant, address indexed company, RiskLevel riskLevel);
    
    /// @dev DAO成员投票事件
    /// @param complaintId 投诉ID
    /// @param voter 投票者地址
    /// @param support 是否支持投诉（true=支持，false=反对）
    /// @param evidence 投票证据材料
    event VoteSubmitted(uint256 indexed complaintId, address indexed voter, bool support, string evidence);
    
    /// @dev 投票验证事件
    /// @param complaintId 投诉ID
    /// @param verifier 验证者地址
    /// @param verified 验证结果（true=验证通过，false=验证失败）
    event VoteVerified(uint256 indexed complaintId, address indexed verifier, bool verified);
    
    /// @dev 投诉解决事件（流程结束）
    /// @param complaintId 投诉ID
    /// @param companyPenalized 企业是否被处罚
    /// @param prizePoolAmount 奖金池总额
    event ComplaintResolved(uint256 indexed complaintId, bool companyPenalized, uint256 prizePoolAmount);
    
    /// @dev 奖励分配事件
    /// @param complaintId 投诉ID
    /// @param totalRewards 分配的总奖励金额
    event RewardsDistributed(uint256 indexed complaintId, uint256 totalRewards);
    
    /// @dev 质押存入事件
    /// @param staker 质押者地址
    /// @param amount 质押金额
    event StakeDeposited(address indexed staker, uint256 amount);
    
    /// @dev 质押提取事件
    /// @param staker 质押者地址
    /// @param amount 提取金额
    event StakeWithdrawn(address indexed staker, uint256 amount);
    
    /// @dev 利息支付事件
    /// @param staker 质押者地址
    /// @param amount 利息金额
    event InterestPaid(address indexed staker, uint256 amount);
    
    // ==================== 核心功能函数 ====================
    
    /// @dev 存入保证金（流程第一步）
    /// 投诉者和企业都需要存入保证金才能参与系统
    /// @param _userType 用户类型（个人或企业），决定最低保证金要求
    function depositGuarantee(UserType _userType) external payable;
    
    /// @dev 提交投诉（流程第二步）
    /// @param _company 被投诉企业地址
    /// @param _description 投诉描述和证据材料
    /// @param _riskLevel 风险等级（由风险评估系统确定）
    /// @return 投诉ID
    function submitComplaint(address _company, string memory _description, RiskLevel _riskLevel) external returns (uint256);
    
    /// @dev DAO成员投票（流程第三步）
    /// @param _complaintId 投诉ID
    /// @param _support 是否支持投诉
    /// @param _evidence 投票证据材料
    function submitVote(uint256 _complaintId, bool _support, string memory _evidence) external;
    
    /// @dev 验证投票结果（流程第四步）
    /// @param _complaintId 投诉ID
    /// @param _verified 验证结果
    function verifyVote(uint256 _complaintId, bool _verified) external;
    
    /// @dev 质押资金（获得年化收益）
    function stake() external payable;
    
    /// @dev 提取质押资金
    /// @param _amount 提取金额
    function withdrawStake(uint256 _amount) external;
    
    /// @dev 提取保证金
    /// @param _amount 提取金额
    function withdrawDeposit(uint256 _amount) external;
    
    /// @dev 计算质押利息
    /// @param _staker 质押者地址
    /// @return 累计利息金额
    function calculateInterest(address _staker) external view returns (uint256);
    
    /// @dev 获取投诉详情
    /// @param _complaintId 投诉ID
    /// @return 投诉完整信息
    function getComplaint(uint256 _complaintId) external view returns (Complaint memory);
    
    /// @dev 获取所有DAO成员列表
    /// @return DAO成员地址数组
    function getDAOMembers() external view returns (address[] memory);
    
    /// @dev 获取质押者信息
    /// @param _staker 质押者地址
    /// @return balance 质押余额
    /// @return interest 累计利息
    /// @return lastStake 最后质押时间
    function getStakerInfo(address _staker) external view returns (uint256 balance, uint256 interest, uint256 lastStake);
} 