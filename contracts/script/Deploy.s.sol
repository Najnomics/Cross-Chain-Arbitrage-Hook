// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CrossChainArbitrageHook} from "../src/hooks/CrossChainArbitrageHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ChainConstants} from "../src/utils/ChainConstants.sol";

contract DeployScript is Script {
    // Addresses will vary by chain - these are placeholders
    address constant POOL_MANAGER_ETHEREUM = 0x0000000000000000000000000000000000000001;
    address constant POOL_MANAGER_ARBITRUM = 0x0000000000000000000000000000000000000002;
    address constant POOL_MANAGER_BASE = 0x0000000000000000000000000000000000000003;
    address constant POOL_MANAGER_POLYGON = 0x0000000000000000000000000000000000000004;
    address constant POOL_MANAGER_OPTIMISM = 0x0000000000000000000000000000000000000005;
    
    // Across Protocol SpokePool addresses (these will need to be updated with actual addresses)
    address constant ACROSS_SPOKE_POOL_ETHEREUM = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address constant ACROSS_SPOKE_POOL_ARBITRUM = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
    address constant ACROSS_SPOKE_POOL_BASE = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
    address constant ACROSS_SPOKE_POOL_POLYGON = 0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096;
    address constant ACROSS_SPOKE_POOL_OPTIMISM = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
    
    CrossChainArbitrageHook hook;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        address poolManager = getPoolManagerForChain(block.chainid);
        address acrossSpokePool = getAcrossSpokePoolForChain(block.chainid);
        
        console2.log("Deploying CrossChainArbitrageHook on chain:", block.chainid);
        console2.log("Pool Manager:", poolManager);
        console2.log("Across SpokePool:", acrossSpokePool);
        
        // Deploy the hook
        hook = new CrossChainArbitrageHook(
            IPoolManager(poolManager),
            acrossSpokePool
        );
        
        console2.log("CrossChainArbitrageHook deployed at:", address(hook));
        
        // Configure the hook with initial settings
        configureHook();
        
        // Add price oracles
        addPriceOracles();
        
        // Add spoke pools for other chains
        addSpokePoolsForOtherChains();
        
        vm.stopBroadcast();
        
        console2.log("Deployment completed!");
        console2.log("Hook address:", address(hook));
        console2.log("Verify with:");
        console2.log("forge verify-contract --chain-id", block.chainid, address(hook));
    }
    
    function configureHook() internal {
        uint256 minProfitBPS = vm.envOr("MIN_PROFIT_BPS", uint256(50)); // 0.5%
        uint256 maxSlippageBPS = vm.envOr("MAX_SLIPPAGE_BPS", uint256(100)); // 1%
        uint256 userProfitShareBPS = vm.envOr("USER_PROFIT_SHARE_BPS", uint256(7000)); // 70%
        
        hook.updateConfiguration(minProfitBPS, maxSlippageBPS, userProfitShareBPS);
        
        console2.log("Hook configured:");
        console2.log("- Min Profit BPS:", minProfitBPS);
        console2.log("- Max Slippage BPS:", maxSlippageBPS);
        console2.log("- User Profit Share BPS:", userProfitShareBPS);
    }
    
    function addPriceOracles() internal {
        // Add WETH/USD price feeds (Chainlink)
        if (block.chainid == ChainConstants.ETHEREUM_CHAIN_ID) {
            // ETH/USD feed on Ethereum
            hook.addOracle(
                ChainConstants.WETH_MAINNET,
                ChainConstants.ETHEREUM_CHAIN_ID,
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH/USD Chainlink feed
                3600, // 1 hour heartbeat
                8 // 8 decimals
            );
        } else if (block.chainid == ChainConstants.ARBITRUM_CHAIN_ID) {
            // ETH/USD feed on Arbitrum
            hook.addOracle(
                ChainConstants.WETH_ARBITRUM,
                ChainConstants.ARBITRUM_CHAIN_ID,
                0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612, // ETH/USD Chainlink feed on Arbitrum
                3600,
                8
            );
        }
        // Add more oracles for other chains and tokens as needed
        
        console2.log("Price oracles added");
    }
    
    function addSpokePoolsForOtherChains() internal {
        // Add spoke pools for cross-chain operations
        if (block.chainid != ChainConstants.ETHEREUM_CHAIN_ID) {
            hook.addSpokePool(ChainConstants.ETHEREUM_CHAIN_ID, ACROSS_SPOKE_POOL_ETHEREUM);
        }
        if (block.chainid != ChainConstants.ARBITRUM_CHAIN_ID) {
            hook.addSpokePool(ChainConstants.ARBITRUM_CHAIN_ID, ACROSS_SPOKE_POOL_ARBITRUM);
        }
        if (block.chainid != ChainConstants.BASE_CHAIN_ID) {
            hook.addSpokePool(ChainConstants.BASE_CHAIN_ID, ACROSS_SPOKE_POOL_BASE);
        }
        if (block.chainid != ChainConstants.POLYGON_CHAIN_ID) {
            hook.addSpokePool(ChainConstants.POLYGON_CHAIN_ID, ACROSS_SPOKE_POOL_POLYGON);
        }
        if (block.chainid != ChainConstants.OPTIMISM_CHAIN_ID) {
            hook.addSpokePool(ChainConstants.OPTIMISM_CHAIN_ID, ACROSS_SPOKE_POOL_OPTIMISM);
        }
        
        console2.log("Cross-chain spoke pools configured");
    }
    
    function getPoolManagerForChain(uint256 chainId) internal pure returns (address) {
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) return POOL_MANAGER_ETHEREUM;
        if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) return POOL_MANAGER_ARBITRUM;
        if (chainId == ChainConstants.BASE_CHAIN_ID) return POOL_MANAGER_BASE;
        if (chainId == ChainConstants.POLYGON_CHAIN_ID) return POOL_MANAGER_POLYGON;
        if (chainId == ChainConstants.OPTIMISM_CHAIN_ID) return POOL_MANAGER_OPTIMISM;
        revert("Unsupported chain for deployment");
    }
    
    function getAcrossSpokePoolForChain(uint256 chainId) internal pure returns (address) {
        if (chainId == ChainConstants.ETHEREUM_CHAIN_ID) return ACROSS_SPOKE_POOL_ETHEREUM;
        if (chainId == ChainConstants.ARBITRUM_CHAIN_ID) return ACROSS_SPOKE_POOL_ARBITRUM;
        if (chainId == ChainConstants.BASE_CHAIN_ID) return ACROSS_SPOKE_POOL_BASE;
        if (chainId == ChainConstants.POLYGON_CHAIN_ID) return ACROSS_SPOKE_POOL_POLYGON;
        if (chainId == ChainConstants.OPTIMISM_CHAIN_ID) return ACROSS_SPOKE_POOL_OPTIMISM;
        revert("Unsupported chain for Across integration");
    }
}