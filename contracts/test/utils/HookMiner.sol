// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title HookMiner
 * @notice Library for mining valid hook addresses with required permissions
 */
library HookMiner {
    // Uniswap v4 hook addresses must have specific flags in their addresses
    // The hook address encodes the permissions it requires
    
    /**
     * @notice Find a salt that produces a valid hook address
     * @param deployer The address that will deploy the hook
     * @param permissions The required permissions encoded in the address
     * @param creationCode The creation code of the hook contract
     * @param constructorArgs The encoded constructor arguments
     * @return hookAddress The computed hook address
     * @return salt The salt that produces the valid address
     */
    function find(
        address deployer,
        uint160 permissions,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 codeHash = keccak256(bytecode);
        
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, codeHash);
            
            if (isValidHookAddress(hookAddress, permissions)) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: Could not find valid address");
    }
    
    /**
     * @notice Compute CREATE2 address
     * @param deployer The deployer address
     * @param salt The salt value
     * @param codeHash The hash of the creation code
     * @return The computed address
     */
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes32 codeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            codeHash
        )))));
    }
    
    /**
     * @notice Check if an address is valid for the given permissions
     * @param hookAddress The hook address to check
     * @param permissions The required permissions
     * @return Whether the address is valid
     */
    function isValidHookAddress(
        address hookAddress,
        uint160 permissions
    ) internal pure returns (bool) {
        // The hook address must have the required permission bits set
        uint160 addr = uint160(hookAddress);
        return (addr & permissions) == permissions;
    }
}