// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ProofGeneratorFixed} from "./ProofGeneratorFixed.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

/// @title ProofHelper - External contract to avoid stack too deep issues
/// @notice Helper contract for generating proofs in tests without stack depth problems
contract ProofHelper {
    /// @notice Generate complete proof set for testing
    function generateProof(
        BeaconRootsVerify.Validator memory validator,
        uint256 validatorIndex,
        uint256 balance
    )
        external
        pure
        returns (
            bytes32[] memory validatorProof,
            bytes32[] memory balanceProof,
            bytes32 balanceLeaf,
            bytes32 stateRoot
        )
    {
        return ProofGeneratorFixed.generateCompleteProof(
            validator,
            validatorIndex,
            balance,
            1000 // totalValidators
        );
    }

    /// @notice Generate proof with custom total validators
    function generateProofWithTotal(
        BeaconRootsVerify.Validator memory validator,
        uint256 validatorIndex,
        uint256 balance,
        uint256 totalValidators
    )
        external
        pure
        returns (
            bytes32[] memory validatorProof,
            bytes32[] memory balanceProof,
            bytes32 balanceLeaf,
            bytes32 stateRoot
        )
    {
        return ProofGeneratorFixed.generateCompleteProof(
            validator, validatorIndex, balance, totalValidators
        );
    }

    /// @notice Create validator with custom withdrawal credentials
    function createValidatorWithCredentials(
        bytes memory pubkey,
        address withdrawalAddress,
        uint64 effectiveBalance
    ) external pure returns (BeaconRootsVerify.Validator memory) {
        return BeaconRootsVerify.Validator({
            pubkey: pubkey,
            withdrawalCredentials: bytes32(uint256(uint160(withdrawalAddress))),
            effectiveBalance: effectiveBalance,
            slashed: false,
            activationEligibilityEpoch: 0,
            activationEpoch: 0,
            exitEpoch: type(uint64).max,
            withdrawableEpoch: type(uint64).max
        });
    }

    /// @notice Create slashed validator
    function createSlashedValidator(
        bytes memory pubkey,
        address withdrawalAddress,
        uint64 effectiveBalance
    ) external pure returns (BeaconRootsVerify.Validator memory) {
        return BeaconRootsVerify.Validator({
            pubkey: pubkey,
            withdrawalCredentials: bytes32(uint256(uint160(withdrawalAddress))),
            effectiveBalance: effectiveBalance,
            slashed: true,
            activationEligibilityEpoch: 0,
            activationEpoch: 0,
            exitEpoch: type(uint64).max,
            withdrawableEpoch: type(uint64).max
        });
    }
}
