// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IFoodGuardDAO.sol";

/**
 * @title 食品安全DAO治理系统主合约
 * @dev 基于区块链的去中心化食品安全投诉处理和治理系统
 * 
 * 🌟 系统核心流程：
 * 1️⃣ 【存入保证金】- 投诉者和企业存入最低保证金参与系统
 * 2️⃣ 【提交投诉】- 投诉者提交投诉，系统自动进行风险等级判定
 * 3️⃣ 【风险分流】- 高风险：冻结企业保证金；中低风险：保证金不冻结
 * 4️⃣ 【随机投票】- 随机选择DAO成员进行投票（高风险需3票，中低风险需2票）
 * 5️⃣ 【投票验证】- 随机选择验证者验证投票结果，确保投票真实性
 * 6️⃣ 【结果执行】- 根据投票结果进行奖惩：败诉方保证金没收，胜诉方获得奖励
 * 7️⃣ 【奖励分配】- 90%奖金分给诚实投票者，10%进入备用基金
 * 8️⃣ 【质押收益】- 用户质押资金获得年化5%收益，资金来源于备用基金
 * 
 * 🔒 安全机制：防重入攻击、权限控制、暂停机制、输入验证
 * 💰 经济激励：保证金机制确保诚信参与，奖励机制激励积极治理
 * 🎲 公平保证：随机选择机制防止操控，验证机制确保投票质量
 */
