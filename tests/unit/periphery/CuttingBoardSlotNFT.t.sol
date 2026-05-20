// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CuttingBoardSlotNFT} from "src/periphery/CuttingBoardSlotNFT.sol";

contract CuttingBoardSlotNFTTest is Test {
    CuttingBoardSlotNFT nft;

    address syndicate;
    address owner;
    address user1;
    address user2;

    uint256 constant AUCTION_ID = 1;
    uint256 constant EXPIRY = 7 days;
    address constant VAULT_A = address(0xA);
    address constant VAULT_B = address(0xB);

    // ── Events ─────────────────────────────────────────────────────────────────

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
    event SlotVaultUpdated(uint256 indexed tokenId, address indexed newVault);
    event Transfer(
        address indexed from, address indexed to, uint256 indexed id
    );

    // ── Setup ──────────────────────────────────────────────────────────────────

    function setUp() public {
        syndicate = makeAddr("syndicate");
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        nft = new CuttingBoardSlotNFT(syndicate, owner, "https://base.uri/");
    }

    // ── Helper ─────────────────────────────────────────────────────────────────

    function _mint(
        address to,
        uint256 auctionId,
        address originalPartner,
        uint96 allocatedWeight,
        uint96 requestedWeight,
        uint128 clearingPrice,
        address vault,
        uint256 expiry,
        bool isPartialFill
    ) internal returns (uint256 tokenId) {
        vm.prank(syndicate);
        tokenId = nft.mint(
            to,
            auctionId,
            originalPartner,
            allocatedWeight,
            requestedWeight,
            clearingPrice,
            vault,
            expiry,
            isPartialFill
        );
    }

    function _mintDefault(address to) internal returns (uint256 tokenId) {
        tokenId = _mint(
            to,
            AUCTION_ID,
            to,
            5000,
            5000,
            1000e18,
            VAULT_A,
            block.timestamp + EXPIRY,
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public view {
        assertEq(nft.syndicate(), syndicate);
        assertEq(nft.owner(), owner);
        assertEq(nft.totalSupply(), 0);
    }

    function test_constructor_revert_zeroSyndicate() public {
        vm.expectRevert(CuttingBoardSlotNFT.NotSyndicate.selector);
        new CuttingBoardSlotNFT(address(0), owner, "");
    }

    /*//////////////////////////////////////////////////////////////
                              MINT
    //////////////////////////////////////////////////////////////*/

    function test_mint_success() public {
        uint256 expiry = block.timestamp + EXPIRY;

        vm.expectEmit(true, true, true, true);
        emit SlotNFTMinted(
            1, AUCTION_ID, user1, VAULT_A, 5000, 6000, 1000e18, expiry, true
        );

        vm.prank(syndicate);
        uint256 tokenId = nft.mint(
            user1, AUCTION_ID, user1, 5000, 6000, 1000e18, VAULT_A, expiry, true
        );

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function test_mint_correctMetadata() public {
        uint256 expiry = block.timestamp + EXPIRY;

        vm.prank(syndicate);
        uint256 tokenId = nft.mint(
            user1, AUCTION_ID, user1, 4000, 6000, 500e18, VAULT_B, expiry, true
        );

        CuttingBoardSlotNFT.SlotRights memory r = nft.getSlotRights(tokenId);
        assertEq(r.auctionId, AUCTION_ID);
        assertEq(r.originalPartner, user1);
        assertEq(r.allocatedWeight, 4000);
        assertEq(r.requestedWeight, 6000);
        assertEq(r.clearingPrice, 500e18);
        assertEq(r.vault, VAULT_B);
        assertEq(r.expiryTimestamp, expiry);
        assertTrue(r.isPartialFill);
    }

    function test_mint_tokenIdIncrements() public {
        uint256 id1 = _mintDefault(user1);
        uint256 id2 = _mintDefault(user2);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(nft.totalSupply(), 2);
    }

    function test_mint_reverseLookup() public {
        uint256 tokenId = _mintDefault(user1);
        assertEq(nft.getTokenId(AUCTION_ID, user1), tokenId);
    }

    function test_mint_revert_notSyndicate() public {
        vm.expectRevert(CuttingBoardSlotNFT.NotSyndicate.selector);
        vm.prank(user1);
        nft.mint(
            user1,
            AUCTION_ID,
            user1,
            5000,
            5000,
            1000e18,
            VAULT_A,
            block.timestamp + EXPIRY,
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                           UPDATE VAULT
    //////////////////////////////////////////////////////////////*/

    function test_updateVault_success() public {
        uint256 tokenId = _mintDefault(user1);

        vm.expectEmit(true, true, false, false);
        emit SlotVaultUpdated(tokenId, VAULT_B);

        vm.prank(syndicate);
        nft.updateVault(tokenId, VAULT_B);

        assertEq(nft.getSlotRights(tokenId).vault, VAULT_B);
    }

    function test_updateVault_revert_notSyndicate() public {
        uint256 tokenId = _mintDefault(user1);

        vm.expectRevert(CuttingBoardSlotNFT.NotSyndicate.selector);
        vm.prank(user1);
        nft.updateVault(tokenId, VAULT_B);
    }

    function test_updateVault_revert_invalidTokenId() public {
        vm.expectRevert(CuttingBoardSlotNFT.InvalidTokenId.selector);
        vm.prank(syndicate);
        nft.updateVault(999, VAULT_B);
    }

    /*//////////////////////////////////////////////////////////////
                             IS VALID
    //////////////////////////////////////////////////////////////*/

    function test_isValid_trueBeforeExpiry() public {
        uint256 expiry = block.timestamp + EXPIRY;
        uint256 tokenId = _mint(
            user1,
            AUCTION_ID,
            user1,
            5000,
            5000,
            1000e18,
            VAULT_A,
            expiry,
            false
        );
        assertTrue(nft.isValid(tokenId));
    }

    function test_isValid_falseAfterExpiry() public {
        uint256 expiry = block.timestamp + EXPIRY;
        uint256 tokenId = _mint(
            user1,
            AUCTION_ID,
            user1,
            5000,
            5000,
            1000e18,
            VAULT_A,
            expiry,
            false
        );
        vm.warp(expiry + 1);
        assertFalse(nft.isValid(tokenId));
    }

    function test_isValid_falseForNonExistent() public view {
        assertFalse(nft.isValid(999));
    }

    function test_isValid_trueAtExactExpiry() public {
        uint256 expiry = block.timestamp + EXPIRY;
        uint256 tokenId = _mint(
            user1,
            AUCTION_ID,
            user1,
            5000,
            5000,
            1000e18,
            VAULT_A,
            expiry,
            false
        );
        vm.warp(expiry);
        assertTrue(nft.isValid(tokenId)); // block.timestamp == expiryTimestamp → valid
    }

    /*//////////////////////////////////////////////////////////////
                          GET SLOT RIGHTS
    //////////////////////////////////////////////////////////////*/

    function test_getSlotRights_success() public {
        uint256 tokenId = _mintDefault(user1);
        CuttingBoardSlotNFT.SlotRights memory r = nft.getSlotRights(tokenId);
        assertEq(r.auctionId, AUCTION_ID);
        assertEq(r.originalPartner, user1);
    }

    function test_getSlotRights_revert_invalidTokenId() public {
        vm.expectRevert(CuttingBoardSlotNFT.InvalidTokenId.selector);
        nft.getSlotRights(0);
    }

    /*//////////////////////////////////////////////////////////////
                           GET TOKEN ID
    //////////////////////////////////////////////////////////////*/

    function test_getTokenId_returnsTokenIdAfterMint() public {
        uint256 tokenId = _mintDefault(user1);
        assertEq(nft.getTokenId(AUCTION_ID, user1), tokenId);
    }

    function test_getTokenId_returnsZeroIfNotMinted() public view {
        assertEq(nft.getTokenId(AUCTION_ID, user1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            SET BASE URI
    //////////////////////////////////////////////////////////////*/

    function test_setBaseURI_success() public {
        vm.prank(owner);
        nft.setBaseURI("https://new.uri/");

        uint256 tokenId = _mintDefault(user1);
        assertEq(nft.tokenURI(tokenId), "https://new.uri/");
    }

    function test_setBaseURI_revert_notOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user1);
        nft.setBaseURI("https://evil.uri/");
    }

    /*//////////////////////////////////////////////////////////////
                         ERC-721 TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_transfer_changesOwnerOf() public {
        uint256 tokenId = _mintDefault(user1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_transfer_slotRightsUnchanged() public {
        uint256 expiry = block.timestamp + EXPIRY;
        vm.prank(syndicate);
        uint256 tokenId = nft.mint(
            user1, AUCTION_ID, user1, 5000, 8000, 999e18, VAULT_B, expiry, true
        );

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        CuttingBoardSlotNFT.SlotRights memory r = nft.getSlotRights(tokenId);
        assertEq(r.originalPartner, user1); // originalPartner unchanged
        assertEq(r.vault, VAULT_B);
        assertEq(r.allocatedWeight, 5000);
        assertTrue(r.isPartialFill);
    }

    function test_transfer_reverseLookupStillPointsToOriginal() public {
        uint256 tokenId = _mintDefault(user1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);
        // Reverse lookup by (auctionId, originalPartner) still works
        assertEq(nft.getTokenId(AUCTION_ID, user1), tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ
    //////////////////////////////////////////////////////////////*/

    function test_fuzz_mint_params(
        uint96 allocatedWeight,
        uint96 requestedWeight,
        uint128 clearingPrice,
        uint256 expiryTimestamp
    ) public {
        vm.prank(syndicate);
        uint256 tokenId = nft.mint(
            user1,
            AUCTION_ID,
            user1,
            allocatedWeight,
            requestedWeight,
            clearingPrice,
            VAULT_A,
            expiryTimestamp,
            allocatedWeight < requestedWeight
        );

        CuttingBoardSlotNFT.SlotRights memory r = nft.getSlotRights(tokenId);
        assertEq(r.allocatedWeight, allocatedWeight);
        assertEq(r.requestedWeight, requestedWeight);
        assertEq(r.clearingPrice, clearingPrice);
        assertEq(r.expiryTimestamp, expiryTimestamp);
    }

    function test_fuzz_isValid_expiryBoundary(uint256 offset) public {
        offset = bound(offset, 1, 365 days);
        uint256 expiry = block.timestamp + offset;
        uint256 tokenId = _mint(
            user1, AUCTION_ID, user1, 1000, 1000, 1e18, VAULT_A, expiry, false
        );

        // Valid up to and including expiry
        vm.warp(expiry);
        assertTrue(nft.isValid(tokenId));

        // Invalid one second after
        vm.warp(expiry + 1);
        assertFalse(nft.isValid(tokenId));
    }

    function test_fuzz_sequentialMints(uint8 count) public {
        count = uint8(bound(count, 1, 20));
        for (uint256 i = 0; i < count; i++) {
            address recipient = address(uint160(i + 1));
            vm.prank(syndicate);
            uint256 tokenId = nft.mint(
                recipient,
                i,
                recipient,
                5000,
                5000,
                1000e18,
                VAULT_A,
                block.timestamp + EXPIRY,
                false
            );
            assertEq(tokenId, i + 1);
            assertEq(nft.ownerOf(tokenId), recipient);
            assertEq(nft.getTokenId(i, recipient), tokenId);
        }
        assertEq(nft.totalSupply(), count);
    }
}
