// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./CuttingBoardDutchAuction.t.sol";
import {CuttingBoardDutchAuction} from
    "src/periphery/deprecated/CuttingBoardDutchAuction.sol";
import {CuttingBoardDutchAuctionV1_1} from
    "src/periphery/CuttingBoardDutchAuctionV1_1.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManager} from "src/periphery/CuttingBoardManager.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";

/**
 * @notice Runs the full V1 test suite against V1_1 (regression guard) and
 *         adds targeted tests for the two bugs fixed in V1_1.
 */
contract CuttingBoardDutchAuctionV1_1Test is CuttingBoardDutchAuctionTest {
    // -------------------------------------------------------------------------
    // Override setup to deploy V1_1 as the implementation
    // -------------------------------------------------------------------------

    function setUp() public override {
        owner = address(this);
        keeper = makeAddr("keeper");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");

        paymentToken = new MockPaymentToken();
        infrared = new MockInfrared();
        chef = new MockBeraChef();

        (nft, manager, auction) = _deployContractsV1_1();

        paymentToken.mint(user1, 1000000e18);
        paymentToken.mint(user2, 1000000e18);

        chef.setWhitelistedVault(vault1, true);
        chef.setWhitelistedVault(vault2, true);
    }

    function _deployContractsV1_1()
        internal
        returns (
            CuttingBoardNFT _nft,
            CuttingBoardManager _manager,
            CuttingBoardDutchAuction _auction
        )
    {
        uint64 currentNonce = vm.getNonce(address(this));
        address predictedManagerProxy =
            vm.computeCreateAddress(address(this), currentNonce + 2);
        address predictedAuction =
            vm.computeCreateAddress(address(this), currentNonce + 4);

        _nft = new CuttingBoardNFT(
            predictedAuction, owner, predictedManagerProxy, ""
        );

        CuttingBoardManager managerImpl = new CuttingBoardManager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(infrared),
                    address(_nft),
                    address(chef),
                    owner,
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );
        _manager = CuttingBoardManager(address(managerProxy));
        require(
            address(_manager) == predictedManagerProxy,
            "Manager address mismatch"
        );

        // Deploy V1_1 implementation instead of V1
        CuttingBoardDutchAuctionV1_1 auctionImpl =
            new CuttingBoardDutchAuctionV1_1();

        ERC1967Proxy auctionProxy = new ERC1967Proxy(
            address(auctionImpl),
            abi.encodeCall(
                CuttingBoardDutchAuction.initialize,
                CuttingBoardDutchAuction.InitParams({
                    infrared: address(infrared),
                    paymentToken: address(paymentToken),
                    treasury: treasury,
                    chef: address(chef),
                    controlNFT: address(_nft),
                    controlManager: address(_manager),
                    governance: owner,
                    keeper: keeper,
                    auctionDuration: AUCTION_DURATION,
                    allocationDuration: ALLOCATION_DURATION,
                    maxAuctions: MAX_AUCTIONS,
                    startingPriceMultiplier: STARTING_PRICE_MULTIPLIER,
                    basePriceDivisor: BASE_PRICE_DIVISOR,
                    minimumPrice: MINIMUM_PRICE
                })
            )
        );
        _auction = CuttingBoardDutchAuction(address(auctionProxy));

        require(
            address(_auction) == predictedAuction, "Auction address mismatch"
        );
    }

    // -------------------------------------------------------------------------
    // Override V1 tests whose expected behavior changes in V1_1
    // -------------------------------------------------------------------------

    /// @dev V1 documented this as a revert; V1_1 fixes it so it succeeds.
    function test_edgeCase_MinimumPriceTooHighCausesRevert() public override {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory expiredAuction,) =
            auction.getAuction(0);
        uint256 expiredBasePrice = expiredAuction.basePrice; // 500e18

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // minimumPrice = expiredBasePrice * 3 = 1500e18  >  starting-from-base = 1000e18
        uint256 tooHighMinimum = expiredBasePrice * 3;
        vm.prank(keeper);
        auction.setMinimumPrice(tooHighMinimum);

        // V1_1: lastClosingPrice = max(500e18, 1500e18) = 1500e18
        //   starting = 1500e18 * 2 = 3000e18
        //   base     = max(750e18, 1500e18) = 1500e18
        //   3000e18 > 1500e18  →  no revert
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
        assertEq(auction.lastClosingPrice(), tooHighMinimum);

        (CuttingBoardDutchAuction.Auction memory newAuction,) =
            auction.getAuction(1);
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
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) = auction.getAuction(0);
        uint256 expiredBase = a0.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Keeper updates minimum to reflect current market (>> expiredBase)
        uint256 marketPrice = expiredBase * 489; // approximate Bepolia ratio
        vm.prank(keeper);
        auction.setMinimumPrice(marketPrice);

        // Must succeed — was the bug
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
    }

    function test_bug1_LastClosingPriceClampedToMinimum() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 highMin = INITIAL_PRICE * 5;
        vm.prank(keeper);
        auction.setMinimumPrice(highMin);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertGe(
            auction.lastClosingPrice(),
            highMin,
            "lastClosingPrice must not drop below minimumPrice"
        );
    }

    function test_bug1_LastClosingPriceNotClampedWhenBasePriceHigher() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Raise minimum slightly so it remains below expiredBase
        // minimumPrice starts at MINIMUM_PRICE=100e18; set to 200e18 (< expiredBase=500e18)
        vm.prank(keeper);
        auction.setMinimumPrice(200e18);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) = auction.getAuction(0);
        uint256 expiredBase = a0.basePrice; // still 500e18 (lastClosingPrice=INITIAL_PRICE=1000e18)

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // minimumPrice (200e18) < expiredBase (500e18): no clamp, uses expiredBase
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.lastClosingPrice(), expiredBase);
    }

    function testFuzz_bug1_StartingAlwaysGtBase(uint256 highMinFactor) public {
        highMinFactor = bound(highMinFactor, 2, 8);

        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory a0,) = auction.getAuction(0);
        uint256 expiredBase = a0.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 highMin = expiredBase * highMinFactor;
        vm.assume(
            highMin <= type(uint128).max / STARTING_PRICE_MULTIPLIER * 1e18
        );

        vm.prank(keeper);
        auction.setMinimumPrice(highMin);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory a1,) = auction.getAuction(1);
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
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertFalse(auction.isValidatorAvailable(validatorPubkey1));

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // V1 returned false here (the bug); V1_1 must return true
        assertTrue(
            auction.isValidatorAvailable(validatorPubkey1),
            "expired unclaimed auction: validator must be reported available"
        );
    }

    function test_bug2_IsValidatorAvailable_ConsistentWithStartAuction()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        bool available = auction.isValidatorAvailable(validatorPubkey1);
        assertTrue(available, "view must report available");

        // Transaction must also succeed when view says available
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 2);
    }

    function test_bug2_IsValidatorAvailable_FalseWhenAuctionStillActive()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        assertFalse(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_bug2_IsValidatorAvailable_OnlyAffectsLastExpiredValidator()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        // Auction 0: validator1 expires unclaimed
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Auction 1: validator2 is active (not expired)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // validator2 has a live auction → not available
        assertFalse(auction.isValidatorAvailable(validatorPubkey2));
        // validator1's mapping was cleared when auction 1 started → available
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_bug2_IsValidatorAvailable_FalseWhenControlPeriodActive()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Auction 0 expired for validator1 but the NFT is still valid
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Validator is NOT available: NFT control period is still active
        assertFalse(auction.isValidatorAvailable(validatorPubkey1));
    }
}
