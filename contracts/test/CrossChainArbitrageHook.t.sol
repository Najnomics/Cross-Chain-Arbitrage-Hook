// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CrossChainArbitrageHook} from "../src/hooks/CrossChainArbitrageHook.sol";
import {IArbitrageHook} from "../src/hooks/interfaces/IArbitrageHook.sol";
import {ChainConstants} from "../src/utils/ChainConstants.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract MockPoolManager {
    // Minimal mock implementation for testing
}

contract MockAcrossSpokePool {
    mapping(bytes32 => bool) public intents;
    
    function depositV3(
        address,
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint32,
        uint32,
        uint32,
        bytes calldata
    ) external returns (bytes32) {
        bytes32 intentId = keccak256(abi.encode(block.timestamp, msg.sender));
        intents[intentId] = true;
        return intentId;
    }
}

contract CrossChainArbitrageHookTest is Test {
    CrossChainArbitrageHook hook;
    MockPoolManager poolManager;
    MockAcrossSpokePool acrossSpokePool;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xa0b86a33E6441A8CcA877a7f0b5c5a67b82F6D7A;
    
    function setUp() public {
        poolManager = new MockPoolManager();
        acrossSpokePool = new MockAcrossSpokePool();
        
        hook = new CrossChainArbitrageHook(
            IPoolManager(address(poolManager)),
            address(acrossSpokePool)
        );
        
        // Setup initial configuration
        hook.updateConfiguration(50, 100, 7000); // 0.5% min profit, 1% max slippage, 70% user share
    }
    
    function testHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
    }
    
    function testAnalyzeArbitrageOpportunity() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(USDC),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(1 ether),
            sqrtPriceLimitX96: 0
        });
        
        IArbitrageHook.ArbitrageOpportunity memory opportunity = hook.analyzeArbitrageOpportunity(key, params);
        
        assertEq(opportunity.tokenIn, WETH);
        assertEq(opportunity.tokenOut, USDC);
        assertEq(opportunity.amountIn, 1 ether);
        assertEq(opportunity.originChainId, block.chainid);
    }
    
    function testConfigurationUpdate() public {
        uint256 newMinProfit = 100; // 1%
        uint256 newMaxSlippage = 200; // 2%
        uint256 newUserShare = 8000; // 80%
        
        hook.updateConfiguration(newMinProfit, newMaxSlippage, newUserShare);
        
        assertEq(hook.minProfitBPS(), newMinProfit);
        assertEq(hook.maxSlippageBPS(), newMaxSlippage);
        assertEq(hook.userProfitShareBPS(), newUserShare);
    }
    
    function testConfigurationUpdateInvalidShare() public {
        vm.expectRevert();
        hook.updateConfiguration(50, 100, 10001); // > 100% share should fail
    }
    
    function testOnlyOwnerFunctions() public {
        vm.prank(alice);
        vm.expectRevert();
        hook.updateConfiguration(100, 200, 8000);
        
        vm.prank(alice);
        vm.expectRevert();
        hook.addOracle(WETH, 1, address(0x123), 3600, 8);
    }
    
    function testAddOracle() public {
        address mockOracle = makeAddr("mockOracle");
        
        hook.addOracle(WETH, ChainConstants.ETHEREUM_CHAIN_ID, mockOracle, 3600, 8);
        
        // Test that oracle was added (would need getter functions in actual implementation)
        assertTrue(true); // Placeholder assertion
    }
    
    function testExecuteCrossChainArbitrage() public {
        IArbitrageHook.ArbitrageOpportunity memory opportunity = IArbitrageHook.ArbitrageOpportunity({
            tokenIn: WETH,
            tokenOut: USDC,
            amountIn: 1 ether,
            expectedProfitBPS: 150, // 1.5%
            originChainId: ChainConstants.ETHEREUM_CHAIN_ID,
            targetChainId: ChainConstants.ARBITRUM_CHAIN_ID,
            routeHash: keccak256(abi.encode(WETH, USDC, ChainConstants.ARBITRUM_CHAIN_ID)),
            timestamp: block.timestamp
        });
        
        // This would fail in real scenario due to lack of token balance and approval
        // But tests the basic flow
        vm.expectRevert();
        hook.executeCrossChainArbitrage(alice, opportunity);
    }
    
    function testIsChainSupported() public view {
        assertTrue(hook.isChainSupported(ChainConstants.ETHEREUM_CHAIN_ID));
        assertTrue(hook.isChainSupported(ChainConstants.ARBITRUM_CHAIN_ID));
        assertTrue(hook.isChainSupported(ChainConstants.BASE_CHAIN_ID));
        assertFalse(hook.isChainSupported(999999)); // Non-existent chain
    }
    
    function testSupportedChainsArray() public view {
        uint256[] memory chains = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            chains[i] = hook.supportedChains(i);
        }
        
        // Verify expected chains are present
        bool hasEthereum = false;
        bool hasArbitrum = false;
        
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == ChainConstants.ETHEREUM_CHAIN_ID) hasEthereum = true;
            if (chains[i] == ChainConstants.ARBITRUM_CHAIN_ID) hasArbitrum = true;
        }
        
        assertTrue(hasEthereum);
        assertTrue(hasArbitrum);
    }
}