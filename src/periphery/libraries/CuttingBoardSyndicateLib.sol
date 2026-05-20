// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IBeraChefVaultCheck} from "src/interfaces/IBeraChefVaultCheck.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CuttingBoardDutchAuctionV1_2 as CuttingBoardDutchAuction} from
    "../CuttingBoardDutchAuctionV1_2.sol";
import {CuttingBoardManagerV1_1 as CuttingBoardManager} from
    "../CuttingBoardManagerV1_1.sol";
import {CuttingBoardNFT} from "../CuttingBoardNFT.sol";
import {CuttingBoardSlotNFT} from "../CuttingBoardSlotNFT.sol";

/// @title CuttingBoardSyndicateLib
/// @notice Library extracting compute-heavy internal functions from CuttingBoardSyndicate
///         to reduce the main contract's deployed bytecode below the 24 576 byte EVM limit.
///         Library functions with `external` visibility deploy in their own bytecode and are
///         invoked via DELEGATECALL.
library CuttingBoardSyndicateLib {
    // ──────────────────────────────────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────────────────────────────────

    enum RoundState {
        Idle, // default — no round opened for this auctionId
        Open, // registration in progress
        Active, // auction claimed; syndicate holds the NFT
        Expired, // auction lapsed before trigger; deposits refunded
        Complete // syndicate completed Active round

    }

    /// @dev Transient result of the fill algorithm — packed into a struct to
    ///      avoid stack-too-deep in triggerClaim.
    struct FillResult {
        address[] included; // partners in descending bid-value order
        uint96[] allocs; // allocated bps per partner
        uint256 count; // number of included partners
        uint96 bfWeight; // remaining bps for the buffer vault
        uint256 bufferRequired; // tokens the buffer must supply (bps cost + rounding dust)
    }

    /// @dev Storage layout: 3 slots.
    ///      Slot 0: validatorHash (32 bytes).
    ///      Slot 1: claimPrice (16) + tokenId (12) + state (1) = 29 bytes.
    ///      Slot 2: bufferVault (20 bytes).
    struct Round {
        bytes32 validatorHash; // keccak256(validatorPubkey) — identifies the validator
        uint128 claimPrice; // actual closing price paid; set after claim
        /// @dev uint96 safely holds all realistic NFT token IDs (max ~7.9e28)
        uint96 tokenId; // CuttingBoardNFT token id; set after claim
        RoundState state;
        /// @dev Snapshot of bufferVault taken at trigger time. Using the live
        ///      $.bufferVault in updateSlotVault would break proposals if governance
        ///      changes the buffer vault while a round is Active.
        address bufferVault; // buffer vault address recorded at triggerClaim()
    }

    /// @dev Storage layout: 3 slots, optimised so the sort hot-path reads only 1 slot.
    ///      Slot 0: weight (12) + maxPricePerBps (16) = 28 bytes.
    ///              Both fields read together in computeFill sort comparator → 1 SLOAD.
    ///      Slot 1: vault (20) + allocatedWeight (12) = 32 bytes (perfect fill).
    ///              Both fields read together in weightsFromStorage → 1 SLOAD.
    ///      Slot 2: deposit (16 bytes).
    struct Slot {
        uint96 weight; // Requested bps; positive multiple of minSlotWeight
        uint128 maxPricePerBps; // Maximum price per basis point partner will accept
        address vault; // BeraChef receiver vault (unique within a round)
        uint96 allocatedWeight; // Actual allocated bps (set at trigger; 0 = open / excluded)
        uint128 deposit; // Held tokens = maxPricePerBps × weight
    }

    /// @custom:storage-location erc7201:infrared.storage.CuttingBoardSyndicate
    struct CuttingBoardSyndicateStorage {
        /// @notice Dutch auction contract being targeted
        CuttingBoardDutchAuction dutchAuction;
        /// @notice Manager that gates cutting board proposals to Infrared
        CuttingBoardManager controlManager;
        /// @notice NFT representing validator control rights (syndicate holds it after claim)
        CuttingBoardNFT controlNFT;
        /// @notice Payment token — captured from the auction at initialisation
        ERC20 paymentToken;
        /// @notice BeraChef interface used for vault whitelist and weight validation
        IBeraChefVaultCheck chef;
        /// @notice Minimum bps per partner slot; must be a positive divisor of 10 000
        uint96 minSlotWeight;
        /// @notice Protocol-owned fallback vault absorbing unallocated bps
        address bufferVault;
        /// @notice Optional per-winner slot NFT contract
        CuttingBoardSlotNFT slotNFT;
        /// @notice Payment tokens held across rounds for the buffer vault's share
        uint256 bufferDeposit;
        /// @notice Set of addresses with a non-zero pending refund.
        /// @dev Maintained as a swap-and-pop array with an index mapping for O(1) removal.
        address[] refundees;
        /// @notice Index of each refundee in the `refundees` array (1-based; 0 = absent)
        mapping(address => uint256) refundeeIndex;
        // Per-auction-round state (all mappings keyed by auctionId)
        mapping(uint256 => Round) rounds;
        mapping(uint256 => address[]) roundPartners;
        mapping(uint256 => mapping(address => Slot)) slots;
        /// @notice Buffer vault's allocated weight for a given Active round (0 otherwise)
        mapping(uint256 => uint96) roundBufferAllocated;
        /// @notice Refund ledger accumulated across all rounds; persists indefinitely
        mapping(address => uint256) pendingRefunds;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Library functions (external → deployed separately, called via DELEGATECALL)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Run the priority fill algorithm and compute the buffer's required payment.
     *
     * Algorithm:
     *   1. Filter to eligible partners (maxPricePerBps × 10 000 ≥ price).
     *      weight and maxPricePerBps share Slot storage slot-0, so both are loaded
     *      with a single SLOAD per partner. Bid values are cached in memory so the
     *      sort loop requires no further storage reads.
     *      Partners whose vault has been de-whitelisted since registration are
     *      excluded so the fill adapts to live BeraChef policy. Individual weights
     *      are capped to the current maxWeightPerVault in case it decreased.
     *   2. Insertion-sort cached bid values (weight × maxPricePerBps) descending.
     *      Ties preserve registration order (insertion sort is stable on strict <).
     *   3. Greedily allocate to 10 000 bps; last included partner may be partial.
     *   4. bufferRequired = price − Σ floor(price × alloc_i / 10 000).
     *      This covers the buffer vault's exact bps cost plus rounding dust
     *      (≤ count − 1 wei). When bfWeight = 0 (partners fill all 10 000 bps),
     *      bufferRequired equals only the rounding dust; bufferDeposit must still
     *      cover it even though the buffer vault receives no bps allocation.
     */
    function computeFill(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        uint256 price
    ) external view returns (FillResult memory fill) {
        address[] memory _partners = $.roundPartners[auctionId];
        uint256 n = _partners.length;

        // Filter: cache bid values, weights, and vaults in memory so the sort
        // loop is entirely in memory (no storage reads beyond the initial filter pass).
        address[] memory eligible = new address[](n);
        uint256[] memory bidValues = new uint256[](n);
        uint96[] memory reqWeights = new uint96[](n);
        address[] memory vaults = new address[](n);
        uint256 ec;

        {
            IBeraChefVaultCheck chef = $.chef;
            uint96 maxPerVault = chef.maxWeightPerVault();
            mapping(address => Slot) storage slots = $.slots[auctionId];
            for (uint256 i = 0; i < n; i++) {
                Slot storage slot = slots[_partners[i]];
                uint96 w = slot.weight;
                uint128 maxP = slot.maxPricePerBps;
                if (uint256(maxP) * 10000 >= price) {
                    address v = slot.vault;
                    // Skip partners whose vault is no longer whitelisted in BeraChef
                    if (!chef.isWhitelistedVault(v)) continue;
                    eligible[ec] = _partners[i];
                    bidValues[ec] = uint256(w) * maxP;
                    // Cap requested weight to the current maxWeightPerVault in case
                    // the cap decreased since registration.
                    reqWeights[ec] = w > maxPerVault ? maxPerVault : w;
                    vaults[ec] = v;
                    ec++;
                }
            }
        }

        // Insertion-sort by bidValues descending (stable on equal values).
        // Operates entirely on memory arrays — no further SLOADs.
        for (uint256 i = 1; i < ec; i++) {
            address keyAddr = eligible[i];
            uint256 keyBid = bidValues[i];
            uint96 keyW = reqWeights[i];
            address keyVault = vaults[i];
            int256 j = int256(i) - 1;
            while (j >= 0 && bidValues[uint256(j)] < keyBid) {
                eligible[uint256(j + 1)] = eligible[uint256(j)];
                bidValues[uint256(j + 1)] = bidValues[uint256(j)];
                reqWeights[uint256(j + 1)] = reqWeights[uint256(j)];
                vaults[uint256(j + 1)] = vaults[uint256(j)];
                j--;
            }
            eligible[uint256(j + 1)] = keyAddr;
            bidValues[uint256(j + 1)] = keyBid;
            reqWeights[uint256(j + 1)] = keyW;
            vaults[uint256(j + 1)] = keyVault;
        }

        // Greedy fill to 10 000 bps. Partners whose vault is already claimed
        // by a higher-priority bid are skipped (only the top bid per vault wins).
        fill.included = new address[](ec);
        fill.allocs = new uint96[](ec);
        address[] memory includedVaults = new address[](ec);
        uint96 filled;

        for (uint256 i = 0; i < ec && filled < 10000; i++) {
            // Skip if this vault is already allocated to a higher-priority partner.
            bool vaultTaken;
            for (uint256 k = 0; k < fill.count; k++) {
                if (vaults[i] == includedVaults[k]) {
                    vaultTaken = true;
                    break;
                }
            }
            if (vaultTaken) continue;

            uint96 remaining = 10000 - filled;
            uint96 alloc = reqWeights[i] < remaining ? reqWeights[i] : remaining;
            fill.included[fill.count] = eligible[i];
            fill.allocs[fill.count] = alloc;
            includedVaults[fill.count] = vaults[i];
            fill.count++;
            filled += alloc;
        }

        fill.bfWeight = 10000 - filled;

        // bufferRequired = price − Σ⌊price × alloc_i / 10 000⌋
        // Covers the buffer's bps cost plus rounding dust (≤ count − 1 wei).
        uint256 partnerTotal;
        for (uint256 i = 0; i < fill.count; i++) {
            partnerTotal += price * fill.allocs[i] / 10000;
        }
        fill.bufferRequired = price - partnerTotal;
    }

    /**
     * @notice Build IBeraChef.Weight[] from a fill result, appending the buffer entry.
     */
    function weightsFromFill(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        address[] memory included,
        uint96[] memory allocs,
        uint256 count,
        uint96 bfWeight
    ) external view returns (IBeraChef.Weight[] memory weights) {
        uint256 total = count + (bfWeight > 0 ? 1 : 0);
        weights = new IBeraChef.Weight[](total);
        for (uint256 i = 0; i < count; i++) {
            weights[i] = IBeraChef.Weight({
                receiver: $.slots[auctionId][included[i]].vault,
                percentageNumerator: allocs[i]
            });
        }
        if (bfWeight > 0) {
            weights[count] = IBeraChef.Weight({
                receiver: $.bufferVault,
                percentageNumerator: bfWeight
            });
        }
    }

    /**
     * @notice Build IBeraChef.Weight[] from stored allocatedWeight values (Active round).
     * @dev Partners with allocatedWeight == 0 were excluded at trigger time and are skipped.
     *      vault and allocatedWeight share Slot storage slot-1, so both are loaded with
     *      a single SLOAD per partner.
     *      The buffer vault entry is appended when roundBufferAllocated[auctionId] > 0.
     */
    function weightsFromStorage(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId
    ) public view returns (IBeraChef.Weight[] memory weights) {
        address[] memory _partners = $.roundPartners[auctionId];
        uint256 n = _partners.length;
        uint96 bfAlloc = $.roundBufferAllocated[auctionId];
        // Use the buffer vault snapshotted at claim time, not the live $.bufferVault.
        // This prevents breakage if governance later calls setBufferVault() while
        // the round is Active.
        address bfVault = $.rounds[auctionId].bufferVault;

        uint256 includedCount;
        for (uint256 i = 0; i < n; i++) {
            if ($.slots[auctionId][_partners[i]].allocatedWeight > 0) {
                includedCount++;
            }
        }

        uint256 total = includedCount + (bfAlloc > 0 ? 1 : 0);
        weights = new IBeraChef.Weight[](total);

        uint256 idx;
        for (uint256 i = 0; i < n; i++) {
            Slot storage slot = $.slots[auctionId][_partners[i]];
            if (slot.allocatedWeight > 0) {
                // vault and allocatedWeight are in the same storage slot-1;
                // reading both costs only 1 SLOAD (second access is warm).
                weights[idx++] = IBeraChef.Weight({
                    receiver: slot.vault,
                    percentageNumerator: slot.allocatedWeight
                });
            }
        }
        if (bfAlloc > 0) {
            weights[idx] = IBeraChef.Weight({
                receiver: bfVault,
                percentageNumerator: bfAlloc
            });
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Errors (used by library functions; duplicated from contract for access)
    // ──────────────────────────────────────────────────────────────────────────

    error VaultNotWhitelisted();
    error DuplicateVaultEntry(address vault);
    error NoSlot();
    error NFTExpiredOrInvalid();
    error BufferWeightExceedsMax();
    error NoBidders();
    error TooManyPartners();
    error NoBufferVault();
    error BufferVaultNotWhitelisted();
    error InsufficientBuffer();

    // ──────────────────────────────────────────────────────────────────────────
    // View helpers (external → deployed in library bytecode)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Validate the new global buffer vault.
     * @dev Checks whitelist and rejects duplicates against any current Open round.
     */
    function validateSetBufferVault(
        CuttingBoardSyndicateStorage storage $,
        address vault
    ) external view {
        if (vault != address(0) && !$.chef.isWhitelistedVault(vault)) {
            revert VaultNotWhitelisted();
        }
        if (vault != address(0)) {
            (uint256 auctionId, bool auctionActive) =
                $.dutchAuction.getActiveAuction();
            if (auctionActive && $.rounds[auctionId].state == RoundState.Open) {
                _rejectDuplicateVault($, auctionId, address(0), vault);
            }
        }
    }

    /**
     * @notice Validate that `newVault` can replace the buffer vault for an Active round.
     * @dev Reverts with VaultNotWhitelisted or DuplicateVaultEntry.
     */
    function validateBufferVaultUpdate(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        address newVault
    ) external view {
        if (!$.chef.isWhitelistedVault(newVault)) revert VaultNotWhitelisted();
        _rejectDuplicateVault($, auctionId, address(0), newVault);
    }

    /**
     * @notice Validate that `newVault` can be assigned to `partnerKey`'s slot.
     * @dev Reverts with VaultNotWhitelisted or DuplicateVaultEntry.
     *      In Active rounds, checks against both the live `$.bufferVault` and
     *      the per-round snapshot `rounds[auctionId].bufferVault`.
     */
    function validateVaultUpdate(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        address partnerKey,
        address newVault
    ) external view {
        if (!$.chef.isWhitelistedVault(newVault)) revert VaultNotWhitelisted();
        if (newVault == $.bufferVault) revert DuplicateVaultEntry(newVault);

        bool isActive = $.rounds[auctionId].state == RoundState.Active;
        // In Open rounds, duplicate vaults are allowed — resolved at trigger time
        // by the fill algorithm (only the top bid per vault wins).
        if (!isActive) return;

        // Also reject the round's snapshotted buffer vault — this may differ
        // from $.bufferVault if governance called setBufferVault or
        // updateRoundBufferVault after triggerClaim.
        address roundBuffer = $.rounds[auctionId].bufferVault;
        if (newVault == roundBuffer) revert DuplicateVaultEntry(newVault);

        _rejectDuplicateVault($, auctionId, partnerKey, newVault);
    }

    /**
     * @notice Check whether an Active round's stored allocation satisfies
     *         current BeraChef rules (whitelist, maxWeightPerVault,
     *         maxNumWeightsPerRewardAllocation).
     * @return valid True if the allocation would pass BeraChef validation.
     */
    function checkRoundAllocationValid(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId
    ) external view returns (bool valid) {
        IBeraChef.Weight[] memory weights = weightsFromStorage($, auctionId);
        valid = $.controlManager.validateWeights(weights);
    }

    /**
     * @notice Governance-forced vault update: validates, updates slot storage,
     *         and syncs SlotNFT metadata. No ownership check.
     */
    function forceVaultUpdate(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        address partner,
        address newVault
    ) external {
        Slot storage slot = $.slots[auctionId][partner];
        if (slot.allocatedWeight == 0) revert NoSlot();

        // Reuse existing validation (whitelist + duplicate checks)
        if (!$.chef.isWhitelistedVault(newVault)) {
            revert VaultNotWhitelisted();
        }
        address roundBuffer = $.rounds[auctionId].bufferVault;
        if (newVault == roundBuffer) revert DuplicateVaultEntry(newVault);
        _rejectDuplicateVault($, auctionId, partner, newVault);

        slot.vault = newVault;

        CuttingBoardSlotNFT _slotNFT = $.slotNFT;
        if (address(_slotNFT) != address(0)) {
            uint256 slotTokenId = _slotNFT.getTokenId(auctionId, partner);
            if (slotTokenId != 0) {
                _slotNFT.updateVault(slotTokenId, newVault);
            }
        }
    }

    /**
     * @dev Build weights from storage and submit a proposal to CuttingBoardManager.
     *      Reverts if the control NFT is expired or invalid.
     */
    function proposeCurrentWeights(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId
    ) external {
        uint256 controlTokenId = $.rounds[auctionId].tokenId;
        if (!$.controlNFT.isValid(controlTokenId)) {
            revert NFTExpiredOrInvalid();
        }
        IBeraChef.Weight[] memory weights = weightsFromStorage($, auctionId);
        $.controlManager.proposeCuttingBoard(controlTokenId, weights);
    }

    /**
     * @dev Validate a FillResult against BeraChef constraints and buffer state.
     *      Reverts with a specific error if any check fails.
     */
    function validateFill(
        CuttingBoardSyndicateStorage storage $,
        FillResult memory fill
    ) external view {
        uint96 maxPerVault = $.chef.maxWeightPerVault();
        if (fill.bfWeight > maxPerVault) revert BufferWeightExceedsMax();
        if (fill.count == 0) revert NoBidders();
        uint256 totalEntries = fill.count + (fill.bfWeight > 0 ? 1 : 0);
        if (totalEntries > $.chef.maxNumWeightsPerRewardAllocation()) {
            revert TooManyPartners();
        }
        if (fill.bfWeight > 0 && $.bufferVault == address(0)) {
            revert NoBufferVault();
        }
        if (fill.bfWeight > 0 && !$.chef.isWhitelistedVault($.bufferVault)) {
            revert BufferVaultNotWhitelisted();
        }
        if (fill.bufferRequired > $.bufferDeposit) {
            revert InsufficientBuffer();
        }
    }

    /**
     * @dev Revert if `vault` matches any partner's vault in the round,
     *      optionally skipping `skipAddr` (use address(0) to skip nobody).
     *      Private — inlined by the compiler into each external caller.
     */
    function _rejectDuplicateVault(
        CuttingBoardSyndicateStorage storage $,
        uint256 auctionId,
        address skipAddr,
        address vault
    ) private view {
        address[] memory _partners = $.roundPartners[auctionId];
        for (uint256 i = 0; i < _partners.length; i++) {
            address p = _partners[i];
            if (p == skipAddr) continue;
            if ($.slots[auctionId][p].vault == vault) {
                revert DuplicateVaultEntry(vault);
            }
        }
    }
}
