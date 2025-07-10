// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Merkle Tree Library
 * @dev Provides functions for calculating Merkle roots
 */
library MerkleTree {
    /**
     * @notice Calculates the Merkle root of an array of SSZ-encoded data using sha256 for hashing
     * @param data The array of SSZ-encoded data (as bytes32 values)
     * @return root The Merkle root of the data
     */
    function calculateMerkleRoot(bytes32[] memory data)
        internal
        pure
        returns (bytes32 root)
    {
        uint256 count = data.length;
        // number of leaves must be even
        if (count % 2 != 0) revert();
        while (count > 1) {
            for (uint256 i = 0; i < count / 2; i++) {
                // Hash pairs of nodes together
                data[i] = sha256(abi.encodePacked(data[2 * i], data[2 * i + 1]));
            }
            // Divide the count by 2 as we are moving up the tree
            count = count / 2;
        }

        // The root is the final remaining node
        root = data[0];
    }

    /**
     * @notice Verifies the inclusion of a leaf node in a Merkle tree using a given proof.
     * @dev Follows a bottom-up approach by iteratively hashing the leaf with proof elements
     *      based on the index and comparing the computed root with the provided Merkle root.
     * @param proof Array of bytes32 values representing the Merkle proof.
     * @param root The Merkle root to verify the leaf node against.
     * @param leaf The leaf node whose inclusion in the Merkle tree is being verified.
     * @param index The index of the leaf node in the tree, used to determine proof element order.
     * @return True if the computed Merkle root matches the provided root, indicating valid inclusion; otherwise, false.
     */
    function verifyMerkleLeaf(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bool) {
        // Iterate over proof elements to compute root hash.
        uint256 proofLength = proof.length;
        for (uint256 i = 0; i < proofLength; i++) {
            // Check if index is odd or even, and place `leaf` and `proofElement` accordingly.
            if (index % 2 == 0) {
                // Index is even, so hash (leaf, proofElement)
                leaf = sha256(abi.encodePacked(leaf, proof[i]));
            } else {
                // Index is odd, so hash (proofElement, leaf)
                leaf = sha256(abi.encodePacked(proof[i], leaf));
            }
            index = index / 2;
        }

        return leaf == root;
    }

    /**
     * @notice Calculates the Merkle root from a leaf, proof, and index.
     * @param proof Array of bytes32 values representing the Merkle proof.
     * @param leaf The leaf node whose inclusion in the Merkle tree is being verified.
     * @param index The index of the leaf node in the tree, used to determine proof element order.
     * @return root The computed Merkle root.
     */
    function calculateMerkleRootFromProof(
        bytes32[] memory proof,
        bytes32 leaf,
        uint256 index
    ) public pure returns (bytes32 root) {
        root = leaf;
        uint256 proofLength = proof.length;
        for (uint256 i = 0; i < proofLength; i++) {
            if (index % 2 == 0) {
                // Index is even, so hash (leaf, proofElement)
                root = sha256(abi.encodePacked(root, proof[i]));
            } else {
                // Index is odd, so hash (proofElement, leaf)
                root = sha256(abi.encodePacked(proof[i], root));
            }
            index = index / 2;
        }
    }
}
