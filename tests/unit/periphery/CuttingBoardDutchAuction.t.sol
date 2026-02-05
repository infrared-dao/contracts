// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CuttingBoardDutchAuction} from
    "src/periphery/CuttingBoardDutchAuction.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManager} from "src/periphery/CuttingBoardManager.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 token for payments
contract MockPaymentToken is ERC20("Mock IR", "IR", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Infrared contract
contract MockInfrared {
    bytes public lastQueuedPubkey;
    uint64 public lastQueuedStartBlock;
    IBeraChef.Weight[] public lastQueuedWeights;
    uint256 public queueCallCount;

    function queueNewCuttingBoard(
        bytes calldata _pubkey,
        uint64 _startBlock,
        IBeraChef.Weight[] calldata _weights
    ) external {
        lastQueuedPubkey = _pubkey;
        lastQueuedStartBlock = _startBlock;
        delete lastQueuedWeights;
        for (uint256 i = 0; i < _weights.length; i++) {
            lastQueuedWeights.push(_weights[i]);
        }
        queueCallCount++;
    }

    function isInfraredValidator(bytes memory) external pure returns (bool) {
        return true; // All validators are valid in tests
    }
}

// Mock BeraChef contract
contract MockBeraChef {
    mapping(address => bool) public whitelistedVaults;
    uint64 public rewardAllocationBlockDelay = 100; // Default to 100 blocks
    uint96 _maxWeightPerVault = 10000;
    uint8 _maxNumWeightsPerRewardAllocation = 10;
    uint64 _startBlock = 0;

    function isWhitelistedVault(address vault) external view returns (bool) {
        return whitelistedVaults[vault];
    }

    function setWhitelistedVault(address vault, bool whitelisted) external {
        whitelistedVaults[vault] = whitelisted;
    }

    function setRewardAllocationBlockDelay(uint64 delay) external {
        rewardAllocationBlockDelay = delay;
    }

    function maxNumWeightsPerRewardAllocation() external view returns (uint8) {
        return _maxNumWeightsPerRewardAllocation;
    }

    function maxWeightPerVault() external view returns (uint96) {
        return _maxWeightPerVault;
    }

    function getQueuedRewardAllocation(bytes calldata)
        external
        view
        returns (IBeraChef.RewardAllocation memory ra)
    {
        ra.startBlock = _startBlock;
    }
}

contract CuttingBoardDutchAuctionTest is Test {
    CuttingBoardDutchAuction public auction;
    CuttingBoardNFT public nft;
    CuttingBoardManager public manager;
    MockPaymentToken public paymentToken;
    MockInfrared public infrared;
    MockBeraChef public chef;

    address public owner;
    address public keeper;
    address public treasury;
    address public user1;
    address public user2;
    address public vault1;
    address public vault2;

    bytes public validatorPubkey1 =
        hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    bytes public validatorPubkey2 =
        hex"fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321";

    // Default auction parameters
    uint256 public constant AUCTION_DURATION = 36 hours;
    uint256 public constant ALLOCATION_DURATION = 7 days;
    uint256 public constant MAX_AUCTIONS = 4;
    uint256 public constant STARTING_PRICE_MULTIPLIER = 2e18; // 2x
    uint256 public constant BASE_PRICE_DIVISOR = 2e18; // 0.5x
    uint256 public constant MINIMUM_PRICE = 100e18; // 100 tokens
    uint256 public constant INITIAL_PRICE = 1000e18; // 1000 tokens
    uint256 public constant PROPOSAL_VALIDITY_DURATION = 1 days;

    event AuctionStarted(
        uint256 indexed auctionId,
        bytes32 indexed validatorHash,
        uint256 startingPrice,
        uint256 basePrice,
        uint256 startTime,
        uint256 allocationDuration
    );

    event AuctionClaimed(
        uint256 indexed auctionId,
        address indexed winner,
        bytes32 indexed validatorHash,
        uint256 pricePaid,
        uint256 controlTokenId,
        uint256 allocationDuration
    );

    function setUp() public {
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

        // Deploy contracts using helper to handle circular dependencies
        (nft, manager, auction) = _deployContracts();

        // Setup user balances
        paymentToken.mint(user1, 1000000e18);
        paymentToken.mint(user2, 1000000e18);

        // Whitelist vaults
        chef.setWhitelistedVault(vault1, true);
        chef.setWhitelistedVault(vault2, true);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(address(auction.paymentToken()), address(paymentToken));
        assertEq(auction.treasury(), treasury);
        assertEq(address(auction.chef()), address(chef));
        assertEq(address(auction.controlNFT()), address(nft));
        assertEq(address(auction.controlManager()), address(manager));
        assertTrue(auction.hasRole(auction.KEEPER_ROLE(), keeper));
        assertTrue(auction.hasRole(auction.GOVERNANCE_ROLE(), owner));
        assertTrue(auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(auction.auctionDuration(), AUCTION_DURATION);
        assertEq(auction.allocationDuration(), ALLOCATION_DURATION);
        assertEq(auction.maxAuctions(), MAX_AUCTIONS);
        assertFalse(auction.paused());
    }

    // ERC7201
    function test_ERC7201_Storage_Slot() public pure {
        assertEq(
            keccak256(
                abi.encode(
                    uint256(
                        keccak256("infrared.storage.CuttingBoardDutchAuction")
                    ) - 1
                )
            ) & ~bytes32(uint256(0xff)),
            0x67c283459ab08c5e5e83c645bebd5b8d5f91d5b9fb7d2a34ff4694a99438fd00
        );
    }

    /*//////////////////////////////////////////////////////////////
                    START VALIDATOR AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_startCuttingBoardAuction_Success() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // uint256 expectedStartingPrice =
        //     (INITIAL_PRICE * STARTING_PRICE_MULTIPLIER) / 1e18;
        // uint256 expectedBasePrice = (INITIAL_PRICE * 1e18) / BASE_PRICE_DIVISOR;

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 1);
        assertTrue(auction.isAuctionActive(0));

        bytes memory storedPubkey = auction.getAuctionValidator(0);
        assertEq(storedPubkey, validatorPubkey1);
    }

    function test_startCuttingBoardAuction_RevertIf_ValidatorNotAvailable()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Try to start auction for same validator - should fail because previous auction not claimed
        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuction.PreviousAuctionNotClaimed.selector
        );
        auction.startCuttingBoardAuction(validatorPubkey1);
    }

    function test_startCuttingBoardAuction_DifferentValidators() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.startPrank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Claim first auction
        vm.stopPrank();

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Now start auction for different validator
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
    }

    function test_startCuttingBoardAuction_RevertIf_EmptyPubkey() public {
        auction.setInitialPrice(INITIAL_PRICE);

        bytes memory emptyPubkey = "";

        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuction.InvalidValidatorPubkey.selector
        );
        auction.startCuttingBoardAuction(emptyPubkey);
    }

    /*//////////////////////////////////////////////////////////////
                    CLAIM VALIDATOR CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claimCuttingBoardControl_Success() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 6000});
        weights[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 4000});

        uint256 price = auction.getCurrentPrice(0);

        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Check NFT was minted
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.ownerOf(1), user1);
        assertTrue(nft.isValid(1));

        // Check auction state
        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(0);

        assertEq(auctionData.winner, user1);
        assertTrue(auctionData.claimed);
        assertEq(auctionData.controlTokenId, 1);

        // Check payment
        assertEq(paymentToken.balanceOf(treasury), price);
    }

    function test_claimCuttingBoardControl_InitialBoardSet() public {
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

        // Verify initial cutting board proposal was created
        uint256 tokenId = 1; // First NFT minted
        (address proposer,,, bool exists, IBeraChef.Weight[] memory propWeights)
        = manager.getProposal(tokenId);

        assertTrue(exists);
        assertEq(proposer, user1);
        assertEq(propWeights.length, 1);
        assertEq(propWeights[0].receiver, vault1);
        assertEq(propWeights[0].percentageNumerator, 10000);

        // Infrared should NOT be called yet (proposal not approved)
        assertEq(infrared.queueCallCount(), 0);

        // Keeper approves the proposal
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // Now infrared should be called
        assertEq(infrared.queueCallCount(), 1);
        assertEq(infrared.lastQueuedPubkey(), validatorPubkey1);
    }

    function test_claimCuttingBoardControl_RevertIf_InvalidWeights() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Invalid weights (don't sum to 10000)
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 5000});

        uint256 price = auction.getCurrentPrice(0);

        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        vm.expectRevert(CuttingBoardManager.InvalidWeightSum.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();
    }

    function test_claimCuttingBoardControl_RevertIf_EmptyWeights() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](0);

        vm.startPrank(user1);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidWeights.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATOR AVAILABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsValidatorAvailable_InitiallyTrue() public view {
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_IsValidatorAvailable_FalseWhenAuctionActive() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertFalse(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_IsValidatorAvailable_FalseDuringControlPeriod() public {
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

        // Still not available during control period
        assertFalse(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_IsValidatorAvailable_TrueAfterExpiry() public {
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

        // Warp past allocation duration
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // Now available again
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATOR ALLOCATED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsValidatorAllocated_InitiallyFalse() public view {
        assertFalse(auction.isValidatorAllocated(validatorPubkey1));
    }

    function test_IsValidatorAllocated_FalseWhenAuctionActiveButNotClaimed()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Auction is active but not claimed - validator is not allocated
        assertFalse(auction.isValidatorAllocated(validatorPubkey1));
    }

    function test_IsValidatorAllocated_TrueDuringControlPeriod() public {
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

        // Validator is now allocated during control period
        assertTrue(auction.isValidatorAllocated(validatorPubkey1));
    }

    function test_IsValidatorAllocated_FalseAfterExpiry() public {
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

        // Warp past allocation duration
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // No longer allocated after expiry
        assertFalse(auction.isValidatorAllocated(validatorPubkey1));
    }

    function test_IsValidatorAllocated_TrueAtExactExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 claimTime = block.timestamp;
        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Warp to exactly the expiry timestamp
        vm.warp(claimTime + ALLOCATION_DURATION + 1);

        // At exact expiry (expiry > block.timestamp), not allocated
        assertFalse(auction.isValidatorAllocated(validatorPubkey1));
    }

    function test_IsValidatorAllocated_TrueJustBeforeExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 claimTime = block.timestamp;
        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Warp to 1 second before expiry
        vm.warp(claimTime + ALLOCATION_DURATION - 1);

        // Still allocated just before expiry
        assertTrue(auction.isValidatorAllocated(validatorPubkey1));
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullLifecycle_AuctionToControl() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // 1. Start auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // 2. Claim auction
        IBeraChef.Weight[] memory initialWeights = new IBeraChef.Weight[](1);
        initialWeights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, initialWeights);
        vm.stopPrank();

        uint256 tokenId = 1;

        // 3. Verify NFT
        assertEq(nft.ownerOf(tokenId), user1);
        assertTrue(nft.isValid(tokenId));

        // Approve initial proposal from claim
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // 4. Update cutting board after delay
        vm.roll(block.number + chef.rewardAllocationBlockDelay());

        IBeraChef.Weight[] memory newWeights = new IBeraChef.Weight[](2);
        newWeights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 7000});
        newWeights[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 3000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, newWeights);

        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // 5. Transfer NFT
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // 6. New owner can update
        vm.roll(block.number + chef.rewardAllocationBlockDelay());

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId, initialWeights);

        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // 7. Control expires
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
        assertFalse(nft.isValid(tokenId));

        // 8. Validator available for new auction
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_MultipleAuctions_DifferentValidators() public {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Auction 1: validator 1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price1 = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price1);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Auction 2: validator 2
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        uint256 price2 = auction.getCurrentPrice(1);
        vm.startPrank(user2);
        paymentToken.approve(address(auction), price2);
        auction.claimCuttingBoardControl(1, weights);
        vm.stopPrank();

        // Both NFTs exist and are valid
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.balanceOf(user2), 1);
        assertTrue(nft.isValid(1));
        assertTrue(nft.isValid(2));

        // Both validators are controlled
        assertFalse(auction.isValidatorAvailable(validatorPubkey1));
        assertFalse(auction.isValidatorAvailable(validatorPubkey2));
    }

    function test_SecondaryMarket_NFTTrading() public {
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

        uint256 tokenId = 1;

        // Approve initial proposal from claim
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // User1 sells NFT to user2 (simulated OTC trade)
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // User2 now controls the validator
        assertEq(nft.ownerOf(tokenId), user2);

        // User2 can update cutting board
        vm.roll(block.number + chef.rewardAllocationBlockDelay());

        IBeraChef.Weight[] memory newWeights = new IBeraChef.Weight[](1);
        newWeights[0] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 10000});

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId, newWeights);

        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);
    }

    function test_EmergencyRevocation() public {
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

        uint256 tokenId = 1;
        assertTrue(nft.isValid(tokenId));

        // Owner revokes control (emergency)
        manager.revokeControl(tokenId);

        assertFalse(nft.isValid(tokenId));

        // User1 still owns NFT but can't propose
        assertEq(nft.ownerOf(tokenId), user1);

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.NFTInactive.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ClaimAtRandomPrice(uint256 elapsed) public {
        // Bound elapsed to valid auction period (0 to just before expiry)
        elapsed = bound(elapsed, 0, AUCTION_DURATION - 1);

        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        vm.warp(block.timestamp + elapsed);

        uint256 price = auction.getCurrentPrice(0);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), user1);
        assertTrue(nft.isValid(1));
    }

    function testFuzz_ValidWeightDistributions(uint96 weight1) public {
        // Bound weight1 to valid range (1 to 9999) so weight2 is also valid
        weight1 = uint96(bound(weight1, 1, 9999));
        uint96 weight2 = uint96(10000 - uint256(weight1));

        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: weight1});
        weights[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: weight2});

        uint256 price = auction.getCurrentPrice(0);

        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        assertTrue(nft.isValid(1));
    }

    /*//////////////////////////////////////////////////////////////
                    GET LAST AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastAuction_NoAuctions() public view {
        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bytes memory validatorPubkey,
            bool exists
        ) = auction.getLastAuction();

        assertEq(auctionId, 0);
        assertEq(auctionData.startTime, 0);
        assertEq(auctionData.startingPrice, 0);
        assertEq(auctionData.winner, address(0));
        assertFalse(auctionData.claimed);
        assertEq(validatorPubkey.length, 0);
        assertFalse(exists);
    }

    function test_getLastAuction_OneAuction() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bytes memory validatorPubkey,
            bool exists
        ) = auction.getLastAuction();

        assertEq(auctionId, 0);
        assertEq(auctionData.startTime, block.timestamp);
        assertFalse(auctionData.claimed);
        assertEq(validatorPubkey, validatorPubkey1);
        assertTrue(exists);
    }

    function test_getLastAuction_MultipleAuctions() public {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Start and claim first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Start second auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bytes memory validatorPubkey,
            bool exists
        ) = auction.getLastAuction();

        assertEq(auctionId, 1);
        assertFalse(auctionData.claimed);
        assertEq(validatorPubkey, validatorPubkey2);
        assertTrue(exists);
    }

    function test_getLastAuction_ClaimedAuction() public {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bytes memory validatorPubkey,
            bool exists
        ) = auction.getLastAuction();

        assertEq(auctionId, 0);
        assertTrue(auctionData.claimed);
        assertEq(auctionData.winner, user1);
        assertEq(validatorPubkey, validatorPubkey1);
        assertTrue(exists);
    }

    /*//////////////////////////////////////////////////////////////
                GET LAST VALIDATOR AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastValidatorAuction_NoAuctions() public view {
        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bool exists
        ) = auction.getLastValidatorAuction(validatorPubkey1);

        assertEq(auctionId, 0);
        assertEq(auctionData.startTime, 0);
        assertFalse(exists);
    }

    function test_getLastValidatorAuction_ValidatorNotFound() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Search for a different validator
        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bool exists
        ) = auction.getLastValidatorAuction(validatorPubkey2);

        assertEq(auctionId, 0);
        assertEq(auctionData.startTime, 0);
        assertFalse(exists);
    }

    function test_getLastValidatorAuction_FoundAtIndex0() public {
        // This test verifies the fix for the off-by-one bug
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bool exists
        ) = auction.getLastValidatorAuction(validatorPubkey1);

        assertEq(auctionId, 0);
        assertEq(auctionData.startTime, block.timestamp);
        assertTrue(exists);
    }

    function test_getLastValidatorAuction_MultipleAuctionsSameValidator()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Start and claim first auction for validator1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price1 = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price1);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Wait for control period to expire
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // Start second auction for same validator
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (
            uint256 auctionId,
            CuttingBoardDutchAuction.Auction memory auctionData,
            bool exists
        ) = auction.getLastValidatorAuction(validatorPubkey1);

        // Should return the most recent auction (index 1)
        assertEq(auctionId, 1);
        assertFalse(auctionData.claimed);
        assertTrue(exists);
    }

    function test_getLastValidatorAuction_DifferentValidators() public {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Auction 0: validator1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Auction 1: validator2
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        price = auction.getCurrentPrice(1);
        vm.startPrank(user2);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(1, weights);
        vm.stopPrank();

        // Check validator1's last auction is index 0
        (uint256 auctionId1,, bool exists1) =
            auction.getLastValidatorAuction(validatorPubkey1);

        assertEq(auctionId1, 0);
        assertTrue(exists1);

        // Check validator2's last auction is index 1
        (uint256 auctionId2,, bool exists2) =
            auction.getLastValidatorAuction(validatorPubkey2);

        assertEq(auctionId2, 1);
        assertTrue(exists2);
    }

    function test_getLastValidatorAuction_Index0WithMultipleAuctions() public {
        // This test specifically verifies the bug fix for index 0
        // when multiple auctions exist
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Auction 0: validator1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        uint256 price = auction.getCurrentPrice(0);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Auction 1: validator2
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        price = auction.getCurrentPrice(1);
        vm.startPrank(user2);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(1, weights);
        vm.stopPrank();

        // Wait for control period to expire
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // Auction 2: validator2 again
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Verify validator1's auction at index 0 is found correctly
        (uint256 auctionId,, bool exists) =
            auction.getLastValidatorAuction(validatorPubkey1);

        assertEq(auctionId, 0);
        assertTrue(exists);
    }

    /*//////////////////////////////////////////////////////////////
                    EXPIRED AUCTION AUTO-SKIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_startAuction_SucceedsAfterPreviousExpires() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 1);
        assertTrue(auction.isAuctionActive(0));

        // Warp past auction duration (let it expire without claiming)
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Previous auction is still unclaimed
        (CuttingBoardDutchAuction.Auction memory prevAuction,) =
            auction.getAuction(0);
        assertFalse(prevAuction.claimed);

        // Start new auction for different validator - should succeed
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
        assertTrue(auction.isAuctionActive(1));

        // First auction remains unclaimed
        (prevAuction,) = auction.getAuction(0);
        assertFalse(prevAuction.claimed);
    }

    function test_startAuction_RevertIf_PreviousNotExpired() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to middle of auction (not expired yet)
        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        // Try to start another auction - should fail
        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuction.PreviousAuctionNotClaimed.selector
        );
        auction.startCuttingBoardAuction(validatorPubkey2);
    }

    function test_startAuction_SucceedsAtExactExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 startTime = block.timestamp;

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to exactly auction end time
        vm.warp(startTime + AUCTION_DURATION);

        // Starting new auction should succeed at exact expiry
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
    }

    function test_startAuction_RevertIf_OneSecondBeforeExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 startTime = block.timestamp;

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to 1 second before auction ends
        vm.warp(startTime + AUCTION_DURATION - 1);

        // Should still fail - auction not yet expired
        vm.prank(keeper);
        vm.expectRevert(
            CuttingBoardDutchAuction.PreviousAuctionNotClaimed.selector
        );
        auction.startCuttingBoardAuction(validatorPubkey2);
    }

    function test_startAuction_ClearsActiveValidatorMapping() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction for validator1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Validator1 is not available (has active auction)
        assertFalse(auction.isValidatorAvailable(validatorPubkey1));

        // Warp past auction duration
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start new auction for validator2 (this triggers cleanup of validator1's active auction)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Validator1 should now be available again (active auction mapping cleared)
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
    }

    function test_startAuction_SameValidatorAfterExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction for validator1
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp past auction duration
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start new auction for same validator - should succeed
        // (previous expired, so validator becomes available again)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 2);

        // Both auctions should be for validator1
        bytes memory validator0 = auction.getAuctionValidator(0);
        bytes memory validator1 = auction.getAuctionValidator(1);
        assertEq(keccak256(validator0), keccak256(validatorPubkey1));
        assertEq(keccak256(validator1), keccak256(validatorPubkey1));
    }

    function test_startAuction_MultipleExpiredAuctions() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Let it expire
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start second auction (skipping first)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Let it expire too
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start third auction (skipping second)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 3);

        // First two auctions are unclaimed
        (CuttingBoardDutchAuction.Auction memory auction0,) =
            auction.getAuction(0);
        (CuttingBoardDutchAuction.Auction memory auction1,) =
            auction.getAuction(1);
        (CuttingBoardDutchAuction.Auction memory auction2,) =
            auction.getAuction(2);

        assertFalse(auction0.claimed);
        assertFalse(auction1.claimed);
        assertFalse(auction2.claimed);

        // Third auction is active
        assertTrue(auction.isAuctionActive(2));
    }

    function test_expiredAuction_CannotBeClaimed() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp past auction duration (expired)
        vm.warp(block.timestamp + AUCTION_DURATION);

        // Attempting to get price should revert
        vm.expectRevert(CuttingBoardDutchAuction.AuctionExpired.selector);
        auction.getCurrentPrice(0);

        // Attempting to claim should also revert
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), INITIAL_PRICE * 2);
        vm.expectRevert(CuttingBoardDutchAuction.AuctionExpired.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();
    }

    function test_expiredAuction_CannotBeClaimedAfterNewAuctionStarts()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp past auction duration
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start new auction (this skips the expired one)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Attempting to claim the old expired auction should revert
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), INITIAL_PRICE * 2);
        vm.expectRevert(CuttingBoardDutchAuction.AuctionExpired.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // New auction can still be claimed
        uint256 newPrice = auction.getCurrentPrice(1);
        vm.startPrank(user1);
        paymentToken.approve(address(auction), newPrice);
        auction.claimCuttingBoardControl(1, weights);
        vm.stopPrank();

        // Only validator2 has control period (validator1's auction expired)
        assertTrue(auction.isValidatorAvailable(validatorPubkey1));
        assertFalse(auction.isValidatorAvailable(validatorPubkey2));
    }

    function test_claim_SucceedsOneSecondBeforeExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 startTime = block.timestamp;

        // Start auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to 1 second before expiry
        vm.warp(startTime + AUCTION_DURATION - 1);

        // Should still be able to claim
        uint256 price = auction.getCurrentPrice(0);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), price);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(0);
        assertTrue(auctionData.claimed);
    }

    function test_claim_RevertsAtExactExpiry() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 startTime = block.timestamp;

        // Start auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to exactly expiry
        vm.warp(startTime + AUCTION_DURATION);

        // Should revert
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), INITIAL_PRICE * 2);
        vm.expectRevert(CuttingBoardDutchAuction.AuctionExpired.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();
    }

    function testFuzz_startAuction_AfterExpiry(uint256 extraTime) public {
        extraTime = bound(extraTime, 0, 365 days);

        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp past auction duration plus some extra time
        vm.warp(block.timestamp + AUCTION_DURATION + extraTime);

        // Should always be able to start new auction after expiry
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        assertEq(auction.getAuctionCount(), 2);
    }

    function testFuzz_claim_RevertsAfterExpiry(uint256 extraTime) public {
        extraTime = bound(extraTime, 0, 365 days);

        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to expiry + extra time
        vm.warp(block.timestamp + AUCTION_DURATION + extraTime);

        // Should always revert after expiry
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), INITIAL_PRICE * 2);
        vm.expectRevert(CuttingBoardDutchAuction.AuctionExpired.selector);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                EXPIRED AUCTION PRICE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_expiredAuction_UpdatesLastClosingPriceToBasePrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Get the base price of the first auction
        (CuttingBoardDutchAuction.Auction memory firstAuction,) =
            auction.getAuction(0);
        uint256 expectedNewClosingPrice = firstAuction.basePrice;

        // Verify lastClosingPrice is still INITIAL_PRICE
        assertEq(auction.lastClosingPrice(), INITIAL_PRICE);

        // Let auction expire without claiming
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start new auction - this should update lastClosingPrice to expired auction's basePrice
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Verify lastClosingPrice was updated to the expired auction's base price
        assertEq(auction.lastClosingPrice(), expectedNewClosingPrice);
    }

    function test_expiredAuction_NewAuctionPricingBasedOnBasePrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Get the base price of the first auction
        (CuttingBoardDutchAuction.Auction memory firstAuction,) =
            auction.getAuction(0);
        uint256 expiredBasePrice = firstAuction.basePrice;

        // Let auction expire
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start new auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // Get new auction details
        (CuttingBoardDutchAuction.Auction memory secondAuction,) =
            auction.getAuction(1);

        // Verify new auction pricing is based on expired auction's base price
        uint256 expectedStartingPrice =
            (expiredBasePrice * STARTING_PRICE_MULTIPLIER) / 1e18;
        uint256 expectedBasePrice =
            (expiredBasePrice * 1e18) / BASE_PRICE_DIVISOR;

        // Base price should be at least minimum price
        if (expectedBasePrice < MINIMUM_PRICE) {
            expectedBasePrice = MINIMUM_PRICE;
        }

        assertEq(secondAuction.startingPrice, expectedStartingPrice);
        assertEq(secondAuction.basePrice, expectedBasePrice);
    }

    function test_expiredAuction_ConsecutiveExpiriesReducePrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start first auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory auction0,) =
            auction.getAuction(0);
        uint256 basePrice0 = auction0.basePrice;

        // Let it expire
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start second auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory auction1,) =
            auction.getAuction(1);
        uint256 basePrice1 = auction1.basePrice;

        // Let it expire
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Start third auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory auction2,) =
            auction.getAuction(2);
        uint256 basePrice2 = auction2.basePrice;

        // Each consecutive expired auction should have lower base price
        // (until it hits minimum price floor)
        assertTrue(
            basePrice1 <= basePrice0,
            "Second auction base price should be <= first"
        );
        assertTrue(
            basePrice2 <= basePrice1,
            "Third auction base price should be <= second"
        );
    }

    function test_expiredAuction_PriceEventuallyHitsMinimum() public {
        // Set a high initial price so we can see multiple reductions
        uint256 highInitialPrice = 10000e18;
        auction.setInitialPrice(highInitialPrice);

        // Run expired auctions until price hits minimum (limited by maxAuctions=4)
        uint256 maxIterations = MAX_AUCTIONS;
        bool hitMinimum = false;

        for (uint256 i = 0; i < maxIterations; i++) {
            bytes memory pubkey =
                i % 2 == 0 ? validatorPubkey1 : validatorPubkey2;

            // Check if previous validator's control has expired (if needed)
            if (i > 1) {
                // Warp past allocation duration to make validator available
                vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
            }

            vm.prank(keeper);
            auction.startCuttingBoardAuction(pubkey);

            (CuttingBoardDutchAuction.Auction memory auctionData,) =
                auction.getAuction(i);

            // Check if we've hit minimum price
            if (auctionData.basePrice == MINIMUM_PRICE) {
                hitMinimum = true;
                // Verify lastClosingPrice is also at or near minimum
                assertTrue(
                    auction.lastClosingPrice() >= MINIMUM_PRICE,
                    "lastClosingPrice should be >= minimum"
                );
                break;
            }

            // Let auction expire
            vm.warp(block.timestamp + AUCTION_DURATION + 1);
        }

        // With basePriceDivisor=2, price halves each expired auction
        // From 10000e18: 5000 -> 2500 -> 1250 -> 625 -> ...
        // Should hit minimum (100e18) relatively quickly
        // If we didn't hit minimum within MAX_AUCTIONS, verify price is decreasing
        if (!hitMinimum) {
            assertTrue(
                auction.lastClosingPrice() < highInitialPrice,
                "Price should have decreased from initial"
            );
        }
    }

    function test_claimedAuction_UpdatesLastClosingPriceToClaimPrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Warp to middle of auction to get a mid-range price
        vm.warp(block.timestamp + AUCTION_DURATION / 2);

        uint256 claimPrice = auction.getCurrentPrice(0);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(user1);
        paymentToken.approve(address(auction), claimPrice);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // lastClosingPrice should be updated to the claim price
        assertEq(auction.lastClosingPrice(), claimPrice);
    }

    /*//////////////////////////////////////////////////////////////
            SET MINIMUM PRICE WITH LASTCLOSINGPRICE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMinimumPrice_UpdatesLastClosingPriceWhenHigher() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Set minimum price higher than lastClosingPrice
        uint256 newMinimumPrice = INITIAL_PRICE * 2;

        vm.prank(keeper);
        auction.setMinimumPrice(newMinimumPrice);

        // lastClosingPrice should be updated to new minimum
        assertEq(auction.lastClosingPrice(), newMinimumPrice);
    }

    function test_setMinimumPrice_DoesNotUpdateLastClosingPriceWhenLower()
        public
    {
        auction.setInitialPrice(INITIAL_PRICE);

        // Set minimum price lower than lastClosingPrice
        uint256 newMinimumPrice = INITIAL_PRICE / 2;

        vm.prank(keeper);
        auction.setMinimumPrice(newMinimumPrice);

        // lastClosingPrice should remain unchanged
        assertEq(auction.lastClosingPrice(), INITIAL_PRICE);
    }

    function test_setMinimumPrice_AuctionCanStartAfterHighMinimumSet() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Set minimum price much higher than lastClosingPrice
        // This would have previously caused InvalidPriceRange
        uint256 newMinimumPrice = INITIAL_PRICE * 3;

        vm.prank(keeper);
        auction.setMinimumPrice(newMinimumPrice);

        // Should now be able to start auction without InvalidPriceRange
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        // Verify auction was created with correct pricing
        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(0);

        // Starting price should be based on updated lastClosingPrice (newMinimumPrice)
        uint256 expectedStartingPrice =
            (newMinimumPrice * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(auctionData.startingPrice, expectedStartingPrice);

        // Base price should be at least the new minimum
        assertTrue(auctionData.basePrice >= newMinimumPrice);
    }

    function test_setMinimumPrice_EmitsInitialPriceSetWhenUpdating() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 newMinimumPrice = INITIAL_PRICE * 2;

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit InitialPriceSet(newMinimumPrice);
        auction.setMinimumPrice(newMinimumPrice);
    }

    function test_setMinimumPrice_PreventsInvalidPriceRangeScenario() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Calculate what minimum price would cause InvalidPriceRange without the fix
        // starting = lastClosingPrice * 2 = INITIAL_PRICE * 2
        // If minimumPrice > starting, we'd get InvalidPriceRange
        uint256 problematicMinimumPrice =
            (INITIAL_PRICE * STARTING_PRICE_MULTIPLIER / 1e18) + 1;

        vm.prank(keeper);
        auction.setMinimumPrice(problematicMinimumPrice);

        // With the fix, lastClosingPrice is updated, so this should work
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 1);
    }

    function testFuzz_setMinimumPrice_AlwaysAllowsValidAuction(
        uint256 newMinimumPrice
    ) public {
        // Bound to reasonable range
        newMinimumPrice = bound(
            newMinimumPrice, 1, type(uint128).max / STARTING_PRICE_MULTIPLIER
        );

        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.setMinimumPrice(newMinimumPrice);

        // Should always be able to start auction after setting minimum price
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 1);

        // Verify pricing is valid (starting > base)
        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(0);
        assertTrue(
            auctionData.startingPrice > auctionData.basePrice,
            "Starting price must be > base price"
        );
    }

    /*//////////////////////////////////////////////////////////////
                SET CLOSING PRICE REFERENCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setClosingPriceReference_Success() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 newPrice = 500e18;

        vm.prank(keeper);
        auction.setClosingPriceReference(newPrice);

        assertEq(auction.lastClosingPrice(), newPrice);
    }

    function test_setClosingPriceReference_EmitsEvent() public {
        auction.setInitialPrice(INITIAL_PRICE);

        uint256 newPrice = 500e18;

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit InitialPriceSet(newPrice);
        auction.setClosingPriceReference(newPrice);
    }

    function test_setClosingPriceReference_RevertIf_ZeroPrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidPrice.selector);
        auction.setClosingPriceReference(0);
    }

    function test_setClosingPriceReference_RevertIf_NotKeeper() public {
        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(user1);
        vm.expectRevert();
        auction.setClosingPriceReference(500e18);
    }

    function test_setClosingPriceReference_CanRecoverFromLowPrice() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction and claim it (not expire) so we have a clean state
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Claim at a low price (near end of auction)
        vm.warp(block.timestamp + AUCTION_DURATION - 1);
        uint256 lowClaimPrice = auction.getCurrentPrice(0);

        vm.startPrank(user1);
        paymentToken.approve(address(auction), lowClaimPrice);
        auction.claimCuttingBoardControl(0, weights);
        vm.stopPrank();

        // Price has been reduced due to low claim price
        assertEq(auction.lastClosingPrice(), lowClaimPrice);
        assertTrue(
            lowClaimPrice < INITIAL_PRICE,
            "Claim price should be lower than initial"
        );

        // Keeper can reset price to a higher value
        uint256 recoveryPrice = INITIAL_PRICE;
        vm.prank(keeper);
        auction.setClosingPriceReference(recoveryPrice);

        assertEq(auction.lastClosingPrice(), recoveryPrice);

        // Wait for control period to expire
        vm.warp(block.timestamp + ALLOCATION_DURATION + 1);

        // New auction should use the recovered price (no expired unclaimed auction to overwrite it)
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(1);

        uint256 expectedStartingPrice =
            (recoveryPrice * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(auctionData.startingPrice, expectedStartingPrice);
    }

    function test_setClosingPriceReference_WorksBeforeAnyAuctions() public {
        // Set initial price first
        auction.setInitialPrice(INITIAL_PRICE);

        // Keeper can also adjust using setClosingPriceReference
        uint256 adjustedPrice = INITIAL_PRICE * 2;
        vm.prank(keeper);
        auction.setClosingPriceReference(adjustedPrice);

        assertEq(auction.lastClosingPrice(), adjustedPrice);

        // Start auction with adjusted price
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(0);

        uint256 expectedStartingPrice =
            (adjustedPrice * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(auctionData.startingPrice, expectedStartingPrice);
    }

    function test_setClosingPriceReference_WorksAfterAuctionsStarted() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start and claim an auction
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

        // Keeper can still adjust price reference
        uint256 newPrice = 2000e18;
        vm.prank(keeper);
        auction.setClosingPriceReference(newPrice);

        assertEq(auction.lastClosingPrice(), newPrice);
    }

    function testFuzz_setClosingPriceReference_AnyValidPrice(uint256 newPrice)
        public
    {
        // The price must be high enough that:
        // starting = newPrice * 2 (startingPriceMultiplier)
        // base = newPrice / 2 (basePriceDivisor)
        // And starting > base (always true for any newPrice > 0)
        // But also base >= minimumPrice, or if base < minimumPrice, then starting > minimumPrice
        // If base < minimumPrice: base = minimumPrice
        // So we need: starting > minimumPrice
        // starting = newPrice * 2
        // We need: newPrice * 2 > minimumPrice
        // newPrice > minimumPrice / 2
        // minimumPrice = 100e18, so newPrice > 50e18

        // Bound to valid range that ensures starting > base after minimum price floor
        newPrice = bound(
            newPrice,
            MINIMUM_PRICE / 2 + 1,
            type(uint128).max / STARTING_PRICE_MULTIPLIER
        );

        auction.setInitialPrice(INITIAL_PRICE);

        vm.prank(keeper);
        auction.setClosingPriceReference(newPrice);

        assertEq(auction.lastClosingPrice(), newPrice);

        // Should be able to start auction with any valid price
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        assertEq(auction.getAuctionCount(), 1);
    }

    /*//////////////////////////////////////////////////////////////
            COMBINED EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_edgeCase_ExpiredAuctionThenMinimumPriceIncrease() public {
        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction and let it expire
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory expiredAuction,) =
            auction.getAuction(0);
        uint256 expiredBasePrice = expiredAuction.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // When starting new auction after expired:
        // 1. lastClosingPrice = expiredBasePrice (from expired auction processing)
        // 2. starting = expiredBasePrice * 2 (multiplier)
        // 3. base = expiredBasePrice / 2 (divisor)
        // 4. If base < minimumPrice, base = minimumPrice
        // 5. Check: starting > base must be true

        // To test minimum price as floor without causing InvalidPriceRange,
        // we need: starting > minimumPrice
        // starting = expiredBasePrice * 2
        // So minimumPrice must be < expiredBasePrice * 2

        // Set minimum price higher than calculated base but lower than starting
        // expiredBasePrice = 500e18 (from INITIAL_PRICE=1000e18, divided by 2)
        // starting = 1000e18
        // calculated base = 250e18
        // Set minimum to 400e18 (> 250e18 but < 1000e18)
        uint256 newMinimum = (expiredBasePrice * 8) / 10; // 80% of expiredBasePrice = 400e18

        vm.prank(keeper);
        auction.setMinimumPrice(newMinimum);

        // Start new auction
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        (CuttingBoardDutchAuction.Auction memory newAuction,) =
            auction.getAuction(1);

        // Calculate expected values
        uint256 expectedStartingPrice =
            (expiredBasePrice * STARTING_PRICE_MULTIPLIER) / 1e18;

        uint256 calculatedBase = (expiredBasePrice * 1e18) / BASE_PRICE_DIVISOR;
        uint256 expectedBase =
            calculatedBase < newMinimum ? newMinimum : calculatedBase;

        // Verify the minimum price acted as floor
        assertEq(newAuction.basePrice, expectedBase);
        assertEq(newAuction.startingPrice, expectedStartingPrice);
        assertTrue(
            newAuction.basePrice >= newMinimum,
            "Base should be at least minimum"
        );
        assertTrue(
            newAuction.startingPrice > newAuction.basePrice,
            "Starting must be > base"
        );
    }

    function test_edgeCase_MinimumPriceTooHighCausesRevert() public {
        // This test documents that setting minimumPrice too high relative to
        // expired auction's base price will cause InvalidPriceRange
        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction and let it expire
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory expiredAuction,) =
            auction.getAuction(0);
        uint256 expiredBasePrice = expiredAuction.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Set minimum price HIGHER than what the starting price will be
        // starting = expiredBasePrice * 2, so minimum > expiredBasePrice * 2 will fail
        uint256 tooHighMinimum = expiredBasePrice * 3;
        vm.prank(keeper);
        auction.setMinimumPrice(tooHighMinimum);

        // Starting new auction will revert because:
        // starting = expiredBasePrice * 2 = 1000e18
        // base = minimumPrice = 1500e18
        // starting <= base -> InvalidPriceRange
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardDutchAuction.InvalidPriceRange.selector);
        auction.startCuttingBoardAuction(validatorPubkey2);
    }

    function test_edgeCase_KeeperResetsAfterClaimedAuction() public {
        auction.setInitialPrice(INITIAL_PRICE);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Run 2 auctions, claim them at low prices to drive price down
        for (uint256 i = 0; i < 2; i++) {
            bytes memory pubkey =
                i % 2 == 0 ? validatorPubkey1 : validatorPubkey2;

            vm.prank(keeper);
            auction.startCuttingBoardAuction(pubkey);

            // Claim near end of auction for low price
            vm.warp(block.timestamp + AUCTION_DURATION - 1);
            uint256 price = auction.getCurrentPrice(i);

            vm.startPrank(user1);
            paymentToken.approve(address(auction), price);
            auction.claimCuttingBoardControl(i, weights);
            vm.stopPrank();

            // Wait for control period to expire
            vm.warp(block.timestamp + ALLOCATION_DURATION + 1);
        }

        uint256 reducedPrice = auction.lastClosingPrice();
        assertTrue(reducedPrice < INITIAL_PRICE, "Price should have reduced");

        // Keeper resets price (no unclaimed expired auction to overwrite it)
        vm.prank(keeper);
        auction.setClosingPriceReference(INITIAL_PRICE);

        // Next auction uses reset price
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            auction.getAuction(2);

        uint256 expectedStartingPrice =
            (INITIAL_PRICE * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(auctionData.startingPrice, expectedStartingPrice);
    }

    function test_edgeCase_ExpiredAuctionOverwritesKeeperPrice() public {
        // This test documents the behavior that expired auction processing
        // ALWAYS overwrites lastClosingPrice, even if keeper set it beforehand
        auction.setInitialPrice(INITIAL_PRICE);

        // Start auction and let it expire
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey1);

        (CuttingBoardDutchAuction.Auction memory expiredAuction,) =
            auction.getAuction(0);
        uint256 expiredBasePrice = expiredAuction.basePrice;

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        // Keeper sets a high price reference
        uint256 highPrice = INITIAL_PRICE * 5;
        vm.prank(keeper);
        auction.setClosingPriceReference(highPrice);

        assertEq(auction.lastClosingPrice(), highPrice);

        // Start new auction - this will overwrite with expired auction's base price
        vm.prank(keeper);
        auction.startCuttingBoardAuction(validatorPubkey2);

        // lastClosingPrice is now the expired auction's base price, not the keeper's high price
        assertEq(auction.lastClosingPrice(), expiredBasePrice);

        (CuttingBoardDutchAuction.Auction memory newAuction,) =
            auction.getAuction(1);

        // Starting price is based on expired base price
        uint256 expectedStartingPrice =
            (expiredBasePrice * STARTING_PRICE_MULTIPLIER) / 1e18;
        assertEq(newAuction.startingPrice, expectedStartingPrice);
    }

    event InitialPriceSet(uint256 price);

    // Helper function to deploy contracts with circular dependencies
    function _deployContracts()
        internal
        returns (
            CuttingBoardNFT _nft,
            CuttingBoardManager _manager,
            CuttingBoardDutchAuction _auction
        )
    {
        // Use vm.computeCreateAddress to predict addresses
        // Deployment order and nonces:
        // nonce + 0: NFT
        // nonce + 1: Manager implementation
        // nonce + 2: Manager proxy
        // nonce + 3: Auction implementation
        // nonce + 4: Auction proxy
        uint64 currentNonce = vm.getNonce(address(this));
        address predictedManagerProxy =
            vm.computeCreateAddress(address(this), currentNonce + 2);
        address predictedAuction =
            vm.computeCreateAddress(address(this), currentNonce + 4);

        // Deploy NFT with predicted auction and manager addresses
        _nft = new CuttingBoardNFT(
            predictedAuction, owner, predictedManagerProxy, ""
        );

        // Deploy Manager implementation
        CuttingBoardManager managerImpl = new CuttingBoardManager();

        // Deploy Manager proxy and initialize
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

        // Deploy Auction implementation
        CuttingBoardDutchAuction auctionImpl = new CuttingBoardDutchAuction();

        // Deploy Auction proxy and initialize (this should be at the predicted address)
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

        // Verify the prediction was correct
        require(
            address(_auction) == predictedAuction, "Auction address mismatch"
        );
    }
}
