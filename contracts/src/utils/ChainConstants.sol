// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ChainConstants
 * @notice Chain-specific constants and configurations
 */
library ChainConstants {
    // Chain IDs
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant ARBITRUM_CHAIN_ID = 42161;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant POLYGON_CHAIN_ID = 137;
    uint256 public constant OPTIMISM_CHAIN_ID = 10;
    
    // Testnet Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 public constant POLYGON_MUMBAI_CHAIN_ID = 80001;
    uint256 public constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;
    
    // Native tokens
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address public constant WETH_POLYGON = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant WETH_OPTIMISM = 0x4200000000000000000000000000000000000006;
    
    // USDC addresses
    address public constant USDC_MAINNET = 0xA0b86a33E6441A8CcA877a7F0b5c5A67b82F6D7A;
    address public constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant USDC_OPTIMISM = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    
    // Gas limits per chain
    uint256 public constant ETHEREUM_GAS_LIMIT = 500000;
    uint256 public constant ARBITRUM_GAS_LIMIT = 2000000;
    uint256 public constant BASE_GAS_LIMIT = 2000000;
    uint256 public constant POLYGON_GAS_LIMIT = 2000000;
    uint256 public constant OPTIMISM_GAS_LIMIT = 2000000;
    
    // Block confirmation requirements
    uint256 public constant ETHEREUM_CONFIRMATIONS = 12;
    uint256 public constant ARBITRUM_CONFIRMATIONS = 1;
    uint256 public constant BASE_CONFIRMATIONS = 1;
    uint256 public constant POLYGON_CONFIRMATIONS = 30;
    uint256 public constant OPTIMISM_CONFIRMATIONS = 1;
    
    /**
     * @notice Get WETH address for a given chain
     * @param chainId Chain ID
     * @return wethAddress WETH address for the chain
     */
    function getWETHAddress(uint256 chainId) internal pure returns (address wethAddress) {
        if (chainId == ETHEREUM_CHAIN_ID) return WETH_MAINNET;
        if (chainId == ARBITRUM_CHAIN_ID) return WETH_ARBITRUM;
        if (chainId == BASE_CHAIN_ID) return WETH_BASE;
        if (chainId == POLYGON_CHAIN_ID) return WETH_POLYGON;
        if (chainId == OPTIMISM_CHAIN_ID) return WETH_OPTIMISM;
        revert("Unsupported chain");
    }
    
    /**
     * @notice Get USDC address for a given chain
     * @param chainId Chain ID
     * @return usdcAddress USDC address for the chain
     */
    function getUSDCAddress(uint256 chainId) internal pure returns (address usdcAddress) {
        if (chainId == ETHEREUM_CHAIN_ID) return USDC_MAINNET;
        if (chainId == ARBITRUM_CHAIN_ID) return USDC_ARBITRUM;
        if (chainId == BASE_CHAIN_ID) return USDC_BASE;
        if (chainId == POLYGON_CHAIN_ID) return USDC_POLYGON;
        if (chainId == OPTIMISM_CHAIN_ID) return USDC_OPTIMISM;
        revert("Unsupported chain");
    }
    
    /**
     * @notice Get gas limit for a given chain
     * @param chainId Chain ID
     * @return gasLimit Gas limit for the chain
     */
    function getGasLimit(uint256 chainId) internal pure returns (uint256 gasLimit) {
        if (chainId == ETHEREUM_CHAIN_ID) return ETHEREUM_GAS_LIMIT;
        if (chainId == ARBITRUM_CHAIN_ID) return ARBITRUM_GAS_LIMIT;
        if (chainId == BASE_CHAIN_ID) return BASE_GAS_LIMIT;
        if (chainId == POLYGON_CHAIN_ID) return POLYGON_GAS_LIMIT;
        if (chainId == OPTIMISM_CHAIN_ID) return OPTIMISM_GAS_LIMIT;
        revert("Unsupported chain");
    }
    
    /**
     * @notice Check if chain is supported
     * @param chainId Chain ID to check
     * @return supported Whether chain is supported
     */
    function isChainSupported(uint256 chainId) internal pure returns (bool supported) {
        return chainId == ETHEREUM_CHAIN_ID ||
               chainId == ARBITRUM_CHAIN_ID ||
               chainId == BASE_CHAIN_ID ||
               chainId == POLYGON_CHAIN_ID ||
               chainId == OPTIMISM_CHAIN_ID;
    }
}