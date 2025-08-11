// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IArbitrageHook} from "../hooks/interfaces/IArbitrageHook.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ProfitDistributor
 * @notice Handles profit sharing and distribution logic for cross-chain arbitrage
 * @dev Manages complex profit distribution schemes including user rewards, protocol fees, and LP incentives
 */
contract ProfitDistributor is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    // Distribution configuration
    struct DistributionConfig {
        uint256 userShareBPS;          // User's share of profits in BPS
        uint256 protocolFeeBPS;        // Protocol fee in BPS  
        uint256 lpIncentiveBPS;        // LP incentive in BPS
        uint256 treasuryBPS;           // Treasury share in BPS
        uint256 burnBPS;               // Amount to burn (if applicable)
        uint256 minDistribution;       // Minimum amount to trigger distribution
        bool autoDistribute;           // Whether to auto-distribute
    }
    
    // Profit tracking
    struct ProfitRecord {
        bytes32 opportunityId;         // Reference to arbitrage opportunity
        address user;                  // User who initiated arbitrage
        address tokenIn;               // Input token
        address tokenOut;              // Output token
        uint256 totalProfit;           // Total profit generated
        uint256 userShare;             // Amount allocated to user
        uint256 protocolFee;           // Protocol fee amount
        uint256 timestamp;             // Distribution timestamp
        bool distributed;              // Whether profits have been distributed
    }
    
    // Reward pools for different tokens
    struct RewardPool {
        address token;                 // Token address
        uint256 totalRewards;          // Total accumulated rewards
        uint256 distributedRewards;    // Already distributed rewards
        uint256 pendingRewards;        // Pending distribution
        mapping(address => uint256) userRewards; // User-specific rewards
        mapping(address => uint256) lastClaimTime; // Last claim timestamp
    }
    
    // State variables
    DistributionConfig public config;
    
    // Profit tracking
    mapping(bytes32 => ProfitRecord) public profitRecords;
    mapping(address => uint256) public userTotalProfits;
    mapping(address => uint256) public userPendingRewards;
    
    // Reward pools
    mapping(address => RewardPool) public rewardPools;
    address[] public supportedTokens;
    mapping(address => bool) public isTokenSupported;
    
    // Statistics
    uint256 public totalProfitsGenerated;
    uint256 public totalDistributed;
    uint256 public totalUsers;
    
    // Distribution settings
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant MIN_CLAIM_INTERVAL = 1 hours;
    address public treasury;
    
    // Events
    event ProfitRecorded(
        bytes32 indexed opportunityId,
        address indexed user,
        uint256 totalProfit,
        uint256 userShare
    );
    
    event ProfitDistributed(
        bytes32 indexed opportunityId,
        address indexed user,
        address token,
        uint256 amount
    );
    
    event RewardsClaimed(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    
    event ConfigurationUpdated(
        uint256 userShareBPS,
        uint256 protocolFeeBPS,
        uint256 lpIncentiveBPS
    );
    
    constructor(
        address initialOwner,
        address _treasury
    ) Ownable(initialOwner) {
        treasury = _treasury;
        
        // Initialize with default distribution
        config = DistributionConfig({
            userShareBPS: 7000,        // 70% to user
            protocolFeeBPS: 2000,      // 20% protocol fee
            lpIncentiveBPS: 500,       // 5% to LPs
            treasuryBPS: 400,          // 4% to treasury
            burnBPS: 100,              // 1% burn
            minDistribution: 0.01 ether, // 0.01 ETH minimum
            autoDistribute: true
        });
    }
    
    /**
     * @notice Record profit from successful arbitrage
     * @param opportunityId Unique opportunity identifier
     * @param user User who executed the arbitrage
     * @param tokenIn Input token address
     * @param tokenOut Output token address  
     * @param totalProfit Total profit amount
     */
    function recordProfit(
        bytes32 opportunityId,
        address user,
        address tokenIn,
        address tokenOut,
        uint256 totalProfit
    ) external nonReentrant whenNotPaused {
        if (totalProfit == 0) {
            revert Errors.InsufficientProfit();
        }
        
        if (profitRecords[opportunityId].opportunityId != bytes32(0)) {
            revert("Profit already recorded");
        }
        
        // Calculate distribution amounts
        uint256 userShare = (totalProfit * config.userShareBPS) / MAX_BPS;
        uint256 protocolFee = (totalProfit * config.protocolFeeBPS) / MAX_BPS;
        uint256 lpIncentive = (totalProfit * config.lpIncentiveBPS) / MAX_BPS;
        uint256 treasuryShare = (totalProfit * config.treasuryBPS) / MAX_BPS;
        
        // Record the profit
        profitRecords[opportunityId] = ProfitRecord({
            opportunityId: opportunityId,
            user: user,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            totalProfit: totalProfit,
            userShare: userShare,
            protocolFee: protocolFee,
            timestamp: block.timestamp,
            distributed: false
        });
        
        // Update user tracking
        if (userTotalProfits[user] == 0) {
            totalUsers++;
        }
        userTotalProfits[user] += totalProfit;
        userPendingRewards[user] += userShare;
        
        // Update global statistics
        totalProfitsGenerated += totalProfit;
        
        // Add to reward pool
        _addToRewardPool(tokenOut, userShare, user);
        _addToRewardPool(tokenOut, lpIncentive, address(0)); // LP pool
        
        emit ProfitRecorded(opportunityId, user, totalProfit, userShare);
        
        // Auto-distribute if enabled and above threshold
        if (config.autoDistribute && userShare >= config.minDistribution) {
            _distributeProfit(opportunityId);
        }
    }
    
    /**
     * @notice Distribute recorded profit to recipients
     * @param opportunityId Opportunity to distribute profits for
     */
    function distributeProfit(bytes32 opportunityId) external nonReentrant {
        _distributeProfit(opportunityId);
    }
    
    /**
     * @notice Claim accumulated rewards for a user
     * @param token Token to claim rewards for
     */
    function claimRewards(address token) external nonReentrant whenNotPaused {
        if (!isTokenSupported[token]) {
            revert Errors.InvalidTokenAddress();
        }
        
        RewardPool storage pool = rewardPools[token];
        uint256 userRewards = pool.userRewards[msg.sender];
        
        if (userRewards == 0) {
            revert("No rewards to claim");
        }
        
        // Check claim cooldown
        if (block.timestamp < pool.lastClaimTime[msg.sender] + MIN_CLAIM_INTERVAL) {
            revert("Claim cooldown active");
        }
        
        // Update state before transfer
        pool.userRewards[msg.sender] = 0;
        pool.distributedRewards += userRewards;
        pool.lastClaimTime[msg.sender] = block.timestamp;
        userPendingRewards[msg.sender] -= userRewards;
        totalDistributed += userRewards;
        
        // Transfer rewards
        IERC20(token).safeTransfer(msg.sender, userRewards);
        
        emit RewardsClaimed(msg.sender, token, userRewards);
    }
    
    /**
     * @notice Batch claim rewards for multiple tokens
     * @param tokens Array of token addresses to claim
     */
    function batchClaimRewards(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (rewardPools[tokens[i]].userRewards[msg.sender] > 0) {
                this.claimRewards(tokens[i]);
            }
        }
    }
    
    /**
     * @notice Update distribution configuration
     * @param newConfig New distribution configuration
     */
    function updateConfiguration(DistributionConfig memory newConfig) external onlyOwner {
        // Validate configuration
        uint256 totalBPS = newConfig.userShareBPS + newConfig.protocolFeeBPS + 
                          newConfig.lpIncentiveBPS + newConfig.treasuryBPS + newConfig.burnBPS;
        
        if (totalBPS != MAX_BPS) {
            revert Errors.InvalidHookData();
        }
        
        config = newConfig;
        
        emit ConfigurationUpdated(
            newConfig.userShareBPS,
            newConfig.protocolFeeBPS,
            newConfig.lpIncentiveBPS
        );
    }
    
    /**
     * @notice Add support for a new token
     * @param token Token address to add
     */
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) {
            revert Errors.InvalidTokenAddress();
        }
        
        if (!isTokenSupported[token]) {
            supportedTokens.push(token);
            isTokenSupported[token] = true;
            
            // Initialize reward pool
            RewardPool storage pool = rewardPools[token];
            pool.token = token;
        }
    }
    
    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) {
            revert Errors.InvalidTokenAddress();
        }
        treasury = newTreasury;
    }
    
    /**
     * @notice Emergency withdraw funds
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(treasury, amount);
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // View functions
    
    /**
     * @notice Get user's claimable rewards for a token
     * @param user User address
     * @param token Token address
     * @return amount Claimable amount
     */
    function getClaimableRewards(address user, address token) external view returns (uint256 amount) {
        if (!isTokenSupported[token]) return 0;
        return rewardPools[token].userRewards[user];
    }
    
    /**
     * @notice Get user's total claimable rewards across all tokens
     * @param user User address
     * @return tokens Array of token addresses
     * @return amounts Array of claimable amounts
     */
    function getAllClaimableRewards(address user) external view returns (
        address[] memory tokens,
        uint256[] memory amounts
    ) {
        uint256 count = 0;
        
        // Count tokens with rewards
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (rewardPools[supportedTokens[i]].userRewards[user] > 0) {
                count++;
            }
        }
        
        // Fill arrays
        tokens = new address[](count);
        amounts = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            uint256 amount = rewardPools[token].userRewards[user];
            if (amount > 0) {
                tokens[index] = token;
                amounts[index] = amount;
                index++;
            }
        }
    }
    
    /**
     * @notice Get supported tokens list
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }
    
    /**
     * @notice Get distribution statistics
     * @return totalGenerated Total profits generated
     * @return totalDist Total distributed
     * @return userCount Total number of users
     */
    function getDistributionStats() external view returns (
        uint256 totalGenerated,
        uint256 totalDist,
        uint256 userCount
    ) {
        return (totalProfitsGenerated, totalDistributed, totalUsers);
    }
    
    // Internal functions
    
    function _distributeProfit(bytes32 opportunityId) internal {
        ProfitRecord storage record = profitRecords[opportunityId];
        
        if (record.opportunityId == bytes32(0)) {
            revert("Invalid opportunity");
        }
        
        if (record.distributed) {
            revert("Already distributed");
        }
        
        record.distributed = true;
        
        emit ProfitDistributed(
            opportunityId,
            record.user,
            record.tokenOut,
            record.userShare
        );
    }
    
    function _addToRewardPool(address token, uint256 amount, address user) internal {
        if (!isTokenSupported[token]) {
            this.addSupportedToken(token);
        }
        
        RewardPool storage pool = rewardPools[token];
        pool.totalRewards += amount;
        
        if (user != address(0)) {
            pool.userRewards[user] += amount;
        } else {
            pool.pendingRewards += amount;
        }
    }
}