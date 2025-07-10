// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Endian Helper Library
 * @dev Provides helper functions for converting values to little-endian format
 */
library EndianHelper {
    /**
     * @notice Converts a 256-bit unsigned integer to little-endian format
     * @param value The unsigned integer to convert
     * @return The little-endian representation of the input value as bytes32
     */
    function toLittleEndian(uint256 value) internal pure returns (bytes32) {
        value = (
            (
                value
                    &
                    0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00
            ) >> 8
        )
            | (
                (
                    value
                        &
                        0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF
                ) << 8
            );
        value = (
            (
                value
                    &
                    0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000
            ) >> 16
        )
            | (
                (
                    value
                        &
                        0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF
                ) << 16
            );
        value = (
            (
                value
                    &
                    0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000
            ) >> 32
        )
            | (
                (
                    value
                        &
                        0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF
                ) << 32
            );
        value = (
            (
                value
                    &
                    0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000
            ) >> 64
        )
            | (
                (
                    value
                        &
                        0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF
                ) << 64
            );
        value = (value >> 128) | (value << 128);
        return bytes32(value);
    }

    /**
     * @notice Converts a boolean value to its little-endian bytes32 representation
     * @param value The boolean to convert
     * @return The little-endian representation of the boolean as bytes32
     */
    function toLittleEndian(bool value) internal pure returns (bytes32) {
        return bytes32(value ? 1 << 248 : 0);
    }

    /// @notice Reverses a uint64 from little-endian to big-endian (needed in Solidity)
    function reverseBytes64(uint64 input) internal pure returns (uint64) {
        input = ((input & 0xFF00FF00FF00FF00) >> 8)
            | ((input & 0x00FF00FF00FF00FF) << 8);
        input = ((input & 0xFFFF0000FFFF0000) >> 16)
            | ((input & 0x0000FFFF0000FFFF) << 16);
        input = (input >> 32) | (input << 32);
        return input;
    }
}
