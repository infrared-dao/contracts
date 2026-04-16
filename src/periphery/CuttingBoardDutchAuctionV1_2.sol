// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CuttingBoardDutchAuctionV1_1} from
    "src/depreciated/periphery/CuttingBoardDutchAuctionV1_1.sol";

/**
 * @title CuttingBoardDutchAuctionV1_2
 * @notice Patch upgrade fixing one bug in CuttingBoardDutchAuctionV1_1:
 *
 *  Bug — setMinimumPrice during a live auction can corrupt lastClosingPrice.
 *
 *    Root cause: setMinimumPrice (V1) raises lastClosingPrice when the new
 *    minimum exceeds it. If called while an auction is live, lastClosingPrice
 *    is lifted above the auction's decay range. When _processClaim later sets
 *    lastClosingPrice = currentPrice (≤ startingPrice), it drops below the
 *    raised minimum.  The next startCuttingBoardAuction then derives a
 *    starting price from this depressed lastClosingPrice while base is
 *    clamped to the higher minimumPrice, causing an InvalidPriceRange revert.
 *
 *    Fix: reject setMinimumPrice while a live (unclaimed, unexpired) auction
 *    exists.  Keepers must wait until the auction ends (claimed or expired)
 *    before adjusting the price floor.
 *
 *  Enhancement — cap multiplier/divisor values to prevent extreme pricing.
 *
 *    Root cause: unbounded startingPriceMultiplier or basePriceDivisor values
 *    can produce auction price ranges so extreme that they are effectively
 *    unusable (e.g., overflow-adjacent starting prices or near-zero base
 *    prices). A malicious or misconfigured keeper could set these to values
 *    orders of magnitude beyond any reasonable range.
 *
 *    Fix: both setStartingPriceMultiplier and setBasePriceDivisor enforce
 *    an upper bound of MAX_MULTIPLIER (100e18, i.e. 100x). This still
 *    allows wide pricing flexibility while preventing degenerate cases.
 */
contract CuttingBoardDutchAuctionV1_2 is CuttingBoardDutchAuctionV1_1 {
    /// @dev Upper bound for startingPriceMultiplier and basePriceDivisor.
    ///      100e18 (100x) prevents extreme price ranges while allowing wide
    ///      keeper flexibility. Values beyond this would produce degenerate
    ///      auction parameters (overflow-adjacent starts or near-zero floors).
    uint256 internal constant MAX_MULTIPLIER = 100e18;

    /// @dev Reverts when setMinimumPrice is called during a live auction.
    error AuctionStillActive();

    /**
     * @notice Update the minimum price floor
     * @param _minimumPrice New minimum price in payment token decimals
     * @dev Overrides V1 to reject calls while a live auction exists, preventing
     *      lastClosingPrice corruption that leads to InvalidPriceRange on the
     *      next startCuttingBoardAuction.
     */
    function setMinimumPrice(uint256 _minimumPrice)
        external
        virtual
        override
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        // Block price floor changes during a live auction
        if ($.auctions.length > 0) {
            Auction memory last = $.auctions[$.auctions.length - 1];
            if (
                !last.claimed
                    && block.timestamp < last.startTime + $.auctionDuration
            ) {
                revert AuctionStillActive();
            }
        }

        if (_minimumPrice == 0) revert InvalidMinimumPrice();
        $.minimumPrice = _minimumPrice;
        if (_minimumPrice > $.lastClosingPrice) {
            $.lastClosingPrice = _minimumPrice;
            emit InitialPriceSet(_minimumPrice);
        }
        emit MinimumPriceUpdated(_minimumPrice);
    }

    /**
     * @notice Update the base price divisor (controls price floor)
     * @param _basePriceDivisor New divisor (e.g., 2e18 = 0.5x previous price)
     * @dev Overrides V1 to enforce upper bound of MAX_MULTIPLIER (100e18).
     *      Must be > 1e18 and <= MAX_MULTIPLIER.
     */
    function setBasePriceDivisor(uint256 _basePriceDivisor)
        external
        virtual
        override
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_basePriceDivisor <= 1e18) revert InvalidDivisor();
        if (_basePriceDivisor > MAX_MULTIPLIER) revert InvalidDivisor();
        $.basePriceDivisor = _basePriceDivisor;
        emit BasePriceDivisorUpdated(_basePriceDivisor);
    }

    /**
     * @notice Update the starting price multiplier (controls auction start price)
     * @param _startingPriceMultiplier New multiplier (e.g., 2e18 = 2x previous price)
     * @dev Overrides V1 to enforce upper bound of MAX_MULTIPLIER (100e18).
     *      Must be > 1e18 and <= MAX_MULTIPLIER.
     */
    function setStartingPriceMultiplier(uint256 _startingPriceMultiplier)
        external
        virtual
        override
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_startingPriceMultiplier <= 1e18) revert InvalidMultiplier();
        if (_startingPriceMultiplier > MAX_MULTIPLIER) {
            revert InvalidMultiplier();
        }
        $.startingPriceMultiplier = _startingPriceMultiplier;
        emit StartingPriceMultiplierUpdated(_startingPriceMultiplier);
    }

    /**
     * @notice Update the allocation duration (control period length)
     * @param _allocationDuration New allocation duration in seconds
     * @dev Overrides V1 to remove the auctions-already-started guard, allowing
     *      governance to adjust the duration after the first auction. Safe because
     *      the value is snapshot into each Auction struct at creation time, so
     *      only future auctions are affected.
     */
    function setAllocationDuration(uint256 _allocationDuration)
        external
        virtual
        override
        onlyGovernor
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_allocationDuration == 0) revert InvalidAllocationDuration();
        $.allocationDuration = _allocationDuration;
        emit AllocationDurationUpdated(_allocationDuration);
    }

    /**
     * @notice Update the auction duration (price decay period)
     * @param _auctionDuration New auction duration in seconds
     * @dev Overrides V1 to remove the auctions-already-started guard, allowing
     *      governance to adjust the duration after the first auction. Rejects
     *      calls while a live auction exists because auctionDuration is read
     *      from storage (not snapshotted into the Auction struct), so changing
     *      it mid-flight would alter the price decay curve, expiry check, and
     *      the setMinimumPrice active-auction guard.
     */
    function setAuctionDuration(uint256 _auctionDuration)
        external
        virtual
        override
        onlyGovernor
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        // Block duration changes during a live auction
        if ($.auctions.length > 0) {
            Auction memory last = $.auctions[$.auctions.length - 1];
            if (
                !last.claimed
                    && block.timestamp < last.startTime + $.auctionDuration
            ) {
                revert AuctionStillActive();
            }
        }

        if (_auctionDuration == 0) revert InvalidDuration();
        $.auctionDuration = _auctionDuration;
        emit AuctionDurationUpdated(_auctionDuration);
    }
}
