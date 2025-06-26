// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，支持最新特性

import "../libraries/DataStructures.sol"; // 导入数据结构库，获取枚举和结构体定义
import "../libraries/Errors.sol"; // 导入错误库，用于统一的错误处理
import "../libraries/Events.sol"; // 导入事件库，用于发出标准化事件
import "@openzeppelin/contracts/access/Ownable.sol"; // 导入 OpenZeppelin 的所有权管理合约

/**
 * @title VotingManager
 * @author Food Safety Governance Team
 * @notice 投票管理模块，负责处理验证者选择、投票收集和结果统计
 * @dev 管理整个投票流程，包括验证者随机选择、投票期限控制、结果计算等
 * 这是食品安全治理系统的核心模块之一，确保决策过程的民主性和公正性
 * 通过随机选择验证者和透明的投票机制，保证案件处理的客观性
 */
contract VotingManager is Ownable {
    // ==================== 状态变量 ====================

    /// @notice 管理员地址 - 拥有系统管理权限的地址
    address public admin;

    /// @notice 治理合约地址（可以调用此合约的函数）
    /// @dev 只有治理合约才能启动投票会话和结束投票
    address public governanceContract;

    /// @notice 所有验证者地址列表 - 系统中注册的所有验证者
    /// @dev 这是验证者池，用于随机选择参与案件投票的验证者
    address[] public validatorPool;

    /// @notice 验证者信息映射 - 存储每个验证者的详细信息
    /// @dev 包括质押金额、声誉分数、参与历史等关键数据
    mapping(address => DataStructures.ValidatorInfo) public validators;

    /// @notice 验证者是否在池中的映射 - 快速查询验证者状态
    /// @dev 避免重复注册，提高查询效率
    mapping(address => bool) public isValidatorInPool;

    /// @notice 案件的投票信息映射 - 每个案件对应一个投票会话
    /// @dev 存储案件的完整投票过程和结果
    mapping(uint256 => VotingSession) public votingSessions;

    /// @notice 用户参与的投票记录 user => caseId => hasVoted
    /// @dev 防止重复投票，记录投票历史
    mapping(address => mapping(uint256 => bool)) public userVotingHistory;

    /// @notice 随机数种子 - 用于验证者随机选择
    /// @dev 确保验证者选择的随机性和不可预测性
    uint256 private randomSeed;

    // ==================== 结构体定义 ====================

    /**
     * @notice 投票会话结构体
     * @dev 记录单个案件的完整投票信息
     * 包含了从投票开始到结束的所有相关数据
     */
    struct VotingSession {
        uint256 caseId; // 案件ID - 与此投票会话关联的案件标识
        address[] selectedValidators; // 选中的验证者列表 - 参与此案件投票的验证者
        mapping(address => DataStructures.VoteInfo) votes; // 投票信息映射 - 每个验证者的具体投票内容
        uint256 supportVotes; // 支持投诉的票数 - 认为投诉成立的投票数量
        uint256 rejectVotes; // 反对投诉的票数 - 认为投诉不成立的投票数量
        uint256 totalVotes; // 总投票数 - 已提交投票的验证者总数
        uint256 startTime; // 投票开始时间 - 投票期开始的时间戳
        uint256 endTime; // 投票结束时间 - 投票期截止的时间戳
        bool isActive; // 投票是否激活 - 当前是否可以提交投票
        bool isCompleted; // 投票是否完成 - 投票流程是否已结束
        bool complaintUpheld; // 投诉是否成立（投票结果）- 最终的投票结论
        uint256 randomSeedUsed; // 使用的随机数种子 - 记录验证者选择时使用的随机数
    }

    // ==================== 修饰符 ====================

    /**
     * @notice 只有治理合约可以调用
     * @dev 确保关键功能只能由授权的治理合约执行
     * 防止未授权访问投票管理功能
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }

    /**
     * @notice 检查案件是否存在
     * @dev 防止对不存在的案件进行操作
     * 通过检查案件ID是否已初始化来验证存在性
     */
    modifier caseExists(uint256 caseId) {
        if (votingSessions[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    /**
     * @notice 检查投票是否激活
     * @dev 确保投票在正确的时间窗口内进行
     * 验证投票期是否开始且未超时
     */
    modifier votingActive(uint256 caseId) {
        VotingSession storage session = votingSessions[caseId];
        if (!session.isActive) {
            revert Errors.VotingNotStarted(caseId);
        }
        if (block.timestamp > session.endTime) {
            revert Errors.VotingPeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    // ==================== 构造函数 ====================

    /**
     * @dev 初始化投票管理合约
     * 设置初始管理员并生成初始随机数种子
     * @param _admin 管理员地址
     */
    constructor(address _admin) Ownable(_admin){
        // 生成初始随机数种子，结合区块信息和调用者信息
        randomSeed = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            )
        );
    }

    // ==================== 验证者管理函数 ====================

    /**
     * @notice 注册验证者
     * @dev 将新的验证者添加到验证者池中
     * 验证者需要提供质押和初始声誉分数
     * @param validatorAddress 验证者地址
     * @param stake 质押金额
     * @param initialReputation 初始声誉分数
     */
    function registerValidator(
        address validatorAddress,
        uint256 stake,
        uint256 initialReputation
    ) external onlyOwner payable {
        // 验证地址有效性，防止零地址注册
        if (validatorAddress == address(0)) {
            revert Errors.ZeroAddress();
        }

        // 防止重复注册同一个验证者
        if (isValidatorInPool[validatorAddress]) {
            revert Errors.DuplicateOperation(validatorAddress, "register");
        }

        // 创建验证者信息记录
        validators[validatorAddress] = DataStructures.ValidatorInfo({
            validatorAddress: validatorAddress, // 验证者的唯一地址标识
            stake: stake, // 质押的保证金数量
            reputationScore: initialReputation, // 初始声誉评分
            totalCasesParticipated: 0, // 参与案件总数（初始为0）
            successfulValidations: 0, // 成功验证次数（初始为0）
            isActive: true, // 设置为活跃状态
            lastActiveTime: block.timestamp // 记录注册时间为最后活跃时间
        });

        // 将验证者添加到验证者池
        validatorPool.push(validatorAddress);
        // 标记验证者已在池中
        isValidatorInPool[validatorAddress] = true;

        // 发出验证者注册事件，记录注册信息
        emit Events.ValidatorRegistered(
            validatorAddress,
            stake,
            initialReputation,
            block.timestamp
        );
    }

    /**
     * @notice 更新验证者状态
     * @dev 由治理合约调用，更新验证者的活跃状态和声誉
     * 用于维护验证者池的质量和活跃度
     * @param validatorAddress 验证者地址
     * @param isActive 是否激活
     * @param newReputation 新声誉分数
     */
    function updateValidatorStatus(
        address validatorAddress,
        bool isActive,
        uint256 newReputation
    ) external onlyGovernance {
        // 验证验证者是否已注册
        if (!isValidatorInPool[validatorAddress]) {
            revert Errors.NotAuthorizedValidator(validatorAddress);
        }

        // 获取验证者信息的存储引用
        DataStructures.ValidatorInfo storage validator = validators[
                    validatorAddress
            ];
        // 更新活跃状态
        validator.isActive = isActive;
        // 更新声誉分数
        validator.reputationScore = newReputation;
        // 更新最后活跃时间
        validator.lastActiveTime = block.timestamp;

        // 发出状态更新事件
        emit Events.ValidatorStatusUpdated(
            validatorAddress,
            isActive,
            newReputation,
            block.timestamp
        );
    }

    // ==================== 投票会话管理函数 ====================

    /**
     * @notice 开始投票会话（选择验证者并启动投票）
     * @dev 为指定案件创建新的投票会话
     * 随机选择验证者并设置投票期限
     * @param caseId 案件ID
     * @param votingDuration 投票持续时间（秒）
     * @param requiredValidators 需要的验证者数量
     * @return selectedValidators 选中的验证者地址数组
     */
    function startVotingSession(
        uint256 caseId,
        uint256 votingDuration,
        uint256 requiredValidators
    ) external onlyGovernance returns (address[] memory selectedValidators) {
        // 防止为同一案件重复创建投票会话
        if (votingSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "voting session");
        }

        // 验证所需验证者数量的合理性
        if (requiredValidators == 0) {
            revert Errors.InsufficientValidators(0, 1);
        }

        // 随机选择指定数量的验证者
        selectedValidators = _selectRandomValidators(requiredValidators);

        // 确保选中的验证者数量满足要求
        if (selectedValidators.length < requiredValidators) {
            revert Errors.InsufficientValidators(
                selectedValidators.length,
                requiredValidators
            );
        }

        // 创建并初始化投票会话
        VotingSession storage session = votingSessions[caseId];
        session.caseId = caseId; // 设置关联的案件ID
        session.selectedValidators = selectedValidators; // 记录选中的验证者
        session.startTime = block.timestamp; // 设置投票开始时间
        session.endTime = block.timestamp + votingDuration; // 计算投票结束时间
        session.isActive = true; // 激活投票会话
        session.isCompleted = false; // 标记为未完成
        session.randomSeedUsed = randomSeed; // 记录使用的随机数种子

        // 更新每个选中验证者的参与案件计数
        for (uint256 i = 0; i < selectedValidators.length; i++) {
            validators[selectedValidators[i]].totalCasesParticipated++;
        }

        // 发出验证者选择事件
        emit Events.ValidatorsSelected(
            caseId,
            selectedValidators,
            randomSeed,
            block.timestamp
        );

        // 发出投票期开始事件
        emit Events.VotingPhaseStarted(
            caseId,
            session.endTime,
            selectedValidators.length,
            block.timestamp
        );

        return selectedValidators;
    }

    /**
     * @notice 提交投票
     * @dev 验证者提交对案件的投票和支持证据
     * 包含完整的投票验证和记录逻辑
     * @param caseId 案件ID
     * @param choice 投票选择（支持或反对投诉）
     * @param reason 投票理由
     * @param evidenceHash 证据哈希
     */
    function submitVote(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string calldata evidenceHash
    ) external caseExists(caseId) votingActive(caseId) {
        // 验证投票提交的有效性
        _validateVoteSubmission(caseId, reason, evidenceHash);

        // 记录投票内容和证据
        _recordVoteAndEvidence(caseId, choice, reason, evidenceHash);

        // 更新投票统计数据
        _updateVotingStatistics(caseId, choice);

        // 发出投票提交事件
        emit Events.VoteSubmitted(
            caseId,
            msg.sender,
            choice,
            reason,
            bytes(evidenceHash).length > 0 ? 1 : 0, // 简化证据计数
            block.timestamp
        );
    }

    /**
     * @notice 验证投票提交的有效性
     * @dev 内部函数，执行投票前的各项检查
     * 确保投票的合法性和完整性
     */
    function _validateVoteSubmission(
        uint256 caseId,
        string calldata reason,
        string calldata evidenceHash
    ) internal view {
        // 检查调用者是否为此案件选中的验证者
        if (!_isSelectedValidator(caseId, msg.sender)) {
            revert Errors.ValidatorNotParticipating(msg.sender, caseId);
        }

        // 检查验证者是否已经投过票，防止重复投票
        if (votingSessions[caseId].votes[msg.sender].hasVoted) {
            revert Errors.AlreadyVoted(msg.sender, caseId);
        }

        // 检查投票理由是否为空，确保投票有充分依据
        if (bytes(reason).length == 0) {
            revert Errors.EmptyVoteReason();
        }

        // 检查证据哈希是否为空（如果需要证据）
        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }
    }

    /**
     * @notice 记录投票和证据
     * @dev 内部函数，将投票信息存储到区块链
     * 包括投票选择、理由和支持证据
     */
    function _recordVoteAndEvidence(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string calldata evidenceHash
    ) internal {
        VotingSession storage session = votingSessions[caseId];

        // 创建投票信息记录
        session.votes[msg.sender].voter = msg.sender; // 记录投票者地址
        session.votes[msg.sender].choice = choice; // 记录投票选择
        session.votes[msg.sender].timestamp = block.timestamp; // 记录投票时间
        session.votes[msg.sender].reason = reason; // 记录投票理由
        session.votes[msg.sender].evidenceHash = evidenceHash; // 记录证据哈希
        session.votes[msg.sender].hasVoted = true; // 标记已投票
    }

    /**
     * @notice 更新投票统计
     * @dev 内部函数，更新投票会话的统计数据
     * 实时跟踪投票进展和倾向
     */
    function _updateVotingStatistics(
        uint256 caseId,
        DataStructures.VoteChoice choice
    ) internal {
        VotingSession storage session = votingSessions[caseId];

        // 增加总投票数
        session.totalVotes++;
        // 根据投票选择更新对应的计数
        if (choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
            session.supportVotes++; // 支持投诉票数增加
        } else {
            session.rejectVotes++; // 反对投诉票数增加
        }

        // 记录用户投票历史
        userVotingHistory[msg.sender][caseId] = true;
    }

    /**
     * @notice 结束投票会话并计算结果
     * @dev 计算最终投票结果并更新验证者统计
     * 只能在投票期结束后调用
     * @param caseId 案件ID
     * @return complaintUpheld 投诉是否成立
     */
    function endVotingSession(
        uint256 caseId
    )
    external
    onlyGovernance
    caseExists(caseId)
    {
        VotingSession storage session = votingSessions[caseId];

        // 检查投票会话是否处于活跃状态
        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        // 检查是否已达到投票截止时间
        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }

        // 更新会话状态
        session.isActive = false; // 停用投票会话
        session.isCompleted = true; // 标记为已完成

        // 发出投票期结束事件
        emit Events.VotingPhaseEnded(
            caseId,
            session.supportVotes,
            session.rejectVotes,
            block.timestamp
        );

    }

    // ==================== 内部函数 ====================

    /**
     * @notice 随机选择验证者
     * @dev 使用随机算法从活跃验证者中选择指定数量的验证者
     * 确保选择过程的公平性和随机性
     * @param count 需要选择的验证者数量
     * @return 选中的验证者地址数组
     */
    function _selectRandomValidators(
        uint256 count
    ) internal returns (address[] memory) {
        // 获取所有活跃验证者列表
        address[] memory activeValidators = _getActiveValidators();

        // 检查是否有足够的活跃验证者
        if (activeValidators.length == 0) {
            revert Errors.InsufficientValidators(0, count);
        }

        // 如果需要的数量超过可用数量，则选择所有可用的
        if (count > activeValidators.length) {
            count = activeValidators.length;
        }

        // 初始化结果数组和使用标记数组
        address[] memory selected = new address[](count);
        bool[] memory used = new bool[](activeValidators.length);
        // todo 改为chainlink的VRF进行随机选择

        // 使用随机选择算法选择验证者
        for (uint256 i = 0; i < count; i++) {
            // 更新随机数种子，增加随机性
            randomSeed = uint256(
                keccak256(
                    abi.encodePacked(
                        randomSeed,
                        block.timestamp,
                        block.prevrandao,
                        i
                    )
                )
            );

            // 计算随机索引
            uint256 index = randomSeed % activeValidators.length;

            // 如果该索引已被选择，寻找下一个未选择的
            while (used[index]) {
                index = (index + 1) % activeValidators.length;
            }

            // 选择验证者并标记为已使用
            selected[i] = activeValidators[index];
            used[index] = true;
        }

        return selected;
    }

    /**
     * @notice 获取所有活跃的验证者
     * @dev 内部函数，过滤出当前活跃的验证者
     * 确保只有活跃验证者参与投票
     * @return 活跃验证者地址数组
     */
    function _getActiveValidators() internal view returns (address[] memory) {
        uint256 activeCount = 0;

        // 第一次遍历：计算活跃验证者数量
        for (uint256 i = 0; i < validatorPool.length; i++) {
            if (validators[validatorPool[i]].isActive) {
                activeCount++;
            }
        }

        // 创建适当大小的数组
        address[] memory activeValidators = new address[](activeCount);
        uint256 index = 0;

        // 第二次遍历：填充活跃验证者数组
        for (uint256 i = 0; i < validatorPool.length; i++) {
            if (validators[validatorPool[i]].isActive) {
                activeValidators[index] = validatorPool[i];
                index++;
            }
        }

        return activeValidators;
    }

    /**
     * @notice 检查地址是否为选中的验证者
     * @dev 内部函数，验证地址是否在指定案件的验证者列表中
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 是否为选中的验证者
     */
    function _isSelectedValidator(
        uint256 caseId,
        address validator
    ) internal view returns (bool) {
        VotingSession storage session = votingSessions[caseId];

        // 遍历选中的验证者列表
        for (uint256 i = 0; i < session.selectedValidators.length; i++) {
            if (session.selectedValidators[i] == validator) {
                return true;
            }
        }

        return false;
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取投票会话信息
     * @dev 公开查询函数，返回投票会话的基本信息
     * 供前端和其他合约查询投票状态
     * @param caseId 案件ID
     * @return 投票会话的各项基本信息
     */
    function getVotingSessionInfo(
        uint256 caseId
    )
    external
    view
    returns (
        uint256, // caseId - 案件ID
        address[] memory, // selectedValidators - 选中的验证者列表
        uint256, // supportVotes - 支持票数
        uint256, // rejectVotes - 反对票数
        uint256, // totalVotes - 总票数
        uint256, // startTime - 开始时间
        uint256, // endTime - 结束时间
        bool, // isActive - 是否活跃
        bool, // isCompleted - 是否完成
        bool // complaintUpheld - 投诉是否成立
    )
    {
        VotingSession storage session = votingSessions[caseId];

        return (
            session.caseId,
            session.selectedValidators,
            session.supportVotes,
            session.rejectVotes,
            session.totalVotes,
            session.startTime,
            session.endTime,
            session.isActive,
            session.isCompleted,
            session.complaintUpheld
        );
    }

    /**
     * @notice 获取验证者投票信息
     * @dev 查询特定验证者在特定案件中的投票详情
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 投票信息结构体
     */
    function getValidatorVote(
        uint256 caseId,
        address validator
    ) external view returns (DataStructures.VoteInfo memory) {
        return votingSessions[caseId].votes[validator];
    }

    /**
     * @notice 获取验证者信息
     * @dev 查询验证者的详细信息和统计数据
     * @param validator 验证者地址
     * @return 验证者详细信息
     */
    function getValidatorInfo(
        address validator
    ) external view returns (DataStructures.ValidatorInfo memory) {
        return validators[validator];
    }

    /**
     * @notice 获取验证者池大小
     * @dev 返回系统中注册的验证者总数
     * @return 验证者总数
     */
    function getValidatorPoolSize() external view returns (uint256) {
        return validatorPool.length;
    }

    /**
     * @notice 获取活跃验证者数量
     * @dev 返回当前活跃的验证者数量
     * @return 活跃验证者数量
     */
    function getActiveValidatorCount() external view returns (uint256) {
        return _getActiveValidators().length;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     * @dev 设置有权调用关键功能的治理合约地址
     * 只有合约所有者可以调用
     * @param _governanceContract 治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyOwner {
        // 验证地址有效性
        if (_governanceContract == address(0)) {
            revert Errors.ZeroAddress();
        }

        // 设置治理合约地址
        governanceContract = _governanceContract;
    }

    /**
     * @notice 移除验证者
     * @dev 将验证者从验证者池中移除
     * 设置为非活跃状态并从池中删除
     * @param validatorAddress 验证者地址
     */
    function removeValidator(address validatorAddress) external onlyOwner {
        // 验证验证者是否存在
        if (!isValidatorInPool[validatorAddress]) {
            revert Errors.NotAuthorizedValidator(validatorAddress);
        }

        // 设置验证者为非活跃状态
        validators[validatorAddress].isActive = false;
        // 从池中标记为移除
        isValidatorInPool[validatorAddress] = false;

        // 从验证者池数组中物理移除
        for (uint256 i = 0; i < validatorPool.length; i++) {
            if (validatorPool[i] == validatorAddress) {
                // 将最后一个元素移到当前位置，然后删除最后一个
                validatorPool[i] = validatorPool[validatorPool.length - 1];
                validatorPool.pop();
                break;
            }
        }

        // 发出状态更新事件
        emit Events.ValidatorStatusUpdated(
            validatorAddress,
            false,
            0,
            block.timestamp
        );
    }
}
