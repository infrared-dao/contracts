// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/periphery/MerkleDistributor.sol";
import "@solmate/tokens/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol, 18)
    {
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MerkleDistributorTest is Test {
    MerkleDistributor public distributor;
    MockERC20 public token;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public david = address(0x5);
    address public nonEligible = address(0x999);

    // Test merkle tree data
    // Tree structure:
    // alice: 100 tokens
    // bob: 200 tokens
    // charlie: 300 tokens
    // david: 150 tokens
    bytes32 public constant MERKLE_ROOT =
        0x4e3c8e2c6d9c4e4a5f6e7a8b9c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d;

    // Pre-calculated merkle proofs (would be generated off-chain)
    bytes32[] aliceProof;
    bytes32[] bobProof;
    bytes32[] charlieProof;
    bytes32[] davidProof;

    uint256 constant ALICE_AMOUNT = 100 ether;
    uint256 constant BOB_AMOUNT = 200 ether;
    uint256 constant CHARLIE_AMOUNT = 300 ether;
    uint256 constant DAVID_AMOUNT = 150 ether;
    uint256 constant TOTAL_ALLOCATION = 750 ether;

    event Claimed(address indexed account, uint256 amount);
    event EmergencyWithdraw(
        address indexed token, address indexed to, uint256 amount
    );

    function setUp() public {
        // Deploy token
        token = new MockERC20("Test Token", "TEST", 10000 ether);

        bytes32 computedRoot = _computeMerkleRoot();

        // Deploy distributor
        distributor = new MerkleDistributor(
            address(token), computedRoot, owner, 90 days, TOTAL_ALLOCATION
        );

        // Fund the distributor
        token.transfer(address(distributor), TOTAL_ALLOCATION);

        // Set total allocated
        // vm.prank(owner);
        // distributor.setTotalAllocated(TOTAL_ALLOCATION);

        // Setup merkle proofs
        _setupMerkleProofs();
    }

    function _computeMerkleRoot() internal view returns (bytes32) {
        // Compute leaves
        bytes32 aliceLeaf = keccak256(abi.encode(alice, ALICE_AMOUNT));
        bytes32 bobLeaf = keccak256(abi.encode(bob, BOB_AMOUNT));
        bytes32 charlieLeaf = keccak256(abi.encode(charlie, CHARLIE_AMOUNT));
        bytes32 davidLeaf = keccak256(abi.encode(david, DAVID_AMOUNT));

        // Compute intermediate nodes (sorted pairs)
        bytes32 node1 = _hashPair(aliceLeaf, bobLeaf);
        bytes32 node2 = _hashPair(charlieLeaf, davidLeaf);

        // Compute root
        return _hashPair(node1, node2);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b
            ? keccak256(abi.encodePacked(a, b))
            : keccak256(abi.encodePacked(b, a));
    }

    function _setupMerkleProofs() internal {
        // Setup proofs for each user
        // In a real scenario, these would be generated off-chain
        bytes32 aliceLeaf = keccak256(abi.encode(alice, ALICE_AMOUNT));
        bytes32 bobLeaf = keccak256(abi.encode(bob, BOB_AMOUNT));
        bytes32 charlieLeaf = keccak256(abi.encode(charlie, CHARLIE_AMOUNT));
        bytes32 davidLeaf = keccak256(abi.encode(david, DAVID_AMOUNT));

        bytes32 node1 = _hashPair(aliceLeaf, bobLeaf);
        bytes32 node2 = _hashPair(charlieLeaf, davidLeaf);

        // Alice's proof: needs bob's leaf and node2
        aliceProof.push(bobLeaf);
        aliceProof.push(node2);

        // Bob's proof: needs alice's leaf and node2
        bobProof.push(aliceLeaf);
        bobProof.push(node2);

        // Charlie's proof: needs david's leaf and node1
        charlieProof.push(davidLeaf);
        charlieProof.push(node1);

        // David's proof: needs charlie's leaf and node1
        davidProof.push(charlieLeaf);
        davidProof.push(node1);
    }

    // ============ Deployment Tests ============

    function testDeployment() public view {
        assertEq(address(distributor.token()), address(token));
        assertEq(distributor.merkleRoot(), _computeMerkleRoot());
        assertEq(distributor.owner(), owner);
        assertEq(distributor.totalAllocated(), TOTAL_ALLOCATION);
        assertGt(distributor.claimDeadline(), block.timestamp);
        assertEq(distributor.claimDeadline(), block.timestamp + 90 days);
    }

    function testCannotDeployWithZeroToken() public {
        vm.expectRevert(MerkleDistributor.ZeroAddress.selector);
        new MerkleDistributor(
            address(0), _computeMerkleRoot(), owner, 90 days, TOTAL_ALLOCATION
        );
    }

    function testCannotDeployWithZeroRoot() public {
        vm.expectRevert(MerkleDistributor.InvalidMerkleRoot.selector);
        new MerkleDistributor(
            address(token), bytes32(0), owner, 90 days, TOTAL_ALLOCATION
        );
    }

    function testCannotDeployWithZeroOwner() public {
        vm.expectRevert(MerkleDistributor.ZeroAddress.selector);
        new MerkleDistributor(
            address(token),
            _computeMerkleRoot(),
            address(0),
            90 days,
            TOTAL_ALLOCATION
        );
    }

    // ============ Valid Claim Tests ============

    function testValidClaim() public {
        uint256 balanceBefore = token.balanceOf(alice);

        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, ALICE_AMOUNT);

        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        assertEq(token.balanceOf(alice), balanceBefore + ALICE_AMOUNT);
        assertEq(distributor.claimed(alice), ALICE_AMOUNT);
        assertEq(distributor.totalClaimed(), ALICE_AMOUNT);
    }

    function testClaimFor() public {
        uint256 balanceBefore = token.balanceOf(bob);

        vm.expectEmit(true, false, false, true);
        emit Claimed(bob, BOB_AMOUNT);

        // Alice claims on behalf of Bob
        vm.prank(alice);
        distributor.claimFor(bob, BOB_AMOUNT, bobProof);

        assertEq(token.balanceOf(bob), balanceBefore + BOB_AMOUNT);
        assertEq(distributor.claimed(bob), BOB_AMOUNT);
    }

    function testMultipleValidClaims() public {
        // Alice claims
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        // Bob claims
        vm.prank(bob);
        distributor.claim(BOB_AMOUNT, bobProof);

        // Charlie claims
        vm.prank(charlie);
        distributor.claim(CHARLIE_AMOUNT, charlieProof);

        // David claims
        vm.prank(david);
        distributor.claim(DAVID_AMOUNT, davidProof);

        assertEq(distributor.totalClaimed(), TOTAL_ALLOCATION);
        assertEq(token.balanceOf(address(distributor)), 0);
    }

    // ============ Invalid Claim Tests ============

    function testCannotClaimWithInvalidProof() public {
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(ALICE_AMOUNT, bobProof); // Using wrong proof
    }

    function testCannotClaimWrongAmount() public {
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(BOB_AMOUNT, aliceProof); // Wrong amount
    }

    function testNonEligibleCannotClaim() public {
        bytes32[] memory emptyProof;
        vm.prank(nonEligible);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(100 ether, emptyProof);
    }

    function testCannotClaimZeroAmount() public {
        bytes32[] memory emptyProof;
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.ZeroAmount.selector);
        distributor.claim(0, emptyProof);
    }

    // ============ Double Claim Prevention Tests ============

    function testCannotDoubleClaim() public {
        // First claim succeeds
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        // Second claim fails
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(ALICE_AMOUNT, aliceProof);
    }

    function testCannotClaimAfterClaimFor() public {
        // Someone claims for Alice
        vm.prank(bob);
        distributor.claimFor(alice, ALICE_AMOUNT, aliceProof);

        // Alice tries to claim again
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(ALICE_AMOUNT, aliceProof);
    }

    // ============ Deadline Tests ============

    function testCannotClaimAfterDeadline() public {
        // Warp to after deadline
        vm.warp(block.timestamp + 91 days);

        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.ClaimingPeriodEnded.selector);
        distributor.claim(ALICE_AMOUNT, aliceProof);
    }

    function testOwnerCanWithdrawAfterDeadline() public {
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        // Warp to after deadline
        vm.warp(block.timestamp + 91 days);

        vm.prank(owner);
        distributor.withdrawUnclaimed(owner);

        assertEq(token.balanceOf(owner), ownerBalanceBefore + TOTAL_ALLOCATION);
        assertEq(token.balanceOf(address(distributor)), 0);
    }

    function testCannotWithdrawBeforeDeadline() public {
        vm.prank(owner);
        vm.expectRevert(MerkleDistributor.DeadlineNotReached.selector);
        distributor.withdrawUnclaimed(owner);
    }

    // ============ Pause Tests ============

    function testOwnerCanPause() public {
        vm.prank(owner);
        distributor.pause();
        assertTrue(distributor.paused());
    }

    function testCannotClaimWhenPaused() public {
        vm.prank(owner);
        distributor.pause();

        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.EnforcedPause.selector);
        distributor.claim(ALICE_AMOUNT, aliceProof);
    }

    function testCanClaimAfterUnpause() public {
        vm.prank(owner);
        distributor.pause();

        vm.prank(owner);
        distributor.unpause();

        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        assertEq(token.balanceOf(alice), ALICE_AMOUNT);
    }

    function testNonOwnerCannotPause() public {
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        distributor.pause();
    }

    function testNonOwnerCannotUnpause() public {
        vm.prank(owner);
        distributor.pause();

        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        distributor.unpause();
    }

    // ============ Token Recovery Tests ============

    function testCanRecoverOtherTokens() public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER", 1000 ether);
        otherToken.transfer(address(distributor), 100 ether);

        uint256 ownerBalanceBefore = otherToken.balanceOf(owner);

        vm.prank(owner);
        distributor.recoverERC20(address(otherToken), owner);

        assertEq(otherToken.balanceOf(owner), ownerBalanceBefore + 100 ether);
        assertEq(otherToken.balanceOf(address(distributor)), 0);
    }

    function testCanRecoverExcessDistributionTokens() public {
        // Send extra tokens
        token.transfer(address(distributor), 500 ether);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        distributor.recoverERC20(address(token), owner);

        // Should only recover the excess (500 ether)
        assertEq(token.balanceOf(owner), ownerBalanceBefore + 500 ether);
        // Should still have the allocated amount
        assertEq(token.balanceOf(address(distributor)), TOTAL_ALLOCATION);
    }

    function testCannotRecoverAllocatedTokensBeforeDeadline() public {
        vm.prank(owner);
        vm.expectRevert(MerkleDistributor.DeadlineNotReached.selector);
        distributor.recoverERC20(address(token), owner);
    }

    function testCanRecoverAllTokensAfterDeadline() public {
        vm.warp(block.timestamp + 91 days);

        uint256 balance = token.balanceOf(address(distributor));

        vm.prank(owner);
        distributor.recoverERC20(address(token), owner);

        assertEq(token.balanceOf(owner), balance);
    }

    function testNonOwnerCannotRecoverTokens() public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER", 1000 ether);
        otherToken.transfer(address(distributor), 100 ether);

        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        distributor.recoverERC20(address(otherToken), alice);
    }

    // ============ View Function Tests ============

    function testCanClaimView() public {
        (bool canClaim, uint256 claimableAmount) =
            distributor.canClaim(alice, ALICE_AMOUNT, aliceProof);
        assertTrue(canClaim);
        assertEq(claimableAmount, ALICE_AMOUNT);

        // After claiming
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        (canClaim, claimableAmount) =
            distributor.canClaim(alice, ALICE_AMOUNT, aliceProof);
        assertFalse(canClaim);
        assertEq(claimableAmount, 0);
    }

    function testCanClaimWithInvalidProof() public view {
        (bool canClaim, uint256 claimableAmount) =
            distributor.canClaim(alice, ALICE_AMOUNT, bobProof);
        assertFalse(canClaim);
        assertEq(claimableAmount, 0);
    }

    function testGetRemainingTime() public {
        uint256 remainingTime = distributor.getRemainingTime();
        assertApproxEqAbs(remainingTime, 90 days, 10);

        vm.warp(block.timestamp + 91 days);
        assertEq(distributor.getRemainingTime(), 0);
    }

    function testIsClaimingActive() public {
        assertTrue(distributor.isClaimingActive());

        // Test when paused
        vm.prank(owner);
        distributor.pause();
        assertFalse(distributor.isClaimingActive());

        // Unpause
        vm.prank(owner);
        distributor.unpause();
        assertTrue(distributor.isClaimingActive());

        // Test after deadline
        vm.warp(block.timestamp + 91 days);
        assertFalse(distributor.isClaimingActive());
    }

    function testGetClaimedAmount() public {
        assertEq(distributor.getClaimedAmount(alice), 0);

        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);

        assertEq(distributor.getClaimedAmount(alice), ALICE_AMOUNT);
    }

    // ============ Gas Tests ============

    function testGasForSingleClaim() public {
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        distributor.claim(ALICE_AMOUNT, aliceProof);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for single claim:", gasUsed);
        // Should be under 150k gas
        assertLt(gasUsed, 150000);
    }

    // ============ Fuzz Tests ============

    function testFuzzCannotClaimRandomAmounts(uint256 randomAmount) public {
        vm.assume(randomAmount != ALICE_AMOUNT);
        vm.assume(randomAmount > 0);

        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(randomAmount, aliceProof);
    }

    function testFuzzRecoverTokens(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1000000 ether);

        MockERC20 randomToken = new MockERC20("Random", "RND", amount);
        randomToken.transfer(address(distributor), amount);

        uint256 balanceBefore = randomToken.balanceOf(owner);

        vm.prank(owner);
        distributor.recoverERC20(address(randomToken), owner);

        assertEq(randomToken.balanceOf(owner), balanceBefore + amount);
    }
}
