// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";

contract CuttingBoardNFTTest is Test {
    CuttingBoardNFT public nft;

    address public owner;
    address public auction;
    address public manager;
    address public user1;
    address public user2;

    bytes public validatorPubkey1 = hex"1234567890abcdef";
    bytes public validatorPubkey2 = hex"fedcba0987654321";

    uint256 public constant EXPIRY_TIMESTAMP = 1000000;
    uint256 public constant AUCTION_ID = 1;

    event ControlNFTMinted(
        uint256 indexed tokenId,
        address indexed owner,
        bytes validatorPubkey,
        uint256 expiryTimestamp,
        uint256 indexed auctionId
    );

    event ControlNFTInvalidated(uint256 indexed tokenId);

    event ManagerUpdated(
        address indexed oldManager, address indexed newManager
    );

    function setUp() public {
        owner = address(this);
        auction = makeAddr("auction");
        manager = makeAddr("manager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        nft = new CuttingBoardNFT(
            auction, owner, manager, "https://infrared.finance/nft/"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        assertEq(nft.auction(), auction);
        assertEq(nft.owner(), owner);
        assertEq(nft.manager(), manager);
        assertEq(nft.name(), "Cutting Board NFT");
        assertEq(nft.symbol(), "CBNFT");
    }

    function test_Constructor_RevertIf_InvalidAuction() public {
        vm.expectRevert(CuttingBoardNFT.NotAuction.selector);
        new CuttingBoardNFT(address(0), owner, manager, "");
    }

    /*//////////////////////////////////////////////////////////////
                        SET MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetManager_Success() public {
        address newManager = makeAddr("newManager");

        vm.expectEmit(true, true, true, true);
        emit ManagerUpdated(manager, newManager);
        nft.setManager(newManager);

        assertEq(nft.manager(), newManager);
    }

    function test_SetManager_RevertIf_InvalidManager() public {
        vm.expectRevert(CuttingBoardNFT.InvalidManager.selector);
        nft.setManager(address(0));
    }

    function test_SetManager_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert("UNAUTHORIZED");
        nft.setManager(makeAddr("newManager"));
    }

    /*//////////////////////////////////////////////////////////////
                        MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        vm.prank(auction);
        vm.expectEmit(true, true, true, true);
        emit ControlNFTMinted(
            1, user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID
        );

        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.totalSupply(), 1);

        (bytes memory pubkey, uint256 expiry, uint256 auctionId, bool active) =
            nft.getControlRights(tokenId);

        assertEq(pubkey, validatorPubkey1);
        assertEq(expiry, EXPIRY_TIMESTAMP);
        assertEq(auctionId, AUCTION_ID);
        assertTrue(active);
    }

    function test_Mint_MultipleNFTs() public {
        vm.startPrank(auction);

        uint256 tokenId1 =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);
        uint256 tokenId2 = nft.mint(
            user2, validatorPubkey2, EXPIRY_TIMESTAMP + 1000, AUCTION_ID + 1
        );

        vm.stopPrank();

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(nft.ownerOf(tokenId1), user1);
        assertEq(nft.ownerOf(tokenId2), user2);
        assertEq(nft.totalSupply(), 2);
    }

    function test_Mint_RevertIf_NotAuction() public {
        vm.prank(user1);
        vm.expectRevert(CuttingBoardNFT.NotAuction.selector);
        nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        IS VALID TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsValid_Active() public {
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1, validatorPubkey1, block.timestamp + 1000, AUCTION_ID
        );

        assertTrue(nft.isValid(tokenId));
    }

    function test_IsValid_Expired() public {
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1, validatorPubkey1, block.timestamp + 1000, AUCTION_ID
        );

        // Warp past expiry
        vm.warp(block.timestamp + 1001);

        assertFalse(nft.isValid(tokenId));
    }

    function test_IsValid_Invalidated() public {
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1, validatorPubkey1, block.timestamp + 1000, AUCTION_ID
        );

        // Invalidate
        vm.prank(manager);
        nft.invalidate(tokenId);

        assertFalse(nft.isValid(tokenId));
    }

    function test_IsValid_NonExistentToken() public view {
        assertFalse(nft.isValid(999));
        assertFalse(nft.isValid(0));
    }

    function test_IsValid_AtExpiryBoundary() public {
        uint256 expiryTime = block.timestamp + 1000;
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, expiryTime, AUCTION_ID);

        // At expiry timestamp exactly
        vm.warp(expiryTime);
        assertTrue(nft.isValid(tokenId)); // Should be valid at exact expiry

        // One second past expiry
        vm.warp(expiryTime + 1);
        assertFalse(nft.isValid(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                        GET VALIDATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetValidator_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        bytes memory pubkey = nft.getValidator(tokenId);
        assertEq(pubkey, validatorPubkey1);
    }

    function test_GetValidator_RevertIf_InvalidTokenId() public {
        vm.expectRevert(CuttingBoardNFT.InvalidTokenId.selector);
        nft.getValidator(999);
    }

    function test_GetValidator_RevertIf_ZeroTokenId() public {
        vm.expectRevert(CuttingBoardNFT.InvalidTokenId.selector);
        nft.getValidator(0);
    }

    /*//////////////////////////////////////////////////////////////
                        GET CONTROL RIGHTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetControlRights_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        (bytes memory pubkey, uint256 expiry, uint256 auctionId, bool active) =
            nft.getControlRights(tokenId);

        assertEq(pubkey, validatorPubkey1);
        assertEq(expiry, EXPIRY_TIMESTAMP);
        assertEq(auctionId, AUCTION_ID);
        assertTrue(active);
    }

    function test_GetControlRights_AfterInvalidation() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        vm.prank(manager);
        nft.invalidate(tokenId);

        (,,, bool active) = nft.getControlRights(tokenId);
        assertFalse(active);
    }

    function test_GetControlRights_RevertIf_InvalidTokenId() public {
        vm.expectRevert(CuttingBoardNFT.InvalidTokenId.selector);
        nft.getControlRights(999);
    }

    /*//////////////////////////////////////////////////////////////
                        INVALIDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Invalidate_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit ControlNFTInvalidated(tokenId);
        nft.invalidate(tokenId);

        (,,, bool active) = nft.getControlRights(tokenId);
        assertFalse(active);
        assertFalse(nft.isValid(tokenId));
    }

    function test_Invalidate_NFTStillOwned() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        vm.prank(manager);
        nft.invalidate(tokenId);

        // User still owns the NFT, it's just invalidated
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function test_Invalidate_RevertIf_NotManager() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        vm.prank(user1);
        vm.expectRevert(CuttingBoardNFT.NotManager.selector);
        nft.invalidate(tokenId);
    }

    function test_Invalidate_RevertIf_InvalidTokenId() public {
        vm.prank(manager);
        vm.expectRevert(CuttingBoardNFT.InvalidTokenId.selector);
        nft.invalidate(999);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
        assertTrue(nft.isValid(tokenId)); // Still valid after transfer
    }

    function test_Transfer_ControlRightsTransfer() public {
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1, validatorPubkey1, block.timestamp + 1000, AUCTION_ID
        );

        assertTrue(nft.isValid(tokenId));

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // New owner should have control rights
        assertEq(nft.ownerOf(tokenId), user2);
        assertTrue(nft.isValid(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                        TOTAL SUPPLY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalSupply_InitiallyZero() public view {
        assertEq(nft.totalSupply(), 0);
    }

    function test_TotalSupply_IncreasesOnMint() public {
        vm.startPrank(auction);

        assertEq(nft.totalSupply(), 0);

        nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);
        assertEq(nft.totalSupply(), 1);

        nft.mint(user2, validatorPubkey2, EXPIRY_TIMESTAMP, AUCTION_ID + 1);
        assertEq(nft.totalSupply(), 2);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN URI TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TokenURI_ExistingToken() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        string memory uri = nft.tokenURI(tokenId);
        assertEq(uri, "https://infrared.finance/nft/");
    }

    function test_TokenURI_MultipleTokens() public {
        vm.startPrank(auction);
        nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);
        uint256 tokenId2 =
            nft.mint(user2, validatorPubkey2, EXPIRY_TIMESTAMP, AUCTION_ID + 1);
        vm.stopPrank();

        assertEq(nft.tokenURI(tokenId2), "https://infrared.finance/nft/");
    }

    function test_TokenURI_RevertIf_NonExistent() public {
        vm.expectRevert(CuttingBoardNFT.InvalidTokenId.selector);
        nft.tokenURI(999);
    }

    function test_TokenURI_EmptyBaseURI() public {
        CuttingBoardNFT nftNoBase =
            new CuttingBoardNFT(auction, owner, manager, "");

        vm.prank(auction);
        uint256 tokenId = nftNoBase.mint(
            user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID
        );

        assertEq(nftNoBase.tokenURI(tokenId), "");
    }

    function test_SetBaseURI_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, EXPIRY_TIMESTAMP, AUCTION_ID);

        nft.setBaseURI("https://new-uri.com/metadata/");

        assertEq(nft.tokenURI(tokenId), "https://new-uri.com/metadata/");
    }

    function test_SetBaseURI_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert("UNAUTHORIZED");
        nft.setBaseURI("https://new-uri.com/");
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(
        address recipient,
        bytes calldata pubkey,
        uint256 expiry,
        uint256 auctionId
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(pubkey.length > 0);
        vm.assume(expiry > block.timestamp);

        vm.prank(auction);
        uint256 tokenId = nft.mint(recipient, pubkey, expiry, auctionId);

        assertEq(nft.ownerOf(tokenId), recipient);
        assertEq(nft.getValidator(tokenId), pubkey);
        assertTrue(nft.isValid(tokenId));
    }

    function testFuzz_IsValid_ExpiryBehavior(
        uint256 mintTime,
        uint256 expiryOffset,
        uint256 checkTime
    ) public {
        mintTime = bound(mintTime, 1, type(uint64).max);
        expiryOffset = bound(expiryOffset, 1, 1000000);
        checkTime = bound(checkTime, mintTime, type(uint64).max);

        vm.warp(mintTime);
        uint256 expiryTime = mintTime + expiryOffset;

        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, expiryTime, AUCTION_ID);

        vm.warp(checkTime);

        bool expectedValid = checkTime <= expiryTime;
        assertEq(nft.isValid(tokenId), expectedValid);
    }

    function testFuzz_MultipleMintsSequential(uint8 count) public {
        vm.assume(count > 0 && count <= 20);

        vm.startPrank(auction);
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = nft.mint(
                user1, validatorPubkey1, EXPIRY_TIMESTAMP + i, AUCTION_ID + i
            );
            assertEq(tokenId, i + 1);
        }
        vm.stopPrank();

        assertEq(nft.totalSupply(), count);
    }
}