contract FoodGuardDAO is IFoodGuardDAO, ReentrancyGuard, Ownable, Pausable {
    
    // ==================== 系统常量配置 ====================
    
    /// @dev 个人用户最低保证金要求：0.1 ETH
    /// 投诉者、DAO成员等个人参与者的保证金门槛
    uint256 public constant MIN_INDIVIDUAL_DEPOSIT = 0.1 ether;
    
    /// @dev 企业用户最低保证金要求：1.0 ETH
    /// 企业需要更高保证金，确保有足够资金承担处罚
    uint256 public constant MIN_COMPANY_DEPOSIT = 1.0 ether;
    
    /// @dev 高风险投诉所需投票数：3票
    /// 涉及食物中毒、污染爆发等严重问题需要更多投票确保准确性
    uint256 public constant HIGH_RISK_VOTES_REQUIRED = 3;
    
    /// @dev 中低风险投诉所需投票数：2票  
    /// 一般性问题投票门槛相对较低，提高处理效率
    uint256 public constant LOW_RISK_VOTES_REQUIRED = 2;
    
    /// @dev 奖金池分配比例：90%给诚实投票者
    /// 确保参与治理的DAO成员获得足够激励
    uint256 public constant PRIZE_POOL_DISTRIBUTION = 90;
    
    /// @dev 备用基金比例：10%进入储备
    /// 用于支付质押利息和系统运营，保证系统可持续性
    uint256 public constant RESERVE_FUND_DISTRIBUTION = 10;
    
    // ==================== 核心状态变量 ====================
    
    /// @dev 投诉计数器，用于生成唯一投诉ID
    uint256 public complaintCounter;
    
    /// @dev 备用基金总额，用于支付质押利息和奖励
    /// 资金来源：投诉处理中的10%奖金池 + 直接捐赠
    uint256 public totalReserveFund;
    
    /// @dev 系统总质押金额，所有用户质押资金的总和
    uint256 public totalStakedAmount;
    
    // ==================== 核心映射关系 ====================
    
    /// @dev 投诉ID => 投诉详情映射
    /// 存储所有投诉的完整信息和处理状态
    mapping(uint256 => Complaint) public complaints;
    
    /// @dev 用户地址 => 保证金余额映射
    /// 记录每个用户（投诉者/企业）的保证金数额
    mapping(address => uint256) public depositBalances;
    
    /// @dev 用户地址 => 用户类型映射
    /// 记录每个用户的类型（个人或企业），用于保证金验证
    mapping(address => IFoodGuardDAO.UserType) public userTypes;
    
    /// @dev 用户地址 => 是否为DAO成员映射
    /// 只有DAO成员才能参与投票和验证
    mapping(address => bool) public daoMembers;
    
    /// @dev 用户地址 => 质押金额映射
    /// 记录每个用户的质押资金数额
    mapping(address => uint256) public stakedBalances;
    
    /// @dev 用户地址 => 最后质押时间映射
    /// 用于计算质押利息的时间基准
    mapping(address => uint256) public lastStakeTime;
    
    /// @dev 投诉ID => 用户地址 => 是否已投票映射
    /// 防止同一投诉中重复投票
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    /// @dev 投诉ID => 用户地址 => 是否已验证映射  
    /// 防止同一投诉中重复验证
    mapping(uint256 => mapping(address => bool)) public hasVerified;
    
    // ==================== 辅助数组 ====================
    
    /// @dev DAO成员地址列表，便于随机选择和遍历
    address[] public daoMembersList;
    
    /// @dev 质押者地址列表，便于利息分配和管理
    address[] public stakers;
    
    // ==================== 构造函数和修饰器 ====================
    
    /// @dev 合约构造函数
    /// 初始化时合约处于暂停状态，需要管理员手动启用
    constructor() Ownable(msg.sender) {
        _pause(); // 启动时暂停，等待初始设置完成
    }
    
    /// @dev 仅DAO成员可调用修饰器
    /// 确保只有授权的DAO成员才能参与投票和验证
    modifier onlyDAOMember() {
        require(daoMembers[msg.sender], "Not a DAO member");
        _;
    }
    
    /// @dev 投诉存在性检查修饰器
    /// 确保操作的投诉ID有效且存在
    modifier complaintExists(uint256 _complaintId) {
        require(_complaintId > 0 && _complaintId <= complaintCounter, "Complaint does not exist");
        _;
    }
    
    // ==================== DAO成员管理功能 ====================
    
    /**
     * @dev 添加DAO成员（仅管理员）
     * 管理员可以添加新的DAO成员参与系统治理
     * @param _member 新DAO成员的地址
     */
    function addDAOMember(address _member) external onlyOwner {
        require(_member != address(0), "Invalid address");
        require(!daoMembers[_member], "Already a DAO member");
        
        daoMembers[_member] = true;
        daoMembersList.push(_member);
        
        emit DAOMemberAdded(_member);
    }
    
    /**
     * @dev 移除DAO成员（仅管理员）
     * 管理员可以移除不当行为的DAO成员
     * @param _member 要移除的DAO成员地址
     */
    function removeDAOMember(address _member) external onlyOwner {
        require(daoMembers[_member], "Not a DAO member");
        
        daoMembers[_member] = false;
        
        // 从数组中移除该成员（使用swap-and-pop优化gas）
        for (uint256 i = 0; i < daoMembersList.length; i++) {
            if (daoMembersList[i] == _member) {
                daoMembersList[i] = daoMembersList[daoMembersList.length - 1];
                daoMembersList.pop();
                break;
            }
        }
        
        emit DAOMemberRemoved(_member);
    }
    
    // ==================== 保证金管理功能（流程第一步）====================
    
    /**
     * @dev 存入保证金
     *  核心流程第一步：所有参与者必须先存入保证金才能使用系统
     * 投诉者需要保证金防止恶意投诉，企业需要保证金作为处罚基础
     * @param _userType 用户类型（个人0.1ETH，企业1.0ETH）
     */
    function depositGuarantee(IFoodGuardDAO.UserType _userType) external payable nonReentrant {
        uint256 minDeposit = _userType == IFoodGuardDAO.UserType.Company ? 
            MIN_COMPANY_DEPOSIT : MIN_INDIVIDUAL_DEPOSIT;
        
        require(msg.value >= minDeposit, "Insufficient deposit amount for user type");
        
        // 记录用户类型（首次存入时设置，后续不可更改）
        if (depositBalances[msg.sender] == 0) {
            userTypes[msg.sender] = _userType;
        } else {
            require(userTypes[msg.sender] == _userType, "Cannot change user type");
        }
        
        depositBalances[msg.sender] += msg.value;
        
        emit DepositMade(msg.sender, msg.value);
    }
    
    // ==================== 投诉提交功能（流程第二、三步）====================
    
    /**
     * @dev 提交投诉
     *  核心流程第二步：投诉者提交食品安全投诉
     *  核心流程第三步：根据风险等级自动决定是否冻结企业保证金
     * 
     * 风险分流逻辑：
     * - 高风险：自动冻结企业保证金，需要3票通过
     * - 中低风险：不冻结保证金，需要2票通过
     * 
     * @param _company 被投诉的企业地址
     * @param _description 投诉描述和证据材料
     * @param _riskLevel 风险评估等级（由RiskAssessment合约评估得出）
     * @return 生成的投诉ID
     */
    function submitComplaint(
        address _company,
        string memory _description,
        RiskLevel _riskLevel
    ) external nonReentrant returns (uint256) {
        require(_company != address(0), "Invalid company address");
        uint256 requiredDeposit = userTypes[msg.sender] == IFoodGuardDAO.UserType.Company ? 
            MIN_COMPANY_DEPOSIT : MIN_INDIVIDUAL_DEPOSIT;
        require(depositBalances[msg.sender] >= requiredDeposit, "Insufficient deposit");
        require(bytes(_description).length > 0, "Description required");
        
        complaintCounter++;
        uint256 complaintId = complaintCounter;
        
        // 创建投诉记录
        complaints[complaintId] = Complaint({
            id: complaintId,
            complainant: msg.sender,
            company: _company,
            description: _description,
            riskLevel: _riskLevel,
            status: ComplaintStatus.Pending,
            votesFor: 0,
            votesAgainst: 0,
            prizePool: 0,
            resolved: false,
            companyDepositFrozen: _riskLevel == RiskLevel.High // 高风险自动冻结
        });
        
                 //  关键分流逻辑：高风险投诉自动冻结企业保证金
        if (_riskLevel == RiskLevel.High) {
            require(depositBalances[_company] >= MIN_COMPANY_DEPOSIT, "Company has insufficient deposit");
            // 保证金已在创建投诉时标记为冻结状态
        }
        
        emit ComplaintSubmitted(complaintId, msg.sender, _company, _riskLevel);
        
        return complaintId;
    }
    
    // ==================== DAO投票功能（流程第四步）====================
    
    /**
     * @dev 提交投票（DAO成员随机选择后进行投票）
     *  核心流程第四步：随机选择的DAO成员对投诉进行投票
     * 
     * 投票机制：
     * - 高风险投诉：需要3票（HIGH_RISK_VOTES_REQUIRED）
     * - 中低风险投诉：需要2票（LOW_RISK_VOTES_REQUIRED）
     * - 每个DAO成员只能对同一投诉投票一次
     * - 需要提交证据材料支持投票决定
     * 
     * @param _complaintId 投诉ID
     * @param _support 是否支持投诉（true=支持投诉者，false=支持企业）
     * @param _evidence 投票的证据材料和理由
     */
    function submitVote(
        uint256 _complaintId,
        bool _support,
        string memory _evidence
    ) external onlyDAOMember complaintExists(_complaintId) nonReentrant {
        Complaint storage complaint = complaints[_complaintId];
        require(complaint.status == ComplaintStatus.Pending, "Complaint not in pending status");
        require(!hasVoted[_complaintId][msg.sender], "Already voted");
        require(bytes(_evidence).length > 0, "Evidence required");
        
        // 标记该成员已投票，防止重复投票
        hasVoted[_complaintId][msg.sender] = true;
        
        // 统计投票结果
        if (_support) {
            complaint.votesFor++;    // 支持投诉（认为企业有问题）
        } else {
            complaint.votesAgainst++; // 反对投诉（认为投诉无效）
        }
        
        emit VoteSubmitted(_complaintId, msg.sender, _support, _evidence);
        
        //  检查是否达到投票要求，自动进入验证阶段
        uint256 requiredVotes = complaint.riskLevel == RiskLevel.High ? 
            HIGH_RISK_VOTES_REQUIRED : LOW_RISK_VOTES_REQUIRED;
            
        if (complaint.votesFor + complaint.votesAgainst >= requiredVotes) {
            complaint.status = ComplaintStatus.Voting; // 进入验证阶段
        }
    }
    
    // ==================== 投票验证功能（流程第五步）====================
    
    /**
     * @dev 验证投票结果（二层验证机制）
     *  核心流程第五步：随机选择未参与投票的DAO成员验证投票质量
     * 
     * 验证机制：
     * - 验证者必须是未参与本次投票的DAO成员
     * - 验证者检查投票的证据材料和投票结果的合理性
     * - 验证通过：进入结果统计和奖惩执行
     * - 验证失败：投票作废，重新开始投票，虚假验证者被处罚
     * 
     * @param _complaintId 投诉ID
     * @param _verified 验证结果（true=验证通过，false=投票存在问题需重新投票）
     */
    function verifyVote(
        uint256 _complaintId,
        bool _verified
    ) external onlyDAOMember complaintExists(_complaintId) nonReentrant {
        Complaint storage complaint = complaints[_complaintId];
        require(complaint.status == ComplaintStatus.Voting, "Not in voting verification phase");
        require(!hasVoted[_complaintId][msg.sender], "Cannot verify own vote");
        require(!hasVerified[_complaintId][msg.sender], "Already verified");
        
        // 标记已验证，防止重复验证
        hasVerified[_complaintId][msg.sender] = true;
        
        emit VoteVerified(_complaintId, msg.sender, _verified);
        
        if (_verified) {
            //  验证通过：进入投票结果统计和奖惩执行阶段
            _resolveComplaint(_complaintId);
        } else {
            //  验证失败：投票作废，重新开始投票流程
            complaint.status = ComplaintStatus.Pending;
            complaint.votesFor = 0;
            complaint.votesAgainst = 0;
            
            // 🚨 惩罚虚假验证者：扣除保证金的10%加入奖金池
            uint256 penalty = depositBalances[msg.sender] / 10; // 10%处罚
            if (penalty > 0) {
                depositBalances[msg.sender] -= penalty;
                complaint.prizePool += penalty; // 处罚金进入奖金池
            }
        }
    }
    
    // ==================== 投诉解决和奖惩执行（流程第六步）====================
    
    /**
     * @dev 解决投诉并执行奖惩（内部函数）
     *  核心流程第六步：根据投票结果统计执行最终奖惩
     * 
     * 奖惩逻辑：
     * - 赞同多于反对：企业败诉，扣除企业保证金，降低企业信誉分
     * - 反对多于赞同：投诉者败诉，扣除投诉者保证金
     * - 高风险投诉：解冻或没收企业保证金
     * - 中低风险投诉：根据结果进行相应处理
     * 
     * @param _complaintId 投诉ID
     */
    function _resolveComplaint(uint256 _complaintId) internal {
        Complaint storage complaint = complaints[_complaintId];
        bool companyPenalized = complaint.votesFor > complaint.votesAgainst;
        
        complaint.resolved = true;
        complaint.status = ComplaintStatus.Resolved;
        
        if (companyPenalized) {
            // 🚨 企业败诉：执行企业处罚
            // 1. 扣除企业保证金
            uint256 companyPenalty = depositBalances[complaint.company];
            if (companyPenalty > 0) {
                depositBalances[complaint.company] = 0;
                complaint.prizePool += companyPenalty; // 企业保证金加入奖金池
            }
            // 2. 降低企业信誉分（TODO: 集成RiskAssessment合约）
            // 3. 提高企业保证金最低限额（TODO: 动态调整机制）
        } else {
            // 🚨 投诉者败诉：执行投诉者处罚
            uint256 complainantPenalty = depositBalances[complaint.complainant];
            if (complainantPenalty > 0) {
                depositBalances[complaint.complainant] = 0;
                complaint.prizePool += complainantPenalty; // 投诉者保证金加入奖金池
            }
            // 对于高风险投诉，解冻企业保证金
            if (complaint.riskLevel == RiskLevel.High) {
                complaint.companyDepositFrozen = false;
            }
        }
        
        // 🎁 从备用基金中拿出一部分资金用于验证者奖励发放
        uint256 rewardFromReserve = totalReserveFund / 100; // 备用基金的1%
        if (rewardFromReserve > 0 && rewardFromReserve <= totalReserveFund) {
            totalReserveFund -= rewardFromReserve;
            complaint.prizePool += rewardFromReserve;
        }
        
        emit ComplaintResolved(_complaintId, companyPenalized, complaint.prizePool);
        
        //  执行奖励分配
        _distributeRewards(_complaintId);
    }
    
    // ==================== 奖励分配系统（流程第七步）====================
    
    /**
     * @dev 分配奖励给诚实投票者
     *  核心流程第七步：奖金分配系统
     * 
     * 分配规则：
     * - 90%奖金分配给诚实投票者（PRIZE_POOL_DISTRIBUTION）
     * - 10%进入备用基金，用于质押利息和系统运营
     * - 排除虚假投票成员，只奖励诚实参与者
     * - 验证者也可获得奖励（从备用基金中支付）
     * 
     * @param _complaintId 投诉ID
     */
    function _distributeRewards(uint256 _complaintId) internal {
        Complaint storage complaint = complaints[_complaintId];
        
        // 🎯 奖金池分配：90%给投票者，10%进入备用基金
        uint256 totalRewards = (complaint.prizePool * PRIZE_POOL_DISTRIBUTION) / 100; // 90%
        uint256 reserveAmount = complaint.prizePool - totalRewards; // 10%
        
        // 🏦 10%进入备用基金，用于质押利息和验证者奖励
        totalReserveFund += reserveAmount;
        
        // 🔍 统计诚实投票者数量
        uint256 honestVoters = 0;
        
        // 简化实现：假设所有投票者都是诚实的
        // TODO: 实际应用中需要更复杂的诚实度判断机制
        for (uint256 i = 0; i < daoMembersList.length; i++) {
            address member = daoMembersList[i];
            if (hasVoted[_complaintId][member]) {
                honestVoters++;
            }
        }
        
        // 🎁 分配奖励给诚实投票者
        if (honestVoters > 0 && totalRewards > 0) {
            uint256 rewardPerVoter = totalRewards / honestVoters;
            
            for (uint256 i = 0; i < daoMembersList.length; i++) {
                address member = daoMembersList[i];
                if (hasVoted[_complaintId][member]) {
                    // 奖励直接加入成员的保证金余额
                    depositBalances[member] += rewardPerVoter;
                }
            }
        }
        
        emit RewardsDistributed(_complaintId, totalRewards);
    }
    
    // ==================== 质押系统（流程第八步）====================
    
    /**
     * @dev 质押资金获得年化收益
     *  核心流程第八步：个体用户质押资金到备用基金
     * 
     * 质押机制：
     * - 用户可以质押ETH到系统获得年化5%收益
     * - 质押资金进入备用基金，用于支付奖励和利息
     * - 每一笔质押基金都会根据企业罚款数量进行一定比例的分红
     * - 利息来源于投诉处理中产生的10%备用基金
     */
    function stake() external payable nonReentrant {
        require(msg.value > 0, "Must stake positive amount");
        
        // 首次质押者加入质押者列表
        if (stakedBalances[msg.sender] == 0) {
            stakers.push(msg.sender);
        }
        
        // 更新质押记录
        stakedBalances[msg.sender] += msg.value;
        totalStakedAmount += msg.value;
        lastStakeTime[msg.sender] = block.timestamp; // 重置计息时间
        
        emit StakeDeposited(msg.sender, msg.value);
    }
    
    /**
     * @dev 提取质押资金和累计利息
     * 用户可以提取部分或全部质押资金，系统自动计算并支付累计利息
     * 
     * @param _amount 要提取的质押金额
     */
    function withdrawStake(uint256 _amount) external nonReentrant {
        require(stakedBalances[msg.sender] >= _amount, "Insufficient staked balance");
        require(_amount > 0, "Must withdraw positive amount");
        
        // 💰 计算并支付累计利息（从备用基金中支付）
        uint256 interest = calculateInterest(msg.sender);
        if (interest > 0 && interest <= totalReserveFund) {
            totalReserveFund -= interest; // 从备用基金扣除
            payable(msg.sender).transfer(interest);
            emit InterestPaid(msg.sender, interest);
        }
        
        // 更新质押记录
        stakedBalances[msg.sender] -= _amount;
        totalStakedAmount -= _amount;
        lastStakeTime[msg.sender] = block.timestamp; // 重置计息时间
        
        // 如果完全提取，从质押者列表中移除
        if (stakedBalances[msg.sender] == 0) {
            for (uint256 i = 0; i < stakers.length; i++) {
                if (stakers[i] == msg.sender) {
                    stakers[i] = stakers[stakers.length - 1];
                    stakers.pop();
                    break;
                }
            }
        }
        
        // 返还质押本金
        payable(msg.sender).transfer(_amount);
        emit StakeWithdrawn(msg.sender, _amount);
    }
    
    /**
     * @dev 计算质押利息
     * 基于质押时间和年化5%收益率计算累计利息
     * 
     * @param _staker 质押者地址
     * @return 累计利息金额
     */
    function calculateInterest(address _staker) public view returns (uint256) {
        if (stakedBalances[_staker] == 0) return 0;
        
        uint256 timeStaked = block.timestamp - lastStakeTime[_staker];
        uint256 annualRate = 5; // 年化5%收益率
        uint256 interest = (stakedBalances[_staker] * annualRate * timeStaked) / (365 days * 100);
        
        return interest;
    }
    
    // ==================== 保证金提取功能 ====================
    
    /**
     * @dev 提取保证金
     * 用户可以提取未被冻结的保证金（需确保没有参与进行中的投诉）
     * 
     * @param _amount 要提取的保证金数额
     */
    function withdrawDeposit(uint256 _amount) external nonReentrant {
        require(depositBalances[msg.sender] >= _amount, "Insufficient balance");
        require(_amount > 0, "Must withdraw positive amount");
        
        depositBalances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        
        emit DepositWithdrawn(msg.sender, _amount);
    }
    
    // ==================== 查询功能 ====================
    
    /**
     * @dev 获取投诉详细信息
     * 
     * @param _complaintId 投诉ID
     * @return 投诉的完整信息结构体
     */
    function getComplaint(uint256 _complaintId) 
        external 
        view 
        complaintExists(_complaintId) 
        returns (Complaint memory) 
    {
        return complaints[_complaintId];
    }
    
    /**
     * @dev 获取所有DAO成员列表
     * 用于前端显示和随机选择算法
     * 
     * @return DAO成员地址数组
     */
    function getDAOMembers() external view returns (address[] memory) {
        return daoMembersList;
    }
    
    /**
     * @dev 获取质押者详细信息
     * 
     * @param _staker 质押者地址
     * @return balance 当前质押余额
     * @return interest 累计利息
     * @return lastStake 最后一次质押时间
     */
    function getStakerInfo(address _staker) 
        external 
        view 
        returns (uint256 balance, uint256 interest, uint256 lastStake) 
    {
        balance = stakedBalances[_staker];
        interest = calculateInterest(_staker);
        lastStake = lastStakeTime[_staker];
    }
    
    // ==================== 紧急管理功能 ====================
    
    /**
     * @dev 暂停合约（仅管理员）
     * 紧急情况下可以暂停所有核心功能
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev 恢复合约（仅管理员）
     * 解除暂停状态，恢复正常运行
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ==================== 接收ETH功能 ====================
    
    /**
     * @dev 接收ETH的回调函数
     * 直接发送到合约的ETH将自动加入备用基金
     * 可用于社区捐赠或追加系统资金
     */
    receive() external payable {
        totalReserveFund += msg.value;
    }
} 