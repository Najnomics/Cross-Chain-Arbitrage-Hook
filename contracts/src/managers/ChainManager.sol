// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ChainConstants} from "../utils/ChainConstants.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChainManager
 * @notice Multi-chain coordination and management
 * @dev Handles chain-specific configurations, monitoring, and coordination
 */
contract ChainManager is Ownable {
    
    // Chain configuration structure
    struct ChainConfig {
        bool isActive;                  // Whether chain is active for arbitrage
        uint256 gasLimit;              // Gas limit for transactions
        uint256 maxGasPrice;           // Maximum gas price willing to pay
        uint256 confirmations;         // Required confirmations
        uint256 blockTime;            // Average block time in seconds
        address spokePoolAddress;      // Across Protocol spoke pool
        uint256 bridgeFee;            // Base bridge fee in BPS
        uint256 minBridgeAmount;       // Minimum amount for bridging
        uint256 maxBridgeAmount;       // Maximum amount for bridging
        bool mevProtectionEnabled;     // MEV protection status
    }
    
    // Chain status monitoring
    struct ChainStatus {
        bool isHealthy;               // Overall chain health
        uint256 lastHeartbeat;        // Last successful heartbeat
        uint256 avgGasPrice;          // Current average gas price
        uint256 pendingTransactions;  // Number of pending transactions
        uint256 failureCount;         // Recent failure count
        uint256 lastBlockNumber;      // Last processed block number
    }
    
    // State variables
    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(uint256 => ChainStatus) public chainStatuses;
    uint256[] public supportedChains;
    mapping(uint256 => bool) public isSupportedChain;
    
    // Health monitoring
    uint256 public constant HEARTBEAT_INTERVAL = 5 minutes;
    uint256 public constant MAX_FAILURES_THRESHOLD = 3;
    uint256 public constant HEALTH_CHECK_WINDOW = 1 hours;
    
    // Events
    event ChainAdded(uint256 indexed chainId, address spokePool);
    event ChainConfigUpdated(uint256 indexed chainId);
    event ChainStatusUpdated(uint256 indexed chainId, bool isHealthy);
    event ChainDeactivated(uint256 indexed chainId, string reason);
    event CrossChainMessageSent(uint256 indexed fromChain, uint256 indexed toChain, bytes32 messageHash);
    
    constructor(address initialOwner) Ownable(initialOwner) {
        // Initialize with default supported chains
        _initializeDefaultChains();
    }
    
    /**
     * @notice Add a new chain to the supported list
     * @param chainId Chain ID to add
     * @param spokePoolAddress Across Protocol spoke pool address
     * @param config Chain configuration
     */
    function addChain(
        uint256 chainId,
        address spokePoolAddress,
        ChainConfig memory config
    ) external onlyOwner {
        if (isSupportedChain[chainId]) {
            revert Errors.InvalidChainId();
        }
        
        if (spokePoolAddress == address(0)) {
            revert Errors.InvalidTokenAddress();
        }
        
        // Add to supported chains
        supportedChains.push(chainId);
        isSupportedChain[chainId] = true;
        
        // Set configuration
        config.spokePoolAddress = spokePoolAddress;
        chainConfigs[chainId] = config;
        
        // Initialize status
        chainStatuses[chainId] = ChainStatus({
            isHealthy: true,
            lastHeartbeat: block.timestamp,
            avgGasPrice: config.maxGasPrice / 2, // Start with 50% of max
            pendingTransactions: 0,
            failureCount: 0,
            lastBlockNumber: 0
        });
        
        emit ChainAdded(chainId, spokePoolAddress);
    }
    
    /**
     * @notice Update chain configuration
     * @param chainId Chain ID to update
     * @param config New configuration
     */
    function updateChainConfig(
        uint256 chainId,
        ChainConfig memory config
    ) external onlyOwner {
        if (!isSupportedChain[chainId]) {
            revert Errors.InvalidChainId();
        }
        
        chainConfigs[chainId] = config;
        emit ChainConfigUpdated(chainId);
    }
    
    /**
     * @notice Update chain health status
     * @param chainId Chain ID to update
     * @param gasPrice Current gas price
     * @param blockNumber Current block number
     * @param pendingTxs Number of pending transactions
     */
    function updateChainStatus(
        uint256 chainId,
        uint256 gasPrice,
        uint256 blockNumber,
        uint256 pendingTxs
    ) external {
        if (!isSupportedChain[chainId]) {
            revert Errors.InvalidChainId();
        }
        
        ChainStatus storage status = chainStatuses[chainId];
        
        // Update basic metrics
        status.avgGasPrice = gasPrice;
        status.lastBlockNumber = blockNumber;
        status.pendingTransactions = pendingTxs;
        status.lastHeartbeat = block.timestamp;
        
        // Assess health
        bool wasHealthy = status.isHealthy;
        status.isHealthy = _assessChainHealth(chainId, status);
        
        // Emit event if health status changed
        if (wasHealthy != status.isHealthy) {
            emit ChainStatusUpdated(chainId, status.isHealthy);
            
            if (!status.isHealthy) {
                emit ChainDeactivated(chainId, "Health check failed");
            }
        }
    }
    
    /**
     * @notice Report a failed transaction on a chain
     * @param chainId Chain ID where failure occurred
     */
    function reportChainFailure(uint256 chainId) external {
        if (!isSupportedChain[chainId]) {
            revert Errors.InvalidChainId();
        }
        
        ChainStatus storage status = chainStatuses[chainId];
        status.failureCount++;
        
        // Check if we should mark chain as unhealthy
        if (status.failureCount >= MAX_FAILURES_THRESHOLD) {
            status.isHealthy = false;
            emit ChainStatusUpdated(chainId, false);
            emit ChainDeactivated(chainId, "Too many failures");
        }
    }
    
    /**
     * @notice Get optimal chain for arbitrage execution
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amount Amount to trade
     * @return chainId Optimal chain ID
     * @return score Optimization score
     */
    function getOptimalChain(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external view returns (uint256 chainId, uint256 score) {
        uint256 bestScore = 0;
        uint256 bestChain = 0;
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint256 currentChainId = supportedChains[i];
            
            // Skip unhealthy chains
            if (!chainStatuses[currentChainId].isHealthy) continue;
            
            // Skip inactive chains
            if (!chainConfigs[currentChainId].isActive) continue;
            
            // Calculate chain score
            uint256 currentScore = _calculateChainScore(currentChainId, amount);
            
            if (currentScore > bestScore) {
                bestScore = currentScore;
                bestChain = currentChainId;
            }
        }
        
        return (bestChain, bestScore);
    }
    
    /**
     * @notice Check if arbitrage between two chains is feasible
     * @param fromChain Origin chain ID
     * @param toChain Target chain ID
     * @param amount Amount to bridge
     * @return feasible Whether arbitrage is feasible
     * @return cost Estimated total cost
     */
    function checkArbitrageFeasibility(
        uint256 fromChain,
        uint256 toChain,
        uint256 amount
    ) external view returns (bool feasible, uint256 cost) {
        // Check both chains are supported and healthy
        if (!isSupportedChain[fromChain] || !isSupportedChain[toChain]) {
            return (false, 0);
        }
        
        if (!chainStatuses[fromChain].isHealthy || !chainStatuses[toChain].isHealthy) {
            return (false, 0);
        }
        
        ChainConfig memory fromConfig = chainConfigs[fromChain];
        ChainConfig memory toConfig = chainConfigs[toChain];
        
        // Check amount limits
        if (amount < fromConfig.minBridgeAmount || amount > fromConfig.maxBridgeAmount) {
            return (false, 0);
        }
        
        // Calculate total cost
        uint256 bridgeFee = (amount * fromConfig.bridgeFee) / 10000;
        uint256 fromChainGas = fromConfig.gasLimit * chainStatuses[fromChain].avgGasPrice;
        uint256 toChainGas = toConfig.gasLimit * chainStatuses[toChain].avgGasPrice;
        
        cost = bridgeFee + fromChainGas + toChainGas;
        feasible = true;
    }
    
    /**
     * @notice Get supported chains list
     * @return Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChains;
    }
    
    /**
     * @notice Get healthy chains only
     * @return Array of healthy chain IDs
     */
    function getHealthyChains() external view returns (uint256[] memory) {
        uint256[] memory tempChains = new uint256[](supportedChains.length);
        uint256 healthyCount = 0;
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint256 chainId = supportedChains[i];
            if (chainStatuses[chainId].isHealthy && chainConfigs[chainId].isActive) {
                tempChains[healthyCount] = chainId;
                healthyCount++;
            }
        }
        
        // Return properly sized array
        uint256[] memory healthyChains = new uint256[](healthyCount);
        for (uint256 i = 0; i < healthyCount; i++) {
            healthyChains[i] = tempChains[i];
        }
        
        return healthyChains;
    }
    
    /**
     * @notice Emergency deactivate a chain
     * @param chainId Chain ID to deactivate
     * @param reason Reason for deactivation
     */
    function emergencyDeactivateChain(uint256 chainId, string calldata reason) external onlyOwner {
        if (isSupportedChain[chainId]) {
            chainConfigs[chainId].isActive = false;
            chainStatuses[chainId].isHealthy = false;
            emit ChainDeactivated(chainId, reason);
        }
    }
    
    /**
     * @notice Reactivate a deactivated chain
     * @param chainId Chain ID to reactivate
     */
    function reactivateChain(uint256 chainId) external onlyOwner {
        if (isSupportedChain[chainId]) {
            chainConfigs[chainId].isActive = true;
            chainStatuses[chainId].isHealthy = true;
            chainStatuses[chainId].failureCount = 0;
            chainStatuses[chainId].lastHeartbeat = block.timestamp;
            emit ChainStatusUpdated(chainId, true);
        }
    }
    
    // Internal functions
    
    function _initializeDefaultChains() internal {
        // Add Ethereum
        _addDefaultChain(ChainConstants.ETHEREUM_CHAIN_ID, ChainConfig({
            isActive: true,
            gasLimit: ChainConstants.ETHEREUM_GAS_LIMIT,
            maxGasPrice: 100 gwei,
            confirmations: ChainConstants.ETHEREUM_CONFIRMATIONS,
            blockTime: 12,
            spokePoolAddress: address(0), // Will be set during deployment
            bridgeFee: 10, // 0.1%
            minBridgeAmount: 0.01 ether,
            maxBridgeAmount: 100 ether,
            mevProtectionEnabled: true
        }));
        
        // Add Arbitrum
        _addDefaultChain(ChainConstants.ARBITRUM_CHAIN_ID, ChainConfig({
            isActive: true,
            gasLimit: ChainConstants.ARBITRUM_GAS_LIMIT,
            maxGasPrice: 1 gwei,
            confirmations: ChainConstants.ARBITRUM_CONFIRMATIONS,
            blockTime: 1,
            spokePoolAddress: address(0),
            bridgeFee: 5, // 0.05%
            minBridgeAmount: 0.001 ether,
            maxBridgeAmount: 1000 ether,
            mevProtectionEnabled: true
        }));
        
        // Add Base
        _addDefaultChain(ChainConstants.BASE_CHAIN_ID, ChainConfig({
            isActive: true,
            gasLimit: ChainConstants.BASE_GAS_LIMIT,
            maxGasPrice: 1 gwei,
            confirmations: ChainConstants.BASE_CONFIRMATIONS,
            blockTime: 2,
            spokePoolAddress: address(0),
            bridgeFee: 5, // 0.05%
            minBridgeAmount: 0.001 ether,
            maxBridgeAmount: 1000 ether,
            mevProtectionEnabled: true
        }));
    }
    
    function _addDefaultChain(uint256 chainId, ChainConfig memory config) internal {
        supportedChains.push(chainId);
        isSupportedChain[chainId] = true;
        chainConfigs[chainId] = config;
        chainStatuses[chainId] = ChainStatus({
            isHealthy: true,
            lastHeartbeat: block.timestamp,
            avgGasPrice: config.maxGasPrice / 2,
            pendingTransactions: 0,
            failureCount: 0,
            lastBlockNumber: 0
        });
    }
    
    function _assessChainHealth(
        uint256 chainId,
        ChainStatus memory status
    ) internal view returns (bool) {
        ChainConfig memory config = chainConfigs[chainId];
        
        // Check heartbeat
        if (block.timestamp - status.lastHeartbeat > HEARTBEAT_INTERVAL * 2) {
            return false;
        }
        
        // Check gas price
        if (status.avgGasPrice > config.maxGasPrice) {
            return false;
        }
        
        // Check failure count
        if (status.failureCount >= MAX_FAILURES_THRESHOLD) {
            return false;
        }
        
        return true;
    }
    
    function _calculateChainScore(
        uint256 chainId,
        uint256 amount
    ) internal view returns (uint256 score) {
        ChainConfig memory config = chainConfigs[chainId];
        ChainStatus memory status = chainStatuses[chainId];
        
        // Base score
        score = 1000;
        
        // Gas cost factor (lower is better)
        uint256 gasCost = config.gasLimit * status.avgGasPrice;
        score = score - (gasCost / 1e9); // Normalize
        
        // Bridge fee factor
        uint256 bridgeFee = (amount * config.bridgeFee) / 10000;
        score = score - (bridgeFee / 1e15); // Normalize
        
        // Speed factor (faster is better)
        score = score + (100 / config.blockTime);
        
        // Health penalty
        if (status.failureCount > 0) {
            score = score - (status.failureCount * 100);
        }
        
        return score;
    }
}