// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MerkleTree} from "./MerkleTree.sol";
import {EndianHelper} from "./EndianHelper.sol";

/**
 * @title Consensus Layer Verifier
 * @dev Verifies Beacon chain data using Merkle hashing to reconstruct the beacon block root, which can be queried on-chain via beacon roots contract (EIP-4788)
 */
library BeaconRootsVerify {
    // Custom errors (self explanatory)
    error RootNotFound();
    error FieldMismatch();

    /**
     * @notice Beacon state balances list container field index in state
     */
    uint256 public constant BALANCES_INDEX = 10;

    /**
     * @notice Beacon state validators list container field index in state
     */
    uint256 public constant VALIDATORS_INDEX = 9;

    /**
     * @notice Beacon state validator proof depth in list container
     */
    uint256 public constant VALIDATOR_PROOF_DEPTH = 41;

    /**
     * @notice Beacon state balance proof depth in list container
     */
    uint256 public constant BALANCE_PROOF_DEPTH = 39;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 BEACON ROOTS (EIP-4788)                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Address of beacon roots contract on ethereum (https://eips.ethereum.org/EIPS/eip-4788)
     */
    address public constant BEACON_ROOTS =
        0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /**
     * @notice Fetches the parent block root from the Beacon Roots contract at a specific timestamp
     * @param timestamp The timestamp for which to fetch the parent beacon block root
     * @return root The parent block root at the given timestamp
     */
    function getParentBeaconBlockRoot(uint256 timestamp)
        public
        view
        returns (bytes32 root)
    {
        (bool success, bytes memory data) =
            BEACON_ROOTS.staticcall(abi.encode(timestamp));
        if (!success) revert RootNotFound();
        root = abi.decode(data, (bytes32));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 BEACON BLOCK HEADER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
    struct BeaconBlockHeader {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
    }

    /**
     * @notice Calculates the Merkle root of a given Beacon block header
     * @param header The Beacon block header data
     * @return root The Merkle root of the block header
     */
    function calculateBeaconHeaderMerkleRoot(BeaconBlockHeader calldata header)
        public
        pure
        returns (bytes32 root)
    {
        // SSZ encode Header
        bytes32[] memory sszHeader = new bytes32[](8);
        sszHeader[0] = EndianHelper.toLittleEndian(header.slot);
        sszHeader[1] = EndianHelper.toLittleEndian(header.proposerIndex);
        sszHeader[2] = header.parentRoot;
        sszHeader[3] = header.stateRoot;
        sszHeader[4] = header.bodyRoot;
        sszHeader[5] = bytes32(0); // padding
        sszHeader[6] = bytes32(0); // padding
        sszHeader[7] = bytes32(0); // padding

        // calculate the header root
        root = MerkleTree.calculateMerkleRoot(sszHeader);
    }

    /**
     * @notice Verifies the Merkle root of a given Beacon block header and root
     * @param header The Beacon block header data
     * @param root The root to verify against
     * @return validRoot True if root matches Merkleized Header
     */
    function verifyBeaconHeaderMerkleRoot(
        BeaconBlockHeader calldata header,
        bytes32 root
    ) public pure returns (bool validRoot) {
        validRoot = root == calculateBeaconHeaderMerkleRoot(header);
    }

    /**
     * @notice Verifies the Merkle root of a given Beacon block header against beacon roots contract
     * @param header The Beacon block header data
     * @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
     * @return validRoot True if beacon roots call matches Merkleized Header
     * @dev will only work for slots within the last 24 hours
     */
    function verifyBeaconHeaderMerkleRoot(
        BeaconBlockHeader calldata header,
        uint256 nextBlockTimestamp
    ) public view returns (bool validRoot) {
        validRoot = getParentBeaconBlockRoot(nextBlockTimestamp)
            == calculateBeaconHeaderMerkleRoot(header);
    }

    /**
     * @notice Verify a merkle proof of the beacon state root against a beacon block header root
     * @param beaconBlockHeaderRoot merkle root of the beacon block header
     * @param beaconStateRoot merkle root of the beacon state
     * @param proof merkle proof of its inclusion under `beaconBlockHeaderRoot`
     * @return validStateRoot True if successfully verified
     */
    function verifyStateRoot(
        bytes32 beaconBlockHeaderRoot,
        bytes32 beaconStateRoot,
        bytes32[] calldata proof
    ) public pure returns (bool validStateRoot) {
        validStateRoot = MerkleTree.verifyMerkleLeaf(
            proof,
            beaconBlockHeaderRoot,
            beaconStateRoot,
            3 // State root index = 3
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VALIDATORS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
    struct Validator {
        bytes pubkey;
        bytes32 withdrawalCredentials;
        uint64 effectiveBalance;
        bool slashed;
        uint64 activationEligibilityEpoch;
        uint64 activationEpoch;
        uint64 exitEpoch;
        uint64 withdrawableEpoch;
    }

    /**
     * @notice Calculates the Merkle root of a given Validator
     * @param validator The Validator data
     * @return root The Merkle root of the block header
     */
    function calculateValidatorMerkleRoot(Validator calldata validator)
        public
        pure
        returns (bytes32 root)
    {
        // SSZ encode Validator
        bytes32[] memory sszValidator = new bytes32[](8);
        sszValidator[0] = sha256(
            abi.encodePacked(
                validator.pubkey,
                bytes16(0) // padding
            )
        );
        sszValidator[1] = validator.withdrawalCredentials;
        sszValidator[2] =
            EndianHelper.toLittleEndian(validator.effectiveBalance);
        sszValidator[3] = EndianHelper.toLittleEndian(validator.slashed);
        sszValidator[4] =
            EndianHelper.toLittleEndian(validator.activationEligibilityEpoch);
        sszValidator[5] = EndianHelper.toLittleEndian(validator.activationEpoch);
        sszValidator[6] = EndianHelper.toLittleEndian(validator.exitEpoch);
        sszValidator[7] =
            EndianHelper.toLittleEndian(validator.withdrawableEpoch);

        // calculate the header root
        root = MerkleTree.calculateMerkleRoot(sszValidator);
    }

    /**
     * @notice Verify a merkle proof of the validator against a beacon state root
     * @param beaconStateRoot merkle root of the beacon state
     * @param validator Validator struct data
     * @param proof merkle proof of the validator
     * @param valIndex index of validator
     * @return validValidator True for successful verification
     */
    function verifyValidator(
        bytes32 beaconStateRoot,
        Validator calldata validator,
        bytes32[] calldata proof,
        uint256 valIndex
    ) public pure returns (bool validValidator) {
        bytes32 validatorRoot = calculateValidatorMerkleRoot(validator);

        bytes32 validatorListRoot = MerkleTree.calculateMerkleRootFromProof(
            proof[:VALIDATOR_PROOF_DEPTH], validatorRoot, valIndex
        );

        validValidator = MerkleTree.verifyMerkleLeaf(
            proof[VALIDATOR_PROOF_DEPTH:],
            beaconStateRoot,
            validatorListRoot,
            VALIDATORS_INDEX
        );
    }

    /**
     * @notice Verify a merkle proof of the validator against beacon roots contract
     * @param header The Beacon block header data
     * @param validator Validator struct data
     * @param proof merkle proof of the validator against state root in header
     * @param valIndex index of validator
     * @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
     * @return validValidator True for successful verification
     */
    function verifyValidator(
        BeaconBlockHeader calldata header,
        Validator calldata validator,
        bytes32[] calldata proof,
        uint256 valIndex,
        uint256 nextBlockTimestamp
    ) public view returns (bool validValidator) {
        bytes32 validatorRoot = calculateValidatorMerkleRoot(validator);

        bytes32 validatorListRoot = MerkleTree.calculateMerkleRootFromProof(
            proof[:VALIDATOR_PROOF_DEPTH], validatorRoot, valIndex
        );

        validValidator = MerkleTree.verifyMerkleLeaf(
            proof[VALIDATOR_PROOF_DEPTH:],
            header.stateRoot,
            validatorListRoot,
            VALIDATORS_INDEX
        );

        if (!validValidator) return false;

        validValidator =
            verifyBeaconHeaderMerkleRoot(header, nextBlockTimestamp);
    }

    /**
     * @notice Verify a merkle proof of the validator balance against a beacon state root
     * @param header The Beacon block header data
     * @param proof merkle proof of the validator balance
     * @param valIndex index of validator
     * @param balance declared balance of validator to prove
     * @param balanceLeaf 32 bytes chunk including packed balance
     * @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
     * @return validValidatorBalance True for successful verification
     */
    function verifyValidatorBalance(
        BeaconBlockHeader calldata header,
        bytes32[] calldata proof,
        uint256 valIndex,
        uint256 balance,
        bytes32 balanceLeaf,
        uint256 nextBlockTimestamp
    ) public view returns (bool validValidatorBalance) {
        // balances are packed, 4 uint64's (LE) in a bytes32 chunk
        // chunk index is determined by index // 4
        // balance offset = index % 4
        uint256 offset = valIndex % 4;
        uint64 _balance = extractBalance(balanceLeaf, offset);

        // verify declared balance is accurate
        if (uint256(_balance) * 1 gwei != balance) return false;

        bytes32 balancesListRoot = MerkleTree.calculateMerkleRootFromProof(
            proof[:BALANCE_PROOF_DEPTH], balanceLeaf, valIndex / 4
        );

        validValidatorBalance = MerkleTree.verifyMerkleLeaf(
            proof[BALANCE_PROOF_DEPTH:],
            header.stateRoot,
            balancesListRoot,
            BALANCES_INDEX
        );

        if (!validValidatorBalance) return false;

        validValidatorBalance =
            verifyBeaconHeaderMerkleRoot(header, nextBlockTimestamp);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*            LIQUID STAKING TOKEN VERIFICATIONS              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Verify public key of a validator by merkle proof of the validator against a beacon state root
     * @param header The Beacon block header data
     * @param validator Validator struct data
     * @param proof merkle proof of the validator
     * @param valIndex index of validator
     * @param pubkey public key to verify
     * @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
     * @return validValidator True for successful verification
     */
    function verifyValidatorPublicKey(
        BeaconBlockHeader calldata header,
        Validator calldata validator,
        bytes32[] calldata proof,
        uint256 valIndex,
        bytes calldata pubkey,
        uint256 nextBlockTimestamp
    ) public view returns (bool validValidator) {
        if (keccak256(validator.pubkey) != keccak256(pubkey)) {
            revert FieldMismatch();
        }

        validValidator = verifyValidator(
            header, validator, proof, valIndex, nextBlockTimestamp
        );
    }

    /**
     * @notice Verify effective balance of a validator by merkle proof of the validator against a beacon state root
     * @param header The Beacon block header data
     * @param validator Validator struct data
     * @param proof merkle proof of the validator
     * @param valIndex index of validator
     * @param effectiveBalance balance to verify
     * @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
     * @return validValidator True for successful verification
     */
    function verifyValidatorEffectiveBalance(
        BeaconBlockHeader calldata header,
        Validator calldata validator,
        bytes32[] calldata proof,
        uint256 valIndex,
        uint64 effectiveBalance,
        uint256 nextBlockTimestamp
    ) public view returns (bool validValidator) {
        if (validator.effectiveBalance != effectiveBalance) {
            revert FieldMismatch();
        }

        validValidator = verifyValidator(
            header, validator, proof, valIndex, nextBlockTimestamp
        );
    }

    /**
     * @notice Verify withdrawal address of a validator by merkle proof of the validator against a beacon state root
     * @param beaconStateRoot merkle root of the beacon state
     * @param validator Validator struct data
     * @param proof merkle proof of the validator
     * @param valIndex index of validator
     * @param withdrawalAddress staker address to verify
     * @return validValidator True for successful verification
     */
    function verifyValidatorWithdrawalAddress(
        bytes32 beaconStateRoot,
        Validator calldata validator,
        bytes32[] calldata proof,
        uint256 valIndex,
        address withdrawalAddress
    ) public pure returns (bool validValidator) {
        if (
            address(uint160(uint256(validator.withdrawalCredentials)))
                != withdrawalAddress
        ) revert FieldMismatch();

        validValidator =
            verifyValidator(beaconStateRoot, validator, proof, valIndex);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPERS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function extractBalance(bytes32 chunk, uint256 offset)
        internal
        pure
        returns (uint64)
    {
        require(offset < 4, "Invalid offset");
        uint256 chunkValue = uint256(chunk);
        uint256 shiftBits = (3 - offset) * 64;

        uint64 leBalance =
            uint64((chunkValue >> shiftBits) & 0xFFFFFFFFFFFFFFFF);
        // Convert from little-endian to big-endian
        return EndianHelper.reverseBytes64(leBalance);
    }
}
