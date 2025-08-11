// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IArbitrageHook} from "./interfaces/IArbitrageHook.sol";
import {IAcrossIntegration} from "./interfaces/IAcrossIntegration.sol";
import {PriceOracle} from "../libraries/PriceOracle.sol";
import {AcrossIntegration} from "../libraries/AcrossIntegration.sol";
import {ProfitCalculator} from "../libraries/ProfitCalculator.sol";
import {ChainConstants} from "../utils/ChainConstants.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CrossChainArbitrageHook
 * @notice Uniswap V4 Hook for cross-chain arbitrage using Across Protocol V4
 * @dev Extends UHI framework with cross-chain MEV capture capabilities
 */
contract CrossChainArbitrageHook is BaseHook, IArbitrageHook, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using PriceOracle for PriceOracle.PriceFeedRegistry;
    using AcrossIntegration for AcrossIntegration.AcrossConfig;
    using ProfitCalculator for ProfitCalculator.ArbitrageParameters;
    
    // State variables
    PriceOracle.PriceFeedRegistry private priceRegistry;
    AcrossIntegration.AcrossConfig private acrossConfig;
    
    // Configuration
    uint256 public minProfitBPS = 50; // 0.5% minimum profit
    uint256 public maxSlippageBPS = 100; // 1% maximum slippage
    uint256 public userProfitShareBPS = 7000; // 70% profit share to users
    uint256 public gasBufferBPS = 200; // 2% buffer for gas estimates
    
    // Supported chains
    uint256[] public supportedChains;
    mapping(uint256 => bool) public isChainSupported;
    
    // Pending arbitrages
    mapping(bytes32 => PendingArbitrage) public pendingArbitrages;
    
    // Events
    event ArbitrageConfigUpdated(
        uint256 minProfitBPS,
        uint256 maxSlippageBPS,
        uint256 userProfitShareBPS
    );
    
    constructor(
        IPoolManager _poolManager,
        address _acrossSpokePool
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        // Initialize Across integration
        acrossConfig.initialize(_acrossSpokePool);
        
        // Initialize supported chains
        _initializeSupportedChains();
    }
    
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * @notice Hook called before each swap to detect arbitrage opportunities
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Analyze cross-chain arbitrage opportunity
        ArbitrageOpportunity memory opportunity = _analyzeArbitrageOpportunity(key, params);
        
        // Check if profitable arbitrage exists
        if (_isProfitable(opportunity)) {
            // Execute cross-chain arbitrage
            bytes32 intentId = _executeCrossChainArbitrage(sender, opportunity);
            
            // Store pending arbitrage
            pendingArbitrages[intentId] = PendingArbitrage({
                user: sender,
                opportunity: opportunity,
                timestamp: block.timestamp,
                status: ArbitrageStatus.PENDING
            });
            
            emit Events.ArbitrageOpportunityDetected(
                keccak256(abi.encode(opportunity)),
                opportunity.tokenIn,
                opportunity.tokenOut,
                opportunity.amountIn,
                opportunity.expectedProfitBPS,
                opportunity.originChainId,
                opportunity.targetChainId
            );
            
            // Skip local swap if cross-chain arbitrage is more profitable
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Execute normal swap if no profitable arbitrage
        return (BaseHook._beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    /**
     * @notice Hook called after swap completion
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Post-swap analytics and cleanup can be added here
        return (BaseHook._afterSwap.selector, 0);
    }
    
    /**
     * @notice Analyze cross-chain arbitrage opportunity
     */
    function analyzeArbitrageOpportunity(
        PoolKey calldata key,
        SwapParams calldata params
    ) external view override returns (ArbitrageOpportunity memory opportunity) {
        return _analyzeArbitrageOpportunity(key, params);
    }
    
    /**
     * @notice Execute cross-chain arbitrage
     */
    function executeCrossChainArbitrage(
        address user,
        ArbitrageOpportunity memory opportunity
    ) external override nonReentrant returns (bytes32 intentId) {
        if (!_isProfitable(opportunity)) {
            revert Errors.InsufficientProfit();
        }
        
        return _executeCrossChainArbitrage(user, opportunity);
    }
    
    /**
     * @notice Get multi-chain prices for token pair
     */
    function getMultiChainPrices(
        address tokenA,
        address tokenB
    ) external view override returns (ChainPriceData[] memory prices) {
        return priceRegistry.getMultiChainPrices(tokenA, tokenB);
    }
    
    /**
     * @notice Check if arbitrage opportunity is profitable
     */
    function isProfitable(
        ArbitrageOpportunity memory opportunity
    ) external view override returns (bool profitable) {
        return _isProfitable(opportunity);
    }
    
    /**
     * @notice Get pending arbitrage details
     */
    function getPendingArbitrage(
        bytes32 intentId
    ) external view override returns (PendingArbitrage memory arbitrage) {
        return pendingArbitrages[intentId];
    }
    
    // Internal functions
    
    function _analyzeArbitrageOpportunity(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal view returns (ArbitrageOpportunity memory opportunity) {
        address tokenIn = Currency.unwrap(key.currency0);
        address tokenOut = Currency.unwrap(key.currency1);
        uint256 amountIn = uint256(int256(params.amountSpecified));
        
        if (params.amountSpecified < 0) {
            // Negative amount means exact output, need to estimate input
            amountIn = uint256(-int256(params.amountSpecified));
            (tokenIn, tokenOut) = (tokenOut, tokenIn); // Swap direction
        }
        
        // Get current local price (simplified - would use actual pool price)
        uint256 localPrice = 1e18; // Placeholder: 1:1 ratio
        
        // Find best cross-chain opportunity
        uint256 bestProfitBPS = 0;
        uint256 bestChainId = block.chainid;
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint256 chainId = supportedChains[i];
            if (chainId == block.chainid) continue;
            
            // Get remote price and calculate profit
            try this.getMultiChainPrices(tokenIn, tokenOut) returns (ChainPriceData[] memory prices) {
                for (uint256 j = 0; j < prices.length; j++) {
                    if (prices[j].chainId == chainId) {
                        uint256 profitBPS = _calculateProfitBPS(
                            amountIn,
                            localPrice,
                            prices[j].price,
                            prices[j].gasEstimate
                        );
                        
                        if (profitBPS > bestProfitBPS) {
                            bestProfitBPS = profitBPS;
                            bestChainId = chainId;
                        }
                        break;
                    }
                }
            } catch {
                // Skip chains with price feed issues
                continue;
            }
        }
        
        opportunity = ArbitrageOpportunity({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            expectedProfitBPS: bestProfitBPS,
            originChainId: block.chainid,
            targetChainId: bestChainId,
            routeHash: keccak256(abi.encode(tokenIn, tokenOut, bestChainId)),
            timestamp: block.timestamp
        });
    }
    
    function _executeCrossChainArbitrage(
        address user,
        ArbitrageOpportunity memory opportunity
    ) internal returns (bytes32 intentId) {
        // Create cross-chain intent via Across Protocol
        return acrossConfig.createArbitrageIntent(opportunity, user);
    }
    
    function _isProfitable(
        ArbitrageOpportunity memory opportunity
    ) internal view returns (bool) {
        return opportunity.expectedProfitBPS >= minProfitBPS &&
               opportunity.targetChainId != block.chainid;
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
    
    function _initializeSupportedChains() internal {
        supportedChains = [
            ChainConstants.ETHEREUM_CHAIN_ID,
            ChainConstants.ARBITRUM_CHAIN_ID,
            ChainConstants.BASE_CHAIN_ID,
            ChainConstants.POLYGON_CHAIN_ID,
            ChainConstants.OPTIMISM_CHAIN_ID
        ];
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            isChainSupported[supportedChains[i]] = true;
        }
    }
    
    // Admin functions
    
    function updateConfiguration(
        uint256 _minProfitBPS,
        uint256 _maxSlippageBPS,
        uint256 _userProfitShareBPS
    ) external onlyOwner {
        if (_userProfitShareBPS > 10000) revert Errors.InvalidHookData();
        
        minProfitBPS = _minProfitBPS;
        maxSlippageBPS = _maxSlippageBPS;
        userProfitShareBPS = _userProfitShareBPS;
        
        emit ArbitrageConfigUpdated(_minProfitBPS, _maxSlippageBPS, _userProfitShareBPS);
    }
    
    function addOracle(
        address token,
        uint256 chainId,
        address feedAddress,
        uint256 heartbeat,
        uint8 decimals
    ) external onlyOwner {
        priceRegistry.addOracle(token, chainId, feedAddress, heartbeat, decimals);
    }
    
    function addSpokePool(uint256 chainId, address spokePool) external onlyOwner {
        acrossConfig.addSpokePool(chainId, spokePool);
    }
}