// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IArbitrageHook} from "../hooks/interfaces/IArbitrageHook.sol";
import {ChainConstants} from "../utils/ChainConstants.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title PriceOracle
 * @notice Multi-chain price oracle integration using Chainlink price feeds
 */
library PriceOracle {
    struct OracleConfig {
        address feedAddress;
        uint256 heartbeat;
        uint8 decimals;
        bool isActive;
    }
    
    struct PriceFeedRegistry {
        mapping(address => mapping(uint256 => OracleConfig)) tokenToChainToOracle;
        mapping(address => uint256[]) tokenToSupportedChains;
    }
    
    /**
     * @notice Get current price for a token on a specific chain
     * @param registry Price feed registry
     * @param token Token address
     * @param chainId Chain ID
     * @return price Current price in 18 decimals
     * @return timestamp Price timestamp
     */
    function getPrice(
        PriceFeedRegistry storage registry,
        address token,
        uint256 chainId
    ) internal view returns (uint256 price, uint256 timestamp) {
        OracleConfig memory config = registry.tokenToChainToOracle[token][chainId];
        
        if (!config.isActive) {
            revert Errors.OracleNotFound();
        }
        
        AggregatorV3Interface priceFeed = AggregatorV3Interface(config.feedAddress);
        
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        // Validate price data
        if (answer <= 0) {
            revert Errors.InvalidPriceData();
        }
        
        // Check if price is stale
        if (block.timestamp - updatedAt > config.heartbeat) {
            revert Errors.StalePrice();
        }
        
        // Convert price to 18 decimals
        price = _normalizePrice(uint256(answer), config.decimals);
        timestamp = updatedAt;
    }
    
    /**
     * @notice Get multi-chain prices for token pair
     * @param registry Price feed registry
     * @param tokenA First token
     * @param tokenB Second token
     * @return prices Array of price data across chains
     */
    function getMultiChainPrices(
        PriceFeedRegistry storage registry,
        address tokenA,
        address tokenB
    ) external view returns (IArbitrageHook.ChainPriceData[] memory prices) {
        uint256[] memory supportedChains = _getCommonSupportedChains(registry, tokenA, tokenB);
        prices = new IArbitrageHook.ChainPriceData[](supportedChains.length);
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint256 chainId = supportedChains[i];
            
            (uint256 priceA, uint256 timestampA) = getPrice(registry, tokenA, chainId);
            (uint256 priceB, uint256 timestampB) = getPrice(registry, tokenB, chainId);
            
            // Calculate exchange rate (tokenA/tokenB)
            uint256 exchangeRate = (priceA * 1e18) / priceB;
            
            prices[i] = IArbitrageHook.ChainPriceData({
                chainId: chainId,
                price: exchangeRate,
                liquidity: _getLiquidityEstimate(tokenA, tokenB, chainId),
                gasEstimate: _getGasEstimate(chainId),
                timestamp: timestampA < timestampB ? timestampA : timestampB
            });
        }
    }
    
    /**
     * @notice Add oracle for token on specific chain
     * @param registry Price feed registry
     * @param token Token address
     * @param chainId Chain ID
     * @param feedAddress Chainlink feed address
     * @param heartbeat Maximum age for price data
     * @param decimals Feed decimals
     */
    function addOracle(
        PriceFeedRegistry storage registry,
        address token,
        uint256 chainId,
        address feedAddress,
        uint256 heartbeat,
        uint8 decimals
    ) external {
        registry.tokenToChainToOracle[token][chainId] = OracleConfig({
            feedAddress: feedAddress,
            heartbeat: heartbeat,
            decimals: decimals,
            isActive: true
        });
        
        // Add to supported chains if not already present
        uint256[] storage supportedChains = registry.tokenToSupportedChains[token];
        bool chainExists = false;
        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i] == chainId) {
                chainExists = true;
                break;
            }
        }
        
        if (!chainExists) {
            supportedChains.push(chainId);
        }
    }
    
    /**
     * @notice Normalize price to 18 decimals
     * @param price Raw price from feed
     * @param decimals Feed decimals
     * @return normalizedPrice Price in 18 decimals
     */
    function _normalizePrice(
        uint256 price,
        uint8 decimals
    ) internal pure returns (uint256 normalizedPrice) {
        if (decimals < 18) {
            normalizedPrice = price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            normalizedPrice = price / (10 ** (decimals - 18));
        } else {
            normalizedPrice = price;
        }
    }
    
    /**
     * @notice Get chains supported by both tokens
     * @param registry Price feed registry
     * @param tokenA First token
     * @param tokenB Second token
     * @return commonChains Array of commonly supported chain IDs
     */
    function _getCommonSupportedChains(
        PriceFeedRegistry storage registry,
        address tokenA,
        address tokenB
    ) internal view returns (uint256[] memory commonChains) {
        uint256[] memory chainsA = registry.tokenToSupportedChains[tokenA];
        uint256[] memory chainsB = registry.tokenToSupportedChains[tokenB];
        
        // Find intersection
        uint256[] memory tempCommon = new uint256[](chainsA.length);
        uint256 commonCount = 0;
        
        for (uint256 i = 0; i < chainsA.length; i++) {
            for (uint256 j = 0; j < chainsB.length; j++) {
                if (chainsA[i] == chainsB[j]) {
                    tempCommon[commonCount] = chainsA[i];
                    commonCount++;
                    break;
                }
            }
        }
        
        // Create properly sized array
        commonChains = new uint256[](commonCount);
        for (uint256 i = 0; i < commonCount; i++) {
            commonChains[i] = tempCommon[i];
        }
    }
    
    /**
     * @notice Estimate liquidity for token pair on chain
     * @param tokenA First token
     * @param tokenB Second token
     * @param chainId Chain ID
     * @return liquidity Estimated liquidity (placeholder implementation)
     */
    function _getLiquidityEstimate(
        address tokenA,
        address tokenB,
        uint256 chainId
    ) internal pure returns (uint256 liquidity) {
        // Placeholder implementation - in production, this would query
        // actual liquidity from DEX pools, lending protocols, etc.
        if (ChainConstants.isChainSupported(chainId)) {
            liquidity = 1000000e18; // $1M liquidity estimate
        } else {
            liquidity = 0;
        }
    }
    
    /**
     * @notice Get gas estimate for chain
     * @param chainId Chain ID
     * @return gasEstimate Estimated gas cost in wei
     */
    function _getGasEstimate(uint256 chainId) internal pure returns (uint256 gasEstimate) {
        uint256 gasLimit = ChainConstants.getGasLimit(chainId);
        
        // Placeholder gas price estimates (in production, fetch from oracles)
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) {
            gasEstimate = gasLimit * 20 gwei; // 20 gwei
        } else if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) {
            gasEstimate = gasLimit * 0.1 gwei; // 0.1 gwei
        } else if (chainId == ChainConstants.BASE_CHAIN_ID) {
            gasEstimate = gasLimit * 0.1 gwei; // 0.1 gwei
        } else if (chainId == ChainConstants.POLYGON_CHAIN_ID) {
            gasEstimate = gasLimit * 30 gwei; // 30 gwei
        } else if (chainId == ChainConstants.OPTIMISM_CHAIN_ID) {
            gasEstimate = gasLimit * 0.001 gwei; // 0.001 gwei
        } else {
            gasEstimate = gasLimit * 10 gwei; // Default
        }
    }
}