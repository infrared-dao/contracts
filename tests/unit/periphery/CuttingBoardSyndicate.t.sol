// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CuttingBoardSyndicate} from "src/periphery/CuttingBoardSyndicate.sol";
import {CuttingBoardSyndicateLib} from
    "src/periphery/libraries/CuttingBoardSyndicateLib.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardSlotNFT} from "src/periphery/CuttingBoardSlotNFT.sol";
import {CuttingBoardDutchAuction as DeprecatedAuction} from
    "src/depreciated/periphery/CuttingBoardDutchAuction.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/*//////////////////////////////////////////////////////////////
                            MOCKS
//////////////////////////////////////////////////////////////*/

contract MockPaymentToken is ERC20("Mock IR", "IR", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockBeraChef {
    mapping(address => bool) public whitelistedVaults;
    uint96 private _maxWeightPerVault = 10000;
    uint8 private _maxNumWeightsPerRewardAllocation = 10;

    function isWhitelistedVault(address vault) external view returns (bool) {
        return whitelistedVaults[vault];
    }

    function setWhitelistedVault(address vault, bool listed) external {
        whitelistedVaults[vault] = listed;
    }

    function maxWeightPerVault() external view returns (uint96) {
        return _maxWeightPerVault;
    }

    function setMaxWeightPerVault(uint96 w) external {
        _maxWeightPerVault = w;
    }

    function maxNumWeightsPerRewardAllocation() external view returns (uint8) {
        return _maxNumWeightsPerRewardAllocation;
    }

    function setMaxNumWeightsPerRewardAllocation(uint8 n) external {
        _maxNumWeightsPerRewardAllocation = n;
    }

    function rewardAllocationBlockDelay() external pure returns (uint64) {
        return 0;
    }

    function getQueuedRewardAllocation(bytes calldata)
        external
        pure
        returns (IBeraChef.RewardAllocation memory ra)
    {
        ra.startBlock = 0;
    }
}

/// @dev Minimal Dutch-auction mock for syndicate unit tests.
///      Simulates auction state and NFT minting without full V1_1 complexity.
contract MockDutchAuction {
    using SafeTransferLib for ERC20;

    ERC20 public paymentToken;
    CuttingBoardNFT public nft;
    uint256 public allocationDuration;

    struct AuctionState {
        bool active;
        bytes validatorPubkey;
        uint256 currentPrice;
        uint256 tokenId;
        bool claimed;
    }

    mapping(uint256 => AuctionState) private _state;
    uint256 public minimumPrice;
    uint256 private _activeAuctionId;

    constructor(address _paymentToken, uint256 _allocationDuration) {
        paymentToken = ERC20(_paymentToken);
        allocationDuration = _allocationDuration;
    }

    /// @dev Set after NFT deployment to resolve the circular dependency.
    function setNFT(address _nft) external {
        nft = CuttingBoardNFT(_nft);
    }

    function configure(
        uint256 id,
        bool active,
        bytes memory pubkey,
        uint256 price
    ) external {
        _state[id].active = active;
        _state[id].validatorPubkey = pubkey;
        _state[id].currentPrice = price;
        _state[id].claimed = false;
        _state[id].tokenId = 0;
        if (active) _activeAuctionId = id;
    }

    function setActive(uint256 id, bool active) external {
        _state[id].active = active;
    }

    function setPrice(uint256 id, uint256 price) external {
        _state[id].currentPrice = price;
    }

    function setMinimumPrice(uint256 _minimumPrice) external {
        minimumPrice = _minimumPrice;
    }

    function isAuctionActive(uint256 id) external view returns (bool) {
        return _state[id].active;
    }

    function getAuctionValidator(uint256 id)
        external
        view
        returns (bytes memory)
    {
        return _state[id].validatorPubkey;
    }

    function getCurrentPrice(uint256 id) external view returns (uint256) {
        return _state[id].currentPrice;
    }

    function claimCuttingBoardControl(uint256 id, IBeraChef.Weight[] calldata)
        external
    {
        AuctionState storage s = _state[id];
        paymentToken.safeTransferFrom(msg.sender, address(this), s.currentPrice);
        s.active = false;
        s.claimed = true;
        s.tokenId = nft.mint(
            msg.sender,
            s.validatorPubkey,
            block.timestamp + allocationDuration,
            id
        );
    }

    function getAuction(uint256 id)
        external
        view
        returns (DeprecatedAuction.Auction memory a, bytes memory pubkey)
    {
        AuctionState memory s = _state[id];
        a = DeprecatedAuction.Auction({
            startTime: 0,
            startingPrice: 0,
            basePrice: 0,
            claimPrice: uint128(s.currentPrice),
            winner: address(0),
            claimed: s.claimed,
            allocationDuration: uint32(allocationDuration),
            controlTokenId: s.tokenId
        });
        pubkey = s.validatorPubkey;
    }

    function setActiveAuctionId(uint256 id) external {
        _activeAuctionId = id;
    }

    function getActiveAuction()
        external
        view
        returns (uint256 auctionId, bool isActive)
    {
        auctionId = _activeAuctionId;
        isActive = _state[auctionId].active;
    }
}

/// @dev Simple manager mock that records proposeCuttingBoard calls.
contract MockCuttingBoardManager {
    uint256 public lastTokenId;
    IBeraChef.Weight[] private _lastWeights;
    uint256 public callCount;

    function proposeCuttingBoard(
        uint256 tokenId,
        IBeraChef.Weight[] calldata weights
    ) external {
        lastTokenId = tokenId;
        delete _lastWeights;
        for (uint256 i = 0; i < weights.length; i++) {
            _lastWeights.push(weights[i]);
        }
        callCount++;
    }

    function getLastWeights()
        external
        view
        returns (IBeraChef.Weight[] memory)
    {
        return _lastWeights;
    }
}

/*//////////////////////////////////////////////////////////////
                        MAIN TEST CONTRACT
//////////////////////////////////////////////////////////////*/

contract CuttingBoardSyndicateTest is Test {
    CuttingBoardSyndicate syndicate;
    MockDutchAuction auction;
    MockCuttingBoardManager manager;
    CuttingBoardNFT nft;
    CuttingBoardSlotNFT slotNFT;
    MockPaymentToken paymentToken;
    MockBeraChef chef;

    address governance;
    address keeper;
    address partner1;
    address partner2;
    address partner3;
    address vault1;
    address vault2;
    address vault3;
    address bufferVault;

    bytes constant VALIDATOR_PUBKEY =
        hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    bytes constant VALIDATOR_PUBKEY_2 =
        hex"fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321";

    uint256 constant ALLOCATION_DURATION = 7 days;
    uint256 constant DEFAULT_PRICE = 1000e18;
    uint256 constant DEFAULT_PRICE_PER_BPS = DEFAULT_PRICE / 10000; // 0.1e18
    uint96 constant MIN_SLOT_WEIGHT = 100;

    // ── Events (duplicated for expectEmit assertions) ──────────────────────

    event BufferVaultSet(address indexed vault);
    event RoundBufferVaultUpdated(
        uint256 indexed auctionId, address indexed newVault
    );
    event BufferDeposited(address indexed depositor, uint256 amount);
    event BufferWithdrawn(address indexed recipient, uint256 amount);
    event MinSlotWeightSet(uint96 minWeight);
    event RoundOpened(uint256 indexed auctionId, bytes32 indexed validatorHash);
    event SlotRegistered(
        uint256 indexed auctionId,
        address indexed partner,
        address indexed vault,
        uint96 weight,
        uint128 maxPricePerBps,
        uint128 deposit
    );
    event SlotVaultUpdated(
        uint256 indexed auctionId,
        address indexed partner,
        address indexed newVault
    );
    event MaxPriceIncreased(
        uint256 indexed auctionId,
        address indexed partner,
        uint128 newMax,
        uint128 additionalDeposit
    );
    event SlotExited(
        uint256 indexed auctionId, address indexed partner, uint128 refund
    );
    event SlotFilled(
        uint256 indexed auctionId,
        address indexed partner,
        uint96 requested,
        uint96 allocated,
        uint256 cost
    );
    event SlotExcluded(
        uint256 indexed auctionId, address indexed partner, uint256 refund
    );
    event BufferUsed(
        uint256 indexed auctionId,
        address indexed vault,
        uint96 weight,
        uint256 cost
    );
    event RoundTriggered(
        uint256 indexed auctionId, uint128 claimPrice, uint256 tokenId
    );
    event RoundExpired(uint256 indexed auctionId);
    event RoundCompleted(uint256 indexed auctionId);
    event RefundClaimed(address indexed partner, uint256 amount);
    event SlotNFTSet(address indexed slotNFT);
    event SlotNFTMinted(
        uint256 indexed tokenId,
        uint256 indexed auctionId,
        address indexed originalPartner,
        address vault,
        uint96 allocatedWeight,
        uint96 requestedWeight,
        uint128 clearingPrice,
        uint256 expiryTimestamp,
        bool isPartialFill
    );

    // ── Setup ──────────────────────────────────────────────────────────────

    function setUp() public {
        governance = address(this);
        keeper = makeAddr("keeper");
        partner1 = makeAddr("partner1");
        partner2 = makeAddr("partner2");
        partner3 = makeAddr("partner3");
        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");
        vault3 = makeAddr("vault3");
        bufferVault = makeAddr("bufferVault");

        paymentToken = new MockPaymentToken();
        chef = new MockBeraChef();
        manager = new MockCuttingBoardManager();

        // Resolve circular dep: mock auction needs NFT, NFT needs auction address
        auction =
            new MockDutchAuction(address(paymentToken), ALLOCATION_DURATION);
        nft = new CuttingBoardNFT(
            address(auction), governance, address(manager), ""
        );
        auction.setNFT(address(nft));

        // Whitelist vaults
        chef.setWhitelistedVault(vault1, true);
        chef.setWhitelistedVault(vault2, true);
        chef.setWhitelistedVault(vault3, true);
        chef.setWhitelistedVault(bufferVault, true);

        // Deploy syndicate proxy
        CuttingBoardSyndicate impl = new CuttingBoardSyndicate();
        syndicate = CuttingBoardSyndicate(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        CuttingBoardSyndicate.initialize,
                        CuttingBoardSyndicate.InitParams({
                            dutchAuction: address(auction),
                            controlManager: address(manager),
                            controlNFT: address(nft),
                            chef: address(chef),
                            governance: governance,
                            keeper: keeper,
                            minSlotWeight: MIN_SLOT_WEIGHT
                        })
                    )
                )
            )
        );

        // Deploy SlotNFT (real contract) and connect to syndicate
        slotNFT = new CuttingBoardSlotNFT(address(syndicate), governance, "");
        syndicate.setSlotNFT(address(slotNFT));

        // Fund participants with generous token balances
        paymentToken.mint(partner1, 1_000_000e18);
        paymentToken.mint(partner2, 1_000_000e18);
        paymentToken.mint(partner3, 1_000_000e18);
        paymentToken.mint(governance, 1_000_000e18);

        // Infinite approvals from each participant to syndicate
        vm.prank(partner1);
        paymentToken.approve(address(syndicate), type(uint256).max);
        vm.prank(partner2);
        paymentToken.approve(address(syndicate), type(uint256).max);
        vm.prank(partner3);
        paymentToken.approve(address(syndicate), type(uint256).max);
        paymentToken.approve(address(syndicate), type(uint256).max); // governance (this)
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    /// Configure a fresh auction and open the syndicate round.
    function _openRound(uint256 auctionId) internal {
        auction.configure(auctionId, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        syndicate.openRound(auctionId);
    }

    function _openRoundWithPrice(uint256 auctionId, uint256 price) internal {
        auction.configure(auctionId, true, VALIDATOR_PUBKEY, price);
        syndicate.openRound(auctionId);
    }

    function _register(
        uint256 auctionId,
        address partner,
        address vault,
        uint96 weight,
        uint128 maxPrice
    ) internal {
        vm.prank(partner);
        syndicate.registerSlot(auctionId, vault, weight, maxPrice);
    }

    /// Set buffer vault (governance) and deposit `amount` from governance account.
    function _setBufferAndDeposit(uint256 amount) internal {
        syndicate.setBufferVault(bufferVault);
        syndicate.depositBuffer(amount);
    }

    /// Set up a round where 2 partners fill all 10 000 bps with no rounding dust.
    /// price = DEFAULT_PRICE = 1000e18, perBps = 0.1e18, exact divisions guaranteed.
    function _fullFillSetup(uint256 auctionId) internal {
        _openRound(auctionId);
        // partner1: 6000 bps @ 0.1e18/bps → deposit = 0.1e18 * 6000 = 600e18
        _register(
            auctionId, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS)
        );
        // partner2: 4000 bps @ 0.1e18/bps → deposit = 0.1e18 * 4000 = 400e18
        _register(
            auctionId, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS)
        );
    }

    /// Trigger a claim on the given auctionId (assumes conditions are met).
    function _triggerClaim(uint256 auctionId) internal {
        syndicate.triggerClaim(auctionId);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_success() public view {
        assertEq(address(syndicate.dutchAuction()), address(auction));
        assertEq(address(syndicate.controlManager()), address(manager));
        assertEq(address(syndicate.controlNFT()), address(nft));
        assertEq(address(syndicate.chef()), address(chef));
        assertEq(address(syndicate.paymentToken()), address(paymentToken));
        assertEq(syndicate.minSlotWeight(), MIN_SLOT_WEIGHT);
        assertEq(syndicate.bufferVault(), address(0));
        assertEq(syndicate.bufferDeposit(), 0);
        assertFalse(syndicate.paused());
    }

    function test_initialize_rolesGranted() public view {
        assertTrue(
            syndicate.hasRole(syndicate.DEFAULT_ADMIN_ROLE(), governance)
        );
        assertTrue(syndicate.hasRole(syndicate.GOVERNANCE_ROLE(), governance));
        assertTrue(syndicate.hasRole(syndicate.KEEPER_ROLE(), keeper));
    }

    function test_initialize_revert_zeroKeeper() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(manager),
                    controlNFT: address(nft),
                    chef: address(chef),
                    governance: governance,
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_defaultMinSlotWeight() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        CuttingBoardSyndicate s2 = CuttingBoardSyndicate(
            address(
                new ERC1967Proxy(
                    address(impl2),
                    abi.encodeCall(
                        CuttingBoardSyndicate.initialize,
                        CuttingBoardSyndicate.InitParams({
                            dutchAuction: address(auction),
                            controlManager: address(manager),
                            controlNFT: address(nft),
                            chef: address(chef),
                            governance: governance,
                            keeper: keeper,
                            minSlotWeight: 0 // should default to 100
                        })
                    )
                )
            )
        );
        assertEq(s2.minSlotWeight(), 100);
    }

    function test_initialize_revert_zeroAuction() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(0),
                    controlManager: address(manager),
                    controlNFT: address(nft),
                    chef: address(chef),
                    governance: governance,
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_revert_zeroManager() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(0),
                    controlNFT: address(nft),
                    chef: address(chef),
                    governance: governance,
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_revert_zeroNFT() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(manager),
                    controlNFT: address(0),
                    chef: address(chef),
                    governance: governance,
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_revert_zeroChef() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(manager),
                    controlNFT: address(nft),
                    chef: address(0),
                    governance: governance,
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_revert_zeroGovernance() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(manager),
                    controlNFT: address(nft),
                    chef: address(chef),
                    governance: address(0),
                    keeper: address(0),
                    minSlotWeight: MIN_SLOT_WEIGHT
                })
            )
        );
    }

    function test_initialize_revert_invalidMinSlotWeight_300() public {
        CuttingBoardSyndicate impl2 = new CuttingBoardSyndicate();
        vm.expectRevert(CuttingBoardSyndicate.InvalidMinSlotWeight.selector);
        new ERC1967Proxy(
            address(impl2),
            abi.encodeCall(
                CuttingBoardSyndicate.initialize,
                CuttingBoardSyndicate.InitParams({
                    dutchAuction: address(auction),
                    controlManager: address(manager),
                    controlNFT: address(nft),
                    chef: address(chef),
                    governance: governance,
                    keeper: keeper,
                    minSlotWeight: 300 // not a divisor of 10000
                })
            )
        );
    }

    function test_initialize_erc7201StorageSlot() public pure {
        assertEq(
            keccak256(
                abi.encode(
                    uint256(keccak256("infrared.storage.CuttingBoardSyndicate"))
                        - 1
                )
            ) & ~bytes32(uint256(0xff)),
            0xfc0b30dd43c7ca556e4ca78929e2b1fe291ff15419dda9ea9db08f129f339e00
        );
    }

    /*//////////////////////////////////////////////////////////////
                        SET BUFFER VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setBufferVault_success() public {
        vm.expectEmit(true, false, false, false);
        emit BufferVaultSet(bufferVault);
        syndicate.setBufferVault(bufferVault);
        assertEq(syndicate.bufferVault(), bufferVault);
    }

    function test_setBufferVault_clearWithZeroAddress() public {
        syndicate.setBufferVault(bufferVault);
        vm.expectEmit(true, false, false, false);
        emit BufferVaultSet(address(0));
        syndicate.setBufferVault(address(0));
        assertEq(syndicate.bufferVault(), address(0));
    }

    function test_setBufferVault_revert_notGovernance() public {
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.setBufferVault(bufferVault);
    }

    function test_setBufferVault_revert_notWhitelisted() public {
        address notListed = makeAddr("notListed");
        vm.expectRevert(CuttingBoardSyndicate.VaultNotWhitelisted.selector);
        syndicate.setBufferVault(notListed);
    }

    function test_setBufferVault_revert_duplicatePartnerVault_openRound()
        public
    {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        // Governance tries to set buffer vault to vault1 (held by partner1)
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, vault1
            )
        );
        syndicate.setBufferVault(vault1);
    }

    function test_setBufferVault_allowsNonConflictingVault_openRound() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        // vault2 is not registered by any partner — should succeed
        syndicate.setBufferVault(vault2);
        assertEq(syndicate.bufferVault(), vault2);
    }

    function test_setBufferVault_noOpenRound_noDuplicateCheck() public {
        // No round is open, so setting buffer to any whitelisted vault is fine
        // even if it would conflict with a partner vault in a hypothetical round
        syndicate.setBufferVault(vault1);
        assertEq(syndicate.bufferVault(), vault1);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW BUFFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawBuffer_success() public {
        syndicate.depositBuffer(500e18);
        uint256 balBefore = paymentToken.balanceOf(partner1);
        vm.expectEmit(true, false, false, true);
        emit BufferWithdrawn(partner1, 500e18);
        syndicate.withdrawBuffer(partner1, 500e18);
        assertEq(paymentToken.balanceOf(partner1), balBefore + 500e18);
        assertEq(syndicate.bufferDeposit(), 0);
    }

    function test_withdrawBuffer_partial() public {
        syndicate.depositBuffer(500e18);
        syndicate.withdrawBuffer(partner1, 200e18);
        assertEq(syndicate.bufferDeposit(), 300e18);
    }

    function test_withdrawBuffer_revert_zeroAddress() public {
        syndicate.depositBuffer(100e18);
        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        syndicate.withdrawBuffer(address(0), 100e18);
    }

    function test_withdrawBuffer_revert_underflow() public {
        syndicate.depositBuffer(100e18);
        vm.expectRevert();
        syndicate.withdrawBuffer(partner1, 200e18);
    }

    function test_withdrawBuffer_revert_notGovernance() public {
        syndicate.depositBuffer(100e18);
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.withdrawBuffer(partner1, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        SET MIN SLOT WEIGHT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMinSlotWeight_success_100() public {
        vm.expectEmit(false, false, false, true);
        emit MinSlotWeightSet(100);
        syndicate.setMinSlotWeight(100);
        assertEq(syndicate.minSlotWeight(), 100);
    }

    function test_setMinSlotWeight_success_200() public {
        syndicate.setMinSlotWeight(200);
        assertEq(syndicate.minSlotWeight(), 200);
    }

    function test_setMinSlotWeight_success_500() public {
        syndicate.setMinSlotWeight(500);
        assertEq(syndicate.minSlotWeight(), 500);
    }

    function test_setMinSlotWeight_success_1000() public {
        syndicate.setMinSlotWeight(1000);
        assertEq(syndicate.minSlotWeight(), 1000);
    }

    function test_setMinSlotWeight_success_10000() public {
        syndicate.setMinSlotWeight(10000);
        assertEq(syndicate.minSlotWeight(), 10000);
    }

    function test_setMinSlotWeight_revert_zero() public {
        vm.expectRevert(CuttingBoardSyndicate.InvalidMinSlotWeight.selector);
        syndicate.setMinSlotWeight(0);
    }

    function test_setMinSlotWeight_revert_notDivisor_300() public {
        vm.expectRevert(CuttingBoardSyndicate.InvalidMinSlotWeight.selector);
        syndicate.setMinSlotWeight(300);
    }

    function test_setMinSlotWeight_revert_notDivisor_700() public {
        vm.expectRevert(CuttingBoardSyndicate.InvalidMinSlotWeight.selector);
        syndicate.setMinSlotWeight(700);
    }

    function test_setMinSlotWeight_revert_notGovernance() public {
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.setMinSlotWeight(200);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT BUFFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositBuffer_success() public {
        uint256 amount = 500e18;
        uint256 balBefore = paymentToken.balanceOf(governance);
        vm.expectEmit(true, false, false, true);
        emit BufferDeposited(governance, amount);
        syndicate.depositBuffer(amount);
        assertEq(syndicate.bufferDeposit(), amount);
        assertEq(paymentToken.balanceOf(governance), balBefore - amount);
        assertEq(paymentToken.balanceOf(address(syndicate)), amount);
    }

    function test_depositBuffer_accumulates() public {
        syndicate.depositBuffer(100e18);
        syndicate.depositBuffer(200e18);
        assertEq(syndicate.bufferDeposit(), 300e18);
    }

    function test_depositBuffer_permissionless() public {
        vm.prank(partner1);
        paymentToken.approve(address(syndicate), type(uint256).max);
        vm.prank(partner1);
        syndicate.depositBuffer(100e18);
        assertEq(syndicate.bufferDeposit(), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN ROUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_openRound_success() public {
        auction.configure(0, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        bytes32 expectedHash = keccak256(VALIDATOR_PUBKEY);
        vm.expectEmit(true, true, false, false);
        emit RoundOpened(0, expectedHash);
        syndicate.openRound(0);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.validatorHash, expectedHash);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Open)
        );
        assertEq(r.claimPrice, 0);
        assertEq(r.tokenId, 0);
    }

    function test_openRound_storesCorrectValidatorHash() public {
        auction.configure(0, true, VALIDATOR_PUBKEY_2, DEFAULT_PRICE);
        syndicate.openRound(0);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.validatorHash, keccak256(VALIDATOR_PUBKEY_2));
    }

    function test_openRound_revert_alreadyOpen() public {
        _openRound(0);
        vm.expectRevert(CuttingBoardSyndicate.RoundAlreadyExists.selector);
        syndicate.openRound(0);
    }

    function test_openRound_revert_alreadyActive() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        vm.expectRevert(CuttingBoardSyndicate.RoundAlreadyExists.selector);
        syndicate.openRound(0);
    }

    function test_openRound_revert_auctionNotActive() public {
        auction.configure(0, false, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        vm.expectRevert(CuttingBoardSyndicate.AuctionNotActive.selector);
        syndicate.openRound(0);
    }

    function test_openRound_revert_paused() public {
        auction.configure(0, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        syndicate.pause();
        vm.expectRevert();
        syndicate.openRound(0);
    }

    function test_openRound_multipleDifferentAuctions() public {
        auction.configure(0, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        auction.configure(1, true, VALIDATOR_PUBKEY_2, DEFAULT_PRICE);
        syndicate.openRound(0);
        syndicate.openRound(1);

        CuttingBoardSyndicateLib.Round memory r0 = syndicate.getRound(0);
        CuttingBoardSyndicateLib.Round memory r1 = syndicate.getRound(1);
        assertEq(
            uint8(r0.state), uint8(CuttingBoardSyndicateLib.RoundState.Open)
        );
        assertEq(
            uint8(r1.state), uint8(CuttingBoardSyndicateLib.RoundState.Open)
        );
        assertNotEq(r0.validatorHash, r1.validatorHash);
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTER SLOT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerSlot_success() public {
        _openRound(0);
        uint128 maxPrice = uint128(DEFAULT_PRICE_PER_BPS);
        uint96 weight = 5000;
        uint128 expectedDeposit = uint128(uint256(maxPrice) * weight);

        uint256 balBefore = paymentToken.balanceOf(partner1);
        vm.expectEmit(true, true, true, true);
        emit SlotRegistered(
            0, partner1, vault1, weight, maxPrice, expectedDeposit
        );
        vm.prank(partner1);
        syndicate.registerSlot(0, vault1, weight, maxPrice);

        assertEq(paymentToken.balanceOf(partner1), balBefore - expectedDeposit);
        assertEq(paymentToken.balanceOf(address(syndicate)), expectedDeposit);

        CuttingBoardSyndicateLib.Slot memory slot =
            syndicate.getSlot(0, partner1);
        assertEq(slot.weight, weight);
        assertEq(slot.maxPricePerBps, maxPrice);
        assertEq(slot.vault, vault1);
        assertEq(slot.deposit, expectedDeposit);
        assertEq(slot.allocatedWeight, 0);

        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, 1);
        assertEq(partners[0], partner1);
    }

    function test_registerSlot_twoPartners() public {
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, 2);
    }

    function test_registerSlot_revert_notOpen_idle() public {
        // Round is Idle (never opened)
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.registerSlot(0, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_revert_notOpen_active() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        vm.prank(partner3);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.registerSlot(0, vault3, 5000, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_revert_slotAlreadyExists() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.SlotAlreadyExists.selector);
        syndicate.registerSlot(0, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_revert_insufficientMaxPrice() public {
        // Set auction minimum so minimumPrice/10000 > 0
        auction.setMinimumPrice(10000e18); // minimumPricePerBps = 1e18
        _openRound(0);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.InsufficientMaxPrice.selector);
        syndicate.registerSlot(0, vault1, 5000, 0); // 0 < 1e18
    }

    function test_registerSlot_revert_zeroWeight() public {
        _openRound(0);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.InvalidWeight.selector);
        syndicate.registerSlot(0, vault1, 0, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_revert_weightNotMultipleOfMin() public {
        _openRound(0);
        // MIN_SLOT_WEIGHT = 100; 150 is not a multiple
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.InvalidWeight.selector);
        syndicate.registerSlot(0, vault1, 150, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_revert_weightExceedsMaxPerVault() public {
        _openRound(0);
        // maxWeightPerVault = 10000; requesting 10001 exceeds it
        chef.setMaxWeightPerVault(5000);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.InvalidWeight.selector);
        syndicate.registerSlot(0, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_registerSlot_allowsManyPartners() public {
        // TooManyPartners is now checked at triggerClaim, not registerSlot.
        // Registration should succeed even if we exceed the eventual limit.
        _openRound(0);
        chef.setMaxNumWeightsPerRewardAllocation(3); // max 2 partners + 1 buffer
        _register(0, partner1, vault1, 100, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 100, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner3, vault3, 100, uint128(DEFAULT_PRICE_PER_BPS));
        // All three registered successfully
        assertEq(syndicate.getPartners(0).length, 3);
    }

    function test_registerSlot_revert_vaultNotWhitelisted() public {
        _openRound(0);
        address notListed = makeAddr("notListed");
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.VaultNotWhitelisted.selector);
        syndicate.registerSlot(
            0, notListed, 5000, uint128(DEFAULT_PRICE_PER_BPS)
        );
    }

    function test_registerSlot_revert_duplicateVault_isBufferVault() public {
        _openRound(0);
        syndicate.setBufferVault(bufferVault);
        vm.prank(partner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, bufferVault
            )
        );
        syndicate.registerSlot(
            0, bufferVault, 5000, uint128(DEFAULT_PRICE_PER_BPS)
        );
    }

    function test_registerSlot_duplicateVault_allowed() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        // Second partner can register the same vault; resolved at trigger time
        _register(0, partner2, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        CuttingBoardSyndicateLib.Slot memory slot1 =
            syndicate.getSlot(0, partner1);
        CuttingBoardSyndicateLib.Slot memory slot2 =
            syndicate.getSlot(0, partner2);
        assertEq(slot1.vault, vault1);
        assertEq(slot2.vault, vault1);
    }

    function test_registerSlot_revert_paused() public {
        _openRound(0);
        syndicate.pause();
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.registerSlot(0, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
    }

    /*//////////////////////////////////////////////////////////////
                        UPDATE SLOT VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSlotVault_success_openState() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        vm.expectEmit(true, true, true, false);
        emit SlotVaultUpdated(0, partner1, vault2);
        vm.prank(partner1);
        syndicate.updateSlotVault(0, vault2);

        CuttingBoardSyndicateLib.Slot memory slot =
            syndicate.getSlot(0, partner1);
        assertEq(slot.vault, vault2);
    }

    function test_updateSlotVault_success_activeState() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        uint256 tokenId = slotNFT.getTokenId(0, partner1);

        // After trigger, state is Active — partner (still NFT holder) can update vault
        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        assertEq(syndicate.getSlot(0, partner1).vault, vault3);
        // SlotNFT metadata kept in sync
        assertEq(slotNFT.getSlotRights(tokenId).vault, vault3);
    }

    function test_updateSlotVault_revert_idleState() public {
        // No round opened — 2-param overload requires Open state
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.updateSlotVault(0, vault2);
    }

    function test_updateSlotVault_revert_expiredState() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.updateSlotVault(0, vault2);
    }

    function test_updateSlotVault_revert_noSlot() public {
        _openRound(0);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NoSlot.selector);
        syndicate.updateSlotVault(0, vault2);
    }

    function test_updateSlotVault_revert_notWhitelisted() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        address notListed = makeAddr("notListed");
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.VaultNotWhitelisted.selector);
        syndicate.updateSlotVault(0, notListed);
    }

    function test_updateSlotVault_revert_bufferVault() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        syndicate.setBufferVault(bufferVault);

        vm.prank(partner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, bufferVault
            )
        );
        syndicate.updateSlotVault(0, bufferVault);
    }

    function test_updateSlotVault_duplicatePartnerVault_allowedInOpen()
        public
    {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        // partner1 can switch to vault2 in Open state; resolved at trigger time
        vm.prank(partner1);
        syndicate.updateSlotVault(0, vault2);

        CuttingBoardSyndicateLib.Slot memory slot =
            syndicate.getSlot(0, partner1);
        assertEq(slot.vault, vault2);
    }

    function test_updateSlotVault_revert_paused() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        syndicate.pause();

        vm.prank(partner1);
        vm.expectRevert();
        syndicate.updateSlotVault(0, vault2);
    }

    /*//////////////////////////////////////////////////////////////
                        INCREASE MAX PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_increaseMaxPrice_success() public {
        _openRound(0);
        uint128 initPerBps = 0.05e18; // 500e18 whole-board / 10000
        _register(0, partner1, vault1, 5000, initPerBps);

        uint128 newMax = 0.1e18; // 1000e18 whole-board / 10000
        uint128 oldDeposit = uint128(uint256(initPerBps) * 5000); // 250e18
        uint128 newDeposit = uint128(uint256(newMax) * 5000); // 500e18
        uint128 additional = newDeposit - oldDeposit; // 250e18

        uint256 balBefore = paymentToken.balanceOf(partner1);
        vm.expectEmit(true, true, false, true);
        emit MaxPriceIncreased(0, partner1, newMax, additional);
        vm.prank(partner1);
        syndicate.increaseMaxPrice(0, newMax);

        assertEq(paymentToken.balanceOf(partner1), balBefore - additional);

        CuttingBoardSyndicateLib.Slot memory slot =
            syndicate.getSlot(0, partner1);
        assertEq(slot.maxPricePerBps, newMax);
        assertEq(slot.deposit, newDeposit);
    }

    function test_increaseMaxPrice_revert_notOpen() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.increaseMaxPrice(0, uint128(DEFAULT_PRICE_PER_BPS) * 2);
    }

    function test_increaseMaxPrice_revert_noSlot() public {
        _openRound(0);
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NoSlot.selector);
        syndicate.increaseMaxPrice(0, uint128(DEFAULT_PRICE_PER_BPS));
    }

    function test_increaseMaxPrice_revert_mustIncrease_equal() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.MaxPriceMustIncrease.selector);
        syndicate.increaseMaxPrice(0, uint128(DEFAULT_PRICE_PER_BPS)); // same value
    }

    function test_increaseMaxPrice_revert_mustIncrease_lower() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.MaxPriceMustIncrease.selector);
        syndicate.increaseMaxPrice(0, uint128(DEFAULT_PRICE_PER_BPS) - 1);
    }

    function test_increaseMaxPrice_revert_paused() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        syndicate.pause();
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.increaseMaxPrice(0, uint128(DEFAULT_PRICE_PER_BPS) * 2);
    }

    /*//////////////////////////////////////////////////////////////
                        TRIGGER CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_triggerClaim_fullFill_success() public {
        _fullFillSetup(0);

        // No buffer needed (exact fill, no rounding)
        vm.expectEmit(true, true, false, true);
        emit SlotFilled(0, partner1, 6000, 6000, DEFAULT_PRICE * 6000 / 10000);
        vm.expectEmit(true, true, false, true);
        emit SlotFilled(0, partner2, 4000, 4000, DEFAULT_PRICE * 4000 / 10000);
        vm.expectEmit(true, false, false, false);
        emit RoundTriggered(0, uint128(DEFAULT_PRICE), 1);
        _triggerClaim(0);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
        assertEq(r.claimPrice, DEFAULT_PRICE);
        assertEq(r.tokenId, 1); // first NFT minted
    }

    function test_triggerClaim_stateBecomesActive() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
    }

    function test_triggerClaim_syndicateOwnsNFT() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        // Token ID 1 is minted to the syndicate
        assertEq(nft.ownerOf(1), address(syndicate));
    }

    function test_triggerClaim_partnerExcessRefunded() public {
        // partner1 bids at 0.2e18/bps but only pays currentPrice/10000 = 0.1e18/bps
        _openRound(0);
        _register(0, partner1, vault1, 6000, 0.2e18); // deposit = 0.2e18 * 6000 = 1200e18
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS)); // deposit = 400e18

        _triggerClaim(0);

        // partner1 cost = 1000e18 * 6000/10000 = 600e18
        // partner1 refund = 1200e18 - 600e18 = 600e18
        assertEq(syndicate.getPendingRefund(partner1), 600e18);
        // partner2 cost = 400e18, deposit = 400e18, refund = 0
        assertEq(syndicate.getPendingRefund(partner2), 0);
    }

    function test_triggerClaim_excludedPartner_refundedFull() public {
        // Arrange: partner1 eligible, partner2 excluded (maxPricePerBps*10000 < currentPrice)
        _openRound(0);
        uint256 price = 800e18;
        auction.setPrice(0, price);
        _register(0, partner1, vault1, 6000, 0.1e18); // eligible: 0.1e18*10000=1000e18 >= 800e18
        _register(0, partner2, vault2, 4000, 0.05e18); // excluded: 0.05e18*10000=500e18 < 800e18

        _setBufferAndDeposit(500e18); // buffer absorbs the 4000 bps

        _triggerClaim(0);

        // partner2 is excluded, gets full deposit refunded
        uint256 p2Deposit = uint256(0.05e18) * 4000; // 200e18
        assertEq(syndicate.getPendingRefund(partner2), p2Deposit);

        // Slot fills event: partner1 only
        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        assertEq(s1.allocatedWeight, 6000);

        CuttingBoardSyndicateLib.Slot memory s2 = syndicate.getSlot(0, partner2);
        assertEq(s2.allocatedWeight, 0); // excluded
    }

    function test_triggerClaim_priorityOrdering() public {
        // partner1: weight=4000, maxPricePerBps=0.3e18 → bid=1200e18 (highest)
        // partner2: weight=3000, maxPricePerBps=0.2e18 → bid=600e18 (lowest)
        // partner3: weight=3000, maxPricePerBps=0.3e18 → bid=900e18 (middle)
        // Expected fill order: partner1, partner3, partner2
        uint256 currentPrice = 2000e18;
        _openRoundWithPrice(0, currentPrice);
        _register(0, partner1, vault1, 4000, 0.3e18); // eligible: 0.3e18*10000=3000e18 >= 2000e18
        _register(0, partner2, vault2, 3000, 0.2e18); // eligible: 0.2e18*10000=2000e18 >= 2000e18
        _register(0, partner3, vault3, 3000, 0.3e18);

        _triggerClaim(0);

        // All fill: 4000 + 3000 + 3000 = 10000, buffer = 0
        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        CuttingBoardSyndicateLib.Slot memory s2 = syndicate.getSlot(0, partner2);
        CuttingBoardSyndicateLib.Slot memory s3 = syndicate.getSlot(0, partner3);

        assertEq(s1.allocatedWeight, 4000);
        assertEq(s2.allocatedWeight, 3000);
        assertEq(s3.allocatedWeight, 3000);

        // partner1 cost = 2000e18 * 4000/10000 = 800e18; deposit = 0.3e18 * 4000 = 1200e18; refund = 400e18
        assertEq(syndicate.getPendingRefund(partner1), 400e18);
        // partner2 cost = 600e18; deposit = 0.2e18 * 3000 = 600e18; refund = 0
        assertEq(syndicate.getPendingRefund(partner2), 0);
        // partner3 cost = 600e18; deposit = 0.3e18 * 3000 = 900e18; refund = 300e18
        assertEq(syndicate.getPendingRefund(partner3), 300e18);
    }

    function test_triggerClaim_partialFill_lastPartner() public {
        // partner2 has the highest bid value and requests more bps than remain after partner1
        // partner2: weight=8000, perBps=0.1e18, bid= 8000*0.1e18=800e18 (higher)
        // partner1: weight=3000, perBps=0.1e18, bid= 3000*0.1e18=300e18 (lower)
        // At currentPrice=500e18, both eligible (0.1e18*10000=1000e18 >= 500e18).
        // Fill order: partner2 first (higher bid)
        // partner2 gets 8000; remaining = 2000; partner1 requested 3000 → partial alloc = 2000
        uint256 currentPrice = 500e18;
        _openRoundWithPrice(0, currentPrice);
        _register(0, partner1, vault1, 3000, 0.1e18);
        _register(0, partner2, vault2, 8000, 0.1e18);

        _triggerClaim(0);

        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        CuttingBoardSyndicateLib.Slot memory s2 = syndicate.getSlot(0, partner2);

        assertEq(s2.allocatedWeight, 8000); // gets full request
        assertEq(s1.allocatedWeight, 2000); // partial fill

        // partner1 deposit = 0.1e18 * 3000 = 300e18
        // partner1 cost = 500e18 * 2000/10000 = 100e18
        // partner1 refund = 300e18 - 100e18 = 200e18
        assertEq(syndicate.getPendingRefund(partner1), 200e18);
    }

    function test_triggerClaim_bufferAbsorbsRemainder() public {
        // Only partner1 with 6000 bps; buffer absorbs 4000 bps
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18); // fund buffer generously

        _triggerClaim(0);

        assertEq(syndicate.getRoundBufferAllocated(0), 4000);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.bufferVault, bufferVault);
    }

    function test_triggerClaim_bufferVaultSnapshotted() public {
        // Set up a scenario where buffer gets some bps
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);

        _triggerClaim(0);

        // Even after governance changes the live bufferVault, the round retains the snapshot
        address newBuf = makeAddr("newBuf");
        chef.setWhitelistedVault(newBuf, true);
        syndicate.setBufferVault(newBuf);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.bufferVault, bufferVault); // old snapshot unchanged
    }

    function test_triggerClaim_roundingDust_requiresBufferDeposit() public {
        // Use price=3 wei: two partners each with 5000 bps
        // partnerTotal = floor(3*5000/10000) * 2 = 1+1 = 2; bufferRequired = 1 (dust)
        // bfWeight = 0 so bufferVault doesn't need to be set
        uint256 dustPrice = 3;
        uint128 perBps = 1; // 1*10000=10000 >= 3 → eligible; deposit = 1*5000=5000 wei
        _openRoundWithPrice(0, dustPrice);
        paymentToken.mint(address(this), 100_000); // fund for dust + deposits
        _register(0, partner1, vault1, 5000, perBps);
        _register(0, partner2, vault2, 5000, perBps);

        // Without buffer deposit, should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.InsufficientBuffer.selector, 1, 0
            )
        );
        _triggerClaim(0);

        // Deposit 1 wei of buffer (bufferVault not needed since bfWeight = 0)
        syndicate.depositBuffer(1);
        _triggerClaim(0); // should succeed now

        assertEq(syndicate.getRoundBufferAllocated(0), 0);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
    }

    function test_triggerClaim_revert_notOpen_idle() public {
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_notOpen_alreadyActive() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_noBidders() public {
        // All partners have maxPricePerBps*10000 below currentPrice
        _openRound(0);
        _register(0, partner1, vault1, 5000, 0.05e18); // 0.05e18*10000=500e18 < 1000e18
        _setBufferAndDeposit(1_000e18);

        // At currentPrice = DEFAULT_PRICE = 1000e18, partner1 is not eligible
        vm.expectRevert(CuttingBoardSyndicate.NoBidders.selector);
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_noBufferVault() public {
        // Partner only fills 6000 bps; buffer needs 4000 bps but bufferVault not set
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));

        vm.expectRevert(CuttingBoardSyndicate.NoBufferVault.selector);
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_insufficientBuffer() public {
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        syndicate.setBufferVault(bufferVault);
        // bufferRequired = price - floor(price*6000/10000) = 1000e18 - 600e18 = 400e18

        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.InsufficientBuffer.selector,
                DEFAULT_PRICE - (DEFAULT_PRICE * 6000 / 10000),
                0
            )
        );
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_bufferWeightExceedsMax() public {
        // Register partner1 with weight=3000 (buffer would absorb the remaining 7000 bps).
        // After registration, lower maxWeightPerVault to 5000 so that bufferWeight 7000 > 5000.
        _openRound(0);
        _register(0, partner1, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);

        chef.setMaxWeightPerVault(5000); // lower cap AFTER registration

        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.BufferWeightExceedsMax.selector,
                7000,
                5000
            )
        );
        _triggerClaim(0);
    }

    function test_triggerClaim_revert_paused() public {
        _fullFillSetup(0);
        syndicate.pause();
        vm.expectRevert();
        _triggerClaim(0);
    }

    function test_triggerClaim_bufferDepositReduced() public {
        uint256 initialBuffer = 600e18;
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS)); // buffer gets 5000
        _setBufferAndDeposit(initialBuffer);

        // bufferRequired = price - floor(price*5000/10000) = 1000e18 - 500e18 = 500e18
        uint256 bufferRequired = DEFAULT_PRICE - (DEFAULT_PRICE * 5000 / 10000);
        _triggerClaim(0);

        assertEq(syndicate.bufferDeposit(), initialBuffer - bufferRequired);
    }

    /*//////////////////////////////////////////////////////////////
                        EXPIRE ROUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_expireRound_success() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        // Expire the auction
        auction.setActive(0, false);

        vm.expectEmit(true, false, false, false);
        emit RoundExpired(0);
        syndicate.expireRound(0);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Expired)
        );
    }

    function test_expireRound_refundsAllPartners() public {
        _openRound(0);
        uint128 maxP1 = uint128(DEFAULT_PRICE_PER_BPS); // 0.1e18
        uint128 maxP2 = 0.05e18;
        _register(0, partner1, vault1, 6000, maxP1);
        _register(0, partner2, vault2, 4000, maxP2);

        uint256 deposit1 = uint256(maxP1) * 6000; // 600e18
        uint256 deposit2 = uint256(maxP2) * 4000; // 200e18

        auction.setActive(0, false);
        syndicate.expireRound(0);

        assertEq(syndicate.getPendingRefund(partner1), deposit1);
        assertEq(syndicate.getPendingRefund(partner2), deposit2);
    }

    function test_expireRound_clearsPartnersAndWeights() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        auction.setActive(0, false);
        syndicate.expireRound(0);

        assertEq(syndicate.getPartners(0).length, 0);
    }

    function test_expireRound_bufferDepositUnchanged() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(200e18);

        auction.setActive(0, false);
        syndicate.expireRound(0);

        // Buffer rolls over and is NOT refunded
        assertEq(syndicate.bufferDeposit(), 200e18);
    }

    function test_expireRound_revert_notOpen_idle() public {
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.expireRound(0);
    }

    function test_expireRound_revert_notOpen_active() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        vm.expectRevert(CuttingBoardSyndicate.NotOpen.selector);
        syndicate.expireRound(0);
    }

    function test_expireRound_revert_auctionStillLive() public {
        _openRound(0);
        // Auction is still active
        vm.expectRevert(CuttingBoardSyndicate.AuctionStillLive.selector);
        syndicate.expireRound(0);
    }

    function test_expireRound_worksWhenPaused() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.pause();

        // Should still work (partners need to recover funds)
        syndicate.expireRound(0);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Expired)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claimRefund_success() public {
        // Set up a round where partner1 gets a refund after trigger
        _openRound(0);
        _register(0, partner1, vault1, 6000, 0.2e18); // deposit = 0.2e18 * 6000 = 1200e18
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));
        _triggerClaim(0);

        // partner1 refund = 1200e18 - 600e18 = 600e18
        uint256 refund = syndicate.getPendingRefund(partner1);
        assertGt(refund, 0);

        uint256 balBefore = paymentToken.balanceOf(partner1);
        vm.expectEmit(true, false, false, true);
        emit RefundClaimed(partner1, refund);
        vm.prank(partner1);
        syndicate.claimRefund(partner1);

        assertEq(paymentToken.balanceOf(partner1), balBefore + refund);
        assertEq(syndicate.getPendingRefund(partner1), 0);
    }

    function test_claimRefund_revert_nothingToRefund() public {
        vm.expectRevert(CuttingBoardSyndicate.NothingToRefund.selector);
        syndicate.claimRefund(partner1);
    }

    function test_claimRefund_worksWhenPaused() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        syndicate.pause();

        // Should still be able to claim refund when paused
        uint256 balBefore = paymentToken.balanceOf(partner1);
        syndicate.claimRefund(partner1);
        assertGt(paymentToken.balanceOf(partner1), balBefore);
    }

    function test_claimRefund_onBehalf() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        uint256 refund = syndicate.getPendingRefund(partner1);
        uint256 balBefore = paymentToken.balanceOf(partner1);

        // partner2 pushes the refund for partner1
        vm.prank(partner2);
        syndicate.claimRefund(partner1);

        assertEq(paymentToken.balanceOf(partner1), balBefore + refund);
        assertEq(syndicate.getPendingRefund(partner1), 0);
    }

    function test_claimAllRefunds_sweepsAll() public {
        // Two partners both get refunds via expiry
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        uint256 r1 = syndicate.getPendingRefund(partner1);
        uint256 r2 = syndicate.getPendingRefund(partner2);
        assertGt(r1, 0);
        assertGt(r2, 0);

        uint256 bal1Before = paymentToken.balanceOf(partner1);
        uint256 bal2Before = paymentToken.balanceOf(partner2);

        syndicate.claimAllRefunds();

        assertEq(paymentToken.balanceOf(partner1), bal1Before + r1);
        assertEq(paymentToken.balanceOf(partner2), bal2Before + r2);
        assertEq(syndicate.getPendingRefund(partner1), 0);
        assertEq(syndicate.getPendingRefund(partner2), 0);
    }

    function test_claimAllRefunds_worksWhenPaused() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        syndicate.pause();
        syndicate.claimAllRefunds(); // should not revert
    }

    function test_claimAllRefunds_skipsZeroBalance() public {
        // Only partner1 has a refund
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        uint256 bal2Before = paymentToken.balanceOf(partner2);
        syndicate.claimAllRefunds();

        // partner2's balance unchanged (no refund)
        assertEq(paymentToken.balanceOf(partner2), bal2Before);
    }

    /*//////////////////////////////////////////////////////////////
                  AUTO-PROPOSAL (via updateSlotVault) TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSlotVault_active_autoProposal() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        uint256 controlTokenId = syndicate.getRound(0).tokenId;

        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        assertEq(manager.callCount(), 1, "proposal auto-submitted");
        assertEq(manager.lastTokenId(), controlTokenId);
    }

    function test_updateSlotVault_active_proposalWeightsReflectChange()
        public
    {
        _fullFillSetup(0);
        _triggerClaim(0);

        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        IBeraChef.Weight[] memory weights = manager.getLastWeights();
        bool foundVault3;
        bool foundVault2;
        for (uint256 i = 0; i < weights.length; i++) {
            if (weights[i].receiver == vault3) {
                assertEq(weights[i].percentageNumerator, 6000);
                foundVault3 = true;
            } else if (weights[i].receiver == vault2) {
                assertEq(weights[i].percentageNumerator, 4000);
                foundVault2 = true;
            }
        }
        assertTrue(foundVault3, "vault3 should replace vault1");
        assertTrue(foundVault2, "vault2 unchanged");
    }

    function test_updateSlotVault_active_revert_nftExpired() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.NFTExpiredOrInvalid.selector);
        syndicate.updateSlotVault(0, partner1, vault3);
    }

    function test_updateSlotVault_active_revert_paused() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        syndicate.pause();

        vm.prank(partner1);
        vm.expectRevert();
        syndicate.updateSlotVault(0, partner1, vault3);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_canTrigger_trueWhenConditionsMet() public {
        _fullFillSetup(0);
        assertTrue(syndicate.canTrigger(0));
    }

    function test_canTrigger_falseWhenNotOpen() public view {
        assertFalse(syndicate.canTrigger(0)); // Idle
    }

    function test_canTrigger_falseWhenNoBidders() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, 0.005e18); // 0.005e18*10000=50e18 << 1000e18
        // currentPrice = DEFAULT_PRICE = 1000e18 > 50e18 → not eligible
        assertFalse(syndicate.canTrigger(0));
    }

    function test_canTrigger_falseWhenInsufficientBuffer() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        syndicate.setBufferVault(bufferVault);
        // bufferRequired > 0 but bufferDeposit = 0
        assertFalse(syndicate.canTrigger(0));
    }

    function test_canTrigger_falseAfterTrigger() public {
        _fullFillSetup(0);
        _triggerClaim(0);
        assertFalse(syndicate.canTrigger(0)); // now Active
    }

    function test_previewFillAt_fullFill() public {
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        (
            address[] memory included,
            uint96[] memory allocations,
            uint256 count,
            uint96 bfWeight,
            uint256 bufferRequired
        ) = syndicate.previewFillAt(0, DEFAULT_PRICE);

        assertEq(count, 2);
        assertEq(bfWeight, 0);
        assertEq(bufferRequired, 0);
        assertEq(included.length, 2);
        assertEq(allocations.length, 2);

        // Verify total allocation = 10000
        uint96 total;
        for (uint256 i = 0; i < count; i++) {
            total += allocations[i];
        }
        assertEq(total, 10000);
    }

    function test_previewFillAt_withExcluded() public {
        _openRound(0);
        _register(0, partner1, vault1, 6000, 0.1e18); // 0.1e18*10000=1000e18 >= 500e18
        _register(0, partner2, vault2, 4000, 0.04e18); // 0.04e18*10000=400e18 < 500e18

        (, uint96[] memory allocations, uint256 count, uint96 bfWeight,) =
            syndicate.previewFillAt(0, 500e18);

        assertEq(count, 1); // only partner1
        assertEq(allocations[0], 6000);
        assertEq(bfWeight, 4000);
    }

    function test_getPendingRefund_returnsCorrectBalance() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        uint256 deposit = uint256(uint128(DEFAULT_PRICE_PER_BPS)) * 5000;
        assertEq(syndicate.getPendingRefund(partner1), deposit);
    }

    function test_getPendingRefunds_enumeratesNonZero() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        // Claim partner1's refund
        vm.prank(partner1);
        syndicate.claimRefund(partner1);

        // Now only partner2 has a balance
        (address[] memory users, uint256[] memory amounts) =
            syndicate.getPendingRefunds();

        assertEq(users.length, 1);
        assertEq(users[0], partner2);
        assertGt(amounts[0], 0);
    }

    function test_getRoundBufferAllocated_zeroBeforeTrigger() public {
        _openRound(0);
        assertEq(syndicate.getRoundBufferAllocated(0), 0);
    }

    function test_getRoundBufferAllocated_afterTrigger() public {
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        assertEq(syndicate.getRoundBufferAllocated(0), 4000);
    }

    function test_getPartners_orderPreserved() public {
        _openRound(0);
        _register(0, partner1, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner3, vault3, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners[0], partner1);
        assertEq(partners[1], partner2);
        assertEq(partners[2], partner3);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE / UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pause_byGovernance() public {
        syndicate.pause();
        assertTrue(syndicate.paused());
    }

    function test_unpause_byGovernance() public {
        syndicate.pause();
        syndicate.unpause();
        assertFalse(syndicate.paused());
    }

    function test_pause_revert_unauthorized() public {
        vm.prank(partner1);
        vm.expectRevert();
        syndicate.pause();
    }

    function test_unpause_revert_notGovernance() public {
        syndicate.pause();
        vm.prank(keeper);
        vm.expectRevert();
        syndicate.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         MULTI-ROUND INDEPENDENCE
    //////////////////////////////////////////////////////////////*/

    function test_multipleRounds_independent() public {
        // Round 0 and round 1 are fully independent; each fills exactly 10 000 bps.
        auction.configure(0, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        auction.configure(1, true, VALIDATOR_PUBKEY_2, DEFAULT_PRICE);

        syndicate.openRound(0);
        syndicate.openRound(1);

        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        // Round 1: 5000 + 5000 = 10 000 bps exactly (same vaults allowed across rounds)
        _register(1, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(1, partner2, vault2, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        _triggerClaim(0);

        // Round 0 active, round 1 still open
        assertEq(
            uint8(syndicate.getRound(0).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
        assertEq(
            uint8(syndicate.getRound(1).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Open)
        );

        _triggerClaim(1);

        assertEq(
            uint8(syndicate.getRound(1).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
    }

    function test_expireRound_thenOpenNewRoundDifferentId() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        auction.setActive(0, false);
        syndicate.expireRound(0);

        // Open a new round for a different auctionId
        auction.configure(1, true, VALIDATOR_PUBKEY, DEFAULT_PRICE);
        syndicate.openRound(1);
        assertEq(
            uint8(syndicate.getRound(1).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Open)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_depositCalculation(uint96 weight, uint128 maxPricePerBps_)
        public
    {
        // weight must be a valid multiple of minSlotWeight and <= maxWeightPerVault
        weight = uint96(bound(weight, 1, 100)) * MIN_SLOT_WEIGHT; // 100–10000 bps in multiples of 100
        // Cap maxPricePerBps so deposit = maxPricePerBps * weight doesn't overflow uint128
        maxPricePerBps_ =
            uint128(bound(maxPricePerBps_, 1, type(uint128).max / 10000));

        _openRound(0);
        uint256 expectedDeposit = uint256(maxPricePerBps_) * weight;

        paymentToken.mint(partner1, expectedDeposit + 1);
        vm.prank(partner1);
        paymentToken.approve(address(syndicate), type(uint256).max);

        vm.prank(partner1);
        syndicate.registerSlot(0, vault1, weight, maxPricePerBps_);

        CuttingBoardSyndicateLib.Slot memory slot =
            syndicate.getSlot(0, partner1);
        assertEq(slot.deposit, expectedDeposit);
    }

    function testFuzz_triggerClaim_twoPartnersTotalAlways10000(
        uint96 w1,
        uint96 w2
    ) public {
        // Constrain weights to valid multiples of MIN_SLOT_WEIGHT
        w1 = uint96(bound(w1, 1, 99)) * MIN_SLOT_WEIGHT;
        w2 = uint96(bound(w2, 1, 99)) * MIN_SLOT_WEIGHT;
        vm.assume(w1 + w2 <= 10000); // ensure valid total

        uint256 price = DEFAULT_PRICE;
        uint128 perBps = uint128(DEFAULT_PRICE_PER_BPS); // per-bps price
        _openRoundWithPrice(0, price);
        _register(0, partner1, vault1, w1, perBps);
        _register(0, partner2, vault2, w2, perBps);

        uint256 bfRequired = price - (price * w1 / 10000) - (price * w2 / 10000);
        if (bfRequired > 0) {
            _setBufferAndDeposit(bfRequired + price); // fund buffer generously
        }
        if (w1 + w2 < 10000 && syndicate.bufferVault() == address(0)) {
            syndicate.setBufferVault(bufferVault);
        }

        _triggerClaim(0);

        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        CuttingBoardSyndicateLib.Slot memory s2 = syndicate.getSlot(0, partner2);

        uint96 bfAlloc = syndicate.getRoundBufferAllocated(0);
        assertEq(
            uint256(s1.allocatedWeight) + s2.allocatedWeight + bfAlloc, 10000
        );
    }

    function testFuzz_bufferRequired_neverExceedsPrice(uint256 price, uint96 w1)
        public
    {
        price = bound(price, 10000, type(uint128).max);
        w1 = uint96(bound(w1, 1, 99)) * MIN_SLOT_WEIGHT;

        uint128 perBps = uint128(price / 10000); // ensure eligible
        uint256 deposit = uint256(perBps) * w1;

        _openRoundWithPrice(0, price);
        paymentToken.mint(partner1, deposit + 1);
        vm.prank(partner1);
        paymentToken.approve(address(syndicate), type(uint256).max);
        _register(0, partner1, vault1, w1, perBps);

        (,,,, uint256 bufferRequired) = syndicate.previewFillAt(0, price);
        assertLe(bufferRequired, price);
    }

    /*//////////////////////////////////////////////////////////////
                         SET SLOT NFT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setSlotNFT_revert_notGovernance() public {
        vm.expectRevert();
        vm.prank(partner1);
        syndicate.setSlotNFT(address(slotNFT));
    }

    /*//////////////////////////////////////////////////////////////
                  TRIGGER CLAIM SLOT NFT ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    function test_triggerClaim_slotNFT_mintedForIncludedPartners() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        // Both included partners should own a SlotNFT
        uint256 token1 = slotNFT.getTokenId(0, partner1);
        uint256 token2 = slotNFT.getTokenId(0, partner2);
        assertTrue(token1 > 0);
        assertTrue(token2 > 0);
        assertEq(slotNFT.ownerOf(token1), partner1);
        assertEq(slotNFT.ownerOf(token2), partner2);
    }

    function test_triggerClaim_slotNFT_isValid() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        uint256 token1 = slotNFT.getTokenId(0, partner1);
        assertTrue(slotNFT.isValid(token1));
    }

    function test_triggerClaim_slotNFT_correctRights() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        // partner1: 6000 bps, full fill
        uint256 token1 = slotNFT.getTokenId(0, partner1);
        CuttingBoardSlotNFT.SlotRights memory r1 = slotNFT.getSlotRights(token1);
        assertEq(r1.auctionId, 0);
        assertEq(r1.originalPartner, partner1);
        assertEq(r1.allocatedWeight, 6000);
        assertEq(r1.requestedWeight, 6000);
        assertEq(r1.clearingPrice, uint128(DEFAULT_PRICE));
        assertEq(r1.vault, vault1);
        assertFalse(r1.isPartialFill);
        // Expiry matches allocationDuration
        assertEq(r1.expiryTimestamp, block.timestamp + ALLOCATION_DURATION);

        // partner2: 4000 bps, full fill
        uint256 token2 = slotNFT.getTokenId(0, partner2);
        CuttingBoardSlotNFT.SlotRights memory r2 = slotNFT.getSlotRights(token2);
        assertEq(r2.allocatedWeight, 4000);
        assertEq(r2.requestedWeight, 4000);
        assertEq(r2.vault, vault2);
        assertFalse(r2.isPartialFill);
    }

    function test_triggerClaim_slotNFT_bufferVaultNoToken() public {
        // Only partner1 with 6000 bps; buffer absorbs 4000 bps — buffer gets NO SlotNFT
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(DEFAULT_PRICE); // cover buffer cost

        _triggerClaim(0);

        // partner1 has a SlotNFT
        assertGt(slotNFT.getTokenId(0, partner1), 0);
        // bufferVault has NO SlotNFT (reverse lookup returns 0)
        assertEq(slotNFT.getTokenId(0, bufferVault), 0);
        assertEq(slotNFT.totalSupply(), 1); // only 1 SlotNFT minted
    }

    function test_triggerClaim_slotNFT_partialFill_isPartialFillTrue() public {
        // Fill order: sorted by bid value (weight × maxPrice) desc.
        // partner1: 8000 × DEFAULT_PRICE → higher bid, fills first (full 8000 bps)
        // partner2: 6000 × DEFAULT_PRICE → fills second, only 2000 bps remain → partial fill
        _openRound(0);
        _register(0, partner1, vault1, 8000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        // 8000 + 2000 = 10000, no buffer required
        _triggerClaim(0);

        uint256 token2 = slotNFT.getTokenId(0, partner2);
        CuttingBoardSlotNFT.SlotRights memory r2 = slotNFT.getSlotRights(token2);
        assertEq(r2.allocatedWeight, 2000); // only 2000 bps remain after partner1 fills 8000
        assertEq(r2.requestedWeight, 6000);
        assertTrue(r2.isPartialFill);
    }

    function test_triggerClaim_duplicateVaults_topBidWins() public {
        // Two partners bid on the same vault (vault1).
        // partner1 bids higher (weight × maxPrice), so partner1 wins vault1.
        // partner2 is excluded (duplicate vault) and gets a full refund.
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        // partner2 bids on vault1 too but lower bid value
        _register(0, partner2, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        // Need buffer to absorb the remaining 4000 bps (partner2's 3000 skipped)
        _setBufferAndDeposit(500e18);

        _triggerClaim(0);

        // partner1 included with 6000 bps
        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        assertEq(s1.allocatedWeight, 6000);

        // partner2 excluded (duplicate vault) — full deposit refunded
        uint256 p2Deposit = uint256(DEFAULT_PRICE_PER_BPS) * 3000;
        assertEq(syndicate.getPendingRefund(partner2), p2Deposit);
    }

    function test_triggerClaim_duplicateVaults_higherBidValueWins() public {
        // partner2 has a smaller weight but higher maxPricePerBps, giving a
        // higher bid value (weight × maxPricePerBps). Both bid on vault1.
        _openRound(0);
        // partner1: bid value = 3000 × 0.1e18 = 300e18
        _register(0, partner1, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        // partner2: bid value = 2000 × 0.2e18 = 400e18 (higher bid value)
        _register(0, partner2, vault1, 2000, 0.2e18);

        // partner2 wins vault1 (higher bid value), partner1 is excluded
        _setBufferAndDeposit(1000e18);

        _triggerClaim(0);

        // partner2 gets allocated (higher bid value)
        CuttingBoardSyndicateLib.Slot memory s2 = syndicate.getSlot(0, partner2);
        assertEq(s2.allocatedWeight, 2000);

        // partner1 excluded — full deposit refunded
        uint256 p1Deposit = uint256(DEFAULT_PRICE_PER_BPS) * 3000;
        assertEq(syndicate.getPendingRefund(partner1), p1Deposit);
    }

    function test_triggerClaim_duplicateVaults_mixedWithUnique() public {
        // partner1 and partner2 both bid vault1, partner3 bids vault2.
        // partner1 wins vault1 (higher bid), partner3 wins vault2.
        // partner2 is excluded (duplicate vault).
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner3, vault2, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        _triggerClaim(0);

        // partner1 gets 5000 bps on vault1
        assertEq(syndicate.getSlot(0, partner1).allocatedWeight, 5000);
        // partner3 gets 5000 bps on vault2
        assertEq(syndicate.getSlot(0, partner3).allocatedWeight, 5000);
        // partner2 excluded — full deposit refunded
        uint256 p2Deposit = uint256(DEFAULT_PRICE_PER_BPS) * 3000;
        assertEq(syndicate.getPendingRefund(partner2), p2Deposit);
    }

    /*//////////////////////////////////////////////////////////////
                  UPDATE SLOT VAULT (ACTIVE STATE) TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSlotVault_activeState_syncsSlotNFT() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        uint256 tokenId = slotNFT.getTokenId(0, partner1);

        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        // Both syndicate slot storage and SlotNFT metadata updated
        assertEq(syndicate.getSlot(0, partner1).vault, vault3);
        assertEq(slotNFT.getSlotRights(tokenId).vault, vault3);
    }

    function test_updateSlotVault_activeState_transferredNFTHolder_success()
        public
    {
        // After trigger, partner1 transfers their SlotNFT to partner3.
        // partner3 (new holder) should be able to redirect the vault via updateSlotVault.
        _fullFillSetup(0);
        _triggerClaim(0);

        uint256 tokenId = slotNFT.getTokenId(0, partner1);
        vm.prank(partner1);
        slotNFT.transferFrom(partner1, partner3, tokenId);
        assertEq(slotNFT.ownerOf(tokenId), partner3);

        vm.expectEmit(true, true, true, false);
        emit SlotVaultUpdated(0, partner1, vault3); // event uses originalPartner

        vm.prank(partner3);
        syndicate.updateSlotVault(0, partner1, vault3);

        assertEq(syndicate.getSlot(0, partner1).vault, vault3);
        assertEq(slotNFT.getSlotRights(tokenId).vault, vault3);
    }

    function test_updateSlotVault_activeState_revert_notNFTHolder() public {
        // partner3 does not hold partner1's SlotNFT → NotSlotNFTHolder
        _fullFillSetup(0);
        _triggerClaim(0);

        vm.expectRevert(CuttingBoardSyndicate.NotSlotNFTHolder.selector);
        vm.prank(partner3);
        syndicate.updateSlotVault(0, partner1, vault3);
    }

    function test_updateSlotVault_revert() public {
        _fullFillSetup(0);
        _triggerClaim(0);

        address newNFT =
            address(new CuttingBoardSlotNFT(address(syndicate), governance, ""));
        vm.expectRevert(CuttingBoardSyndicate.SlotNFTAlreadySet.selector);
        syndicate.setSlotNFT(newNFT);
    }

    function test_updateSlotVault_activeState_multipleNFTsHeld() public {
        // Alice buys SlotNFTs from both partner1 and partner2 on secondary market.
        // She should be able to update each slot independently.
        _fullFillSetup(0);
        _triggerClaim(0);

        address alice = makeAddr("alice");

        uint256 tokenId1 = slotNFT.getTokenId(0, partner1);
        uint256 tokenId2 = slotNFT.getTokenId(0, partner2);

        // Transfer both SlotNFTs to alice
        vm.prank(partner1);
        slotNFT.transferFrom(partner1, alice, tokenId1);
        vm.prank(partner2);
        slotNFT.transferFrom(partner2, alice, tokenId2);

        // Alice updates partner1's slot to vault3
        vm.prank(alice);
        syndicate.updateSlotVault(0, partner1, vault3);
        assertEq(syndicate.getSlot(0, partner1).vault, vault3);
        assertEq(slotNFT.getSlotRights(tokenId1).vault, vault3);

        // Alice updates partner2's slot to vault4
        address vault4 = makeAddr("vault4");
        chef.setWhitelistedVault(vault4, true);
        vm.prank(alice);
        syndicate.updateSlotVault(0, partner2, vault4);
        assertEq(syndicate.getSlot(0, partner2).vault, vault4);
        assertEq(slotNFT.getSlotRights(tokenId2).vault, vault4);
    }

    function test_updateSlotVault_activeState_revert_notActive() public {
        // 3-param overload requires Active state, reverts on Open
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);
    }

    /*//////////////////////////////////////////////////////////////
                       MINIMUM PRICE PER BPS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_minimumPricePerBps_returnsAuctionMinDivided() public {
        auction.setMinimumPrice(50000e18);
        assertEq(syndicate.minimumPricePerBps(), 50000e18 / 10000);
        assertEq(syndicate.minimumPricePerBps(), 5e18);
    }

    function test_minimumPricePerBps_zeroWhenAuctionMinZero() public view {
        // Default mock has minimumPrice = 0
        assertEq(syndicate.minimumPricePerBps(), 0);
    }

    function test_minimumPricePerBps_roundsDown() public {
        // minimumPrice = 9999 → 9999/10000 = 0 (rounds down)
        auction.setMinimumPrice(9999);
        assertEq(syndicate.minimumPricePerBps(), 0);

        // minimumPrice = 10001 → 10001/10000 = 1
        auction.setMinimumPrice(10001);
        assertEq(syndicate.minimumPricePerBps(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                         RECOVER ERC20 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_recoverERC20_success() public {
        // Deploy a stray token and accidentally send it to the syndicate
        MockPaymentToken strayToken = new MockPaymentToken();
        strayToken.mint(address(syndicate), 100e18);

        uint256 balBefore = strayToken.balanceOf(governance);
        syndicate.recoverERC20(address(strayToken), governance, 100e18);

        assertEq(strayToken.balanceOf(governance), balBefore + 100e18);
        assertEq(strayToken.balanceOf(address(syndicate)), 0);
    }

    function test_recoverERC20_revert_paymentToken() public {
        vm.expectRevert(
            CuttingBoardSyndicate.CannotRecoverPaymentToken.selector
        );
        syndicate.recoverERC20(address(paymentToken), governance, 1);
    }

    function test_recoverERC20_revert_notGovernance() public {
        MockPaymentToken strayToken = new MockPaymentToken();
        strayToken.mint(address(syndicate), 100e18);

        vm.prank(partner1);
        vm.expectRevert();
        syndicate.recoverERC20(address(strayToken), partner1, 100e18);
    }

    function test_recoverERC20_revert_zeroAddress() public {
        MockPaymentToken strayToken = new MockPaymentToken();
        strayToken.mint(address(syndicate), 100e18);

        vm.expectRevert(CuttingBoardSyndicate.ZeroAddress.selector);
        syndicate.recoverERC20(address(strayToken), address(0), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                  TOO MANY PARTNERS AT TRIGGER TIME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_triggerClaim_revert_tooManyPartners() public {
        // Set maxNumWeightsPerRewardAllocation to 2 (very restrictive)
        chef.setMaxNumWeightsPerRewardAllocation(2);
        _openRound(0);
        // Register 3 partners — all eligible, fill 10000 bps together
        _register(0, partner1, vault1, 4000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner3, vault3, 3000, uint128(DEFAULT_PRICE_PER_BPS));

        // 3 included partners > maxNumWeightsPerRewardAllocation (2)
        vm.expectRevert(CuttingBoardSyndicate.TooManyPartners.selector);
        _triggerClaim(0);
    }

    function test_triggerClaim_tooManyPartners_passesWhenSomeExcluded()
        public
    {
        // 3 registered but only 2 eligible at current price
        chef.setMaxNumWeightsPerRewardAllocation(2);
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS)); // eligible
        _register(0, partner2, vault2, 5000, uint128(DEFAULT_PRICE_PER_BPS)); // eligible
        _register(0, partner3, vault3, 3000, 0.005e18); // excluded: 0.005e18*10000=50e18 < 1000e18

        // Only 2 included, fits in maxNumWeightsPerRewardAllocation
        _triggerClaim(0);
        assertEq(
            uint8(syndicate.getRound(0).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );
    }

    function test_triggerClaim_tooManyPartners_bufferCountedInTotal() public {
        // 2 partners + buffer = 3 entries, but max is 2
        chef.setMaxNumWeightsPerRewardAllocation(2);
        _openRound(0);
        _register(0, partner1, vault1, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        // 4000 bps goes to buffer → 2 partners + 1 buffer = 3 entries
        _setBufferAndDeposit(1_000e18);

        vm.expectRevert(CuttingBoardSyndicate.TooManyPartners.selector);
        _triggerClaim(0);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT OVERFLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerSlot_revert_depositOverflow() public {
        _openRound(0);
        // maxPricePerBps * weight would exceed uint128 max
        uint128 hugePrice = type(uint128).max / 5000; // ~6.8e34
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.DepositOverflow.selector);
        syndicate.registerSlot(0, vault1, 10000, hugePrice);
    }

    function test_registerSlot_depositExactlyMaxUint128_succeeds() public {
        _openRound(0);
        // weight=1 bps (need minSlotWeight=1 for this), maxPricePerBps=type(uint128).max
        // deposit = type(uint128).max * 1 = type(uint128).max → fits
        // But minSlotWeight is 100, so use weight=100 and maxPrice that fits
        uint128 maxPrice = type(uint128).max / 100; // deposit = maxPrice * 100 ≤ uint128 max
        paymentToken.mint(partner1, type(uint256).max / 2);
        vm.startPrank(partner1);
        paymentToken.approve(address(syndicate), type(uint256).max);
        syndicate.registerSlot(0, vault1, 100, maxPrice);
        vm.stopPrank();
    }

    function test_increaseMaxPrice_revert_depositOverflow() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));

        uint128 hugePrice = type(uint128).max / 2000;
        vm.prank(partner1);
        vm.expectRevert(CuttingBoardSyndicate.DepositOverflow.selector);
        syndicate.increaseMaxPrice(0, hugePrice);
    }

    /*//////////////////////////////////////////////////////////////
              EXCLUDED VAULT UPDATE TESTS (ACTIVE STATE)
    //////////////////////////////////////////////////////////////*/

    function test_updateSlotVault_activeState_excludedPartnerVaultAvailable()
        public
    {
        // Partner 3 registers with a low per-bps price and gets excluded
        // when we raise the auction price. Partners 1&2 use a high price
        // so they remain eligible.
        _openRound(0);
        // 2x per-bps price so partners 1&2 stay eligible even at doubled price
        uint128 highPerBps = uint128(DEFAULT_PRICE_PER_BPS * 2);
        _register(0, partner1, vault1, 5000, highPerBps);
        _register(0, partner2, vault2, 5000, highPerBps);
        // partner3 at base per-bps price — will be excluded when price doubles
        _register(0, partner3, vault3, 3000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(100e18);

        // Double the auction price so partner3 is excluded
        auction.setPrice(0, DEFAULT_PRICE * 2);
        _triggerClaim(0);

        // Confirm partner3 was excluded
        CuttingBoardSyndicateLib.Slot memory s3 = syndicate.getSlot(0, partner3);
        assertEq(s3.allocatedWeight, 0, "partner3 should be excluded");

        // Now partner1 (included) should be able to switch to vault3
        // which was registered by excluded partner3
        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        CuttingBoardSyndicateLib.Slot memory s1 = syndicate.getSlot(0, partner1);
        assertEq(s1.vault, vault3, "partner1 should now have vault3");
    }

    function test_updateSlotVault_activeState_includedPartnerVaultStillBlocked()
        public
    {
        // Two included partners — they should NOT be able to switch to each
        // other's vaults (included partners' vaults are still in the allocation).
        _fullFillSetup(0);
        _setBufferAndDeposit(100e18);
        _triggerClaim(0);

        vm.prank(partner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, vault2
            )
        );
        syndicate.updateSlotVault(0, partner1, vault2);
    }

    /*//////////////////////////////////////////////////////////////
                    SYBIL REGISTRATION CAP TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The registerSlot cap (5 * maxNumWeightsPerRewardAllocation) prevents
    ///      a sybil attacker from registering enough partners to push
    ///      triggerClaim over the block gas limit.
    function test_registerSlot_revert_tooManyPartners_sybilCap() public {
        // maxNumWeightsPerRewardAllocation = 10 → cap = 50
        chef.setMaxNumWeightsPerRewardAllocation(10);
        _openRound(0);

        // Create and register 50 distinct partners with unique whitelisted vaults
        uint256 cap = 5 * uint256(chef.maxNumWeightsPerRewardAllocation());
        for (uint256 i = 0; i < cap; i++) {
            address sybil = makeAddr(string.concat("sybil", vm.toString(i)));
            address v = makeAddr(string.concat("sybilVault", vm.toString(i)));
            chef.setWhitelistedVault(v, true);
            paymentToken.mint(sybil, 1_000_000e18);
            vm.prank(sybil);
            paymentToken.approve(address(syndicate), type(uint256).max);
            _register(
                0, sybil, v, MIN_SLOT_WEIGHT, uint128(DEFAULT_PRICE_PER_BPS)
            );
        }

        // 51st registration must revert
        address attacker = makeAddr("attacker51");
        address attackerVault = makeAddr("attackerVault51");
        chef.setWhitelistedVault(attackerVault, true);
        paymentToken.mint(attacker, 1_000_000e18);
        vm.prank(attacker);
        paymentToken.approve(address(syndicate), type(uint256).max);

        vm.prank(attacker);
        vm.expectRevert(CuttingBoardSyndicate.TooManyPartners.selector);
        syndicate.registerSlot(
            0, attackerVault, MIN_SLOT_WEIGHT, uint128(DEFAULT_PRICE_PER_BPS)
        );
    }

    /// @dev With a smaller maxNumWeightsPerRewardAllocation the cap tightens accordingly.
    function test_registerSlot_revert_tooManyPartners_smallCap() public {
        chef.setMaxNumWeightsPerRewardAllocation(2);
        _openRound(0);

        uint256 cap = 5 * uint256(chef.maxNumWeightsPerRewardAllocation()); // 10

        for (uint256 i = 0; i < cap; i++) {
            address sybil = makeAddr(string.concat("s", vm.toString(i)));
            address v = makeAddr(string.concat("sv", vm.toString(i)));
            chef.setWhitelistedVault(v, true);
            paymentToken.mint(sybil, 1_000_000e18);
            vm.prank(sybil);
            paymentToken.approve(address(syndicate), type(uint256).max);
            _register(
                0, sybil, v, MIN_SLOT_WEIGHT, uint128(DEFAULT_PRICE_PER_BPS)
            );
        }

        // Next registration reverts
        address attacker = makeAddr("attackerX");
        address attackerVault = makeAddr("attackerVaultX");
        chef.setWhitelistedVault(attackerVault, true);
        paymentToken.mint(attacker, 1_000_000e18);
        vm.prank(attacker);
        paymentToken.approve(address(syndicate), type(uint256).max);

        vm.prank(attacker);
        vm.expectRevert(CuttingBoardSyndicate.TooManyPartners.selector);
        syndicate.registerSlot(
            0, attackerVault, MIN_SLOT_WEIGHT, uint128(DEFAULT_PRICE_PER_BPS)
        );
    }

    /// @dev Registering exactly at the cap succeeds; only exceeding it reverts.
    function test_registerSlot_atCapSucceeds() public {
        chef.setMaxNumWeightsPerRewardAllocation(2);
        _openRound(0);

        uint256 cap = 5 * uint256(chef.maxNumWeightsPerRewardAllocation()); // 10

        for (uint256 i = 0; i < cap; i++) {
            address sybil = makeAddr(string.concat("ok", vm.toString(i)));
            address v = makeAddr(string.concat("okv", vm.toString(i)));
            chef.setWhitelistedVault(v, true);
            paymentToken.mint(sybil, 1_000_000e18);
            vm.prank(sybil);
            paymentToken.approve(address(syndicate), type(uint256).max);
            _register(
                0, sybil, v, MIN_SLOT_WEIGHT, uint128(DEFAULT_PRICE_PER_BPS)
            );
        }

        // Should have exactly `cap` partners registered
        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, cap, "partners should equal cap");
    }

    /*//////////////////////////////////////////////////////////////
            LIVE POLICY DRIFT TESTS (vault whitelist & weight cap)
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault de-whitelisted after registration → fill excludes that partner,
    ///         buffer absorbs remaining bps, triggerClaim succeeds.
    function test_triggerClaim_vaultDewhitelistedAfterRegistration() public {
        _openRound(0);
        // partner1 = 6000 bps, partner2 = 4000 bps → full fill, no buffer needed
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        // De-whitelist vault2 after registration
        chef.setWhitelistedVault(vault2, false);

        // Now partner2 is ineligible. partner1 fills 6000, buffer needs 4000.
        // maxWeightPerVault default is 10000, so 4000 buffer is fine.
        _setBufferAndDeposit(DEFAULT_PRICE); // enough for buffer share
        _triggerClaim(0);

        // partner1 should be included, partner2 should be excluded (refunded)
        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, 1, "only partner1 should remain");
        assertEq(partners[0], partner1);

        // partner2's full deposit should be refundable
        assertGt(
            syndicate.getPendingRefund(partner2),
            0,
            "partner2 should have refund"
        );
    }

    /// @notice canTrigger returns false when vault de-whitelisting makes the fill
    ///         infeasible (e.g. buffer weight exceeds max).
    function test_canTrigger_falseAfterVaultDewhitelisted() public {
        _openRound(0);
        // partner1 = 2000 bps → buffer would need 8000 bps
        _register(0, partner1, vault1, 2000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 8000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(DEFAULT_PRICE);

        // Before de-whitelist: both fill 10000, no buffer needed
        assertTrue(syndicate.canTrigger(0), "should be triggerable");

        // De-whitelist vault2 → partner1 alone = 2000 bps, buffer = 8000 bps
        chef.setWhitelistedVault(vault2, false);

        // maxWeightPerVault = 10000 by default, so 8000 buffer is OK.
        // But let's also lower maxWeightPerVault to 5000 to force failure.
        chef.setMaxWeightPerVault(5000);

        assertFalse(
            syndicate.canTrigger(0),
            "should not be triggerable: buffer weight exceeds max"
        );
    }

    /// @notice maxWeightPerVault decreased after registration → fill caps individual
    ///         allocations, remaining bps go to buffer.
    function test_triggerClaim_maxWeightPerVaultDecreased() public {
        _openRound(0);
        // partner1 requests 6000 bps at a time when maxWeightPerVault = 10000
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        // Lower maxWeightPerVault to 3000 after registration
        chef.setMaxWeightPerVault(3000);

        // partner1 capped to 3000, partner2 capped to 3000 (was 4000 but cap is 3000)
        // Total filled = 6000 bps, buffer = 4000 bps
        // buffer 4000 > maxPerVault 3000 → should revert
        _setBufferAndDeposit(DEFAULT_PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.BufferWeightExceedsMax.selector,
                uint96(4000),
                uint96(3000)
            )
        );
        _triggerClaim(0);
    }

    /// @notice maxWeightPerVault decreased but fill still feasible with enough partners.
    function test_triggerClaim_maxWeightPerVaultDecreased_stillFeasible()
        public
    {
        _openRound(0);
        address vault4 = makeAddr("vault4");
        chef.setWhitelistedVault(vault4, true);

        // 4 partners requesting 2500 bps each → perfectly fills 10000
        _register(0, partner1, vault1, 2500, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 2500, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner3, vault3, 2500, uint128(DEFAULT_PRICE_PER_BPS));
        address partner4 = makeAddr("partner4");
        paymentToken.mint(partner4, 1_000_000e18);
        vm.prank(partner4);
        paymentToken.approve(address(syndicate), type(uint256).max);
        _register(0, partner4, vault4, 2500, uint128(DEFAULT_PRICE_PER_BPS));

        // Lower maxWeightPerVault to 2500 — all allocs still fit
        chef.setMaxWeightPerVault(2500);

        // No buffer needed (all 4 × 2500 = 10000)
        // But still need minimal buffer deposit for rounding dust
        _setBufferAndDeposit(1e18);
        _triggerClaim(0);

        // Verify all 4 included
        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, 4, "all 4 partners should be included");
    }

    /// @notice Buffer vault de-whitelisted → triggerClaim reverts when buffer bps > 0.
    function test_triggerClaim_revert_bufferVaultDewhitelisted() public {
        _openRound(0);
        // Only partner1 with 5000 bps → buffer needs 5000 bps
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(DEFAULT_PRICE);

        // De-whitelist the buffer vault
        chef.setWhitelistedVault(bufferVault, false);

        vm.expectRevert(
            CuttingBoardSyndicate.BufferVaultNotWhitelisted.selector
        );
        _triggerClaim(0);
    }

    /// @notice Buffer vault de-whitelisted → canTrigger returns false.
    function test_canTrigger_falseWhenBufferVaultDewhitelisted() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(DEFAULT_PRICE);

        assertTrue(syndicate.canTrigger(0), "should be triggerable before");

        chef.setWhitelistedVault(bufferVault, false);

        assertFalse(
            syndicate.canTrigger(0),
            "should not be triggerable with de-whitelisted buffer vault"
        );
    }

    /// @notice Vault de-whitelisted but partners fill 10000 without it → buffer
    ///         vault whitelist doesn't matter (bfWeight = 0).
    function test_triggerClaim_bufferVaultDewhitelisted_noBufferNeeded()
        public
    {
        _openRound(0);
        _register(0, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(0, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));

        // De-whitelist buffer vault — but partners fill 10000, no buffer used
        _setBufferAndDeposit(1e18); // minimal for rounding dust
        chef.setWhitelistedVault(bufferVault, false);

        _triggerClaim(0);

        address[] memory partners = syndicate.getPartners(0);
        assertEq(partners.length, 2, "both partners included");
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE ROUND TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Helper: set up and trigger a round, returning the control NFT token id.
    function _triggerAndGetTokenId(uint256 auctionId)
        internal
        returns (uint256 tokenId)
    {
        _fullFillSetup(auctionId);
        _setBufferAndDeposit(1e18);
        _triggerClaim(auctionId);
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(auctionId);
        tokenId = r.tokenId;
    }

    function test_completeRound_success() public {
        uint256 tokenId = _triggerAndGetTokenId(0);
        // Verify round is Active
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Active)
        );

        // Warp past NFT expiry
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
        assertFalse(nft.isValid(tokenId), "NFT should be expired");

        vm.expectEmit(true, false, false, false);
        emit RoundCompleted(0);
        syndicate.completeRound(0);

        r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Complete)
        );
    }

    function test_completeRound_permissionless() public {
        _triggerAndGetTokenId(0);
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // Random address can call it
        address random = makeAddr("random");
        vm.prank(random);
        syndicate.completeRound(0);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Complete)
        );
    }

    function test_completeRound_revert_notActive_idle() public {
        // Round 99 was never opened → Idle
        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.completeRound(99);
    }

    function test_completeRound_revert_notActive_open() public {
        _openRound(0);
        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.completeRound(0);
    }

    function test_completeRound_revert_notActive_expired() public {
        _openRound(0);
        auction.setActive(0, false);
        syndicate.expireRound(0);

        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.completeRound(0);
    }

    function test_completeRound_revert_notActive_alreadyComplete() public {
        _triggerAndGetTokenId(0);
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
        syndicate.completeRound(0);

        // Second call should revert — already Complete
        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.completeRound(0);
    }

    function test_completeRound_revert_nftStillValid() public {
        _triggerAndGetTokenId(0);
        // NFT is still valid — should revert
        vm.expectRevert(CuttingBoardSyndicate.NFTStillValid.selector);
        syndicate.completeRound(0);
    }

    function test_completeRound_revert_nftStillValid_justBeforeExpiry()
        public
    {
        _triggerAndGetTokenId(0);
        // Warp to exactly the expiry boundary (still valid)
        vm.warp(block.timestamp + ALLOCATION_DURATION);
        vm.expectRevert(CuttingBoardSyndicate.NFTStillValid.selector);
        syndicate.completeRound(0);
    }

    function test_completeRound_worksWhilePaused() public {
        _triggerAndGetTokenId(0);
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        syndicate.pause();
        assertTrue(syndicate.paused());

        // completeRound is not gated by whenNotPaused
        syndicate.completeRound(0);

        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(
            uint8(r.state), uint8(CuttingBoardSyndicateLib.RoundState.Complete)
        );
    }

    function test_completeRound_blocksUpdateSlotVault() public {
        _triggerAndGetTokenId(0);
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
        syndicate.completeRound(0);

        // Active-state updateSlotVault overload requires Active — should revert
        address newVault = makeAddr("newVault");
        chef.setWhitelistedVault(newVault, true);
        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.updateSlotVault(0, partner1, newVault);
    }

    function test_completeRound_independentRounds() public {
        // Trigger round 0 for validator 1
        _triggerAndGetTokenId(0);

        // Set up and trigger round 1 for a different validator
        auction.configure(1, true, VALIDATOR_PUBKEY_2, DEFAULT_PRICE);
        syndicate.openRound(1);
        _register(1, partner1, vault1, 6000, uint128(DEFAULT_PRICE_PER_BPS));
        _register(1, partner2, vault2, 4000, uint128(DEFAULT_PRICE_PER_BPS));
        _triggerClaim(1);

        // Expire only round 0's NFT
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        syndicate.completeRound(0);

        // Round 0 is Complete
        assertEq(
            uint8(syndicate.getRound(0).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Complete)
        );
        // Round 1 is still Active (same expiry in this test since triggered at same time,
        // but the point is completeRound(0) doesn't affect round 1's state)
        // Both rounds were triggered at the same block so both NFTs expire together.
        // Verify round 1 is independently completable.
        syndicate.completeRound(1);
        assertEq(
            uint8(syndicate.getRound(1).state),
            uint8(CuttingBoardSyndicateLib.RoundState.Complete)
        );
    }

    /*//////////////////////////////////////////////////////////////
                  UPDATE ROUND BUFFER VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateRoundBufferVault_success() public {
        // Trigger a round that uses buffer vault
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        // Verify original buffer vault is snapshotted
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.bufferVault, bufferVault);

        // Set up a new whitelisted vault as replacement
        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);

        vm.expectEmit(true, true, false, false);
        emit RoundBufferVaultUpdated(0, newBuffer);
        syndicate.updateRoundBufferVault(0, newBuffer);

        r = syndicate.getRound(0);
        assertEq(r.bufferVault, newBuffer);
    }

    function test_updateRoundBufferVault_proposalUsesNewVault() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        // Replace buffer vault
        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);
        syndicate.updateRoundBufferVault(0, newBuffer);

        // updateSlotVault triggers a proposal — weights should use newBuffer
        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        IBeraChef.Weight[] memory weights = manager.getLastWeights();
        bool foundNewBuffer;
        for (uint256 i = 0; i < weights.length; i++) {
            if (weights[i].receiver == newBuffer) foundNewBuffer = true;
            // Old buffer should not appear
            assertTrue(weights[i].receiver != bufferVault);
        }
        assertTrue(foundNewBuffer, "proposal should use new buffer vault");
    }

    function test_updateRoundBufferVault_revert_notGovernance() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);

        vm.prank(partner1);
        vm.expectRevert();
        syndicate.updateRoundBufferVault(0, newBuffer);
    }

    function test_updateRoundBufferVault_revert_notActive() public {
        vm.expectRevert(CuttingBoardSyndicate.NotActive.selector);
        syndicate.updateRoundBufferVault(0, vault1);
    }

    function test_updateRoundBufferVault_revert_notWhitelisted() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        address notListed = makeAddr("notListed");
        vm.expectRevert(CuttingBoardSyndicate.VaultNotWhitelisted.selector);
        syndicate.updateRoundBufferVault(0, notListed);
    }

    function test_updateRoundBufferVault_revert_duplicatePartnerVault()
        public
    {
        _fullFillSetup(0);
        _setBufferAndDeposit(1e18);
        _triggerClaim(0);

        // vault1 is already used by partner1
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, vault1
            )
        );
        syndicate.updateRoundBufferVault(0, vault1);
    }

    function test_updateRoundBufferVault_doesNotAffectGlobalBufferVault()
        public
    {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);
        syndicate.updateRoundBufferVault(0, newBuffer);

        // Global bufferVault should be unchanged
        assertEq(syndicate.bufferVault(), bufferVault);
    }

    /*//////////////////////////////////////////////////////////////
          VALIDATE VAULT UPDATE — SNAPSHOTTED BUFFER VAULT CHECK
    //////////////////////////////////////////////////////////////*/

    /// @notice The exact attack scenario: governance changes global bufferVault
    ///         after triggerClaim, then a partner tries to set their vault to
    ///         the old (snapshotted) buffer vault address. Must revert.
    function test_updateSlotVault_revert_snapshotBufferVaultAfterGovChange()
        public
    {
        // 1. Trigger round — buffer vault V_old is snapshotted
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        address oldBuffer = bufferVault;
        CuttingBoardSyndicateLib.Round memory r = syndicate.getRound(0);
        assertEq(r.bufferVault, oldBuffer);

        // 2. Governance changes global bufferVault to V_new
        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);
        syndicate.setBufferVault(newBuffer);
        assertEq(syndicate.bufferVault(), newBuffer);

        // 3. Partner tries to set their vault to V_old (the snapshotted buffer)
        //    This must revert — otherwise weightsFromStorage would produce
        //    duplicate receivers (partner vault = V_old, buffer entry = V_old).
        vm.prank(partner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, oldBuffer
            )
        );
        syndicate.updateSlotVault(0, partner1, oldBuffer);
    }

    /// @notice Same scenario but with updateRoundBufferVault instead of
    ///         setBufferVault — the round snapshot differs from the global.
    function test_updateSlotVault_revert_snapshotBufferAfterRoundUpdate()
        public
    {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        // Governance updates the *round's* buffer vault
        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);
        syndicate.updateRoundBufferVault(0, newBuffer);

        // Partner tries to set vault to newBuffer (now the round's buffer)
        vm.prank(partner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CuttingBoardSyndicate.DuplicateVaultEntry.selector, newBuffer
            )
        );
        syndicate.updateSlotVault(0, partner1, newBuffer);
    }

    /// @notice Partner can still update to a vault that is neither the live
    ///         nor the snapshotted buffer vault.
    function test_updateSlotVault_allowedAfterBufferVaultChange() public {
        _openRound(0);
        _register(0, partner1, vault1, 5000, uint128(DEFAULT_PRICE_PER_BPS));
        _setBufferAndDeposit(1_000e18);
        _triggerClaim(0);

        // Change global buffer vault
        address newBuffer = makeAddr("newBuffer");
        chef.setWhitelistedVault(newBuffer, true);
        syndicate.setBufferVault(newBuffer);

        // Partner updates to vault3 — neither old nor new buffer
        vm.prank(partner1);
        syndicate.updateSlotVault(0, partner1, vault3);

        CuttingBoardSyndicateLib.Slot memory s = syndicate.getSlot(0, partner1);
        assertEq(s.vault, vault3);
    }
}
