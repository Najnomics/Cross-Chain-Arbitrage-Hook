// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/**
 * @title IArbitrageHook
 * @notice Interface for the Cross-Chain Arbitrage Hook
 */
interface IArbitrageHook {
    struct ArbitrageOpportunity {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedProfitBPS;
        uint256 originChainId;
        uint256 targetChainId;
        bytes32 routeHash;
        uint256 timestamp;
    }
    
    struct ChainPriceData {
        uint256 chainId;
        uint256 price;
        uint256 liquidity;
        uint256 gasEstimate;
        uint256 timestamp;
    }
    
    enum ArbitrageStatus {
        PENDING,
        EXECUTED,
        FAILED,
        CANCELLED
    }
    
    struct PendingArbitrage {
        address user;
        ArbitrageOpportunity opportunity;
        uint256 timestamp;
        ArbitrageStatus status;
    }
    
    /**
     * @notice Analyze potential arbitrage opportunity for a swap
     * @param key Pool key for the swap
     * @param params Swap parameters
     * @return opportunity Arbitrage opportunity details
     */
    function analyzeArbitrageOpportunity(
        PoolKey calldata key,
        SwapParams calldata params
    ) external view returns (ArbitrageOpportunity memory opportunity);
    
    /**
     * @notice Execute cross-chain arbitrage
     * @param user User initiating the arbitrage
     * @param opportunity Arbitrage opportunity to execute
     * @return intentId Across Protocol intent ID
     */
    function executeCrossChainArbitrage(
        address user,
        ArbitrageOpportunity memory opportunity
    ) external returns (bytes32 intentId);
    
    /**
     * @notice Get multi-chain price data for token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return prices Array of price data across chains
     */
    function getMultiChainPrices(
        address tokenA,
        address tokenB
    ) external view returns (ChainPriceData[] memory prices);
    
    /**
     * @notice Check if arbitrage opportunity is profitable
     * @param opportunity Arbitrage opportunity to check
     * @return profitable Whether the opportunity is profitable
     */
    function isProfitable(
        ArbitrageOpportunity memory opportunity
    ) external view returns (bool profitable);
    
    /**
     * @notice Get pending arbitrage by intent ID
     * @param intentId Across Protocol intent ID
     * @return arbitrage Pending arbitrage details
     */
    function getPendingArbitrage(
        bytes32 intentId
    ) external view returns (PendingArbitrage memory arbitrage);
}