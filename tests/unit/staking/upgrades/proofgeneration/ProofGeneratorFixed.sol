// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

/// @title Proof Generator for Unit Tests (Fixed Version)
/// @notice Generates valid Merkle proofs for testing beacon chain validator states
/// @dev This is for testing only - would be too gas intensive for production
library ProofGeneratorFixed {
    // Constants matching Python implementation
    uint256 constant VALIDATOR_REGISTRY_LIMIT = 1099511627776; // 2^40
    uint256 constant STATE_FIELDS_COUNT = 28; // Capella has 28 fields

    // Precomputed zero hashes for efficiency
    bytes32 constant ZERO_HASH_0 = bytes32(0);
    bytes32 constant ZERO_HASH_1 =
        0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;

    /// @notice Generate a complete proof for a validator with custom data
    function generateValidatorProof(
        BeaconRootsVerify.Validator memory validator,
        uint256 validatorIndex,
        uint256 totalValidators
    )
        internal
        pure
        returns (bytes32[] memory validatorProof, bytes32 validatorsRoot)
    {
        // Calculate the validator's leaf hash
        bytes32 validatorLeaf =
            BeaconRootsVerify.calculateValidatorMerkleRoot(validator);

        // Generate fixed capacity proof (depth 41 as expected by BeaconRootsVerify)
        uint256 depth = BeaconRootsVerify.VALIDATOR_PROOF_DEPTH;
        validatorProof = new bytes32[](depth);

        bytes32 currentHash = validatorLeaf;
        uint256 currentIndex = validatorIndex;

        // Build proof with zero hashes for padding
        for (uint256 i = 0; i < depth; i++) {
            bytes32 sibling;

            if (currentIndex % 2 == 0) {
                // Need right sibling
                if (currentIndex + 1 < totalValidators) {
                    sibling = generateDeterministicHash(
                        "validator", i, currentIndex + 1
                    );
                } else {
                    sibling = getZeroHash(i);
                }
                validatorProof[i] = sibling;
                currentHash = sha256(abi.encodePacked(currentHash, sibling));
            } else {
                // Need left sibling
                sibling =
                    generateDeterministicHash("validator", i, currentIndex - 1);
                validatorProof[i] = sibling;
                currentHash = sha256(abi.encodePacked(sibling, currentHash));
            }

            currentIndex = currentIndex / 2;
        }

        validatorsRoot = currentHash;
    }

    /// @notice Generate proof for balance verification
    function generateBalanceProof(
        uint256 balance,
        uint256 validatorIndex,
        uint256 totalValidators
    )
        internal
        pure
        returns (
            bytes32[] memory balanceProof,
            bytes32 balanceLeaf,
            bytes32 balancesRoot
        )
    {
        // Balances are packed 4 per leaf
        uint256 leafIndex = validatorIndex / 4;
        uint256 offsetInLeaf = validatorIndex % 4;

        // Create balance leaf with our balance at correct offset
        balanceLeaf = packBalanceLeafCorrect(balance, offsetInLeaf);

        // Generate balance proof (depth 39 as expected by BeaconRootsVerify)
        uint256 depth = BeaconRootsVerify.BALANCE_PROOF_DEPTH;
        balanceProof = new bytes32[](depth);

        bytes32 currentHash = balanceLeaf;
        uint256 currentIndex = leafIndex;

        // Build fixed capacity proof
        for (uint256 i = 0; i < depth; i++) {
            bytes32 sibling;
            uint256 totalChunks = (totalValidators + 3) / 4; // Ceiling division

            if (currentIndex % 2 == 0) {
                if (currentIndex + 1 < totalChunks) {
                    sibling = generateDeterministicHash(
                        "balance", i, currentIndex + 1
                    );
                } else {
                    sibling = getZeroHash(i);
                }
                balanceProof[i] = sibling;
                currentHash = sha256(abi.encodePacked(currentHash, sibling));
            } else {
                sibling =
                    generateDeterministicHash("balance", i, currentIndex - 1);
                balanceProof[i] = sibling;
                currentHash = sha256(abi.encodePacked(sibling, currentHash));
            }

            currentIndex = currentIndex / 2;
        }

        balancesRoot = currentHash;
    }

    /// @notice Generate state proof for validators or balances
    function generateStateProof(
        bytes32 validatorsRoot,
        bytes32 balancesRoot,
        bool forValidators
    ) internal pure returns (bytes32[] memory stateProof, bytes32 stateRoot) {
        // Create proper state tree with correct number of fields
        uint256 treeSize = 32; // Next power of 2 after 28
        bytes32[] memory stateLeaves = new bytes32[](treeSize);

        // Fill with deterministic values for all state fields
        for (uint256 i = 0; i < treeSize; i++) {
            if (i == BeaconRootsVerify.VALIDATORS_INDEX) {
                stateLeaves[i] = validatorsRoot;
            } else if (i == BeaconRootsVerify.BALANCES_INDEX) {
                stateLeaves[i] = balancesRoot;
            } else if (i >= STATE_FIELDS_COUNT) {
                stateLeaves[i] = bytes32(0); // Padding
            } else {
                stateLeaves[i] = generateDeterministicHash("state", 0, i);
            }
        }

        // Build complete merkle tree
        uint256 depth = 5; // log2(32) = 5
        bytes32[] memory tree = buildMerkleTree(stateLeaves);
        stateRoot = tree[tree.length - 1];

        // Generate proof for the requested index
        uint256 targetIndex = forValidators
            ? BeaconRootsVerify.VALIDATORS_INDEX
            : BeaconRootsVerify.BALANCES_INDEX;
        stateProof = new bytes32[](depth);

        uint256 currentIndex = targetIndex;
        uint256 levelStart = 0;

        for (uint256 i = 0; i < depth; i++) {
            uint256 siblingIndex = currentIndex ^ 1;
            stateProof[i] = tree[levelStart + siblingIndex];
            currentIndex = currentIndex / 2;
            levelStart += (treeSize >> i);
        }
    }

    /// @notice Pack balance into leaf format (4 balances per leaf, little-endian)
    function packBalanceLeafCorrect(uint256 balance, uint256 offset)
        internal
        pure
        returns (bytes32)
    {
        require(offset < 4, "Invalid offset");

        uint64 balanceGwei = uint64(balance / 1 gwei);
        bytes memory packed = new bytes(32);

        // Pack all 4 balances
        for (uint256 i = 0; i < 4; i++) {
            uint64 currentBalance;
            if (i == offset) {
                currentBalance = balanceGwei;
            } else {
                currentBalance = 32000000000; // 32 ETH in gwei
            }

            // Write as little-endian at correct position
            for (uint256 j = 0; j < 8; j++) {
                packed[i * 8 + j] = bytes1(uint8(currentBalance >> (j * 8)));
            }
        }

        return bytes32(packed);
    }

    /// @notice Build complete merkle tree from leaves
    function buildMerkleTree(bytes32[] memory leaves)
        internal
        pure
        returns (bytes32[] memory)
    {
        uint256 n = leaves.length;
        require(n > 0 && (n & (n - 1)) == 0, "Leaves must be power of 2");

        bytes32[] memory tree = new bytes32[](2 * n - 1);

        // Copy leaves
        for (uint256 i = 0; i < n; i++) {
            tree[i] = leaves[i];
        }

        // Build tree
        uint256 levelStart = 0;
        uint256 levelSize = n;

        while (levelSize > 1) {
            uint256 nextLevelStart = levelStart + levelSize;
            for (uint256 i = 0; i < levelSize / 2; i++) {
                tree[nextLevelStart + i] = sha256(
                    abi.encodePacked(
                        tree[levelStart + 2 * i], tree[levelStart + 2 * i + 1]
                    )
                );
            }
            levelStart = nextLevelStart;
            levelSize = levelSize / 2;
        }

        return tree;
    }

    /// @notice Get zero hash at specific depth
    function getZeroHash(uint256 depth) internal pure returns (bytes32) {
        if (depth == 0) return ZERO_HASH_0;
        if (depth == 1) return ZERO_HASH_1;

        // For higher depths, would need more precomputed values
        // For testing, use deterministic hash
        return keccak256(abi.encodePacked("ZERO", depth));
    }

    /// @notice Calculate log2 ceiling
    function log2Ceil(uint256 x) internal pure returns (uint256) {
        require(x > 0, "log2Ceil of 0");
        uint256 n = 0;
        uint256 y = x - 1;
        while (y > 0) {
            n++;
            y >>= 1;
        }
        return n;
    }

    /// @notice Generate complete proof set for testing
    function generateCompleteProof(
        BeaconRootsVerify.Validator memory validator,
        uint256 validatorIndex,
        uint256 balance,
        uint256 totalValidators
    )
        internal
        pure
        returns (
            bytes32[] memory fullValidatorProof,
            bytes32[] memory fullBalanceProof,
            bytes32 balanceLeaf,
            bytes32 stateRoot
        )
    {
        // 1. Generate validator proof with length mixing
        (bytes32[] memory validatorTreeProof, bytes32 validatorsRoot) =
            generateValidatorProof(validator, validatorIndex, totalValidators);

        // 2. Generate balance proof with length mixing
        (
            bytes32[] memory balanceTreeProof,
            bytes32 _balanceLeaf,
            bytes32 balancesRoot
        ) = generateBalanceProof(balance, validatorIndex, totalValidators);
        balanceLeaf = _balanceLeaf;

        // 3. Generate state proofs
        (bytes32[] memory validatorStateProof, bytes32 _stateRoot) =
            generateStateProof(validatorsRoot, balancesRoot, true);
        stateRoot = _stateRoot;

        (bytes32[] memory balanceStateProof,) =
            generateStateProof(validatorsRoot, balancesRoot, false);

        // 4. Combine proofs
        fullValidatorProof = new bytes32[](
            validatorTreeProof.length + validatorStateProof.length
        );
        for (uint256 i = 0; i < validatorTreeProof.length; i++) {
            fullValidatorProof[i] = validatorTreeProof[i];
        }
        for (uint256 i = 0; i < validatorStateProof.length; i++) {
            fullValidatorProof[validatorTreeProof.length + i] =
                validatorStateProof[i];
        }

        // Similar for balance proof
        fullBalanceProof =
            new bytes32[](balanceTreeProof.length + balanceStateProof.length);
        for (uint256 i = 0; i < balanceTreeProof.length; i++) {
            fullBalanceProof[i] = balanceTreeProof[i];
        }
        for (uint256 i = 0; i < balanceStateProof.length; i++) {
            fullBalanceProof[balanceTreeProof.length + i] = balanceStateProof[i];
        }
    }

    /// @notice Generate deterministic hash for sibling nodes
    function generateDeterministicHash(
        string memory treeType,
        uint256 depth,
        uint256 index
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(treeType, depth, index, "PROOF_GENERATOR")
        );
    }
}
