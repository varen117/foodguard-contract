// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/DataStructures.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";

/**
 * @title VotingManager
 * @author Food Safety Governance Team
 * @notice 投票管理模块，负责处理验证者选择、投票收集和结果统计
 * @dev 管理整个投票流程，包括验证者随机选择、投票期限控制、结果计算等
 */
contract VotingManager {
    // ==================== 状态变量 ====================

    /// @notice 管理员地址
    address public admin;

    /// @notice 治理合约地址（可以调用此合约的函数）
    address public governanceContract;

    /// @notice 所有验证者地址列表
    address[] public validatorPool;

    /// @notice 验证者信息映射
    mapping(address => DataStructures.ValidatorInfo) public validators;

    /// @notice 验证者是否在池中的映射
    mapping(address => bool) public isValidatorInPool;

    /// @notice 案件的投票信息映射
    mapping(uint256 => VotingSession) public votingSessions;

    /// @notice 用户参与的投票记录 user => caseId => hasVoted
    mapping(address => mapping(uint256 => bool)) public userVotingHistory;

    /// @notice 随机数种子
    uint256 private randomSeed;

    // ==================== 结构体定义 ====================

    /**
     * @notice 投票会话结构体
     * @dev 记录单个案件的完整投票信息
     */
    struct VotingSession {
        uint256 caseId; // 案件ID
        address[] selectedValidators; // 选中的验证者列表
        mapping(address => DataStructures.VoteInfo) votes; // 投票信息映射
        uint256 supportVotes; // 支持投诉的票数
        uint256 rejectVotes; // 反对投诉的票数
        uint256 totalVotes; // 总投票数
        uint256 startTime; // 投票开始时间
        uint256 endTime; // 投票结束时间
        bool isActive; // 投票是否激活
        bool isCompleted; // 投票是否完成
        bool complaintUpheld; // 投诉是否成立（投票结果）
        uint256 randomSeedUsed; // 使用的随机数种子
    }

    // ==================== 修饰符 ====================

    /**
     * @notice 只有管理员可以调用
     */
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Errors.InsufficientPermission(msg.sender, "ADMIN");
        }
        _;
    }

    /**
     * @notice 只有治理合约可以调用
     */
    modifier onlyGovernance() {
        if (msg.sender != governanceContract) {
            revert Errors.InsufficientPermission(msg.sender, "GOVERNANCE");
        }
        _;
    }

    /**
     * @notice 检查案件是否存在
     */
    modifier caseExists(uint256 caseId) {
        if (votingSessions[caseId].caseId == 0) {
            revert Errors.CaseNotFound(caseId);
        }
        _;
    }

    /**
     * @notice 检查投票是否激活
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

    constructor(address _admin) {
        admin = _admin;
        randomSeed = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            )
        );
    }

    // ==================== 验证者管理函数 ====================

    /**
     * @notice 注册验证者
     * @param validatorAddress 验证者地址
     * @param stake 质押金额
     * @param initialReputation 初始声誉分数
     */
    function registerValidator(
        address validatorAddress,
        uint256 stake,
        uint256 initialReputation
    ) external onlyAdmin payable {
        if (validatorAddress == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (isValidatorInPool[validatorAddress]) {
            revert Errors.DuplicateOperation(validatorAddress, "register");
        }

        // if (msg.) {

        // }

        validators[validatorAddress] = DataStructures.ValidatorInfo({
            validatorAddress: validatorAddress,
            stake: stake,
            reputationScore: initialReputation,
            totalCasesParticipated: 0,
            successfulValidations: 0,
            isActive: true,
            lastActiveTime: block.timestamp
        });

        validatorPool.push(validatorAddress);
        isValidatorInPool[validatorAddress] = true;

        emit Events.ValidatorRegistered(
            validatorAddress,
            stake,
            initialReputation,
            block.timestamp
        );
    }

    /**
     * @notice 更新验证者状态
     * @param validatorAddress 验证者地址
     * @param isActive 是否激活
     * @param newReputation 新声誉分数
     */
    function updateValidatorStatus(
        address validatorAddress,
        bool isActive,
        uint256 newReputation
    ) external onlyGovernance {
        if (!isValidatorInPool[validatorAddress]) {
            revert Errors.NotAuthorizedValidator(validatorAddress);
        }

        DataStructures.ValidatorInfo storage validator = validators[
            validatorAddress
        ];
        validator.isActive = isActive;
        validator.reputationScore = newReputation;
        validator.lastActiveTime = block.timestamp;

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
     * @param caseId 案件ID
     * @param votingDuration 投票持续时间（秒）
     * @param requiredValidators 需要的验证者数量
     */
    function startVotingSession(
        uint256 caseId,
        uint256 votingDuration,
        uint256 requiredValidators
    ) external onlyGovernance returns (address[] memory selectedValidators) {
        if (votingSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "voting session");
        }

        if (requiredValidators == 0) {
            revert Errors.InsufficientValidators(0, 1);
        }

        // 选择验证者
        selectedValidators = _selectRandomValidators(requiredValidators);

        if (selectedValidators.length < requiredValidators) {
            revert Errors.InsufficientValidators(
                selectedValidators.length,
                requiredValidators
            );
        }

        // 创建投票会话
        VotingSession storage session = votingSessions[caseId];
        session.caseId = caseId;
        session.selectedValidators = selectedValidators;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + votingDuration;
        session.isActive = true;
        session.isCompleted = false;
        session.randomSeedUsed = randomSeed;

        // 更新验证者参与记录
        for (uint256 i = 0; i < selectedValidators.length; i++) {
            validators[selectedValidators[i]].totalCasesParticipated++;
        }

        emit Events.ValidatorsSelected(
            caseId,
            selectedValidators,
            randomSeed,
            block.timestamp
        );

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
     * @param caseId 案件ID
     * @param choice 投票选择
     * @param reason 投票理由
     * @param evidenceHashes 证据哈希数组
     * @param evidenceTypes 证据类型数组
     * @param evidenceDescriptions 证据描述数组
     */
    function submitVote(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string[] calldata evidenceHashes,
        string[] calldata evidenceTypes,
        string[] calldata evidenceDescriptions
    ) external caseExists(caseId) votingActive(caseId) {
        _validateVoteSubmission(
            caseId,
            reason,
            evidenceHashes,
            evidenceTypes,
            evidenceDescriptions
        );
        _recordVoteAndEvidence(
            caseId,
            choice,
            reason,
            evidenceHashes,
            evidenceTypes,
            evidenceDescriptions
        );
        _updateVotingStatistics(caseId, choice);

        emit Events.VoteSubmitted(
            caseId,
            msg.sender,
            choice,
            reason,
            evidenceHashes.length,
            block.timestamp
        );
    }

    /**
     * @notice 验证投票提交的有效性
     */
    function _validateVoteSubmission(
        uint256 caseId,
        string calldata reason,
        string[] calldata evidenceHashes,
        string[] calldata evidenceTypes,
        string[] calldata evidenceDescriptions
    ) internal view {
        // 检查是否为选中的验证者
        if (!_isSelectedValidator(caseId, msg.sender)) {
            revert Errors.ValidatorNotParticipating(msg.sender, caseId);
        }

        // 检查是否已经投过票
        if (votingSessions[caseId].votes[msg.sender].hasVoted) {
            revert Errors.AlreadyVoted(msg.sender, caseId);
        }

        // 检查投票理由是否为空
        if (bytes(reason).length == 0) {
            revert Errors.EmptyVoteReason();
        }

        // 验证证据数组长度一致
        if (
            evidenceHashes.length != evidenceTypes.length ||
            evidenceTypes.length != evidenceDescriptions.length
        ) {
            revert Errors.InsufficientEvidence(
                evidenceHashes.length,
                evidenceTypes.length
            );
        }
    }

    /**
     * @notice 记录投票和证据
     */
    function _recordVoteAndEvidence(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string[] calldata evidenceHashes,
        string[] calldata evidenceTypes,
        string[] calldata evidenceDescriptions
    ) internal {
        VotingSession storage session = votingSessions[caseId];

        // 创建投票信息
        session.votes[msg.sender].voter = msg.sender;
        session.votes[msg.sender].choice = choice;
        session.votes[msg.sender].timestamp = block.timestamp;
        session.votes[msg.sender].reason = reason;
        session.votes[msg.sender].hasVoted = true;

        // 添加证据
        for (uint256 i = 0; i < evidenceHashes.length; i++) {
            session.votes[msg.sender].evidences.push(
                DataStructures.Evidence({
                    description: evidenceDescriptions[i],
                    ipfsHash: evidenceHashes[i],
                    location: "",
                    timestamp: block.timestamp,
                    submitter: msg.sender,
                    evidenceType: evidenceTypes[i]
                })
            );
        }
    }

    /**
     * @notice 更新投票统计
     */
    function _updateVotingStatistics(
        uint256 caseId,
        DataStructures.VoteChoice choice
    ) internal {
        VotingSession storage session = votingSessions[caseId];

        session.totalVotes++;
        if (choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
            session.supportVotes++;
        } else {
            session.rejectVotes++;
        }

        userVotingHistory[msg.sender][caseId] = true;
    }

    /**
     * @notice 结束投票会话并计算结果
     * @param caseId 案件ID
     */
    function endVotingSession(
        uint256 caseId
    )
        external
        onlyGovernance
        caseExists(caseId)
        returns (bool complaintUpheld)
    {
        VotingSession storage session = votingSessions[caseId];

        if (!session.isActive) {
            revert Errors.InvalidCaseStatus(caseId, 0, 1);
        }

        if (block.timestamp < session.endTime) {
            revert Errors.OperationTooEarly(block.timestamp, session.endTime);
        }

        // 计算投票结果
        complaintUpheld = session.supportVotes > session.rejectVotes;

        session.isActive = false;
        session.isCompleted = true;
        session.complaintUpheld = complaintUpheld;

        // 更新验证者成功验证次数（假设多数意见为正确）
        for (uint256 i = 0; i < session.selectedValidators.length; i++) {
            address validator = session.selectedValidators[i];
            DataStructures.VoteInfo storage vote = session.votes[validator];

            if (vote.hasVoted) {
                bool votedWithMajority = (complaintUpheld &&
                    vote.choice ==
                    DataStructures.VoteChoice.SUPPORT_COMPLAINT) ||
                    (!complaintUpheld &&
                        vote.choice ==
                        DataStructures.VoteChoice.REJECT_COMPLAINT);

                if (votedWithMajority) {
                    validators[validator].successfulValidations++;
                }
            }
        }

        emit Events.VotingPhaseEnded(
            caseId,
            session.supportVotes,
            session.rejectVotes,
            block.timestamp
        );

        return complaintUpheld;
    }

    // ==================== 内部函数 ====================

    /**
     * @notice 随机选择验证者
     * @param count 需要选择的验证者数量
     * @return 选中的验证者地址数组
     */
    function _selectRandomValidators(
        uint256 count
    ) internal returns (address[] memory) {
        // 获取活跃验证者
        address[] memory activeValidators = _getActiveValidators();

        if (activeValidators.length == 0) {
            revert Errors.InsufficientValidators(0, count);
        }

        if (count > activeValidators.length) {
            count = activeValidators.length;
        }

        address[] memory selected = new address[](count);
        bool[] memory used = new bool[](activeValidators.length);

        // 使用简单的随机选择算法
        for (uint256 i = 0; i < count; i++) {
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

            uint256 index = randomSeed % activeValidators.length;

            // 如果已经选择过，寻找下一个未选择的
            while (used[index]) {
                index = (index + 1) % activeValidators.length;
            }

            selected[i] = activeValidators[index];
            used[index] = true;
        }

        return selected;
    }

    /**
     * @notice 获取所有活跃的验证者
     * @return 活跃验证者地址数组
     */
    function _getActiveValidators() internal view returns (address[] memory) {
        uint256 activeCount = 0;

        // 先计算活跃验证者数量
        for (uint256 i = 0; i < validatorPool.length; i++) {
            if (validators[validatorPool[i]].isActive) {
                activeCount++;
            }
        }

        address[] memory activeValidators = new address[](activeCount);
        uint256 index = 0;

        // 填充活跃验证者数组
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
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 是否为选中的验证者
     */
    function _isSelectedValidator(
        uint256 caseId,
        address validator
    ) internal view returns (bool) {
        VotingSession storage session = votingSessions[caseId];

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
     * @param caseId 案件ID
     * @return 投票会话基本信息
     */
    function getVotingSessionInfo(
        uint256 caseId
    )
        external
        view
        returns (
            uint256, // caseId
            address[] memory, // selectedValidators
            uint256, // supportVotes
            uint256, // rejectVotes
            uint256, // totalVotes
            uint256, // startTime
            uint256, // endTime
            bool, // isActive
            bool, // isCompleted
            bool // complaintUpheld
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
     * @param caseId 案件ID
     * @param validator 验证者地址
     * @return 投票信息
     */
    function getValidatorVote(
        uint256 caseId,
        address validator
    ) external view returns (DataStructures.VoteInfo memory) {
        return votingSessions[caseId].votes[validator];
    }

    /**
     * @notice 获取验证者信息
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
     * @return 验证者总数
     */
    function getValidatorPoolSize() external view returns (uint256) {
        return validatorPool.length;
    }

    /**
     * @notice 获取活跃验证者数量
     * @return 活跃验证者数量
     */
    function getActiveValidatorCount() external view returns (uint256) {
        return _getActiveValidators().length;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     * @param _governanceContract 治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyAdmin {
        if (_governanceContract == address(0)) {
            revert Errors.ZeroAddress();
        }

        governanceContract = _governanceContract;
    }

    /**
     * @notice 移除验证者
     * @param validatorAddress 验证者地址
     */
    function removeValidator(address validatorAddress) external onlyAdmin {
        if (!isValidatorInPool[validatorAddress]) {
            revert Errors.NotAuthorizedValidator(validatorAddress);
        }

        validators[validatorAddress].isActive = false;
        isValidatorInPool[validatorAddress] = false;

        // 从验证者池中移除
        for (uint256 i = 0; i < validatorPool.length; i++) {
            if (validatorPool[i] == validatorAddress) {
                validatorPool[i] = validatorPool[validatorPool.length - 1];
                validatorPool.pop();
                break;
            }
        }

        emit Events.ValidatorStatusUpdated(
            validatorAddress,
            false,
            0,
            block.timestamp
        );
    }
}
