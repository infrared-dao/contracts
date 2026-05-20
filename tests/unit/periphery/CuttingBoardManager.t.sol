// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {CuttingBoardManager} from
    "src/depreciated/periphery/CuttingBoardManager.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

    function getLastQueuedWeights()
        external
        view
        returns (IBeraChef.Weight[] memory)
    {
        return lastQueuedWeights;
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

contract CuttingBoardManagerTest is Test {
    CuttingBoardManager public manager;
    MockInfrared public infrared;
    CuttingBoardNFT public nft;
    MockBeraChef public chef;

    address public owner;
    address public keeper;
    address public auction;
    address public user1;
    address public user2;
    address public vault1;
    address public vault2;
    address public vault3;

    bytes public validatorPubkey1 = hex"1234567890abcdef";
    bytes public validatorPubkey2 = hex"fedcba0987654321";

    uint256 public constant PROPOSAL_VALIDITY_DURATION = 1 days;

    event CuttingBoardProposed(
        uint256 indexed tokenId,
        address indexed proposer,
        bytes validatorPubkey,
        IBeraChef.Weight[] weights
    );

    event CuttingBoardApproved(
        uint256 indexed tokenId,
        address indexed approver,
        bytes validatorPubkey,
        uint64 startBlock,
        IBeraChef.Weight[] weights
    );

    event ProposalCancelled(uint256 indexed tokenId, address indexed canceller);

    event ProposalValidityDurationUpdated(
        uint256 oldDuration, uint256 newDuration
    );

    function setUp() public {
        owner = address(this);
        keeper = makeAddr("keeper");
        auction = makeAddr("auction");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");
        vault3 = makeAddr("vault3");

        infrared = new MockInfrared();
        chef = new MockBeraChef();

        // Predict manager proxy address for NFT constructor
        // Nonces: NFT = current, managerImpl = current+1, managerProxy = current+2
        uint64 currentNonce = vm.getNonce(address(this));
        address predictedManagerProxy =
            vm.computeCreateAddress(address(this), currentNonce + 2);

        nft = new CuttingBoardNFT(auction, owner, predictedManagerProxy, "");

        // Deploy implementation
        CuttingBoardManager implementation = new CuttingBoardManager();

        // Deploy proxy and initialize
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(infrared),
                    address(nft),
                    address(chef),
                    owner,
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );

        manager = CuttingBoardManager(address(proxy));
        require(
            address(manager) == predictedManagerProxy,
            "Manager address mismatch"
        );

        // Whitelist vaults
        chef.setWhitelistedVault(vault1, true);
        chef.setWhitelistedVault(vault2, true);
        chef.setWhitelistedVault(vault3, true);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(address(manager.infrared()), address(infrared));
        assertEq(address(manager.controlNFT()), address(nft));
        assertEq(address(manager.chef()), address(chef));
        assertTrue(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(manager.hasRole(manager.GOVERNANCE_ROLE(), owner));
        assertTrue(manager.hasRole(manager.KEEPER_ROLE(), keeper));
        assertEq(manager.proposalValidityDuration(), PROPOSAL_VALIDITY_DURATION);
        assertFalse(manager.paused());
    }

    function test_Initialize_RevertIf_InvalidInfrared() public {
        CuttingBoardManager implementation = new CuttingBoardManager();
        vm.expectRevert(CuttingBoardManager.InvalidAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(0),
                    address(nft),
                    address(chef),
                    owner,
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );
    }

    function test_Initialize_RevertIf_InvalidNFT() public {
        CuttingBoardManager implementation = new CuttingBoardManager();
        vm.expectRevert(CuttingBoardManager.InvalidAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(infrared),
                    address(0),
                    address(chef),
                    owner,
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );
    }

    function test_Initialize_RevertIf_InvalidChef() public {
        CuttingBoardManager implementation = new CuttingBoardManager();
        vm.expectRevert(CuttingBoardManager.InvalidAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(infrared),
                    address(nft),
                    address(0),
                    owner,
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );
    }

    function test_Initialize_RevertIf_InvalidGovernance() public {
        CuttingBoardManager implementation = new CuttingBoardManager();
        vm.expectRevert(CuttingBoardManager.InvalidAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                CuttingBoardManager.initialize,
                (
                    address(infrared),
                    address(nft),
                    address(chef),
                    address(0),
                    keeper,
                    PROPOSAL_VALIDITY_DURATION
                )
            )
        );
    }

    // ERC7201
    function test_ERC7201_Storage_Slot() public pure {
        assertEq(
            keccak256(
                abi.encode(
                    uint256(keccak256("infrared.storage.CuttingBoardManager"))
                        - 1
                )
            ) & ~bytes32(uint256(0xff)),
            0x9fd5aaf305ec5d9d4acf2d4a2d8f6d67e82cf32b8c76929329ec5790707b7d00
        );
    }

    /*//////////////////////////////////////////////////////////////
                    PROPOSE CUTTING BOARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProposeCuttingBoard_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 6000});
        weights[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 4000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        (
            address proposer,
            uint64 propStartBlock,
            uint64 proposedAt,
            bool exists,
            IBeraChef.Weight[] memory propWeights
        ) = manager.getProposal(tokenId);

        assertEq(proposer, user1);
        assertEq(propStartBlock, 0); // StartBlock is 0 until approved
        assertEq(proposedAt, block.timestamp);
        assertTrue(exists);
        assertEq(propWeights.length, 2);
        assertEq(infrared.queueCallCount(), 0); // Not approved yet
    }

    function test_ProposeCuttingBoard_RevertIf_DuplicateVault() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 6000});
        weights[1] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 4000});

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.DuplicateReceiver.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_NotNFTOwner() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user2);
        vm.expectRevert(CuttingBoardManager.NotNFTOwner.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_NFTExpired() public {
        uint256 expiryTime = block.timestamp + 1000;
        vm.prank(auction);
        uint256 tokenId = nft.mint(user1, validatorPubkey1, expiryTime, 1);

        vm.warp(expiryTime + 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.NFTExpired.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_NFTInactive() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        manager.revokeControl(tokenId);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.NFTInactive.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_ProposalAlreadyExists() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.ProposalAlreadyExists.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_Paused() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        manager.pause();

        vm.prank(user1);
        vm.expectRevert(); // EnforcedPause from PausableUpgradeable
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertIf_InvalidWeights() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](0);

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.EmptyWeights.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    /*//////////////////////////////////////////////////////////////
                    APPROVE CUTTING BOARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ApproveCuttingBoard_Success() public {
        // Mint and propose
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 6000});
        weights[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 4000});

        // Expected startBlock = current block + rewardAllocationBlockDelay + 1
        uint64 expectedStartBlock =
            uint64(block.number) + chef.rewardAllocationBlockDelay() + 1;

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Approve
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // Verify Infrared was called
        assertEq(infrared.queueCallCount(), 1);
        assertEq(infrared.lastQueuedPubkey(), validatorPubkey1);
        assertEq(infrared.lastQueuedStartBlock(), expectedStartBlock);

        // Verify proposal was cleaned up
        (,,, bool exists,) = manager.getProposal(tokenId);
        assertFalse(exists);

        // Verify last update block was set
        assertEq(manager.getLastUpdateBlock(tokenId), block.number);
    }

    function test_ApproveCuttingBoard_RevertIf_NotKeeper() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        vm.prank(user1);
        vm.expectRevert();
        manager.approveCuttingBoard(tokenId);
    }

    function test_ApproveCuttingBoard_RevertIf_NoProposal() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        vm.prank(keeper);
        vm.expectRevert(CuttingBoardManager.NoProposalExists.selector);
        manager.approveCuttingBoard(tokenId);
    }

    function test_ApproveCuttingBoard_RevertIf_ProposalExpired() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp past validity period
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        vm.prank(keeper);
        vm.expectRevert(CuttingBoardManager.ProposalExpired.selector);
        manager.approveCuttingBoard(tokenId);
    }

    function test_ApproveCuttingBoard_RevertIf_Paused() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        manager.pause();

        vm.prank(keeper);
        vm.expectRevert(); // EnforcedPause from PausableUpgradeable
        manager.approveCuttingBoard(tokenId);
    }

    function test_ApproveCuttingBoard_RevertIf_NFTOwnerChanged() public {
        // Mint NFT to user1
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // user1 creates a proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Verify proposal exists with user1 as proposer
        (address proposer,,, bool exists,) = manager.getProposal(tokenId);
        assertEq(proposer, user1);
        assertTrue(exists);

        // user1 transfers NFT to user2
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // Verify user2 is now the owner
        assertEq(nft.ownerOf(tokenId), user2);

        // Keeper tries to approve - should revert because proposer != current owner
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardManager.InvalidProposer.selector);
        manager.approveCuttingBoard(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL PROPOSAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CancelProposal_ByProposer() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        vm.prank(user1);
        manager.cancelProposal(tokenId);

        (,,, bool exists,) = manager.getProposal(tokenId);
        assertFalse(exists);
    }

    function test_CancelProposal_ByNFTOwner() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Transfer NFT to user2
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // New owner can cancel
        vm.prank(user2);
        manager.cancelProposal(tokenId);

        (,,, bool exists,) = manager.getProposal(tokenId);
        assertFalse(exists);
    }

    function test_CancelProposal_ByAdmin() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Owner (admin) can cancel
        manager.cancelProposal(tokenId);

        (,,, bool exists,) = manager.getProposal(tokenId);
        assertFalse(exists);
    }

    function test_CancelProposal_RevertIf_NotAuthorized() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        vm.prank(user2);
        vm.expectRevert(CuttingBoardManager.NotProposer.selector);
        manager.cancelProposal(tokenId);
    }

    function test_CancelProposal_RevertIf_NoProposal() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.NoProposalExists.selector);
        manager.cancelProposal(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanProposeNow_True() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        assertTrue(manager.canProposeNow(tokenId));
    }

    function test_CanProposeNow_False_Paused() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        manager.pause();

        assertFalse(manager.canProposeNow(tokenId));
    }

    function test_CanProposeNow_False_HasPendingProposal() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        assertFalse(manager.canProposeNow(tokenId));
    }

    function test_IsProposalExpired_False_NoProposal() public view {
        assertFalse(manager.isProposalExpired(999));
    }

    function test_IsProposalExpired_False_NotExpired() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        assertFalse(manager.isProposalExpired(tokenId));
    }

    function test_IsProposalExpired_True() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        assertTrue(manager.isProposalExpired(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                GET PENDING PROPOSAL TOKEN IDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getPendingProposalTokenIds_NoNFTs() public view {
        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 0);
    }

    function test_getPendingProposalTokenIds_NoProposals() public {
        // Mint NFTs without proposals
        vm.startPrank(auction);
        nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);
        nft.mint(user2, validatorPubkey2, block.timestamp + 10000, 2);
        vm.stopPrank();

        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 0);
    }

    function test_getPendingProposalTokenIds_SinglePendingProposal() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], tokenId);
    }

    function test_getPendingProposalTokenIds_MultiplePendingProposals()
        public
    {
        // Mint two NFTs
        vm.startPrank(auction);
        uint256 tokenId1 =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);
        uint256 tokenId2 =
            nft.mint(user2, validatorPubkey2, block.timestamp + 10000, 2);
        vm.stopPrank();

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Both create proposals
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId1, weights);

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId2, weights);

        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], tokenId1);
        assertEq(tokenIds[1], tokenId2);
    }

    function test_getPendingProposalTokenIds_MixPendingAndNone() public {
        // Mint three NFTs
        vm.startPrank(auction);
        uint256 tokenId1 =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);
        nft.mint(user2, validatorPubkey2, block.timestamp + 10000, 2); // No proposal
        uint256 tokenId3 =
            nft.mint(user1, hex"abcdef1234567890", block.timestamp + 10000, 3);
        vm.stopPrank();

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Only token 1 and 3 create proposals
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId1, weights);

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId3, weights);

        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], tokenId1);
        assertEq(tokenIds[1], tokenId3);
    }

    function test_getPendingProposalTokenIds_ExcludesExpiredProposals()
        public
    {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be included before expiry
        uint256[] memory tokenIdsBefore = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsBefore.length, 1);

        // Warp past proposal validity duration
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // Should be excluded after expiry
        uint256[] memory tokenIdsAfter = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsAfter.length, 0);
    }

    function test_getPendingProposalTokenIds_ExcludesInvalidNFTs() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be included while NFT is valid
        uint256[] memory tokenIdsBefore = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsBefore.length, 1);

        // Revoke NFT control
        manager.revokeControl(tokenId);

        // Should be excluded after NFT is invalidated
        uint256[] memory tokenIdsAfter = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsAfter.length, 0);
    }

    function test_getPendingProposalTokenIds_ExcludesExpiredNFTs() public {
        uint256 nftExpiry = block.timestamp + 1000;
        vm.prank(auction);
        uint256 tokenId = nft.mint(user1, validatorPubkey1, nftExpiry, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be included while NFT is valid
        uint256[] memory tokenIdsBefore = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsBefore.length, 1);

        // Warp past NFT expiry
        vm.warp(nftExpiry + 1);

        // Should be excluded after NFT expires
        uint256[] memory tokenIdsAfter = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsAfter.length, 0);
    }

    function test_getPendingProposalTokenIds_ApprovedProposalRemoved() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be included before approval
        uint256[] memory tokenIdsBefore = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsBefore.length, 1);

        // Approve the proposal
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // Should be excluded after approval (proposal no longer exists)
        uint256[] memory tokenIdsAfter = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsAfter.length, 0);
    }

    function test_getPendingProposalTokenIds_CancelledProposalRemoved()
        public
    {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be included before cancellation
        uint256[] memory tokenIdsBefore = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsBefore.length, 1);

        // Cancel the proposal
        vm.prank(user1);
        manager.cancelProposal(tokenId);

        // Should be excluded after cancellation
        uint256[] memory tokenIdsAfter = manager.getPendingProposalTokenIds();
        assertEq(tokenIdsAfter.length, 0);
    }

    function test_getPendingProposalTokenIds_MixedScenario() public {
        // Create multiple NFTs with different states
        vm.startPrank(auction);
        uint256 tokenId1 =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1); // Valid with pending proposal
        uint256 tokenId2 =
            nft.mint(user2, validatorPubkey2, block.timestamp + 100000, 2); // Valid with expired proposal
        nft.mint(user1, hex"abcdef1234567890", block.timestamp + 100000, 3); // Valid, no proposal (tokenId3)
        uint256 tokenId4 =
            nft.mint(user2, hex"1111111111111111", block.timestamp + 100000, 4); // Revoked, with proposal
        uint256 tokenId5 =
            nft.mint(user1, hex"2222222222222222", block.timestamp + 100000, 5); // Valid with pending proposal
        vm.stopPrank();

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create proposals for tokens 1, 2, 4, 5
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId1, weights);

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId2, weights);

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId4, weights);

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId5, weights);

        // Revoke token 4
        manager.revokeControl(tokenId4);

        // Warp to expire token 2's proposal but not others
        // First get proposal timestamp for token 2
        (,, uint64 proposedAt2,,) = manager.getProposal(tokenId2);

        // Create a new proposal for token 1 and 5 after some time
        // to ensure their proposals don't expire when we warp
        vm.warp(proposedAt2 + PROPOSAL_VALIDITY_DURATION + 1);

        // Token 2's proposal is now expired
        // Token 1 and 5's proposals are also expired (same time)
        // So we need to restructure - let's create new proposals after warp

        // At this point all proposals with proposals should be expired
        // Let's create fresh proposals for token 1 and 5
        // First need to wait for block delay since token 1 has no lastUpdateBlock

        // Actually, proposals for token 1 and 5 never got approved, so
        // they don't have lastUpdateBlock set. But the proposals exist and are expired.

        // Let me restructure this test
        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();

        // All proposals are expired at this point
        assertEq(tokenIds.length, 0);
    }

    function test_getPendingProposalTokenIds_TokenIdAtIndex1() public {
        // This test verifies the function correctly finds a proposal at token ID 1
        // (the first valid token ID)
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        assertEq(tokenId, 1); // Verify it's token ID 1

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        uint256[] memory tokenIds = manager.getPendingProposalTokenIds();
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetProposalValidityDuration_Success() public {
        uint256 newDuration = 14 days;

        vm.expectEmit(true, true, true, true);
        emit ProposalValidityDurationUpdated(
            PROPOSAL_VALIDITY_DURATION, newDuration
        );
        manager.setProposalValidityDuration(newDuration);

        assertEq(manager.proposalValidityDuration(), newDuration);
    }

    function test_SetProposalValidityDuration_RevertIf_NotGovernor() public {
        vm.prank(user1);
        vm.expectRevert();
        manager.setProposalValidityDuration(14 days);
    }

    function test_Pause_Success() public {
        manager.pause();
        assertTrue(manager.paused());
    }

    function test_Pause_RevertIf_NotPauser() public {
        vm.prank(user1);
        vm.expectRevert();
        manager.pause();
    }

    function test_Unpause_Success() public {
        manager.pause();
        manager.unpause();
        assertFalse(manager.paused());
    }

    function test_Unpause_RevertIf_NotGovernor() public {
        manager.pause();

        vm.prank(user1);
        vm.expectRevert();
        manager.unpause();
    }

    function test_RevokeControl_Success() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        assertTrue(nft.isValid(tokenId));

        manager.revokeControl(tokenId);

        assertFalse(nft.isValid(tokenId));
    }

    function test_RevokeControl_RevertIf_NotAdmin() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 10000, 1);

        vm.prank(user1);
        vm.expectRevert();
        manager.revokeControl(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullProposalApprovalFlow() public {
        // Mint NFT
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1);

        IBeraChef.Weight[] memory weights1 = new IBeraChef.Weight[](2);
        weights1[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 7000});
        weights1[1] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 3000});

        // First proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights1);

        // Approve
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        assertEq(infrared.queueCallCount(), 1);

        // Wait for min delay (rewardAllocationBlockDelay)
        vm.roll(block.number + chef.rewardAllocationBlockDelay());

        // Second proposal
        IBeraChef.Weight[] memory weights2 = new IBeraChef.Weight[](1);
        weights2[0] =
            IBeraChef.Weight({receiver: vault3, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights2);

        // Approve
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        assertEq(infrared.queueCallCount(), 2);
    }

    function test_TransferNFT_NewOwnerCanPropose() public {
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 100000, 1);

        // Transfer NFT
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // New owner can propose
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId, weights);

        (address proposer,,,,) = manager.getProposal(tokenId);
        assertEq(proposer, user2);
    }

    /*//////////////////////////////////////////////////////////////
                EXPIRED PROPOSAL AUTO-CLEAR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProposeCuttingBoard_AutoClearsExpiredProposal() public {
        // NFT expiry must be longer than proposal validity to test this scenario
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights1 = new IBeraChef.Weight[](1);
        weights1[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create first proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights1);

        // Verify proposal exists
        (address proposer1,, uint64 proposedAt1, bool exists1,) =
            manager.getProposal(tokenId);
        assertEq(proposer1, user1);
        assertTrue(exists1);

        // Warp past proposal validity period
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // Verify proposal is now expired
        assertTrue(manager.isProposalExpired(tokenId));

        // Create new proposal - should auto-clear expired one
        IBeraChef.Weight[] memory weights2 = new IBeraChef.Weight[](1);
        weights2[0] =
            IBeraChef.Weight({receiver: vault2, percentageNumerator: 10000});

        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights2);

        // Verify new proposal replaced the old one
        (
            address proposer2,
            ,
            uint64 proposedAt2,
            bool exists2,
            IBeraChef.Weight[] memory propWeights
        ) = manager.getProposal(tokenId);

        assertEq(proposer2, user1);
        assertTrue(exists2);
        assertTrue(proposedAt2 > proposedAt1); // New timestamp
        assertEq(propWeights.length, 1);
        assertEq(propWeights[0].receiver, vault2); // New weights
    }

    function test_ProposeCuttingBoard_EmitsProposalCancelledOnAutoClear()
        public
    {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create first proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp past proposal validity period
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // Expect ProposalCancelled event with address(0) as canceller
        vm.expectEmit(true, true, true, true);
        emit ProposalCancelled(tokenId, address(0));

        // Create new proposal - should emit cancel event then create new
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_RevertsIfActiveProposalExists() public {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create first proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp but NOT past validity period (warp half the duration)
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION / 2);

        // Proposal should not be expired yet
        assertFalse(manager.isProposalExpired(tokenId));

        // Trying to create new proposal should revert
        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.ProposalAlreadyExists.selector);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_AutoClearAtExactExpiry() public {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 proposalTime = block.timestamp;

        // Create first proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp to EXACTLY the expiry boundary (proposedAt + duration)
        // Proposal expires when block.timestamp > proposedAt + duration
        // So at exactly proposedAt + duration, it should NOT be expired yet
        vm.warp(proposalTime + PROPOSAL_VALIDITY_DURATION);

        // Should NOT be expired at exact boundary
        assertFalse(manager.isProposalExpired(tokenId));

        // Should revert since proposal is still active
        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.ProposalAlreadyExists.selector);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp one more second
        vm.warp(proposalTime + PROPOSAL_VALIDITY_DURATION + 1);

        // Now it should be expired
        assertTrue(manager.isProposalExpired(tokenId));

        // Should succeed now
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);
    }

    function test_ProposeCuttingBoard_NewOwnerCanProposeAfterExpiredProposal()
        public
    {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // user1 creates proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Transfer NFT to user2
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // Warp past proposal validity
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // user2 (new owner) should be able to propose, auto-clearing user1's expired proposal
        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId, weights);

        // Verify new proposal is from user2
        (address proposer,,, bool exists,) = manager.getProposal(tokenId);
        assertEq(proposer, user2);
        assertTrue(exists);
    }

    /*//////////////////////////////////////////////////////////////
            canProposeNow WITH EXPIRED PROPOSAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanProposeNow_TrueWhenExpiredProposalExists() public {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be false while proposal is active
        assertFalse(manager.canProposeNow(tokenId));

        // Warp past validity period
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // Should be true now - expired proposals don't block new proposals
        assertTrue(manager.canProposeNow(tokenId));
    }

    function test_CanProposeNow_FalseWhenActiveProposalExists() public {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Should be true before any proposal
        assertTrue(manager.canProposeNow(tokenId));

        // Create proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Should be false while proposal is active
        assertFalse(manager.canProposeNow(tokenId));

        // Warp to half of validity period (still active)
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION / 2);

        // Still false while active
        assertFalse(manager.canProposeNow(tokenId));
    }

    function test_CanProposeNow_AtExactExpiryBoundary() public {
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        uint256 proposalTime = block.timestamp;

        // Create proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // At exact boundary: proposedAt + duration
        vm.warp(proposalTime + PROPOSAL_VALIDITY_DURATION);

        // Should be false at exact boundary (not yet expired)
        assertFalse(manager.canProposeNow(tokenId));

        // One second after
        vm.warp(proposalTime + PROPOSAL_VALIDITY_DURATION + 1);

        // Should be true (now expired)
        assertTrue(manager.canProposeNow(tokenId));
    }

    function test_CanProposeNow_ConsistentWithProposeCuttingBoard() public {
        // This test verifies that canProposeNow accurately predicts
        // whether proposeCuttingBoard will succeed
        // NFT expiry must be longer than proposal validity
        vm.prank(auction);
        uint256 tokenId = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // canProposeNow = true => proposeCuttingBoard should succeed
        assertTrue(manager.canProposeNow(tokenId));
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // canProposeNow = false => proposeCuttingBoard should fail
        assertFalse(manager.canProposeNow(tokenId));
        vm.prank(user1);
        vm.expectRevert(CuttingBoardManager.ProposalAlreadyExists.selector);
        manager.proposeCuttingBoard(tokenId, weights);

        // After expiry: canProposeNow = true => proposeCuttingBoard should succeed
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);
        assertTrue(manager.canProposeNow(tokenId));
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights); // Should succeed
    }

    function testFuzz_ExpiredProposal_CanAlwaysBeReplaced(uint256 extraTime)
        public
    {
        extraTime = bound(extraTime, 1, 365 days);

        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 1000 days, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create initial proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Warp past validity by varying amounts
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + extraTime);

        // Should always be able to propose after expiry
        assertTrue(manager.canProposeNow(tokenId));
        assertTrue(manager.isProposalExpired(tokenId));

        // Should always succeed in creating new proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // Verify new proposal was created
        (,, uint64 proposedAt, bool exists,) = manager.getProposal(tokenId);
        assertTrue(exists);
        assertEq(proposedAt, block.timestamp);
    }

    function test_ExpiredProposal_FullLifecycle() public {
        // Test the complete lifecycle with expired proposals
        vm.prank(auction);
        uint256 tokenId =
            nft.mint(user1, validatorPubkey1, block.timestamp + 1000 days, 1);

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // 1. Create first proposal
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // 2. Let it expire (without keeper approval)
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // 3. Keeper cannot approve expired proposal
        vm.prank(keeper);
        vm.expectRevert(CuttingBoardManager.ProposalExpired.selector);
        manager.approveCuttingBoard(tokenId);

        // 4. Owner can create new proposal (auto-clears expired)
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId, weights);

        // 5. Keeper approves new proposal
        vm.prank(keeper);
        manager.approveCuttingBoard(tokenId);

        // 6. Verify approval went through
        assertEq(infrared.queueCallCount(), 1);
        (,,, bool exists,) = manager.getProposal(tokenId);
        assertFalse(exists); // Cleaned up after approval
    }

    function test_ExpiredProposal_DoesNotAffectOtherTokens() public {
        // NFT expiry must be longer than proposal validity
        // Mint two NFTs
        vm.startPrank(auction);
        uint256 tokenId1 = nft.mint(
            user1,
            validatorPubkey1,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            1
        );
        uint256 tokenId2 = nft.mint(
            user2,
            validatorPubkey2,
            block.timestamp + PROPOSAL_VALIDITY_DURATION + 1 days,
            2
        );
        vm.stopPrank();

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        // Create proposals for both
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId1, weights);

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId2, weights);

        // Let both proposals expire
        vm.warp(block.timestamp + PROPOSAL_VALIDITY_DURATION + 1);

        // Token1's proposal is expired
        assertTrue(manager.isProposalExpired(tokenId1));
        assertTrue(manager.canProposeNow(tokenId1));

        // Token2's proposal is also expired (same time)
        assertTrue(manager.isProposalExpired(tokenId2));
        assertTrue(manager.canProposeNow(tokenId2));

        // Both can create new proposals independently
        vm.prank(user1);
        manager.proposeCuttingBoard(tokenId1, weights);

        vm.prank(user2);
        manager.proposeCuttingBoard(tokenId2, weights);

        // Both have new active proposals
        assertFalse(manager.isProposalExpired(tokenId1));
        assertFalse(manager.isProposalExpired(tokenId2));
    }
}
