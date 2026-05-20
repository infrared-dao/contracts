// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {
    CuttingBoardDutchAuctionTest,
    CuttingBoardManager,
    MockBeraChef,
    MockInfrared,
    MockPaymentToken
} from "./CuttingBoardDutchAuction.t.sol";
import {CuttingBoardDutchAuction} from
    "src/depreciated/periphery/CuttingBoardDutchAuction.sol";
import {CuttingBoardDutchAuctionV1_1} from
    "src/depreciated/periphery/CuttingBoardDutchAuctionV1_1.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManagerV1_1} from
    "src/periphery/CuttingBoardManagerV1_1.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";

/**
 * @notice Runs the full V1 test suite against V1_1 (regression guard) and
 *         adds targeted tests for the two bugs fixed in V1_1.
 */
contract CuttingBoardDutchAuctionV1_1Test is CuttingBoardDutchAuctionTest {
    CuttingBoardDutchAuctionV1_1 auctionV1_1;
    // -------------------------------------------------------------------------
    // Override setup to deploy V1_1 as the implementation
    // -------------------------------------------------------------------------

    function setUp() public virtual override {
        super.setUp();
        _deployContractsV1_1();
    }

    function _deployContractsV1_1() internal {
        // Deploy V1_1 implementation instead of V1
        CuttingBoardDutchAuctionV1_1 auctionImpl =
            new CuttingBoardDutchAuctionV1_1();

        auction.upgradeToAndCall(address(auctionImpl), "");

        auctionV1_1 = CuttingBoardDutchAuctionV1_1(address(auction));
    }

    // -------------------------------------------------------------------------
    // Override V1 tests whose expected behavior changes in V1_1
    // -------------------------------------------------------------------------

    /// @dev V1 documented this as a revert; V1_1 fixes it so it succeeds.
    function test_edgeCase_MinimumPriceTooHighCausesRevert() public override {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory expiredAuction,) =
            auctionV1_1.getAuction(0);
        uint256 expiredBasePrice = expiredAuction.basePrice; // 500e18

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // minimumPrice = expiredBasePrice * 3 = 1500e18  >  starting-from-base = 1000e18
        uint256 tooHighMinimum = expiredBasePrice * 3;
        vm.prank(keeper);
        auctionV1_1.setMinimumPrice(tooHighMinimum);

        // V1_1: lastClosingPrice = max(500e18, 1500e18) = 1500e18
        //   starting = 1500e18 * 2 = 3000e18
        //   base     = max(750e18, 1500e18) = 1500e18
        //   3000e18 > 1500e18  →  no revert
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auctionV1_1.getAuctionCount(), 2);
        assertEq(auctionV1_1.lastClosingPrice(), tooHighMinimum);

        (CuttingBoardDutchAuction.Auction memory newAuction,) =
            auctionV1_1.getAuction(1);
        uint256 expectedStarting =
            (tooHighMinimum * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(newAuction.startingPrice, expectedStarting);
        assertEq(newAuction.basePrice, tooHighMinimum);
        assertTrue(newAuction.startingPrice > newAuction.basePrice);
    }

    // -------------------------------------------------------------------------
    // Bug 1 regression tests
    // -------------------------------------------------------------------------

    /// Bepolia reproduction: basePrice=10 IR, minimumPrice=244,449 IR
    function test_bug1_KeeperWorkflow_SetMinimumThenStartAuction() public {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) =
            auctionV1_1.getAuction(0);
        uint256 expiredBase = a0.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Keeper updates minimum to reflect current market (>> expiredBase)
        uint256 marketPrice = expiredBase * 489; // approximate Bepolia ratio
        vm.prank(keeper);
        auctionV1_1.setMinimumPrice(marketPrice);

        // Must succeed — was the bug
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auctionV1_1.getAuctionCount(), 2);
    }

    function test_bug1_LastClosingPriceClampedToMinimum() public {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 highMin = INITIAL_PRICE * 5;
        vm.prank(keeper);
        auctionV1_1.setMinimumPrice(highMin);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        assertGe(
            auctionV1_1.lastClosingPrice(),
            highMin,
            "lastClosingPrice must not drop below minimumPrice"
        );
    }

    function test_bug1_LastClosingPriceNotClampedWhenBasePriceHigher() public {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        // Raise minimum slightly so it remains below expiredBase
        // minimumPrice starts at MINIMUM_PRICE=100e18; set to 200e18 (< expiredBase=500e18)
        vm.prank(keeper);
        auctionV1_1.setMinimumPrice(200e18);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) =
            auctionV1_1.getAuction(0);
        uint256 expiredBase = a0.basePrice; // still 500e18 (lastClosingPrice=INITIAL_PRICE=1000e18)

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // minimumPrice (200e18) < expiredBase (500e18): no clamp, uses expiredBase
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auctionV1_1.lastClosingPrice(), expiredBase);
    }

    function testFuzz_bug1_StartingAlwaysGtBase(uint256 highMinFactor) public {
        highMinFactor = bound(highMinFactor, 2, 8);

        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) =
            auctionV1_1.getAuction(0);
        uint256 expiredBase = a0.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 highMin = expiredBase * highMinFactor;
        vm.assume(
            highMin <= type(uint128).max / STARTING_PRICE_MULTIPLIER * 1e18
        );

        vm.prank(keeper);
        auctionV1_1.setMinimumPrice(highMin);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory a1,) =
            auctionV1_1.getAuction(1);
        assertTrue(
            a1.startingPrice > a1.basePrice,
            "startingPrice must exceed basePrice"
        );
    }

    // -------------------------------------------------------------------------
    // Bug 2 regression tests
    // -------------------------------------------------------------------------

    function test_bug2_IsValidatorAvailable_TrueWhenOwnAuctionExpired()
        public
    {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        assertFalse(auctionV1_1.isValidatorAvailable(validatorPubkey1));

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // V1 returned false here (the bug); V1_1 must return true
        assertTrue(
            auctionV1_1.isValidatorAvailable(validatorPubkey1),
            "expired unclaimed auctionV1_1: validator must be reported available"
        );
    }

    function test_bug2_IsValidatorAvailable_ConsistentWithStartAuction()
        public
    {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        bool available = auctionV1_1.isValidatorAvailable(validatorPubkey1);
        assertTrue(available, "view must report available");

        // Transaction must also succeed when view says available
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auctionV1_1.getAuctionCount(), 2);
    }

    function test_bug2_IsValidatorAvailable_FalseWhenAuctionStillActive()
        public
    {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        assertFalse(auctionV1_1.isValidatorAvailable(validatorPubkey1));
    }

    function test_bug2_IsValidatorAvailable_OnlyAffectsLastExpiredValidator()
        public
    {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        // Auction 0: validator1 expires unclaimed
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Auction 1: validator2 is active (not expired)
        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey2);

        // validator2 has a live auctionV1_1 → not available
        assertFalse(auctionV1_1.isValidatorAvailable(validatorPubkey2));
        // validator1's mapping was cleared when auctionV1_1 1 started → available
        assertTrue(auctionV1_1.isValidatorAvailable(validatorPubkey1));
    }

    function test_bug2_IsValidatorAvailable_FalseWhenControlPeriodActive()
        public
    {
        auctionV1_1.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auctionV1_1.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auctionV1_1.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auctionV1_1), price);
        auctionV1_1.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Auction 0 expired for validator1 but the NFT is still valid
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Validator is NOT available: NFT control period is still active
        assertFalse(auctionV1_1.isValidatorAvailable(validatorPubkey1));
    }
}
