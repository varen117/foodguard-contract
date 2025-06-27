// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // 使用 Solidity 0.8.20 版本，支持最新特性

import "../libraries/DataStructures.sol"; // 导入数据结构库，获取枚举和结构体定义
import "../libraries/Errors.sol"; // 导入错误库，用于统一的错误处理
import "../libraries/Events.sol"; // 导入事件库，用于发出标准化事件
import "../libraries/CommonModifiers.sol"; // 导入公共修饰符库
import "@openzeppelin/contracts/access/Ownable.sol"; // 导入 OpenZeppelin 的所有权管理合约

/**
 * @title VotingManager
 * @author Food Safety Governance Team
 * @notice 投票管理模块，负责处理验证者选择、投票收集和结果统计
 * @dev 管理整个投票流程，包括验证者随机选择、投票期限控制、结果计算等
 * 这是食品安全治理系统的核心模块之一，确保决策过程的民主性和公正性
 * 通过随机选择验证者和透明的投票机制，保证案件处理的客观性
 */
contract VotingManager is Ownable, CommonModifiers {
    // ==================== 状态变量 ====================

    /// @notice 案件的投票信息映射
    mapping(uint256 => DataStructures.VotingSession) public votingSessions;

    /// @notice 用户参与的投票记录 user => caseId => hasVoted（保留用于防重复投票）
    mapping(address => mapping(uint256 => bool)) public userVotingHistory;

    // ==================== 简化的修饰符 ====================

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
        DataStructures.VotingSession storage session = votingSessions[caseId];
        if (!session.isActive || block.timestamp > session.endTime) {
            revert Errors.VotingPeriodEnded(session.endTime, block.timestamp);
        }
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ==================== 投票会话管理函数 ====================

    /**
     * @notice 开始投票会话（指定验证者）
     */
    function startVotingSessionWithValidators(
        uint256 caseId,
        address[] calldata selectedValidators,
        uint256 votingDuration
    ) external onlyGovernance returns (address[] memory) {
        if (votingSessions[caseId].caseId != 0) {
            revert Errors.DuplicateOperation(address(0), "voting session");
        }

        if (selectedValidators.length == 0) {
            revert Errors.InsufficientValidators(0, 1);
        }

        // 验证所有验证者地址
        for (uint256 i = 0; i < selectedValidators.length; i++) {
            _requireNotZeroAddress(selectedValidators[i]);
        }

        // 创建并初始化投票会话
        DataStructures.VotingSession storage session = votingSessions[caseId];
        session.caseId = caseId;
        session.selectedValidators = selectedValidators;
        session.startTime = block.timestamp;
        session.endTime = block.timestamp + votingDuration;
        session.isActive = true;
        session.isCompleted = false;

        // 发出验证者选择事件
        emit Events.ValidatorsSelected(
            caseId,
            selectedValidators,
            block.timestamp
        );

        // 发出投票期开始事件
        emit Events.VotingPhaseStarted(
            caseId,
            session.endTime,
            block.timestamp
        );

        return selectedValidators;
    }

    /**
     * @notice 提交投票
     */
    function submitVote(
        uint256 caseId,
        DataStructures.VoteChoice choice,
        string calldata reason,
        string calldata evidenceHash
    )
    external
    caseExists(caseId)
    votingActive(caseId)
    {
        DataStructures.VotingSession storage session = votingSessions[caseId];

        // 验证用户是否已投票
        if (userVotingHistory[msg.sender][caseId]) {
            revert Errors.AlreadyVoted(msg.sender, caseId);
        }

        // 检查是否为选中的验证者
        bool isValidator = false;
        for (uint256 i = 0; i < session.selectedValidators.length; i++) {
            if (session.selectedValidators[i] == msg.sender) {
                isValidator = true;
                break;
            }
        }

        if (!isValidator) {
            revert Errors.ValidatorNotParticipating(msg.sender, caseId);
        }

        // 检查投票理由和证据
        if (bytes(reason).length == 0) {
            revert Errors.EmptyVoteReason();
        }

        if (bytes(evidenceHash).length == 0) {
            revert Errors.EmptyEvidenceDescription();
        }

        // 记录投票信息
        session.votes[msg.sender] = DataStructures.VoteInfo({
            voter: msg.sender,
            choice: choice,
            timestamp: block.timestamp,
            reason: reason,
            evidenceHash: evidenceHash,
            hasVoted: true
        });

        // 更新投票统计
        if (choice == DataStructures.VoteChoice.SUPPORT_COMPLAINT) {
            session.supportVotes++;
        } else {
            session.rejectVotes++;
        }
        session.totalVotes++;

        // 标记用户已投票
        userVotingHistory[msg.sender][caseId] = true;

        // 发出投票事件
        emit Events.VoteSubmitted(
            caseId,
            msg.sender,
            choice,
            block.timestamp
        );
    }

    /**
     * @notice 结束投票会话
     */
    function endVotingSession(
        uint256 caseId
    )
    external
    onlyGovernance
    caseExists(caseId)
    returns (
        bool complaintUpheld,
        address[] memory validatorAddresses,
        DataStructures.VoteChoice[] memory validatorChoices
    )
    {
        DataStructures.VotingSession storage session = votingSessions[caseId];

        if (session.isCompleted) {
            revert Errors.DuplicateOperation(address(0), "end voting");
        }

        // 标记投票会话为完成
        session.isActive = false;
        session.isCompleted = true;

        // 计算投票结果
        complaintUpheld = session.supportVotes > session.rejectVotes;
        session.complaintUpheld = complaintUpheld;

        // 返回验证者地址和选择
        validatorAddresses = session.selectedValidators;
        validatorChoices = new DataStructures.VoteChoice[](validatorAddresses.length);

        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            address validator = validatorAddresses[i];
            if (session.votes[validator].hasVoted) {
                validatorChoices[i] = session.votes[validator].choice;
            } else {
                validatorChoices[i] = DataStructures.VoteChoice.REJECT_COMPLAINT;
            }
        }

        // 发出投票完成事件
        emit Events.VotingCompleted(
            caseId,
            complaintUpheld,
            session.supportVotes,
            session.rejectVotes,
            block.timestamp
        );
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 获取投票会话信息
     */
    function getVotingSessionInfo(uint256 caseId) external view caseExists(caseId) returns (DataStructures.VotingSession) {
        return votingSessions[caseId];
    }

    /**
     * @notice 获取验证者投票信息
     */
    function getValidatorVote(
        uint256 caseId,
        address validator
    )
    external
    view
    caseExists(caseId)
    returns (DataStructures.VoteInfo memory)
    {
        return votingSessions[caseId].votes[validator];
    }

    /**
     * @notice 检查验证者是否参与案件
     */
    function isSelectedValidator(
        uint256 caseId,
        address validator
    )
    external
    view
    returns (bool)
    {
        if (votingSessions[caseId].caseId == 0) {
            return false;
        }

        address[] memory validators = votingSessions[caseId].selectedValidators;
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == validator) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice 获取案件验证者列表
     */
    function getCaseValidators(uint256 caseId)
    external
    view
    caseExists(caseId)
    returns (address[] memory)
    {
        return votingSessions[caseId].selectedValidators;
    }

    // ==================== 管理函数 ====================

    /**
     * @notice 设置治理合约地址
     */
    function setGovernanceContract(
        address _governanceContract
    ) external onlyOwner {
        _setGovernanceContract(_governanceContract);
    }
}
