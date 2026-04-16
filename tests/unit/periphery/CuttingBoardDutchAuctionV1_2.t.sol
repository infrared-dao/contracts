// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./CuttingBoardDutchAuctionV1_1.t.sol";
import {CuttingBoardDutchAuction} from
    "src/depreciated/periphery/CuttingBoardDutchAuction.sol";
import {CuttingBoardDutchAuctionV1_2} from
    "src/periphery/CuttingBoardDutchAuctionV1_2.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManager} from
    "src/depreciated/periphery/CuttingBoardManager.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";

/**
 * @notice Runs the full V1_1 test suite against V1_2 (regression guard) and
 *         adds targeted tests for the setMinimumPrice guard added in V1_2.
 */
contract CuttingBoardDutchAuctionV1_2Test is
    CuttingBoardDutchAuctionV1_1Test
{
    CuttingBoardDutchAuctionV1_2 auctionV1_2;

    event AllocationDurationUpdated(uint256 newDuration);

    // -------------------------------------------------------------------------
    // Override setup to deploy V1_2 as the implementation
    // -------------------------------------------------------------------------

    function setUp() public override {
        super.setUp();
        _deployContractsV1_2();
    }

    function _deployContractsV1_2() internal {
        // Deploy V1_2 implementation instead of V1_1
        CuttingBoardDutchAuctionV1_2 auctionImpl =
            new CuttingBoardDutchAuctionV1_2();

        auction.upgradeToAndCall(address(auctionImpl), "");

        auctionV1_2 = CuttingBoardDutchAuctionV1_2(address(auction));
    }

    // -------------------------------------------------------------------------
    // Override V1_1 tests whose expected behavior changes in V1_2
    // -------------------------------------------------------------------------

    /// @dev V1_1 allowed setMinimumPrice during a live auction and its
    ///      bug1 tests called setMinimumPrice after an expired auction.
    ///      Those still work in V1_2 because the auction is expired (not live).
    ///      No V1_1 tests need overriding — all setMinimumPrice calls in
    ///      existing tests happen before any auction or after expiry.

    // -------------------------------------------------------------------------
    // V1_2: setMinimumPrice guard tests
    // -------------------------------------------------------------------------

    function test_setMinimumPrice_revert_duringLiveAuction() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Auction is live — setMinimumPrice must revert
        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setMinimumPrice(MINIMUM_PRICE * 2);
    }

    function test_setMinimumPrice_revert_duringLiveAuction_midway() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to midpoint — still live
        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setMinimumPrice(MINIMUM_PRICE * 3);
    }

    function test_setMinimumPrice_revert_duringLiveAuction_lastSecond()
        public
    {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to 1 second before expiry — still live
        vm.warp(block.timestamp + AUCTION_DURATION - 1);

        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setMinimumPrice(MINIMUM_PRICE * 2);
    }

    function test_setMinimumPrice_succeedsAfterAuctionExpires() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp past expiry
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 newMin = MINIMUM_PRICE * 5;
        vm.prank(keeper);
        auctionV1_2.setMinimumPrice(newMin);

        assertEq(auctionV1_2.minimumPrice(), newMin);
    }

    function test_setMinimumPrice_succeedsAfterAuctionClaimed() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Claim the auctionV1_2
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auctionV1_2.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auctionV1_2), price);
        auctionV1_2.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Now setMinimumPrice should succeed — auctionV1_2 is claimed
        uint256 newMin = MINIMUM_PRICE * 3;
        vm.prank(keeper);
        auctionV1_2.setMinimumPrice(newMin);

        assertEq(auctionV1_2.minimumPrice(), newMin);
    }

    function test_setMinimumPrice_succeedsBeforeAnyAuction() public {
        // No auctionV1_2s started yet — must succeed
        uint256 newMin = MINIMUM_PRICE * 2;
        vm.prank(keeper);
        auctionV1_2.setMinimumPrice(newMin);

        assertEq(auctionV1_2.minimumPrice(), newMin);
    }

    function test_setMinimumPrice_succeedsAtExactExpiry() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to exact expiry boundary
        vm.warp(block.timestamp + AUCTION_DURATION);

        uint256 newMin = MINIMUM_PRICE * 2;
        vm.prank(keeper);
        auctionV1_2.setMinimumPrice(newMin);

        assertEq(auctionV1_2.minimumPrice(), newMin);
    }

    // -------------------------------------------------------------------------
    // V1_2: multiplier / divisor cap tests
    // -------------------------------------------------------------------------

    function test_setStartingPriceMultiplier_revert_exceedsMaxMultiplier()
        public
    {
        uint256 tooHigh = 100e18 + 1; // just above MAX_MULTIPLIER
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidMultiplier.selector);
        auctionV1_2.setStartingPriceMultiplier(tooHigh);
    }

    function test_setStartingPriceMultiplier_succeedsAtMaxMultiplier() public {
        uint256 maxVal = 100e18; // exactly MAX_MULTIPLIER
        vm.prank(keeper);
        auctionV1_2.setStartingPriceMultiplier(maxVal);
        assertEq(auctionV1_2.startingPriceMultiplier(), maxVal);
    }

    function test_setBasePriceDivisor_revert_exceedsMaxMultiplier() public {
        uint256 tooHigh = 100e18 + 1; // just above MAX_MULTIPLIER
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidDivisor.selector);
        auctionV1_2.setBasePriceDivisor(tooHigh);
    }

    function test_setBasePriceDivisor_succeedsAtMaxMultiplier() public {
        uint256 maxVal = 100e18; // exactly MAX_MULTIPLIER
        vm.prank(keeper);
        auctionV1_2.setBasePriceDivisor(maxVal);
        assertEq(auctionV1_2.basePriceDivisor(), maxVal);
    }

    function test_setStartingPriceMultiplier_revert_extremeValue() public {
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidMultiplier.selector);
        auctionV1_2.setStartingPriceMultiplier(type(uint256).max);
    }

    function test_setBasePriceDivisor_revert_extremeValue() public {
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidDivisor.selector);
        auctionV1_2.setBasePriceDivisor(type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // V1_2: existing guard tests (continued)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // V1_2: setAllocationDuration (guard removed) tests
    // -------------------------------------------------------------------------

    function test_setAllocationDuration_succeedsAfterAuctionsStarted() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // V1 would revert with AuctionsAlreadyStarted; V1_2 allows it
        uint256 newDuration = 14 days;
        auctionV1_2.setAllocationDuration(newDuration);

        assertEq(auctionV1_2.allocationDuration(), newDuration);
    }

    function test_setAllocationDuration_onlyAffectsFutureAuctions() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Snapshot the existing auction's allocationDuration
        (CuttingBoardDutchAuction.Auction memory a0,) =
            auctionV1_2.getAuction(0);
        uint32 originalDuration = a0.allocationDuration;
        assertEq(originalDuration, ALLOCATION_DURATION);

        // Change duration
        uint256 newDuration = 14 days;
        auctionV1_2.setAllocationDuration(newDuration);

        // Existing auction keeps original duration
        (CuttingBoardDutchAuction.Auction memory a0After,) =
            auctionV1_2.getAuction(0);
        assertEq(
            a0After.allocationDuration,
            originalDuration,
            "existing auction duration must not change"
        );

        // Claim the first auction so we can start a new one
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});
        uint256 price = auctionV1_2.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auctionV1_2), price);
        auctionV1_2.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Start next auction — should use new duration
        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory a1,) =
            auctionV1_2.getAuction(1);
        assertEq(
            a1.allocationDuration,
            uint32(newDuration),
            "new auction must use updated duration"
        );
    }

    function test_setAllocationDuration_revert_zero() public {
        vm.expectRevert(
            CuttingBoardDutchAuction.InvalidAllocationDuration.selector
        );
        auctionV1_2.setAllocationDuration(0);
    }

    function test_setAllocationDuration_revert_nonGovernor() public {
        vm.prank(user1);
        vm.expectRevert();
        auctionV1_2.setAllocationDuration(14 days);
    }

    function test_setAllocationDuration_succeedsBeforeAnyAuction() public {
        uint256 newDuration = 30 days;
        auctionV1_2.setAllocationDuration(newDuration);
        assertEq(auctionV1_2.allocationDuration(), newDuration);
    }

    function test_setAllocationDuration_emitsEvent() public {
        uint256 newDuration = 14 days;
        vm.expectEmit(false, false, false, true);
        emit AllocationDurationUpdated(newDuration);
        auctionV1_2.setAllocationDuration(newDuration);
    }

    // -------------------------------------------------------------------------
    // V1_2: setAuctionDuration guard tests
    // -------------------------------------------------------------------------

    function test_setAuctionDuration_revert_duringLiveAuction() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Auction is live — setAuctionDuration must revert
        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setAuctionDuration(12 hours);
    }

    function test_setAuctionDuration_revert_duringLiveAuction_midway() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to midpoint — still live
        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setAuctionDuration(1 hours);
    }

    function test_setAuctionDuration_revert_duringLiveAuction_lastSecond()
        public
    {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to 1 second before expiry — still live
        vm.warp(block.timestamp + AUCTION_DURATION - 1);

        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setAuctionDuration(48 hours);
    }

    function test_setAuctionDuration_succeedsAfterAuctionExpires() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp past expiry
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 newDuration = 12 hours;
        auctionV1_2.setAuctionDuration(newDuration);

        assertEq(auctionV1_2.auctionDuration(), newDuration);
    }

    function test_setAuctionDuration_succeedsAfterAuctionClaimed() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Claim the auction
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auctionV1_2.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auctionV1_2), price);
        auctionV1_2.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Now setAuctionDuration should succeed — auction is claimed
        uint256 newDuration = 48 hours;
        auctionV1_2.setAuctionDuration(newDuration);

        assertEq(auctionV1_2.auctionDuration(), newDuration);
    }

    function test_setAuctionDuration_succeedsBeforeAnyAuction() public {
        uint256 newDuration = 48 hours;
        auctionV1_2.setAuctionDuration(newDuration);
        assertEq(auctionV1_2.auctionDuration(), newDuration);
    }

    function test_setAuctionDuration_succeedsAtExactExpiry() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Warp to exact expiry boundary
        vm.warp(block.timestamp + AUCTION_DURATION);

        uint256 newDuration = 24 hours;
        auctionV1_2.setAuctionDuration(newDuration);

        assertEq(auctionV1_2.auctionDuration(), newDuration);
    }

    function test_setAuctionDuration_revert_zero() public {
        vm.expectRevert(CuttingBoardDutchAuction.InvalidDuration.selector);
        auctionV1_2.setAuctionDuration(0);
    }

    function test_setAuctionDuration_revert_nonGovernor() public {
        vm.prank(user1);
        vm.expectRevert();
        auctionV1_2.setAuctionDuration(12 hours);
    }

    // -------------------------------------------------------------------------
    // V1_2: existing guard tests (continued)
    // -------------------------------------------------------------------------

    function test_setMinimumPrice_revert_preservesOnlyKeeperGuard() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        // Non-keeper cannot call setMinimumPrice even without a live auctionV1_2
        vm.prank(user1);
        vm.expectRevert();
        auctionV1_2.setMinimumPrice(MINIMUM_PRICE * 2);
    }

    function test_setMinimumPrice_revert_zeroStillReverts() public {
        // Zero minimum still reverts with InvalidMinimumPrice, not AuctionStillActive
        vm.prank(keeper);
        vm.expectRevert();
        auctionV1_2.setMinimumPrice(0);
    }

    /// @dev End-to-end: demonstrates the bug scenario V1_2 prevents.
    ///      Without the guard, setMinimumPrice during a live auctionV1_2 would
    ///      corrupt lastClosingPrice and cause InvalidPriceRange on the next
    ///      startCuttingBoardAuction.
    function test_setMinimumPrice_preventsLastClosingPriceCorruption() public {
        auctionV1_2.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey1);

        // Try to raise minimum during live auctionV1_2 — blocked by V1_2
        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuctionV1_2.AuctionStillActive.selector
        );
        auctionV1_2.setMinimumPrice(INITIAL_PRICE * 10);

        // Claim at the current (decayed) price
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.warp(block.timestamp + AUCTION_DURATION / 2);
        uint256 claimPrice = auctionV1_2.getCurrentPrice(0);

        vm.startPrank(user1);
        paymentToken.approve(address(auctionV1_2), claimPrice);
        auctionV1_2.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // After claim, lastClosingPrice = claimPrice. Now raise minimum safely.
        uint256 highMin = claimPrice * 3;
        vm.prank(keeper);
        auctionV1_2.setMinimumPrice(highMin);

        // Next auctionV1_2 uses max(lastClosingPrice, minimumPrice) correctly
        vm.prank(keeper);
        auctionV1_2.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory a1,) =
            auctionV1_2.getAuction(1);
        assertTrue(
            a1.startingPrice > a1.basePrice,
            "startingPrice must exceed basePrice"
        );
    }
}
