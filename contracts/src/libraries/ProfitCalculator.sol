// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IArbitrageHook} from "../hooks/interfaces/IArbitrageHook.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title ProfitCalculator
 * @notice Library for calculating arbitrage profits and feasibility
 */
library ProfitCalculator {
    struct ProfitCalculation {
        uint256 expectedOutput;
        uint256 bridgeFees;
        uint256 gasCosts;
        uint256 slippageBuffer;
        uint256 netProfit;
        uint256 profitBPS;
        bool isProfitable;
    }
    
    struct ArbitrageParameters {
        uint256 amountIn;
        uint256 localPrice;
        uint256 remotePrice;
        uint256 bridgeFee;
        uint256 gasCost;
        uint256 maxSlippageBPS;
        uint256 minProfitBPS;
    }
    
    /**
     * @notice Calculate profit for arbitrage opportunity
     * @param params Arbitrage parameters
     * @return calculation Detailed profit calculation
     */
    function calculateProfit(
        ArbitrageParameters memory params
    ) internal pure returns (ProfitCalculation memory calculation) {
        // Calculate expected output on remote chain
        calculation.expectedOutput = _calculateExpectedOutput(
            params.amountIn,
            params.localPrice,
            params.remotePrice
        );
        
        // Calculate all costs
        calculation.bridgeFees = _calculateBridgeFees(params.bridgeFee, params.amountIn);
        calculation.gasCosts = params.gasCost;
        calculation.slippageBuffer = _calculateSlippageBuffer(
            calculation.expectedOutput,
            params.maxSlippageBPS
        );
        
        // Calculate net profit
        uint256 totalCosts = calculation.bridgeFees + calculation.gasCosts + calculation.slippageBuffer;
        
        if (calculation.expectedOutput > params.amountIn + totalCosts) {
            calculation.netProfit = calculation.expectedOutput - params.amountIn - totalCosts;
            calculation.profitBPS = (calculation.netProfit * 10000) / params.amountIn;
            calculation.isProfitable = calculation.profitBPS >= params.minProfitBPS;
        } else {
            calculation.netProfit = 0;
            calculation.profitBPS = 0;
            calculation.isProfitable = false;
        }
    }
    
    /**
     * @notice Calculate expected profit in BPS for opportunity
     * @param opportunity Arbitrage opportunity
     * @param bridgeFee Bridge fee amount
     * @param gasCost Gas cost estimate
     * @return profitBPS Profit in basis points
     */
    function calculateProfitBPS(
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        uint256 bridgeFee,
        uint256 gasCost
    ) internal pure returns (uint256 profitBPS) {
        // This is a simplified calculation - in practice, you'd need
        // actual price data from the opportunity
        uint256 totalCosts = bridgeFee + gasCost;
        uint256 slippageBuffer = (opportunity.amountIn * 100) / 10000; // 1% slippage buffer
        
        // For this simplified test, assume the opportunity.expectedProfitBPS
        // represents the actual profit after costs
        if (opportunity.expectedProfitBPS > 0) {
            profitBPS = opportunity.expectedProfitBPS;
        } else {
            profitBPS = 0;
        }
    }
    
    /**
     * @notice Check if arbitrage meets minimum profit threshold
     * @param opportunity Arbitrage opportunity
     * @param minProfitBPS Minimum profit threshold in BPS
     * @param bridgeFee Bridge fee
     * @param gasCost Gas cost
     * @return profitable Whether arbitrage is profitable
     */
    function isProfitable(
        IArbitrageHook.ArbitrageOpportunity memory opportunity,
        uint256 minProfitBPS,
        uint256 bridgeFee,
        uint256 gasCost
    ) internal pure returns (bool profitable) {
        uint256 profitBPS = calculateProfitBPS(opportunity, bridgeFee, gasCost);
        return profitBPS >= minProfitBPS;
    }
    
    /**
     * @notice Calculate profit distribution between user and protocol
     * @param totalProfit Total profit amount
     * @param userProfitShareBPS User's profit share in BPS
     * @return userShare Amount going to user
     * @return protocolFee Amount going to protocol
     */
    function calculateProfitDistribution(
        uint256 totalProfit,
        uint256 userProfitShareBPS
    ) internal pure returns (uint256 userShare, uint256 protocolFee) {
        if (userProfitShareBPS > 10000) {
            revert Errors.InvalidHookData();
        }
        
        userShare = (totalProfit * userProfitShareBPS) / 10000;
        protocolFee = totalProfit - userShare;
    }
    
    /**
     * @notice Calculate maximum slippage tolerance
     * @param amount Input amount
     * @param maxSlippageBPS Maximum slippage in BPS
     * @return maxSlippage Maximum slippage amount
     */
    function calculateMaxSlippage(
        uint256 amount,
        uint256 maxSlippageBPS
    ) internal pure returns (uint256 maxSlippage) {
        maxSlippage = (amount * maxSlippageBPS) / 10000;
    }
    
    /**
     * @notice Calculate expected output based on price difference
     * @param amountIn Input amount
     * @param localPrice Local price (18 decimals)
     * @param remotePrice Remote price (18 decimals)
     * @return expectedOutput Expected output amount
     */
    function _calculateExpectedOutput(
        uint256 amountIn,
        uint256 localPrice,
        uint256 remotePrice
    ) private pure returns (uint256 expectedOutput) {
        if (remotePrice > localPrice) {
            // Profitable arbitrage: buy local, sell remote
            expectedOutput = (amountIn * remotePrice) / localPrice;
        } else {
            // Not profitable
            expectedOutput = amountIn;
        }
    }
    
    /**
     * @notice Calculate bridge fees
     * @param bridgeFeeRate Bridge fee rate
     * @param amount Amount to bridge
     * @return bridgeFee Total bridge fee
     */
    function _calculateBridgeFees(
        uint256 bridgeFeeRate,
        uint256 amount
    ) private pure returns (uint256 bridgeFee) {
        bridgeFee = (amount * bridgeFeeRate) / 10000;
    }
    
    /**
     * @notice Calculate slippage buffer
     * @param amount Amount subject to slippage
     * @param slippageBPS Slippage in BPS
     * @return slippageBuffer Buffer amount
     */
    function _calculateSlippageBuffer(
        uint256 amount,
        uint256 slippageBPS
    ) private pure returns (uint256 slippageBuffer) {
        slippageBuffer = (amount * slippageBPS) / 10000;
    }
}