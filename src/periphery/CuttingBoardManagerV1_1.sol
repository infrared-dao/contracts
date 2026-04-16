// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CuttingBoardManager} from
    "src/depreciated/periphery/CuttingBoardManager.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IBeraChefVaultCheck} from "src/interfaces/IBeraChefVaultCheck.sol";

/**
 * @title CuttingBoardManagerV1_1
 * @notice Upgrade adding three capabilities to CuttingBoardManager:
 *
 *  1. `validateWeights` — public view exposing the internal _validateWeights
 *     check so keepers, the syndicate, and off-chain monitoring can verify
 *     whether a set of weights would pass under current BeraChef rules without
 *     submitting a transaction.
 *
 *  2. `refreshAllocation` — keeper-gated function that re-queues the current
 *     active reward allocation for a validator controlled by an NFT. Bypasses
 *     the propose/approve flow since the weights have not changed. Designed
 *     for the BeraChef `rewardAllocationInactivityBlockSpan` which can cause
 *     an unchanged allocation to become stale and fall back to the default if
 *     not periodically refreshed.
 *
 *  3. `isAllocationAtRisk` — view that checks whether a validator's active
 *     allocation is approaching the inactivity boundary and will need a
 *     refresh soon.
 */
contract CuttingBoardManagerV1_1 is CuttingBoardManager {
    // Redeclare the storage slot constant — same value as V1's private constant.
    // Required because V1 declared it `private`, making it inaccessible to V2.
    bytes32 private constant _STORAGE_LOCATION =
        0x9fd5aaf305ec5d9d4acf2d4a2d8f6d67e82cf32b8c76929329ec5790707b7d00;

    function _getStorage()
        private
        pure
        returns (CuttingBoardManagerStorage storage $)
    {
        assembly {
            $.slot := _STORAGE_LOCATION
        }
    }

    /// @dev Thrown when the active allocation has no weights to refresh.
    error NoActiveAllocation();

    /// @dev Emitted when a keeper refreshes an allocation without changing weights.
    event AllocationRefreshed(
        uint256 indexed tokenId, bytes validatorPubkey, uint64 startBlock
    );

    /**
     * @notice Check whether `weights` satisfy current BeraChef rules.
     * @dev Pure read-only logic reimplemented as `view` since the inherited
     *      `_validateWeights` lacks the `view` modifier (deployed V1 cannot
     *      be changed).
     * @return valid True if valid otherwise false
     */
    function validateWeights(IBeraChef.Weight[] calldata weights)
        external
        view
        virtual
        returns (bool valid)
    {
        if (weights.length == 0) return false;

        CuttingBoardManagerStorage storage $ = _getStorage();

        if (weights.length > $.chef.maxNumWeightsPerRewardAllocation()) {
            return false;
        }

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            IBeraChef.Weight calldata weight = weights[i];
            if (
                weight.percentageNumerator == 0
                    || weight.percentageNumerator > $.chef.maxWeightPerVault()
            ) {
                return false;
            }
            if (!$.chef.isWhitelistedVault(weight.receiver)) {
                return false;
            }
            // Check for duplicate receivers
            for (uint256 j = 0; j < i; j++) {
                if (weights[j].receiver == weight.receiver) {
                    return false;
                }
            }
            totalWeight += weight.percentageNumerator;
        }
        if (totalWeight != 10000) return false;
        valid = true;
    }

    /**
     * @notice Re-queue the current active allocation for a validator to
     *         prevent inactivity-based staleness in BeraChef.
     * @dev Keeper-only, bypasses the 2-step propose/approve flow since the
     *      weights are unchanged. Reads the validator's current active
     *      allocation directly from BeraChef and re-queues it via Infrared.
     *
     *      Requirements:
     *      - NFT must be valid (active and not expired).
     *      - The validator must have an active allocation with weights.
     *      - No queued allocation may be pending for this validator.
     *      - Respects `rewardAllocationBlockDelay` between updates.
     *
     * @param tokenId The control NFT token ID.
     */
    function refreshAllocation(uint256 tokenId)
        external
        virtual
        whenNotPaused
        onlyKeeper
    {
        CuttingBoardManagerStorage storage $ = _getStorage();

        // Verify NFT is still valid
        uint64 beraBlockDelay = $.chef.rewardAllocationBlockDelay();
        (, uint256 expiry,, bool active) =
            $.controlNFT.getControlRights(tokenId);
        if (!active) revert NFTInactive();
        if (block.timestamp + (2 * uint256(beraBlockDelay)) > expiry) {
            revert NFTExpired();
        }

        // Enforce minimum delay between updates
        if (
            $.lastUpdateBlock[tokenId] != 0
                && block.number < $.lastUpdateBlock[tokenId] + beraBlockDelay
        ) {
            revert UpdateTooSoon();
        }

        bytes memory pubkey = $.controlNFT.getValidator(tokenId);

        // Check there is no current queue
        {
            IBeraChef.RewardAllocation memory ra =
                $.chef.getQueuedRewardAllocation(pubkey);
            if (ra.startBlock > 0) revert AlreadyQueue();
        }

        // Verify it is at risk of staleness
        {
            (bool atRisk,) = isAllocationAtRisk(pubkey);
            if (!atRisk) revert UpdateTooSoon();
        }

        // Read the last set allocation from BeraChef
        IBeraChef.RewardAllocation memory activeRA =
            $.chef.getSetActiveRewardAllocation(pubkey);
        if (activeRA.weights.length == 0) revert NoActiveAllocation();

        // Update last update block
        $.lastUpdateBlock[tokenId] = block.number;

        uint64 startBlock = uint64(block.number) + beraBlockDelay + 1;

        // Re-queue via Infrared — same path as approveCuttingBoard
        $.infrared.queueNewCuttingBoard(pubkey, startBlock, activeRA.weights);

        emit AllocationRefreshed(tokenId, pubkey, startBlock);
    }

    /**
     * @notice Check if a validator's active allocation is approaching staleness.
     * @dev Returns true if the allocation's start block plus the inactivity
     *      span is within `marginBlocks` of the current block number.
     *      Returns false if the inactivity span is not configured (returns 0)
     *      or the validator has no active allocation.
     *
     * @param validatorPubkey The validator's 48-byte public key.
     * @return atRisk True if stale for more than half inactivity period.
     * @return blocksRemaining Blocks until inactivity deadline (0 if already stale
     *         or if inactivity span is not configured).
     */
    function isAllocationAtRisk(bytes memory validatorPubkey)
        public
        view
        virtual
        returns (bool atRisk, uint256 blocksRemaining)
    {
        CuttingBoardManagerStorage storage $ = _getStorage();

        uint256 inactivitySpan = $.chef.rewardAllocationInactivityBlockSpan();

        if (inactivitySpan == 0) return (false, 0);

        IBeraChef.RewardAllocation memory activeRA =
            $.chef.getSetActiveRewardAllocation(validatorPubkey);
        if (activeRA.startBlock == 0) return (false, 0);

        uint256 deadline = activeRA.startBlock + inactivitySpan;
        if (block.number >= deadline) {
            return (true, 0);
        }

        blocksRemaining = deadline - block.number;
        // define at risk as staleness for more than half of the inactivity span
        if (blocksRemaining >= inactivitySpan / 2) {
            return (false, blocksRemaining);
        }
        atRisk = true;
    }
}
