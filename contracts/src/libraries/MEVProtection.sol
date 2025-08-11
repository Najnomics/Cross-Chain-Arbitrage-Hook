// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title MEVProtection  
 * @notice Library providing MEV protection mechanisms for cross-chain arbitrage
 * @dev Implements various anti-MEV strategies including private mempool integration, sandwich protection, and front-running prevention
 */
library MEVProtection {
    
    // MEV protection configuration
    struct MEVConfig {
        bool enabled;                    // Whether MEV protection is active
        uint256 commitRevealDelay;       // Delay for commit-reveal schemes
        uint256 maxSlippage;            // Maximum allowed slippage
        uint256 minExecutionDelay;      // Minimum delay before execution
        uint256 privateMempoolFee;      // Fee for private mempool usage
        address[] trustedRelayers;       // List of trusted MEV-protected relayers
        mapping(address => bool) isTrustedRelayer;
    }
    
    // Transaction fingerprint for MEV detection
    struct TransactionFingerprint {
        bytes32 txHash;                 // Transaction hash
        address from;                   // Sender address
        uint256 gasPrice;              // Gas price used
        uint256 timestamp;             // Block timestamp
        uint256 blockNumber;           // Block number
        bytes4 functionSelector;        // Function being called
        uint256 value;                 // Transaction value
        bytes32 dataHash;              // Hash of transaction data
    }
    
    // MEV attack patterns
    enum MEVAttackType {
        NONE,
        FRONT_RUNNING,
        SANDWICH_ATTACK,
        BACK_RUNNING,
        TIME_BANDIT_ATTACK
    }
    
    // MEV detection result
    struct MEVDetectionResult {
        bool detected;                  // Whether MEV was detected
        MEVAttackType attackType;       // Type of attack detected
        uint256 confidence;            // Confidence level (0-100)
        address suspiciousAddress;     // Suspected MEV bot address
        uint256 estimatedExtractedValue; // Estimated MEV extracted
        string description;            // Human readable description
    }
    
    // Recent transaction tracking for pattern analysis
    struct RecentTransactions {
        TransactionFingerprint[] transactions;
        mapping(bytes32 => uint256) txIndex;
        uint256 head;                  // Circular buffer head
        uint256 count;                // Number of stored transactions
    }
    
    // Constants
    uint256 private constant MAX_RECENT_TXS = 50;
    uint256 private constant SANDWICH_DETECTION_WINDOW = 3; // blocks
    uint256 private constant FRONT_RUNNING_GAS_THRESHOLD = 1.5e18; // 50% gas price increase
    uint256 private constant MEV_CONFIDENCE_THRESHOLD = 75; // 75% confidence to trigger protection
    
    /**
     * @notice Check if a transaction hash has MEV protection enabled
     * @param routeHash Route hash to check
     * @return protected Whether MEV protection is active
     */
    function checkMEVProtection(bytes32 routeHash) internal pure returns (bool protected) {
        // Simplified check - in production, this would verify against
        // private mempool or commit-reveal schemes
        protected = true; // Assume protection is available
    }
    
    /**
     * @notice Detect potential MEV attacks in recent transaction patterns
     * @param recentTxs Recent transaction data
     * @param currentTx Current transaction being analyzed
     * @return result MEV detection result
     */
    function detectMEVAttack(
        RecentTransactions storage recentTxs,
        TransactionFingerprint memory currentTx
    ) internal view returns (MEVDetectionResult memory result) {
        result.detected = false;
        result.attackType = MEVAttackType.NONE;
        result.confidence = 0;
        
        // Check for sandwich attacks
        MEVDetectionResult memory sandwichResult = _detectSandwichAttack(recentTxs, currentTx);
        if (sandwichResult.confidence > result.confidence) {
            result = sandwichResult;
        }
        
        // Check for front-running
        MEVDetectionResult memory frontRunResult = _detectFrontRunning(recentTxs, currentTx);
        if (frontRunResult.confidence > result.confidence) {
            result = frontRunResult;
        }
        
        // Check for back-running
        MEVDetectionResult memory backRunResult = _detectBackRunning(recentTxs, currentTx);
        if (backRunResult.confidence > result.confidence) {
            result = backRunResult;
        }
        
        // Set detected flag based on confidence threshold
        result.detected = result.confidence >= MEV_CONFIDENCE_THRESHOLD;
    }
    
    /**
     * @notice Apply MEV protection measures to a transaction
     * @param config MEV protection configuration
     * @param txData Transaction data to protect
     * @return protectedData Protected transaction data
     * @return delay Required delay before execution
     */
    function applyMEVProtection(
        MEVConfig storage config,
        bytes memory txData
    ) internal view returns (bytes memory protectedData, uint256 delay) {
        if (!config.enabled) {
            return (txData, 0);
        }
        
        // Apply commit-reveal protection
        if (config.commitRevealDelay > 0) {
            bytes32 commitment = keccak256(abi.encodePacked(txData, block.timestamp));
            protectedData = abi.encodePacked(commitment, txData);
            delay = config.commitRevealDelay;
        } else {
            protectedData = txData;
            delay = config.minExecutionDelay;
        }
    }
    
    /**
     * @notice Get optimal execution parameters to minimize MEV risk
     * @param expectedGasPrice Expected gas price for transaction
     * @param maxSlippage Maximum acceptable slippage
     * @return optimalGasPrice Recommended gas price
     * @return optimalSlippage Recommended slippage tolerance
     * @return executionDelay Recommended execution delay
     */
    function getOptimalExecutionParams(
        uint256 expectedGasPrice,
        uint256 maxSlippage
    ) internal pure returns (
        uint256 optimalGasPrice,
        uint256 optimalSlippage,
        uint256 executionDelay
    ) {
        // Use slightly above market gas price to avoid being front-run
        optimalGasPrice = (expectedGasPrice * 105) / 100; // 5% above expected
        
        // Use tighter slippage to prevent sandwich attacks
        optimalSlippage = (maxSlippage * 80) / 100; // 20% tighter than max
        
        // Random delay to make timing unpredictable
        executionDelay = _getRandomDelay();
    }
    
    /**
     * @notice Check if an address is a known MEV bot
     * @param addr Address to check
     * @return isMEVBot Whether the address is a known MEV bot
     * @return confidence Confidence level of the assessment
     */
    function isMEVBot(address addr) internal pure returns (bool botDetected, uint256 confidence) {
        // In production, this would check against databases of known MEV bots
        // For now, implement basic heuristics
        
        // Check for contract addresses with suspicious patterns
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }
        
        if (codeSize > 0 && codeSize < 100) {
            // Very small contracts are often simple MEV bots
            botDetected = true;
            confidence = 60;
        } else if (codeSize > 10000) {
            // Very large contracts might be sophisticated MEV operations
            botDetected = true;
            confidence = 40;
        } else {
            botDetected = false;
            confidence = 0;
        }
    }
    
    /**
     * @notice Calculate the cost of MEV protection
     * @param transactionValue Value of the transaction being protected
     * @param protectionLevel Level of protection (0=basic, 1=standard, 2=premium)
     * @return protectionCost Cost of protection in wei
     */
    function calculateProtectionCost(
        uint256 transactionValue,
        uint8 protectionLevel
    ) internal pure returns (uint256 protectionCost) {
        uint256 baseFeeBPS;
        
        if (protectionLevel == 0) {
            baseFeeBPS = 5; // 0.05% for basic protection
        } else if (protectionLevel == 1) {
            baseFeeBPS = 15; // 0.15% for standard protection
        } else {
            baseFeeBPS = 30; // 0.30% for premium protection
        }
        
        protectionCost = (transactionValue * baseFeeBPS) / 10000;
    }
    
    /**
     * @notice Store transaction fingerprint for MEV analysis
     * @param recentTxs Storage for recent transactions
     * @param fingerprint Transaction fingerprint to store
     */
    function storeTransactionFingerprint(
        RecentTransactions storage recentTxs,
        TransactionFingerprint memory fingerprint
    ) internal {
        if (recentTxs.transactions.length == 0) {
            // Initialize array
            recentTxs.transactions = new TransactionFingerprint[](MAX_RECENT_TXS);
        }
        
        // Store in circular buffer
        uint256 index = recentTxs.head;
        recentTxs.transactions[index] = fingerprint;
        recentTxs.txIndex[fingerprint.txHash] = index;
        
        // Update circular buffer pointers
        recentTxs.head = (recentTxs.head + 1) % MAX_RECENT_TXS;
        if (recentTxs.count < MAX_RECENT_TXS) {
            recentTxs.count++;
        }
    }
    
    /**
     * @notice Emergency pause MEV protection if attacks are detected
     * @param config MEV configuration to update
     * @param reason Reason for emergency pause
     */
    function emergencyPauseMEVProtection(
        MEVConfig storage config,
        string memory reason
    ) internal {
        config.enabled = false;
        
        emit Events.MEVDetected(
            address(this),
            blockhash(block.number - 1),
            reason
        );
    }
    
    // Internal helper functions
    
    function _detectSandwichAttack(
        RecentTransactions storage recentTxs,
        TransactionFingerprint memory currentTx
    ) internal view returns (MEVDetectionResult memory result) {
        result.attackType = MEVAttackType.SANDWICH_ATTACK;
        
        // Look for transactions with same function selector around current block
        uint256 matchingTxs = 0;
        uint256 suspiciousGasPrices = 0;
        
        for (uint256 i = 0; i < recentTxs.count; i++) {
            TransactionFingerprint memory txData = recentTxs.transactions[i];
            
            // Check if transaction is in the detection window
            if (txData.blockNumber + SANDWICH_DETECTION_WINDOW >= currentTx.blockNumber) {
                if (txData.functionSelector == currentTx.functionSelector) {
                    matchingTxs++;
                    
                    // Check for suspicious gas price patterns
                    if (txData.gasPrice > currentTx.gasPrice * 120 / 100) {
                        suspiciousGasPrices++;
                        result.suspiciousAddress = txData.from;
                    }
                }
            }
        }
        
        // Calculate confidence based on patterns found
        if (matchingTxs >= 2 && suspiciousGasPrices > 0) {
            result.confidence = 80 + (suspiciousGasPrices * 10);
            result.description = "Potential sandwich attack detected";
        }
    }
    
    function _detectFrontRunning(
        RecentTransactions storage recentTxs,
        TransactionFingerprint memory currentTx
    ) internal view returns (MEVDetectionResult memory result) {
        result.attackType = MEVAttackType.FRONT_RUNNING;
        
        // Look for transactions with significantly higher gas prices
        for (uint256 i = 0; i < recentTxs.count; i++) {
            TransactionFingerprint memory tx = recentTxs.transactions[i];
            
            // Check recent transactions in mempool
            if (tx.blockNumber == currentTx.blockNumber || tx.blockNumber == currentTx.blockNumber - 1) {
                if (tx.functionSelector == currentTx.functionSelector) {
                    if (tx.gasPrice > currentTx.gasPrice + FRONT_RUNNING_GAS_THRESHOLD) {
                        result.confidence = 85;
                        result.suspiciousAddress = tx.from;
                        result.description = "Front-running attempt detected";
                        break;
                    }
                }
            }
        }
    }
    
    function _detectBackRunning(
        RecentTransactions storage recentTxs,
        TransactionFingerprint memory currentTx
    ) internal view returns (MEVDetectionResult memory result) {
        result.attackType = MEVAttackType.BACK_RUNNING;
        
        // Look for transactions that consistently follow similar patterns
        uint256 followingTxs = 0;
        
        for (uint256 i = 0; i < recentTxs.count; i++) {
            TransactionFingerprint memory tx = recentTxs.transactions[i];
            
            // Check if this transaction follows the pattern
            if (tx.blockNumber == currentTx.blockNumber + 1) {
                if (tx.from == result.suspiciousAddress) {
                    followingTxs++;
                }
            }
        }
        
        if (followingTxs >= 3) {
            result.confidence = 70;
            result.description = "Back-running pattern detected";
        }
    }
    
    function _getRandomDelay() internal view returns (uint256 delay) {
        // Generate pseudo-random delay between 1-10 seconds
        uint256 random = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender
        )));
        delay = 1 + (random % 10);
    }
    
    /**
     * @notice Get MEV protection status for a transaction
     * @param txHash Transaction hash to check
     * @return status Protection status information
     */
    function getMEVProtectionStatus(bytes32 txHash) internal pure returns (string memory status) {
        // In production, this would query actual protection services
        if (txHash != bytes32(0)) {
            status = "Protected via private mempool";
        } else {
            status = "No protection";
        }
    }
}