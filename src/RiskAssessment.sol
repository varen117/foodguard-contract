// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFoodGuardDAO.sol";

/**
 * @title 食品安全风险评估系统
 * @dev 智能风险评估合约，自动判定投诉的风险等级
 * 
 * 🔍 风险评估核心功能：
 * 1. 基于关键词的智能识别：通过投诉描述中的关键词判断严重程度
 * 2. 企业历史记录评估：考虑企业过往违规记录和声誉分数  
 * 3. 多维度综合评分：结合投诉类型、企业历史、证据质量等因素
 * 4. 动态风险阈值：根据系统运行情况调整风险判定标准
 * 
 * 🎯 风险等级分类：
 * - 高风险（≥80分）：食物中毒、污染爆发等严重安全事件
 * - 中风险（50-79分）：卫生问题、过期食品等一般安全问题
 * - 低风险（<50分）：包装问题、外观缺陷等轻微问题
 */
contract RiskAssessment is Ownable {
    
    /// @dev 风险因子结构体
    /// 包含影响风险评估的四个核心维度
    struct RiskFactors {
        uint256 companyHistoryScore;    // 企业历史违规分数（0-100）
        uint256 complaintTypeScore;     // 投诉类型严重程度分数（0-100）
        uint256 evidenceQualityScore;   // 证据质量分数（0-100）
        uint256 geographicImpactScore;  // 地理影响范围分数（0-100）
    }
    
    /// @dev 企业地址 => 历史违规次数映射
    mapping(address => uint256) public companyViolationHistory;
    
    /// @dev 企业地址 => 声誉分数映射（0-100分）
    mapping(address => uint256) public companyReputationScore;
    
    /// @dev 高风险阈值：80分
    /// 达到此分数的投诉将被标记为高风险，需要冻结企业保证金
    uint256 public constant HIGH_RISK_THRESHOLD = 80;
    
    /// @dev 中风险阈值：50分
    /// 50-79分之间的投诉为中风险，不冻结保证金但需要投票处理
    uint256 public constant MEDIUM_RISK_THRESHOLD = 50;
    
    // ==================== 事件定义 ====================
    
    /// @dev 风险评估完成事件
    /// @param company 被评估企业地址
    /// @param riskLevel 评估得出的风险等级
    /// @param totalScore 综合风险评分
    event RiskAssessed(address indexed company, IFoodGuardDAO.RiskLevel riskLevel, uint256 totalScore);
    
    /// @dev 企业违规记录更新事件
    /// @param company 企业地址
    /// @param newViolationCount 新的违规次数
    event CompanyViolationUpdated(address indexed company, uint256 newViolationCount);
    
    /// @dev 企业声誉分数更新事件
    /// @param company 企业地址
    /// @param newScore 新的声誉分数
    event ReputationScoreUpdated(address indexed company, uint256 newScore);
    
    /// @dev 构造函数
    /// 初始化风险评估系统
    constructor() Ownable(msg.sender) {}
    
    // ==================== 核心风险评估功能 ====================
    
    /**
     * @dev 综合风险评估（主函数）
     * 🔥 流程图中的"风险等级判定"核心实现
     * 
     * 评估算法：
     * - 企业历史记录权重：40%
     * - 投诉类型严重程度权重：35%
     * - 证据质量权重：15%
     * - 地理影响范围权重：10%
     * 
     * @param _company 被投诉企业地址
     * @param _complaintDescription 投诉描述（用于关键词分析）
     * @param _evidenceQuality 证据质量评分（0-100）
     * @return 风险等级（高/中/低）
     */
    function assessRisk(
        address _company,
        string memory _complaintDescription,
        uint256 _evidenceQuality
    ) external view returns (IFoodGuardDAO.RiskLevel) {
        RiskFactors memory factors = RiskFactors({
            companyHistoryScore: _calculateHistoryScore(_company),
            complaintTypeScore: _calculateComplaintTypeScore(_complaintDescription),
            evidenceQualityScore: _evidenceQuality,
            geographicImpactScore: _calculateGeographicImpact(_company)
        });
        
        uint256 totalScore = _calculateTotalRiskScore(factors);
        
        if (totalScore >= HIGH_RISK_THRESHOLD) {
            return IFoodGuardDAO.RiskLevel.High;
        } else if (totalScore >= MEDIUM_RISK_THRESHOLD) {
            return IFoodGuardDAO.RiskLevel.Medium;
        } else {
            return IFoodGuardDAO.RiskLevel.Low;
        }
    }
    
    // ==================== 风险评估算法实现 ====================
    
    /**
     * @dev 计算企业历史风险分数
     * 基于企业过往违规记录和声誉评估历史风险
     * 
     * 计算逻辑：
     * - 违规次数每次+10分
     * - 声誉分数越低风险越高（100-声誉分）
     * - 总分上限100分
     * 
     * @param _company 企业地址
     * @return 企业历史风险分数（0-100）
     */
    function _calculateHistoryScore(address _company) internal view returns (uint256) {
        uint256 violations = companyViolationHistory[_company];
        uint256 reputation = companyReputationScore[_company];
        
        // 违规次数越多风险越高，声誉越低风险越高
        uint256 historyScore = (violations * 10) + (100 - reputation);
        
        return historyScore > 100 ? 100 : historyScore;
    }
    
    /**
     * @dev 计算投诉类型风险分数
     * 通过关键词分析判断投诉的严重程度
     * 
     * 关键词权重：
     * - 高风险：poisoning（中毒）、contamination（污染）、outbreak（爆发）+40分
     * - 中风险：hygiene（卫生）、expiry（过期）、mold（霉变）+25分
     * - 低风险：taste（口味）、appearance（外观）、packaging（包装）+10分
     * 
     * @param _description 投诉描述文本
     * @return 投诉类型风险分数（20-100）
     */
    function _calculateComplaintTypeScore(string memory _description) internal pure returns (uint256) {
        bytes memory descBytes = bytes(_description);
        uint256 score = 20; // 基础分数20分
        
        //检查高风险关键词（+40分）
        if (_containsKeyword(descBytes, "poisoning") || 
            _containsKeyword(descBytes, "contamination") ||
            _containsKeyword(descBytes, "outbreak")) {
            score += 40; // 食物中毒、污染、爆发等严重问题
        }
        
        //   检查中风险关键词（+25分）
        if (_containsKeyword(descBytes, "hygiene") || 
            _containsKeyword(descBytes, "expiry") ||
            _containsKeyword(descBytes, "mold")) {
            score += 25; // 卫生问题、过期、霉变等中等问题
        }
        
        // 检查低风险关键词（+10分）
        if (_containsKeyword(descBytes, "taste") || 
            _containsKeyword(descBytes, "appearance") ||
            _containsKeyword(descBytes, "packaging")) {
            score += 10; // 口味、外观、包装等轻微问题
        }
        
        return score > 100 ? 100 : score;
    }
    
    /**
     * @dev 计算地理影响风险分数
     * 基于企业声誉评估潜在的地理影响范围
     * 
     * 评估逻辑：
     * - 声誉较好的企业（>50分）：影响范围较小，风险分数20
     * - 声誉较差的企业（≤50分）：可能产生更大负面影响，风险分数40
     * 
     * @param _company 企业地址
     * @return 地理影响风险分数（20或40）
     */
    function _calculateGeographicImpact(address _company) internal view returns (uint256) {
        uint256 reputation = companyReputationScore[_company];
        
        // 声誉差的企业可能产生更大的负面影响
        return reputation > 50 ? 20 : 40;
    }
    
    /**
     * @dev 计算综合风险总分
     * 使用加权平均法计算最终风险评分
     * 
     * 权重分配：
     * - 企业历史记录：40%（最重要，反映企业过往表现）
     * - 投诉类型严重程度：35%（次重要，直接反映问题严重性）
     * - 证据质量：15%（重要，影响投诉可信度）
     * - 地理影响范围：10%（参考，评估潜在影响面）
     * 
     * @param _factors 四个维度的风险因子
     * @return 综合风险总分（0-100）
     */
    function _calculateTotalRiskScore(RiskFactors memory _factors) internal pure returns (uint256) {
        // 加权平均计算总分
        uint256 totalScore = (
            _factors.companyHistoryScore * 40 +      // 40%权重：企业历史
            _factors.complaintTypeScore * 35 +       // 35%权重：投诉类型
            _factors.evidenceQualityScore * 15 +     // 15%权重：证据质量
            _factors.geographicImpactScore * 10      // 10%权重：地理影响
        ) / 100;
        
        return totalScore;
    }
    
    /**
     * @dev 检查文本中是否包含特定关键词
     * 用于分析投诉描述中的风险关键词
     * 
     * @param _data 要搜索的文本数据（字节格式）
     * @param _keyword 要查找的关键词
     * @return 是否找到关键词
     */
    function _containsKeyword(bytes memory _data, string memory _keyword) internal pure returns (bool) {
        bytes memory keywordBytes = bytes(_keyword);
        
        // 如果文本长度小于关键词长度，直接返回false
        if (_data.length < keywordBytes.length) {
            return false;
        }
        
        // 遍历文本查找关键词
        for (uint256 i = 0; i <= _data.length - keywordBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < keywordBytes.length; j++) {
                if (_data[i + j] != keywordBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        
        return false;
    }
    
    // ==================== 企业信息管理功能 ====================
    
    /**
     * @dev 更新企业违规历史记录（仅管理员）
     * 当企业在投诉中败诉时，系统自动更新其违规记录
     * 
     * @param _company 企业地址
     * @param _violations 新的违规次数
     */
    function updateViolationHistory(address _company, uint256 _violations) external onlyOwner {
        companyViolationHistory[_company] = _violations;
        emit CompanyViolationUpdated(_company, _violations);
    }
    
    /**
     * @dev 更新企业声誉分数（仅管理员）
     * 根据企业的表现和投诉结果调整声誉评分
     * 
     * @param _company 企业地址
     * @param _score 新的声誉分数（0-100分）
     */
    function updateReputationScore(address _company, uint256 _score) external onlyOwner {
        require(_score <= 100, "Score must be <= 100");
        companyReputationScore[_company] = _score;
        emit ReputationScoreUpdated(_company, _score);
    }
    
    // ==================== 查询功能 ====================
    
    /**
     * @dev 获取企业风险档案
     * 返回企业的违规历史和声誉评分
     * 
     * @param _company 企业地址
     * @return violations 历史违规次数
     * @return reputation 当前声誉分数
     */
    function getCompanyRiskProfile(address _company) 
        external 
        view 
        returns (uint256 violations, uint256 reputation) 
    {
        violations = companyViolationHistory[_company];
        reputation = companyReputationScore[_company];
    }
} 