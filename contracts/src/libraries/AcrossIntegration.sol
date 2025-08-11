// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IArbitrageHook} from "../hooks/interfaces/IArbitrageHook.sol";
import {IAcrossIntegration} from "../hooks/interfaces/IAcrossIntegration.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

// Across V4 SpokePool interface (simplified)
interface IAcrossSpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable returns (bytes32);
    
    function fillV3Relay(
        bytes calldata relayData,
        uint256 repaymentChainId
    ) external;
    
    function executeV3SlowRelay(
        bytes calldata relayData
    ) external;
}

/**
 * @title AcrossIntegration
 * @notice Library for integrating with Across Protocol V4
 */
library AcrossIntegration {
    using SafeERC20 for IERC20;
    
    struct AcrossConfig {
        address spokePool;
        mapping(uint256 => address) chainIdToSpokePool;
        mapping(address => bool) authorizedRelayers;
        uint256 defaultFillDeadline;
        uint256 defaultExclusivityDeadline;
    }
    
    /**
     * @notice Initialize Across integration
     * @param config Across configuration storage
     * @param spokePool Main spoke pool address
     */
    function initialize(
        AcrossConfig storage config,
        address spokePool
    ) external {
        config.spokePool = spokePool;
        config.defaultFillDeadline = 4 hours;
        config.defaultExclusivityDeadline = 1 minutes;
    }
    
    /**
     * @notice Create cross-chain arbitrage intent
     * @param config Across configuration
     * @param opportunity Arbitrage opportunity
     * @param user Original user address
     * @return intentId Generated intent ID
     */
    function createArbitrageIntent(
        AcrossConfig storage config,
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        address user
    ) external returns (bytes32 intentId) {
        if (config.spokePool == address(0)) {
            revert Errors.InvalidChainId();
        }
        
        // Build calldata for destination chain execution
        bytes memory arbitrageCalldata = abi.encodeWithSelector(
            bytes4(keccak256("executeArbitrageOnDestination(tuple,address)")),
            opportunity,
            user
        );
        
        // Calculate quote parameters
        uint32 quoteTimestamp = uint32(block.timestamp);
        uint32 fillDeadline = uint32(block.timestamp + config.defaultFillDeadline);
        uint32 exclusivityDeadline = uint32(block.timestamp + config.defaultExclusivityDeadline);
        
        // Transfer tokens to spoke pool
        IERC20(opportunity.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            opportunity.amountIn
        );
        
        IERC20(opportunity.tokenIn).approve(config.spokePool, opportunity.amountIn);
        
        // Create the cross-chain intent
        intentId = IAcrossSpokePool(config.spokePool).depositV3(
            address(this), // depositor
            address(this), // recipient (this contract on dest chain)
            opportunity.tokenIn, // input token
            opportunity.tokenOut, // output token
            opportunity.amountIn, // input amount
            opportunity.amountIn, // output amount (will be adjusted by arbitrage)
            opportunity.targetChainId, // destination chain
            address(0), // no exclusive relayer
            quoteTimestamp,
            fillDeadline,
            exclusivityDeadline,
            arbitrageCalldata // execution message
        );
        
        emit Events.CrossChainArbitrageInitiated(
            intentId,
            user,
            keccak256(abi.encode(opportunity)),
            opportunity.amountIn,
            opportunity.targetChainId
        );
    }
    
    /**
     * @notice Execute arbitrage on destination chain
     * @param config Across configuration
     * @param opportunity Arbitrage opportunity
     * @param originalUser Original user address
     * @return amountOut Amount received from arbitrage
     */
    function executeArbitrageOnDestination(
        AcrossConfig storage config,
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        address originalUser
    ) external returns (uint256 amountOut) {
        // Verify this is called by Across spoke pool
        if (msg.sender != config.spokePool) {
            revert Errors.OnlyAcrossProtocol();
        }
        
        // Execute the arbitrage trade on destination chain
        // This is a placeholder - in practice, you'd interact with
        // the actual DEX (Uniswap V4, V3, etc.) on the destination chain
        amountOut = _executeSwapOnDestination(
            opportunity.tokenIn,
            opportunity.tokenOut,
            opportunity.amountIn
        );
        
        // Calculate profit
        uint256 profit = amountOut > opportunity.amountIn ? 
            amountOut - opportunity.amountIn : 0;
        
        if (profit > 0) {
            // Distribute profits according to protocol rules
            uint256 userShare = (profit * 7000) / 10000; // 70% to user
            uint256 protocolFee = profit - userShare;
            
            // Bridge profits back to original chain
            _bridgeProfitsBack(
                config,
                opportunity.originChainId,
                originalUser,
                userShare,
                protocolFee
            );
        }
        
        emit Events.ArbitrageExecuted(
            keccak256(abi.encode(opportunity)),
            profit,
            amountOut,
            originalUser
        );
    }
    
    /**
     * @notice Get bridge quote for cross-chain transfer
     * @param config Across configuration
     * @param tokenAddress Token to bridge
     * @param amount Amount to bridge
     * @param destinationChainId Target chain
     * @return quote Bridge quote details
     */
    function getBridgeQuote(
        AcrossConfig storage config,
        address tokenAddress,
        uint256 amount,
        uint256 destinationChainId
    ) external view returns (IAcrossIntegration.BridgeQuote memory quote) {
        // Placeholder implementation - in practice, you'd query
        // Across Protocol's quote API or on-chain quote contract
        quote = IAcrossIntegration.BridgeQuote({
            bridgeFee: (amount * 10) / 10000, // 0.1% fee
            estimatedTime: 60, // 60 seconds
            maxSlippage: (amount * 50) / 10000, // 0.5% max slippage
            gasLimit: 200000 // Gas limit for destination execution
        });
    }
    
    /**
     * @notice Bridge profits back to origin chain
     * @param config Across configuration
     * @param originChainId Origin chain ID
     * @param user User address
     * @param userShare User's profit share
     * @param protocolFee Protocol fee
     */
    function _bridgeProfitsBack(
        AcrossConfig storage config,
        uint256 originChainId,
        address user,
        uint256 userShare,
        uint256 protocolFee
    ) private {
        if (userShare > 0) {
            // Create intent to bridge user's profits back
            // This is simplified - in practice, you'd use the actual Across API
            emit Events.ProfitDistributed(
                bytes32(0), // opportunity ID
                user,
                userShare,
                protocolFee
            );
        }
    }
    
    /**
     * @notice Execute swap on destination chain
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return amountOut Output amount
     */
    function _executeSwapOnDestination(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        // Placeholder implementation - in practice, you'd interact with
        // Uniswap V4 PoolManager or other DEXs on the destination chain
        
        // For now, simulate a profitable trade
        amountOut = amountIn + ((amountIn * 150) / 10000); // 1.5% profit
    }
    
    /**
     * @notice Add spoke pool for a chain
     * @param config Across configuration
     * @param chainId Chain ID
     * @param spokePool Spoke pool address
     */
    function addSpokePool(
        AcrossConfig storage config,
        uint256 chainId,
        address spokePool
    ) external {
        config.chainIdToSpokePool[chainId] = spokePool;
    }
    
    /**
     * @notice Check if intent is settled
     * @param intentId Intent ID
     * @return settled Whether intent is settled
     */
    function isIntentSettled(bytes32 intentId) external view returns (bool settled) {
        // Placeholder - in practice, you'd query Across Protocol's state
        return true;
    }
}