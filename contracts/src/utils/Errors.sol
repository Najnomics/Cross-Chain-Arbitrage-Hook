// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Errors
 * @notice Custom error definitions for the Cross-Chain Arbitrage Hook
 */
library Errors {
    // Hook-related errors
    error InvalidHookData();
    error InsufficientProfit();
    error InvalidChainId();
    error InvalidTokenAddress();
    
    // Arbitrage-related errors
    error ArbitrageOpportunityNotFound();
    error InsufficientLiquidity();
    error ExcessiveSlippage();
    error ArbitrageExecutionFailed();
    
    // Oracle-related errors
    error InvalidPriceData();
    error StalePrice();
    error OracleNotFound();
    
    // Access control errors
    error Unauthorized();
    error OnlyPoolManager();
    error OnlyAcrossProtocol();
    
    // MEV protection errors
    error SandwichDetected();
    error FrontRunningDetected();
    error MaxGasExceeded();
    
    // Cross-chain errors
    error BridgeFailure();
    error InvalidDestinationChain();
    error IntentCreationFailed();
    error SettlementTimeout();
}