// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CuttingBoardDutchAuction} from
    "./deprecated/CuttingBoardDutchAuction.sol";

/**
 * @title CuttingBoardDutchAuctionV1_1
 * @notice Patch upgrade fixing two bugs in CuttingBoardDutchAuction (V1):
 *
 *  Bug 1 — InvalidPriceRange revert when keeper raises minimumPrice above an
 *           expired auction's basePrice.
 *
 *    Root cause: startCuttingBoardAuction unconditionally set
 *      lastClosingPrice = prevAuction.basePrice
 *    which silently discarded any keeper-set minimumPrice that exceeded that
 *    value.  The subsequent price-range check then fired because:
 *      starting = lastClosingPrice * multiplier   (small, reset by expired base)
 *      base     = max(lastClosingPrice / divisor, minimumPrice)  (large, market)
 *      starting <= base  →  InvalidPriceRange revert
 *
 *    Fix: clamp lastClosingPrice = max(prevAuction.basePrice, minimumPrice).
 *
 *  Bug 2 — isValidatorAvailable returns false for a validator whose last
 *           auction expired unclaimed, while startCuttingBoardAuction for the
 *           same validator succeeds (inconsistency between view and tx).
 *
 *    Root cause: startCuttingBoardAuction clears
 *      activeValidatorAuctions[prevValidatorHash] = 0
 *    before checking _isValidatorAvailable, but the public view function did
 *    not simulate this clearing, so off-chain keepers relying on the view
 *    would never restart a stuck validator.
 *
 *    Fix: isValidatorAvailable simulates the same clearing logic before
 *    delegating to _isValidatorAvailable.
 */
contract CuttingBoardDutchAuctionV1_1 is CuttingBoardDutchAuction {
    /**
     * @notice Start auction for a specific validator
     * @dev Overrides V1 to clamp lastClosingPrice >= minimumPrice when an expired
     *      unclaimed auction is processed, preventing InvalidPriceRange reverts
     *      after the keeper has raised the minimum price above the stale base price.
     */
    function startCuttingBoardAuction(bytes calldata validatorPubkey)
        external
        virtual
        override
        onlyKeeper
        whenNotPaused
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if ($.auctions.length >= $.maxAuctions) revert AllAuctionsCompleted();
        if (validatorPubkey.length != 48) revert InvalidValidatorPubkey();
        if (!$.infrared.isInfraredValidator(validatorPubkey)) {
            revert InvalidValidatorPubkey();
        }

        // Prevent simultaneous auctions - previous must be claimed first
        if ($.auctions.length > 0) {
            Auction memory prevAuction = $.auctions[$.auctions.length - 1];
            if (!prevAuction.claimed) {
                // Allow starting new auction if previous expired
                uint256 auctionEndTime =
                    prevAuction.startTime + $.auctionDuration;
                if (block.timestamp < auctionEndTime) {
                    revert PreviousAuctionNotClaimed();
                }
                // BUG 1 FIX: never let lastClosingPrice drop below minimumPrice.
                // V1 used prevAuction.basePrice unconditionally, which could reset
                // the price below a keeper-set minimumPrice and cause InvalidPriceRange.
                $.lastClosingPrice = prevAuction.basePrice > $.minimumPrice
                    ? prevAuction.basePrice
                    : $.minimumPrice;
                // Previous auction expired - clear active validator auction mapping
                bytes32 prevValidatorHash =
                    keccak256($.auctionValidators[$.auctions.length - 1]);
                $.activeValidatorAuctions[prevValidatorHash] = 0;
            }
        }

        // Check validator is available (not currently controlled)
        bytes32 validatorHash = keccak256(validatorPubkey);
        if (!_isValidatorAvailable(validatorHash)) {
            revert ValidatorNotAvailable();
        }

        // For first auction, require initial price
        if ($.auctions.length == 0) {
            if ($.lastClosingPrice == 0) revert SetInitialPriceFirst();
        }

        // Calculate prices
        if ($.lastClosingPrice > type(uint256).max / $.startingPriceMultiplier)
        {
            revert PriceOverflow();
        }
        uint256 starting =
            ($.lastClosingPrice * $.startingPriceMultiplier) / 1e18;
        uint256 base = ($.lastClosingPrice * 1e18) / $.basePriceDivisor;

        if (base < $.minimumPrice) {
            base = $.minimumPrice;
        }

        if (starting <= base) revert InvalidPriceRange();
        if (starting > type(uint128).max) revert PriceOverflow();
        if (base > type(uint128).max) revert PriceOverflow();
        if (block.timestamp > type(uint128).max) revert PriceOverflow();
        if ($.allocationDuration > type(uint32).max) revert PriceOverflow();

        uint256 auctionId = $.auctions.length;

        $.auctions.push(
            Auction({
                startTime: uint128(block.timestamp),
                startingPrice: uint128(starting),
                basePrice: uint128(base),
                claimPrice: 0,
                winner: address(0),
                claimed: false,
                allocationDuration: uint32($.allocationDuration),
                controlTokenId: 0
            })
        );

        $.auctionValidators[auctionId] = validatorPubkey;
        $.activeValidatorAuctions[validatorHash] = auctionId + 1;

        emit AuctionStarted(
            auctionId,
            validatorHash,
            starting,
            base,
            block.timestamp,
            $.allocationDuration
        );
    }

    /**
     * @notice Check if a validator is available for auction
     * @dev Overrides V1 to simulate the activeValidatorAuctions clearing that
     *      startCuttingBoardAuction performs for the globally-last expired unclaimed
     *      auction, making this view consistent with the transaction outcome.
     *      V1 returned false for a validator whose own last auction had just expired,
     *      causing keepers that used this as a pre-flight check to skip it permanently.
     */
    function isValidatorAvailable(bytes calldata validatorPubkey)
        external
        view
        virtual
        override
        returns (bool)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        bytes32 validatorHash = keccak256(validatorPubkey);

        // BUG 2 FIX: simulate the clearing startCuttingBoardAuction performs for
        // the globally-last expired unclaimed auction so this view matches what
        // the transaction would actually do.
        if ($.auctions.length > 0) {
            Auction memory prev = $.auctions[$.auctions.length - 1];
            if (
                !prev.claimed
                    && block.timestamp >= prev.startTime + $.auctionDuration
            ) {
                bytes32 prevHash =
                    keccak256($.auctionValidators[$.auctions.length - 1]);
                if (prevHash == validatorHash) {
                    // activeValidatorAuctions would be zeroed — only the NFT
                    // validity check (active control period) can still block.
                    uint256 tokenId = $.validatorControlTokenId[validatorHash];
                    return !$.controlNFT.isValid(tokenId);
                }
            }
        }

        return _isValidatorAvailable(validatorHash);
    }
}
