// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IArbitrageHook} from "./IArbitrageHook.sol";

/**
 * @title IAcrossIntegration
 * @notice Interface for Across Protocol V4 integration
 */
interface IAcrossIntegration {
    struct CrossChainIntent {
        address tokenIn;
        uint256 amountIn;
        uint256 destinationChainId;
        address recipient;
        bytes calldata_;
        uint256 timestamp;
    }
    
    struct BridgeQuote {
        uint256 bridgeFee;
        uint256 estimatedTime;
        uint256 maxSlippage;
        uint256 gasLimit;
    }
    
    /**
     * @notice Create cross-chain intent for arbitrage
     * @param opportunity Arbitrage opportunity details
     * @param user User address
     * @return intentId Created intent ID
     */
    function createArbitrageIntent(
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        address user
    ) external returns (bytes32 intentId);
    
    /**
     * @notice Get quote for cross-chain bridge
     * @param tokenAddress Token to bridge
     * @param amount Amount to bridge
     * @param destinationChainId Target chain ID
     * @return quote Bridge quote details
     */
    function getBridgeQuote(
        address tokenAddress,
        uint256 amount,
        uint256 destinationChainId
    ) external view returns (BridgeQuote memory quote);
    
    /**
     * @notice Execute arbitrage on destination chain
     * @param opportunity Arbitrage opportunity
     * @param originalUser Original user address
     * @return amountOut Amount received from arbitrage
     */
    function executeArbitrageOnDestination(
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        address originalUser
    ) external returns (uint256 amountOut);
    
    /**
     * @notice Bridge profits back to origin chain
     * @param originChainId Origin chain ID
     * @param user User address
     * @param userShare User's profit share
     * @param protocolFee Protocol fee amount
     */
    function bridgeProfitsBack(
        uint256 originChainId,
        address user,
        uint256 userShare,
        uint256 protocolFee
    ) external;
    
    /**
     * @notice Check if intent is settled
     * @param intentId Intent ID to check
     * @return settled Whether intent is settled
     */
    function isIntentSettled(bytes32 intentId) external view returns (bool settled);
    
    /**
     * @notice Get supported chains
     * @return chainIds Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint256[] memory chainIds);
}