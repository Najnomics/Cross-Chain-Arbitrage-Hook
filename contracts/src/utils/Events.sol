// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Events
 * @notice Event definitions for the Cross-Chain Arbitrage Hook
 */
library Events {
    // Arbitrage events
    event ArbitrageOpportunityDetected(
        bytes32 indexed opportunityId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 expectedProfitBPS,
        uint256 originChainId,
        uint256 targetChainId
    );
    
    event CrossChainArbitrageInitiated(
        bytes32 indexed intentId,
        address indexed user,
        bytes32 indexed opportunityId,
        uint256 amountIn,
        uint256 targetChainId
    );
    
    event ArbitrageExecuted(
        bytes32 indexed opportunityId,
        uint256 profit,
        uint256 amountOut,
        address indexed beneficiary
    );
    
    event ProfitDistributed(
        bytes32 indexed opportunityId,
        address indexed user,
        uint256 userShare,
        uint256 protocolFee
    );
    
    // Oracle events
    event PriceOracleUpdated(
        address indexed token,
        uint256 indexed chainId,
        uint256 price,
        uint256 timestamp
    );
    
    event ChainlinkOracleAdded(
        address indexed token,
        uint256 indexed chainId,
        address oracle
    );
    
    // Configuration events
    event ArbitrageConfigUpdated(uint256 minProfitBPS, uint256 maxSlippageBPS, uint256 userProfitShareBPS);
    event MinProfitThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event MaxSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event UserProfitShareUpdated(uint256 oldShare, uint256 newShare);
    
    // MEV protection events
    event MEVDetected(
        address indexed detector,
        bytes32 indexed transactionHash,
        string mevType
    );
    
    event PrivateMempoolUsed(
        bytes32 indexed transactionHash,
        address indexed relayer
    );
}