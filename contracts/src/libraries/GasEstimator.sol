// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ChainConstants} from "../utils/ChainConstants.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title GasEstimator
 * @notice Library for estimating gas costs across different chains
 * @dev Provides sophisticated gas cost estimation for cross-chain arbitrage
 */
library GasEstimator {
    
    // Gas cost structure for different operation types
    struct GasProfile {
        uint256 baseGas;           // Base gas for transaction
        uint256 tokenTransfer;     // Additional gas for token transfer
        uint256 swapGas;          // Gas for DEX swap
        uint256 bridgeGas;        // Gas for cross-chain bridge
        uint256 complexityFactor; // Multiplier for complex operations
    }
    
    // Chain-specific gas configurations
    struct ChainGasConfig {
        uint256 baseFeeMultiplier;    // Base fee multiplier for EIP-1559 chains
        uint256 priorityFeePerGas;    // Priority fee for faster inclusion
        uint256 maxFeePerGas;         // Maximum fee willing to pay
        uint256 gasLimitBuffer;       // Buffer percentage for gas limit
        uint256 congestionMultiplier; // Multiplier during network congestion
        bool supportsEIP1559;         // Whether chain supports EIP-1559
    }
    
    // Historical gas data for trend analysis
    struct GasHistory {
        uint256[] recentPrices;       // Recent gas prices
        uint256[] timestamps;         // Corresponding timestamps
        uint256 average;              // Moving average
        uint256 trend;                // Price trend (increase/decrease)
    }
    
    // Constants
    uint256 private constant GAS_PRICE_HISTORY_SIZE = 20;
    uint256 private constant BASE_GAS_LIMIT = 21000;
    uint256 private constant SWAP_GAS_ESTIMATE = 150000;
    uint256 private constant BRIDGE_GAS_ESTIMATE = 200000;
    uint256 private constant COMPLEX_ARBITRAGE_GAS = 500000;
    
    /**
     * @notice Estimate gas cost for arbitrage execution on target chain
     * @param chainId Target chain ID
     * @param amountIn Input amount for arbitrage
     * @param complexity Complexity level (0=simple, 1=medium, 2=complex)
     * @return gasEstimate Total gas cost estimate in wei
     * @return gasLimit Recommended gas limit
     */
    function estimateArbitrageGas(
        uint256 chainId,
        uint256 amountIn,
        uint8 complexity
    ) internal pure returns (uint256 gasEstimate, uint256 gasLimit) {
        ChainGasConfig memory config = getChainGasConfig(chainId);
        GasProfile memory profile = getGasProfile(complexity);
        
        // Calculate base gas limit
        gasLimit = profile.baseGas + profile.swapGas + profile.bridgeGas;
        
        // Apply complexity factor
        gasLimit = (gasLimit * profile.complexityFactor) / 100;
        
        // Add buffer for safety
        gasLimit = (gasLimit * (100 + config.gasLimitBuffer)) / 100;
        
        // Calculate cost based on chain type
        if (config.supportsEIP1559) {
            // EIP-1559 gas calculation
            uint256 baseFee = getCurrentBaseFee(chainId);
            gasEstimate = gasLimit * (baseFee + config.priorityFeePerGas);
        } else {
            // Legacy gas calculation
            uint256 gasPrice = getCurrentGasPrice(chainId);
            gasEstimate = gasLimit * gasPrice;
        }
        
        // Apply congestion multiplier if network is congested
        if (isNetworkCongested(chainId)) {
            gasEstimate = (gasEstimate * config.congestionMultiplier) / 100;
        }
    }
    
    /**
     * @notice Estimate gas for cross-chain bridge operation
     * @param fromChain Origin chain ID
     * @param toChain Destination chain ID
     * @param amount Amount being bridged
     * @return fromChainGas Gas cost on origin chain
     * @return toChainGas Gas cost on destination chain
     */
    function estimateBridgeGas(
        uint256 fromChain,
        uint256 toChain,
        uint256 amount
    ) internal pure returns (uint256 fromChainGas, uint256 toChainGas) {
        // Origin chain gas (for initiating bridge)
        uint256 fromGasLimit = BRIDGE_GAS_ESTIMATE + _getAmountBasedGas(amount);
        uint256 fromGasPrice = getCurrentGasPrice(fromChain);
        fromChainGas = fromGasLimit * fromGasPrice;
        
        // Destination chain gas (for execution)
        uint256 toGasLimit = SWAP_GAS_ESTIMATE + BASE_GAS_LIMIT;
        uint256 toGasPrice = getCurrentGasPrice(toChain);
        toChainGas = toGasLimit * toGasPrice;
        
        // Apply chain-specific multipliers
        fromChainGas = _applyChainMultiplier(fromChain, fromChainGas);
        toChainGas = _applyChainMultiplier(toChain, toChainGas);
    }
    
    /**
     * @notice Get current gas price for a chain
     * @param chainId Chain ID
     * @return gasPrice Current gas price in wei
     */
    function getCurrentGasPrice(uint256 chainId) internal pure returns (uint256 gasPrice) {
        // In production, this would query actual gas price oracles
        // For now, return chain-specific estimates
        
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            gasPrice = 20 gwei; // Ethereum mainnet
        } else if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) {
            gasPrice = 0.1 gwei; // Arbitrum
        } else if (chainId == ChainConstants.BASE_CHAIN_ID) {
            gasPrice = 0.1 gwei; // Base
        } else if (chainId == ChainConstants.POLYGON_CHAIN_ID) {
            gasPrice = 30 gwei; // Polygon
        } else if (chainId == ChainConstants.OPTIMISM_CHAIN_ID) {
            gasPrice = 0.001 gwei; // Optimism
        } else {
            gasPrice = 10 gwei; // Default for unknown chains
        }
    }
    
    /**
     * @notice Get current base fee for EIP-1559 chains
     * @param chainId Chain ID
     * @return baseFee Current base fee in wei
     */
    function getCurrentBaseFee(uint256 chainId) internal pure returns (uint256 baseFee) {
        // In production, this would query the actual base fee
        // For now, return estimates based on current gas prices
        
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            baseFee = 15 gwei; // Ethereum base fee
        } else if (chainId == ChainConstants.BASE_CHAIN_ID) {
            baseFee = 0.05 gwei; // Base base fee
        } else {
            baseFee = getCurrentGasPrice(chainId) * 80 / 100; // 80% of gas price as base fee
        }
    }
    
    /**
     * @notice Check if network is currently congested
     * @param chainId Chain ID to check
     * @return congested Whether network is congested
     */
    function isNetworkCongested(uint256 chainId) internal pure returns (bool congested) {
        // In production, this would analyze mempool size, gas prices, etc.
        // For now, return false as a placeholder
        congested = false;
    }
    
    /**
     * @notice Get optimal gas price for fast inclusion
     * @param chainId Chain ID
     * @param urgency Urgency level (0=slow, 1=standard, 2=fast)
     * @return gasPrice Optimal gas price
     * @return estimatedTime Estimated confirmation time in seconds
     */
    function getOptimalGasPrice(
        uint256 chainId,
        uint8 urgency
    ) internal pure returns (uint256 gasPrice, uint256 estimatedTime) {
        uint256 basePrice = getCurrentGasPrice(chainId);
        
        if (urgency == 0) {
            // Slow - 80% of current price
            gasPrice = (basePrice * 80) / 100;
            estimatedTime = 300; // 5 minutes
        } else if (urgency == 1) {
            // Standard - current price
            gasPrice = basePrice;
            estimatedTime = 180; // 3 minutes
        } else {
            // Fast - 150% of current price
            gasPrice = (basePrice * 150) / 100;
            estimatedTime = 60; // 1 minute
        }
        
        // Apply chain-specific adjustments
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            estimatedTime *= 12; // Block time multiplier
        } else if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) {
            estimatedTime *= 1; // Near instant
        }
    }
    
    /**
     * @notice Calculate gas cost in USD equivalent
     * @param chainId Chain ID
     * @param gasAmount Gas amount in wei
     * @return usdCost Cost in USD (scaled by 1e18)
     */
    function calculateGasCostUSD(
        uint256 chainId,
        uint256 gasAmount
    ) internal pure returns (uint256 usdCost) {
        // Get native token price (simplified)
        uint256 nativeTokenPriceUSD = getNativeTokenPrice(chainId);
        usdCost = (gasAmount * nativeTokenPriceUSD) / 1e18;
    }
    
    /**
     * @notice Get maximum gas price willing to pay for profitable arbitrage
     * @param expectedProfit Expected arbitrage profit
     * @param maxGasRatio Maximum gas cost as percentage of profit (in BPS)
     * @return maxGasPrice Maximum gas price in wei
     */
    function getMaxGasPrice(
        uint256 expectedProfit,
        uint256 maxGasRatio
    ) internal pure returns (uint256 maxGasPrice) {
        uint256 maxGasCost = (expectedProfit * maxGasRatio) / 10000;
        maxGasPrice = maxGasCost / COMPLEX_ARBITRAGE_GAS;
    }
    
    // Internal helper functions
    
    function getChainGasConfig(uint256 chainId) internal pure returns (ChainGasConfig memory config) {
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            config = ChainGasConfig({
                baseFeeMultiplier: 100,
                priorityFeePerGas: 2 gwei,
                maxFeePerGas: 50 gwei,
                gasLimitBuffer: 20, // 20% buffer
                congestionMultiplier: 150, // 50% increase during congestion
                supportsEIP1559: true
            });
        } else if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) {
            config = ChainGasConfig({
                baseFeeMultiplier: 100,
                priorityFeePerGas: 0.01 gwei,
                maxFeePerGas: 2 gwei,
                gasLimitBuffer: 10,
                congestionMultiplier: 120,
                supportsEIP1559: false
            });
        } else {
            // Default configuration
            config = ChainGasConfig({
                baseFeeMultiplier: 100,
                priorityFeePerGas: 1 gwei,
                maxFeePerGas: 20 gwei,
                gasLimitBuffer: 15,
                congestionMultiplier: 130,
                supportsEIP1559: true
            });
        }
    }
    
    function getGasProfile(uint8 complexity) internal pure returns (GasProfile memory profile) {
        if (complexity == 0) {
            // Simple arbitrage
            profile = GasProfile({
                baseGas: BASE_GAS_LIMIT,
                tokenTransfer: 65000,
                swapGas: SWAP_GAS_ESTIMATE,
                bridgeGas: BRIDGE_GAS_ESTIMATE,
                complexityFactor: 100 // No multiplier
            });
        } else if (complexity == 1) {
            // Medium complexity
            profile = GasProfile({
                baseGas: BASE_GAS_LIMIT,
                tokenTransfer: 65000,
                swapGas: SWAP_GAS_ESTIMATE * 2, // Multiple swaps
                bridgeGas: BRIDGE_GAS_ESTIMATE,
                complexityFactor: 130 // 30% increase
            });
        } else {
            // Complex arbitrage
            profile = GasProfile({
                baseGas: BASE_GAS_LIMIT,
                tokenTransfer: 65000,
                swapGas: COMPLEX_ARBITRAGE_GAS,
                bridgeGas: BRIDGE_GAS_ESTIMATE,
                complexityFactor: 160 // 60% increase
            });
        }
    }
    
    function getNativeTokenPrice(uint256 chainId) internal pure returns (uint256 priceUSD) {
        // Simplified price feeds - in production, use actual oracles
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            priceUSD = 2000e18; // $2000 ETH
        } else if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) {
            priceUSD = 2000e18; // ETH on Arbitrum
        } else if (chainId == ChainConstants.BASE_CHAIN_ID) {
            priceUSD = 2000e18; // ETH on Base
        } else if (chainId == ChainConstants.POLYGON_CHAIN_ID) {
            priceUSD = 1e18; // $1 MATIC
        } else {
            priceUSD = 1500e18; // Default
        }
    }
    
    function _getAmountBasedGas(uint256 amount) internal pure returns (uint256 additionalGas) {
        // Larger amounts may require more gas due to complexity
        if (amount > 100 ether) {
            additionalGas = 50000;
        } else if (amount > 10 ether) {
            additionalGas = 25000;
        } else {
            additionalGas = 0;
        }
    }
    
    function _applyChainMultiplier(uint256 chainId, uint256 gasCost) internal pure returns (uint256) {
        // Chain-specific cost adjustments
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            return (gasCost * 120) / 100; // 20% increase for Ethereum
        } else if (chainId == ChainConstants.POLYGON_CHAIN_ID) {
            return (gasCost * 80) / 100; // 20% decrease for Polygon
        }
        return gasCost; // No adjustment for other chains
    }
    
    /**
     * @notice Extension function for uint256 to estimate gas price for chain
     * @param chainId Chain ID to estimate for
     * @return gasPrice Estimated gas price
     */
    function estimateGasPrice(uint256 chainId) internal pure returns (uint256 gasPrice) {
        return getCurrentGasPrice(chainId);
    }
}