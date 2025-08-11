// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IArbitrageHook} from "../hooks/interfaces/IArbitrageHook.sol";
import {IAcrossIntegration} from "../hooks/interfaces/IAcrossIntegration.sol";
import {PriceOracle} from "../libraries/PriceOracle.sol";
import {ProfitCalculator} from "../libraries/ProfitCalculator.sol";
import {GasEstimator} from "../libraries/GasEstimator.sol";
import {MEVProtection} from "../libraries/MEVProtection.sol";
import {ChainConstants} from "../utils/ChainConstants.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ArbitrageManager
 * @notice Core arbitrage logic and execution management
 * @dev Handles the complex logic of arbitrage opportunity detection, validation, and execution
 */
contract ArbitrageManager is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using PriceOracle for PriceOracle.PriceFeedRegistry;
    using ProfitCalculator for ProfitCalculator.ArbitrageParameters;
    using GasEstimator for uint256;
    using MEVProtection for bytes32;

    // State variables
    PriceOracle.PriceFeedRegistry private priceRegistry;
    
    // Arbitrage configuration
    struct ArbitrageConfig {
        uint256 minProfitBPS;           // Minimum profit threshold in basis points
        uint256 maxSlippageBPS;         // Maximum allowed slippage in basis points  
        uint256 maxGasPrice;            // Maximum gas price willing to pay
        uint256 minLiquidity;           // Minimum liquidity required for arbitrage
        uint256 maxPositionSize;        // Maximum position size per arbitrage
        bool mevProtectionEnabled;      // Whether MEV protection is active
        uint256 executionDelay;         // Delay between detection and execution
    }
    
    ArbitrageConfig public config;
    
    // Active arbitrage tracking
    mapping(bytes32 => IArbitrageHook.ArbitrageOpportunity) public activeOpportunities;
    mapping(bytes32 => uint256) public opportunityTimestamps;
    mapping(address => uint256) public userArbitrageCount;
    
    // Performance tracking
    struct ArbitrageStats {
        uint256 totalExecuted;
        uint256 totalProfit;
        uint256 successRate;
        uint256 averageExecutionTime;
    }
    
    ArbitrageStats public stats;
    
    // Events
    event OpportunityDetected(
        bytes32 indexed opportunityId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 expectedProfitBPS,
        uint256 targetChainId
    );
    
    event ArbitrageValidated(
        bytes32 indexed opportunityId,
        bool isValid,
        string reason
    );
    
    event ExecutionStarted(
        bytes32 indexed opportunityId,
        address indexed executor,
        uint256 timestamp
    );
    
    event ExecutionCompleted(
        bytes32 indexed opportunityId,
        uint256 actualProfit,
        uint256 executionTime
    );

    constructor(address initialOwner) Ownable(initialOwner) {
        // Initialize with sensible defaults
        config = ArbitrageConfig({
            minProfitBPS: 50,              // 0.5%
            maxSlippageBPS: 100,           // 1%
            maxGasPrice: 100 gwei,         // 100 gwei max
            minLiquidity: 10000e18,        // $10,000 min liquidity
            maxPositionSize: 100 ether,     // 100 ETH max position
            mevProtectionEnabled: true,
            executionDelay: 5 seconds
        });
    }
    
    /**
     * @notice Detect and validate arbitrage opportunities
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount to arbitrage
     * @return opportunities Array of validated opportunities
     */
    function detectOpportunities(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (IArbitrageHook.ArbitrageOpportunity[] memory opportunities) {
        // Get multi-chain price data
        IArbitrageHook.ChainPriceData[] memory priceData = priceRegistry.getMultiChainPrices(tokenIn, tokenOut);
        
        // Create array to store opportunities
        IArbitrageHook.ArbitrageOpportunity[] memory tempOpportunities = 
            new IArbitrageHook.ArbitrageOpportunity[](priceData.length);
        uint256 validCount = 0;
        
        // Analyze each chain for opportunities
        for (uint256 i = 0; i < priceData.length; i++) {
            if (priceData[i].chainId == block.chainid) continue;
            
            // Calculate potential profit
            uint256 localPrice = _getLocalPrice(tokenIn, tokenOut);
            uint256 profitBPS = _calculateProfitBPS(
                amountIn,
                localPrice,
                priceData[i].price,
                priceData[i].gasEstimate
            );
            
            // Validate opportunity
            if (_isOpportunityValid(priceData[i], amountIn, profitBPS)) {
                tempOpportunities[validCount] = IArbitrageHook.ArbitrageOpportunity({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedProfitBPS: profitBPS,
                    originChainId: block.chainid,
                    targetChainId: priceData[i].chainId,
                    routeHash: keccak256(abi.encode(tokenIn, tokenOut, priceData[i].chainId)),
                    timestamp: block.timestamp
                });
                validCount++;
            }
        }
        
        // Return only valid opportunities
        opportunities = new IArbitrageHook.ArbitrageOpportunity[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            opportunities[i] = tempOpportunities[i];
        }
    }
    
    /**
     * @notice Validate a specific arbitrage opportunity
     * @param opportunity Arbitrage opportunity to validate
     * @return isValid Whether the opportunity is valid
     * @return reason Validation result description
     */
    function validateOpportunity(
        IArbitrageHook.ArbitrageOpportunity memory opportunity
    ) external view returns (bool isValid, string memory reason) {
        // Check minimum profit threshold
        if (opportunity.expectedProfitBPS < config.minProfitBPS) {
            return (false, "Insufficient profit");
        }
        
        // Check position size limits
        if (opportunity.amountIn > config.maxPositionSize) {
            return (false, "Position size too large");
        }
        
        // Check chain support
        if (!ChainConstants.isChainSupported(opportunity.targetChainId)) {
            return (false, "Target chain not supported");
        }
        
        // Check liquidity requirements
        IArbitrageHook.ChainPriceData[] memory priceData = priceRegistry.getMultiChainPrices(
            opportunity.tokenIn, 
            opportunity.tokenOut
        );
        
        uint256 targetLiquidity = 0;
        for (uint256 i = 0; i < priceData.length; i++) {
            if (priceData[i].chainId == opportunity.targetChainId) {
                targetLiquidity = priceData[i].liquidity;
                break;
            }
        }
        
        if (targetLiquidity < config.minLiquidity) {
            return (false, "Insufficient target liquidity");
        }
        
        // Check gas price constraints
        uint256 estimatedGasPrice = opportunity.targetChainId.estimateGasPrice();
        if (estimatedGasPrice > config.maxGasPrice) {
            return (false, "Gas price too high");
        }
        
        // MEV protection check
        if (config.mevProtectionEnabled) {
            if (!opportunity.routeHash.checkMEVProtection()) {
                return (false, "MEV risk detected");
            }
        }
        
        return (true, "Valid opportunity");
    }
    
    /**
     * @notice Execute arbitrage opportunity with full validation
     * @param opportunity Arbitrage opportunity to execute
     * @param executor Address executing the arbitrage
     * @return success Whether execution was successful
     * @return intentId Cross-chain intent ID if successful
     */
    function executeArbitrage(
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        address executor
    ) external nonReentrant returns (bool success, bytes32 intentId) {
        bytes32 opportunityId = keccak256(abi.encode(opportunity));
        
        // Validate opportunity
        (bool isValid, string memory reason) = this.validateOpportunity(opportunity);
        if (!isValid) {
            emit ArbitrageValidated(opportunityId, false, reason);
            return (false, bytes32(0));
        }
        
        emit ArbitrageValidated(opportunityId, true, "Validated");
        
        // Apply execution delay for MEV protection
        if (config.mevProtectionEnabled && config.executionDelay > 0) {
            if (opportunityTimestamps[opportunityId] == 0) {
                opportunityTimestamps[opportunityId] = block.timestamp;
                activeOpportunities[opportunityId] = opportunity;
                return (false, bytes32(0)); // Wait for delay
            }
            
            if (block.timestamp < opportunityTimestamps[opportunityId] + config.executionDelay) {
                return (false, bytes32(0)); // Still waiting
            }
        }
        
        emit ExecutionStarted(opportunityId, executor, block.timestamp);
        
        // Execute the cross-chain arbitrage
        // This would integrate with the AcrossIntegration library
        success = true; // Placeholder
        intentId = opportunityId; // Placeholder
        
        if (success) {
            // Update statistics
            stats.totalExecuted++;
            userArbitrageCount[executor]++;
            
            emit ExecutionCompleted(opportunityId, opportunity.expectedProfitBPS, block.timestamp);
            
            // Clean up temporary storage
            delete opportunityTimestamps[opportunityId];
            delete activeOpportunities[opportunityId];
        }
    }
    
    /**
     * @notice Update arbitrage configuration
     * @param newConfig New configuration parameters
     */
    function updateConfig(ArbitrageConfig memory newConfig) external onlyOwner {
        if (newConfig.minProfitBPS > 10000 || newConfig.maxSlippageBPS > 10000) {
            revert Errors.InvalidHookData();
        }
        
        config = newConfig;
        
        emit Events.ArbitrageConfigUpdated(
            newConfig.minProfitBPS,
            newConfig.maxSlippageBPS,
            0 // userProfitShareBPS not in this config
        );
    }
    
    /**
     * @notice Add price oracle for token on specific chain
     */
    function addOracle(
        address token,
        uint256 chainId,
        address feedAddress,
        uint256 heartbeat,
        uint8 decimals
    ) external onlyOwner {
        priceRegistry.addOracle(token, chainId, feedAddress, heartbeat, decimals);
    }
    
    // Internal functions
    
    function _getLocalPrice(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 price) {
        // For internal calls, we can't use try-catch, so use direct calls with fallbacks
        (bool success1, bytes memory data1) = address(this).staticcall(
            abi.encodeWithSignature("getPrice(address,uint256)", tokenIn, block.chainid)
        );
        (bool success2, bytes memory data2) = address(this).staticcall(
            abi.encodeWithSignature("getPrice(address,uint256)", tokenOut, block.chainid)
        );
        
        if (success1 && success2) {
            (uint256 priceIn,) = abi.decode(data1, (uint256, uint256));
            (uint256 priceOut,) = abi.decode(data2, (uint256, uint256));
            price = (priceIn * 1e18) / priceOut;
        } else {
            price = 1e18; // 1:1 fallback
        }
    }
    
    // Helper function to get price using the price registry
    function getPrice(address token, uint256 chainId) external view returns (uint256 priceResult, uint256 timestamp) {
        return priceRegistry.getPrice(token, chainId);
    }
    
    function _calculateProfitBPS(
        uint256 amountIn,
        uint256 localPrice,
        uint256 remotePrice,
        uint256 gasCost
    ) internal view returns (uint256 profitBPS) {
        if (remotePrice <= localPrice) return 0;
        
        uint256 expectedOutput = (amountIn * remotePrice) / localPrice;
        uint256 bridgeFee = (amountIn * 10) / 10000; // 0.1% bridge fee
        uint256 totalCosts = bridgeFee + gasCost;
        
        if (expectedOutput > amountIn + totalCosts) {
            uint256 profit = expectedOutput - amountIn - totalCosts;
            profitBPS = (profit * 10000) / amountIn;
        }
    }
    
    function _isOpportunityValid(
        IArbitrageHook.ChainPriceData memory priceData,
        uint256 amountIn,
        uint256 profitBPS
    ) internal view returns (bool) {
        return profitBPS >= config.minProfitBPS &&
               priceData.liquidity >= config.minLiquidity &&
               amountIn <= config.maxPositionSize;
    }
    
    // View functions for statistics
    
    function getArbitrageStats() external view returns (ArbitrageStats memory) {
        return stats;
    }
    
    function getUserArbitrageCount(address user) external view returns (uint256) {
        return userArbitrageCount[user];
    }
    
    function getActiveOpportunity(bytes32 opportunityId) 
        external view returns (IArbitrageHook.ArbitrageOpportunity memory) {
        return activeOpportunities[opportunityId];
    }
}