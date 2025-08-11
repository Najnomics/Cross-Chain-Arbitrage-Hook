// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {CrossChainArbitrageHook} from "../src/hooks/CrossChainArbitrageHook.sol";
import {IArbitrageHook} from "../src/hooks/interfaces/IArbitrageHook.sol";
import {ChainConstants} from "../src/utils/ChainConstants.sol";
import {PriceOracle} from "../src/libraries/PriceOracle.sol";
import {AcrossIntegration} from "../src/libraries/AcrossIntegration.sol";
import {ProfitCalculator} from "../src/libraries/ProfitCalculator.sol";
import {Events} from "../src/utils/Events.sol";
import {Errors} from "../src/utils/Errors.sol";

/**
 * @title CrossChainArbitrageHookUnitTest
 * @notice Unit tests for individual components without hook address validation
 */
contract CrossChainArbitrageHookUnitTest is Test {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xa0b86a33e6441A8CcA877a7f0b5c5a67b82F6D7A;
    
    function testChainConstants() public pure {
        assertTrue(ChainConstants.isChainSupported(ChainConstants.ETHEREUM_CHAIN_ID));
        assertTrue(ChainConstants.isChainSupported(ChainConstants.ARBITRUM_CHAIN_ID));
        assertTrue(ChainConstants.isChainSupported(ChainConstants.BASE_CHAIN_ID));
        assertTrue(ChainConstants.isChainSupported(ChainConstants.POLYGON_CHAIN_ID));
        assertTrue(ChainConstants.isChainSupported(ChainConstants.OPTIMISM_CHAIN_ID));
        
        assertFalse(ChainConstants.isChainSupported(999999));
    }
    
    function testChainConstantsAddresses() public pure {
        assertEq(ChainConstants.getWETHAddress(ChainConstants.ETHEREUM_CHAIN_ID), ChainConstants.WETH_MAINNET);
        assertEq(ChainConstants.getWETHAddress(ChainConstants.ARBITRUM_CHAIN_ID), ChainConstants.WETH_ARBITRUM);
        assertEq(ChainConstants.getWETHAddress(ChainConstants.BASE_CHAIN_ID), ChainConstants.WETH_BASE);
        
        assertEq(ChainConstants.getUSDCAddress(ChainConstants.ETHEREUM_CHAIN_ID), ChainConstants.USDC_MAINNET);
        assertEq(ChainConstants.getUSDCAddress(ChainConstants.ARBITRUM_CHAIN_ID), ChainConstants.USDC_ARBITRUM);
        assertEq(ChainConstants.getUSDCAddress(ChainConstants.BASE_CHAIN_ID), ChainConstants.USDC_BASE);
    }
    
    function testChainConstantsGasLimits() public pure {
        assertEq(ChainConstants.getGasLimit(ChainConstants.ETHEREUM_CHAIN_ID), ChainConstants.ETHEREUM_GAS_LIMIT);
        assertEq(ChainConstants.getGasLimit(ChainConstants.ARBITRUM_CHAIN_ID), ChainConstants.ARBITRUM_GAS_LIMIT);
        assertEq(ChainConstants.getGasLimit(ChainConstants.BASE_CHAIN_ID), ChainConstants.BASE_GAS_LIMIT);
    }
    
    function testProfitCalculatorSimple() public pure {
        ProfitCalculator.ArbitrageParameters memory params = ProfitCalculator.ArbitrageParameters({
            amountIn: 1 ether,
            localPrice: 1800e18, // $1800 ETH
            remotePrice: 1850e18, // $1850 ETH (2.8% higher)
            bridgeFee: 10, // 0.1% in BPS
            gasCost: 0.01 ether, // 0.01 ETH gas
            maxSlippageBPS: 100, // 1%
            minProfitBPS: 50 // 0.5%
        });
        
        ProfitCalculator.ProfitCalculation memory calc = ProfitCalculator.calculateProfit(params);
        
        assertTrue(calc.expectedOutput > params.amountIn);
        assertTrue(calc.isProfitable);
        assertTrue(calc.profitBPS >= params.minProfitBPS);
    }
    
    function testProfitCalculatorUnprofitable() public pure {
        ProfitCalculator.ArbitrageParameters memory params = ProfitCalculator.ArbitrageParameters({
            amountIn: 1 ether,
            localPrice: 1800e18, // $1800 ETH
            remotePrice: 1805e18, // $1805 ETH (only 0.28% higher)
            bridgeFee: 10, // 0.1% in BPS
            gasCost: 0.01 ether, // 0.01 ETH gas
            maxSlippageBPS: 100, // 1%
            minProfitBPS: 50 // 0.5%
        });
        
        ProfitCalculator.ProfitCalculation memory calc = ProfitCalculator.calculateProfit(params);
        
        assertFalse(calc.isProfitable);
        assertTrue(calc.profitBPS < params.minProfitBPS);
    }
    
    function testProfitDistribution() public pure {
        uint256 totalProfit = 1 ether;
        uint256 userShareBPS = 7000; // 70%
        
        (uint256 userShare, uint256 protocolFee) = ProfitCalculator.calculateProfitDistribution(
            totalProfit,
            userShareBPS
        );
        
        assertEq(userShare, 0.7 ether);
        assertEq(protocolFee, 0.3 ether);
        assertEq(userShare + protocolFee, totalProfit);
    }
    
    function testMaxSlippageCalculation() public pure {
        uint256 amount = 1 ether;
        uint256 maxSlippageBPS = 100; // 1%
        
        uint256 maxSlippage = ProfitCalculator.calculateMaxSlippage(amount, maxSlippageBPS);
        
        assertEq(maxSlippage, 0.01 ether); // 1% of 1 ETH
    }
    
    function testErrorsAndEvents() public {
        // Test that events can be emitted (this is more of a compilation test)
        vm.expectEmit(true, true, true, true);
        emit Events.ArbitrageOpportunityDetected(
            bytes32(0),
            WETH,
            USDC,
            1 ether,
            150, // 1.5% profit
            1, // Ethereum
            42161 // Arbitrum
        );
        
        emit Events.ArbitrageOpportunityDetected(
            bytes32(0),
            WETH,
            USDC,
            1 ether,
            150,
            1,
            42161
        );
    }
    
    function testInvalidProfitShare() public {
        uint256 totalProfit = 1 ether;
        uint256 invalidShareBPS = 10001; // > 100%
        
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidHookData.selector));
        ProfitCalculator.calculateProfitDistribution(totalProfit, invalidShareBPS);
    }
}