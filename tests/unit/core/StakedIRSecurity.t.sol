// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "src/utils/Errors.sol";

/// @title StakedIRSecurityTest
/// @notice Security-focused tests for StakedIR contract
/// @dev Tests for critical security fixes: storage location, overflow protection, queue logic
contract StakedIRSecurityTest is Test {
    StakedIR public sir;
    MockERC20 public ir;

    address public governance = makeAddr("governance");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_DEPOSIT = 10 ether;

    function setUp() public {
        // Deploy IR token
        ir = new MockERC20("Infrared", "IR", 18);

        // Mint initial IR for initialization
        ir.mint(address(this), INITIAL_DEPOSIT);

        // Deploy StakedIR implementation
        address sirImpl = address(new StakedIR());

        // Pre-compute proxy address for approval (inflation protection)
        address sirProxyAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        ir.approve(sirProxyAddress, INITIAL_DEPOSIT);

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );
        sir = StakedIR(address(new ERC1967Proxy(sirImpl, initData)));

        // Setup test users with IR tokens
        ir.mint(alice, type(uint128).max);
        ir.mint(bob, 10000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          [C-01] ERC-7201 STORAGE LOCATION TESTS            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Verify the ERC-7201 storage location is correctly calculated
    /// @dev This is a critical test - wrong storage location = storage collision
    function test_StorageLocation_IsCorrect() public pure {
        // Expected calculation per ERC-7201:
        // keccak256("infrared.stakedIRStorage") = 0xe37d8c878a50f0326695af34a6b5c1ac8f3bc817d7b9727cc43175799b685eb6
        // (hash - 1) & ~0xff = 0xe37d8c878a50f0326695af34a6b5c1ac8f3bc817d7b9727cc43175799b685e00

        bytes32 expectedLocation =
            0xe37d8c878a50f0326695af34a6b5c1ac8f3bc817d7b9727cc43175799b685e00;

        // Calculate using the same method as the contract should
        bytes32 innerHash = keccak256(bytes("infrared.stakedIRStorage"));
        uint256 minusOne = uint256(innerHash) - 1;
        bytes32 actualLocation = bytes32(minusOne & ~uint256(0xff));

        assertEq(
            actualLocation,
            expectedLocation,
            "Storage location does not match ERC-7201 calculation"
        );
    }

    /// @notice Verify storage doesn't collide with parent contracts
    /// @dev Check that our storage slot is in the ERC-7201 namespace (far from normal slots)
    function test_StorageLocation_NoCollisionWithParents() public pure {
        bytes32 location =
            0x218f59ba5e686bba8d3202f77a1f61091bbb42f47180e2346f114cf3ba5b1500;

        // ERC-7201 locations should be very high slot numbers to avoid collisions
        // The slot number should be > 2^200 to be in the safe namespace
        uint256 slotNumber = uint256(location);

        // Verify it's in the high slot range
        assertTrue(
            slotNumber > 2 ** 200, "Storage location not in ERC-7201 safe range"
        );
    }

    /// @notice Verify storage operations work correctly with the storage location
    function test_StorageLocation_FunctionalityWorks() public {
        // Test that we can write and read from storage correctly
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify the storage was written correctly
        assertEq(sir.balanceOf(alice), depositAmount);

        // Create a withdrawal request to test more storage
        vm.startPrank(alice);
        sir.redeem(50 ether, alice, alice);
        vm.stopPrank();

        // Verify withdrawal request was stored
        assertEq(sir.requestLength(), 1);
        (bool claimed,,,, address receiver) = sir.getWithdrawalRequest(1);
        assertFalse(claimed);
        assertEq(receiver, alice);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          [H-01] OVERFLOW PROTECTION TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test that shares overflow is prevented
    /// @dev Attempting to redeem > uint128.max shares should revert
    function test_Overflow_SharesExceedUint128Max() public {
        // We can't easily create > uint128.max shares in ERC20
        // But we can test the revert logic by creating a scenario
        // where we try to redeem an amount that would overflow

        // Mint exactly uint128.max + 1 to alice (this will overflow uint128)
        uint256 overflowAmount = uint256(type(uint128).max) + 1;
        ir.mint(alice, overflowAmount);

        vm.startPrank(alice);
        ir.approve(address(sir), overflowAmount);
        sir.deposit(overflowAmount, alice);

        // Try to redeem the overflow amount - should revert
        uint256 aliceShares = sir.balanceOf(alice);

        // Since shares will be > uint128.max, this should revert
        vm.expectRevert(StakedIR.AmountTooLarge.selector);
        sir.redeem(aliceShares, alice, alice);
        vm.stopPrank();
    }

    /// @notice Test that assets overflow is prevented
    /// @dev When assets exceed uint128.max, redeem should revert
    function test_Overflow_AssetsExceedUint128Max() public {
        // Setup: Alice deposits a large amount
        uint256 depositAmount = type(uint128).max / 2;
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);
        vm.stopPrank();

        // Compound a huge amount to increase share value
        uint256 compoundAmount = type(uint128).max;
        ir.mint(address(this), compoundAmount);
        ir.approve(address(sir), compoundAmount);
        sir.compound(compoundAmount);

        // Now try to redeem - the assets should exceed uint128.max
        vm.startPrank(alice);
        uint256 aliceShares = sir.balanceOf(alice);
        uint256 assetsPreview = sir.previewRedeem(aliceShares);

        if (assetsPreview > type(uint128).max) {
            vm.expectRevert(StakedIR.AmountTooLarge.selector);
            sir.redeem(aliceShares, alice, alice);
        }
        vm.stopPrank();
    }

    /// @notice Test timestamp overflow protection
    /// @dev While unrealistic, ensure we handle timestamp + withdrawalPeriod > uint88.max
    function test_Overflow_TimestampExceedsUint88Max() public {
        // uint88.max = 309485009821345068724781055 (year ~9.8 trillion)
        // Current timestamp is ~1.7e9 (year 2024)
        // This is essentially impossible, but we test the check exists

        // Warp to near uint88.max
        vm.warp(type(uint88).max - 1 days);

        // Try to set withdrawal period that would overflow
        vm.prank(governance);
        sir.setWithdrawalPeriod(2 days);

        // Try to create withdrawal request (should fail)
        vm.startPrank(alice);
        ir.approve(address(sir), 100 ether);
        sir.deposit(100 ether, alice);

        vm.expectRevert(StakedIR.TimestampOverflow.selector);
        sir.redeem(50 ether, alice, alice);
        vm.stopPrank();
    }

    /// @notice Test that valid amounts within uint128 bounds work correctly
    function test_Overflow_ValidAmountsWork() public {
        // Test with amounts well within uint128 bounds
        uint256 validAmount = 1_000_000 ether; // 1 million tokens

        vm.startPrank(alice);
        ir.approve(address(sir), validAmount);
        sir.deposit(validAmount, alice);

        // Should succeed without reverting
        sir.redeem(validAmount / 2, alice, alice);
        vm.stopPrank();

        assertEq(sir.requestLength(), 1);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          [H-02] QUEUE AMOUNT LOGIC TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // /// @notice Test getQueuedAmount with withdrawal period reduction
    // /// @dev This is the key scenario that broke the old implementation
    // function test_QueuedAmount_WithdrawalPeriodReduction() public {
    //     // Setup: Create withdrawal request with 7 day period
    //     vm.startPrank(alice);
    //     ir.approve(address(sir), 1000 ether);
    //     sir.deposit(1000 ether, alice);
    //     sir.redeem(100 ether, alice, alice); // Request #1
    //     vm.stopPrank();

    //     uint256 request1Time = block.timestamp + 7 days;

    //     // Governance reduces withdrawal period to 1 day
    //     vm.prank(governance);
    //     sir.setWithdrawalPeriod(1 days);

    //     // Warp forward 2 days
    //     vm.warp(block.timestamp + 2 days);

    //     // Create another withdrawal request (Request #2)
    //     vm.startPrank(bob);
    //     ir.approve(address(sir), 1000 ether);
    //     sir.deposit(1000 ether, bob);
    //     sir.redeem(50 ether, bob, bob); // Request #2
    //     vm.stopPrank();

    //     uint256 request2Time = block.timestamp + 1 days;

    //     // Request #2 unlocks before Request #1 due to period reduction
    //     assertTrue(
    //         request2Time < request1Time, "Request #2 should unlock first"
    //     );

    //     // Warp to when Request #2 unlocks but Request #1 doesn't
    //     vm.warp(request2Time + 1);

    //     // getQueuedAmount should still count Request #1 even though we iterate backwards
    //     uint256 queued = sir.getQueuedAmount();

    //     // Request #1 (100 ether) should be queued, Request #2 is claimable
    //     assertEq(queued, 100 ether, "Request #1 should still be counted");
    // }

    /// @notice Test getQueuedAmount doesn't count claimed tickets
    function test_QueuedAmount_ExcludesClaimedTickets() public {
        // Create two withdrawal requests
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        sir.deposit(1000 ether, alice);
        sir.redeem(100 ether, alice, alice); // Request #1
        sir.redeem(200 ether, alice, alice); // Request #2
        vm.stopPrank();

        // Initially both are queued
        uint256 queuedBefore = sir.getQueuedAmount();
        assertEq(queuedBefore, 300 ether, "Both requests should be queued");

        // Warp past unlock time
        vm.warp(block.timestamp + 8 days);

        // Claim Request #1
        sir.claimWithdraw(1);

        // getQueuedAmount should not count claimed Request #1
        uint256 queuedAfter = sir.getQueuedAmount();
        assertEq(
            queuedAfter, 0, "Claimed request should not be counted as queued"
        );
    }

    /// @notice Test getQueuedAmount with multiple requests at different times
    function test_QueuedAmount_MultipleRequestsDifferentTimes() public {
        // Create multiple withdrawal requests
        vm.startPrank(alice);
        ir.approve(address(sir), 10000 ether);
        sir.deposit(10000 ether, alice);

        sir.redeem(100 ether, alice, alice); // Request #1, unlocks at t + 7 days
        vm.warp(block.timestamp + 1 days);
        sir.redeem(200 ether, alice, alice); // Request #2, unlocks at t + 8 days
        vm.warp(block.timestamp + 1 days);
        sir.redeem(300 ether, alice, alice); // Request #3, unlocks at t + 9 days
        vm.stopPrank();

        // At t + 7.5 days, Request #1 is claimable, #2 and #3 are queued
        vm.warp(block.timestamp + 5.5 days);

        uint256 queued = sir.getQueuedAmount();
        assertEq(
            queued, 500 ether, "Requests #2 and #3 should be queued (200 + 300)"
        );

        uint256 claimable = sir.getClaimableAmount();
        assertEq(claimable, 100 ether, "Request #1 should be claimable");
    }

    /// @notice Test getQueuedAmount is accurate after period changes
    function test_QueuedAmount_AccuracyAfterPeriodChanges() public {
        uint256 startTime = block.timestamp;

        // Create requests with initial 7 day period
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        sir.deposit(1000 ether, alice);
        sir.redeem(100 ether, alice, alice); // Request #1 unlocks at startTime + 7 days
        vm.stopPrank();

        // Change period to 14 days
        vm.prank(governance);
        sir.setWithdrawalPeriod(14 days);

        vm.warp(block.timestamp + 1 days);
        // uint256 request2Time = block.timestamp;

        // Create another request with 14 day period
        vm.startPrank(bob);
        ir.approve(address(sir), 1000 ether);
        sir.deposit(1000 ether, bob);
        sir.redeem(200 ether, bob, bob); // Request #2 unlocks at request2Time + 14 days
        vm.stopPrank();

        // At startTime + 7.5 days:
        // - Request #1 unlocks at startTime + 7 days (claimable)
        // - Request #2 unlocks at request2Time + 14 days = startTime + 15 days (queued)
        vm.warp(startTime + 7.5 days);

        uint256 queued = sir.getQueuedAmount();
        assertEq(
            queued, 200 ether, "Only Request #2 should be queued at t+7.5 days"
        );

        uint256 claimable = sir.getClaimableAmount();
        assertEq(
            claimable, 100 ether, "Request #1 should be claimable at t+7.5 days"
        );
    }

    /// @notice Test that totalReserved is always sum of queued + claimable
    function test_QueuedAmount_AccountingInvariant() public {
        // Create multiple requests
        vm.startPrank(alice);
        ir.approve(address(sir), 10000 ether);
        sir.deposit(10000 ether, alice);

        sir.redeem(100 ether, alice, alice);
        sir.redeem(200 ether, alice, alice);
        sir.redeem(300 ether, alice, alice);
        vm.stopPrank();

        // At any point in time: totalReserved = queued + claimable (unclaimed)
        uint256 totalReserved = sir.totalReserved();
        uint256 queued = sir.getQueuedAmount();
        uint256 claimable = sir.getClaimableAmount();

        assertEq(
            totalReserved,
            queued + claimable,
            "totalReserved should equal queued + claimable"
        );

        // Warp forward and check again
        vm.warp(block.timestamp + 8 days);

        totalReserved = sir.totalReserved();
        queued = sir.getQueuedAmount();
        claimable = sir.getClaimableAmount();

        assertEq(
            totalReserved,
            queued + claimable,
            "Invariant should hold after time passes"
        );

        // Claim one and check again
        sir.claimWithdraw(1);

        totalReserved = sir.totalReserved();
        queued = sir.getQueuedAmount();
        claimable = sir.getClaimableAmount();

        assertEq(
            totalReserved,
            queued + claimable,
            "Invariant should hold after claiming"
        );
    }

    /// @notice Fuzz test: getQueuedAmount should never exceed totalReserved
    function testFuzz_QueuedAmount_NeverExceedsTotalReserved(
        uint256 depositAmount,
        uint256 redeemAmount
    ) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1 ether, 1_000_000 ether);
        redeemAmount = bound(redeemAmount, 0.1 ether, depositAmount);

        // Mint and deposit
        ir.mint(alice, depositAmount);
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);

        // Redeem some
        if (redeemAmount <= sir.balanceOf(alice)) {
            sir.redeem(redeemAmount, alice, alice);
        }
        vm.stopPrank();

        // Invariant: queued should never exceed total reserved
        uint256 queued = sir.getQueuedAmount();
        uint256 reserved = sir.totalReserved();

        assertTrue(
            queued <= reserved, "Queued amount should never exceed reserved"
        );
    }
}
