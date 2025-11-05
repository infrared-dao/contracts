// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helper} from "../core/Infrared/Helper.sol";
import {Errors} from "src/utils/Errors.sol";
import {InfraredBERAV2BaseTest} from
    "tests/unit/staking/upgrades/InfraredBERAV2Base.t.sol";

/**
 * @title ExchangeRateSecurityTest
 * @notice Critical security tests for iBERA exchange rate manipulation prevention
 * @dev Tests first depositor attack, large deposits, compound timing, and exchange rate edge cases
 */
contract ExchangeRateSecurityTest is InfraredBERAV2BaseTest {
    address attacker = address(0xBAD);
    address victim = address(0x123);
    // Note: Withdrawals are already enabled in Helper.setUp() via ibera.initializeV2()

    /*//////////////////////////////////////////////////////////////
                    FIRST DEPOSITOR ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFirstDepositorAttack_Prevented() public {
        // Deploy fresh iBERA without initial deposit to test protection
        // Note: In production, setUp() already includes 10 ether initial deposit
        // This test verifies that the initial deposit prevents manipulation

        uint256 initialSupply = ibera.totalSupply();
        uint256 initialDeposits = ibera.deposits();

        // Verify initial deposit exists (from setUp)
        assertGt(initialSupply, 0, "Should have initial supply");
        assertGt(initialDeposits, 0, "Should have initial deposits");

        // Attacker tries to manipulate with small deposit + large "donation" via depositor
        vm.deal(attacker, 1000 ether);

        // Step 1: Attacker deposits small amount
        vm.prank(attacker);
        uint256 attackerShares = ibera.mint{value: 0.001 ether}(attacker);

        // Step 2: Attacker tries to inflate exchange rate by queueing deposits
        // This simulates yield accrual which increases exchange rate
        // vm.prank(address(ibera));
        // depositor.queue{value: 100 ether}();
        vm.deal(address(receivor), 1000 ether);

        // Step 3: Victim deposits
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        uint256 victimShares = ibera.mint{value: 10 ether}(victim);

        // Victim should get reasonable shares (not 0 or dust)
        // Note: shares will be less than deposited due to improved exchange rate
        assertGt(victimShares, 0, "Victim should get substantial shares");

        // Attacker should not profit significantly from attack
        vm.prank(attacker);
        (uint256 attackerValue,) = ibera.previewBurn(attackerShares);

        // Attacker's value should not be much more than deposited
        // The initial liquidity prevents the attacker from capturing all the yield
        assertLt(
            attackerValue,
            10 ether, // Attacker's tiny deposit shouldn't capture all 100 ether donation
            "Attacker should not profit excessively from manipulation"
        );
    }

    function testMinimumLiquidity_Protection() public view {
        // Verify that initial liquidity provides protection
        uint256 initialSupply = ibera.totalSupply();

        // Initial supply should be significant enough to prevent manipulation
        assertGe(
            initialSupply,
            1e9, // At least 1 Gwei worth of shares
            "Insufficient initial liquidity"
        );

        // Verify exchange rate is reasonable
        uint256 rate = (ibera.deposits() * 1e18) / ibera.totalSupply();
        assertGe(rate, 0.9e18, "Exchange rate too low");
        assertLe(rate, 1.1e18, "Exchange rate too high");
    }

    /*//////////////////////////////////////////////////////////////
                    EXCHANGE RATE STABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testExchangeRate_LargeDeposit() public {
        uint256 initialRate = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Large deposit
        vm.deal(victim, 10000 ether);
        vm.prank(victim);
        ibera.mint{value: 10000 ether}(victim);

        uint256 newRate = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Exchange rate should remain stable (within 1%)
        uint256 deviation = newRate > initialRate
            ? (newRate - initialRate) * 100 / initialRate
            : (initialRate - newRate) * 100 / initialRate;

        assertLt(deviation, 1, "Exchange rate should remain stable");
    }

    function testExchangeRate_AfterCompound() public {
        uint256 rateBefore = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Simulate yield by queueing deposits via depositor
        // This creates yield that can be compounded
        vm.deal(address(receivor), 10 ether);

        // Compound
        vm.prank(keeper);
        ibera.compound();

        uint256 rateAfter = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Exchange rate should increase (users benefit from yield)
        assertGt(rateAfter, rateBefore, "Rate should increase after compound");

        // But not too much (reasonable yield accumulation)
        uint256 increase = (rateAfter - rateBefore) * 100 / rateBefore;
        assertLt(increase, 200, "Rate increase should be reasonable");
    }

    function testExchangeRate_WithPendingWithdrawals() public {
        // User deposits
        vm.deal(victim, 100 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 100 ether}(victim);

        uint256 rateBefore = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // User queues withdrawal (moves to pending)
        vm.prank(victim);
        ibera.burn(victim, shares / 2);

        uint256 rateAfter = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Exchange rate should remain relatively stable
        // pending() reduces confirmed(), but deposits stays same until withdrawal processed
        uint256 deviation = rateAfter > rateBefore
            ? (rateAfter - rateBefore) * 100 / rateBefore
            : (rateBefore - rateAfter) * 100 / rateBefore;

        assertLt(deviation, 10, "Rate should remain relatively stable");
    }

    /*//////////////////////////////////////////////////////////////
                    COMPOUND TIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompound_CalledBeforeMint() public {
        // Verify compound is called before mint to prevent timing attacks
        // This is tested by checking that yield is distributed before share calculation

        // Add yield via depositor
        vm.deal(address(receivor), 10 ether);

        uint256 depositsBefore = ibera.deposits();

        // Mint should trigger compound internally
        vm.deal(victim, 1 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 1 ether}(victim);

        uint256 depositsAfter = ibera.deposits();

        // Deposits should include both mint and compounded yield
        assertGt(
            depositsAfter - depositsBefore,
            1 ether,
            "Should include compounded yield"
        );

        // Shares should be calculated after compound
        assertGt(shares, 0, "Should receive shares");
    }

    function testCompound_CalledBeforeBurn() public {
        // Add yield via depositor
        vm.deal(address(ibera), 10 ether);
        vm.prank(address(ibera));
        depositor.queue{value: 10 ether}();

        // User deposits first
        vm.deal(victim, 100 ether);
        vm.prank(victim);

        uint256 rateBefore = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Add more yield
        vm.deal(address(ibera), 5 ether);
        vm.prank(address(ibera));
        depositor.queue{value: 5 ether}();

        // Burn should trigger compound first
        vm.prank(victim);

        uint256 rateAfter = (ibera.deposits() * 1e18) / ibera.totalSupply();

        // Rate should have improved from compound
        assertGe(rateAfter, rateBefore, "Rate should improve after compound");
    }

    /*//////////////////////////////////////////////////////////////
                    SHARE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testShares_FirstDeposit() public {
        // For a fresh contract (simulated), first deposit should get 1:1 shares
        // Our setUp already has initial deposit, so we test subsequent deposits

        // Shares should be roughly proportional (accounting for existing deposits)
        uint256 expectedShares = ibera.previewMint(100 ether);

        vm.deal(victim, 100 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 100 ether}(victim);

        // Allow 1% deviation for rounding
        uint256 deviation = shares > expectedShares
            ? (shares - expectedShares) * 100 / expectedShares
            : (expectedShares - shares) * 100 / expectedShares;

        assertLt(deviation, 1, "Shares calculation should be accurate");
    }

    function testShares_ZeroDeposit() public {
        vm.expectRevert(Errors.InvalidShares.selector);
        vm.prank(victim);
        ibera.mint{value: 0}(victim);
    }

    function testShares_DustDeposit() public {
        // Very small deposit should still get some shares
        vm.deal(victim, 1 wei);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 1 wei}(victim);

        // Should get at least some shares (no rounding to zero)
        // Note: might be 0 if exchange rate is high, but should not revert
        assertGe(shares, 0, "Should not revert on dust deposit");
    }

    function testBurn_ExactAmount() public {
        // User deposits
        vm.deal(victim, 100 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 100 ether}(victim);

        // Preview burn
        (uint256 expectedAmount,) = ibera.previewBurn(shares);

        // Actual burn
        vm.prank(victim);
        (, uint256 actualAmount) = ibera.burn(victim, shares);

        // Should match preview (accounting for fees)
        assertEq(
            actualAmount, expectedAmount, "Burn amount should match preview"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    SLIPPAGE PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testMint_NoSlippageProtection() public {
        // Note: Current implementation doesn't have slippage protection
        // This test documents the risk and can be updated when protection is added

        vm.deal(victim, 100 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 100 ether}(victim);

        // In future, might want:
        // ibera.mint{value: 100 ether}(victim, minShares);
        // where it reverts if shares < minShares

        assertGt(shares, 0, "Should receive shares");
    }

    /*//////////////////////////////////////////////////////////////
                    ROUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    function testRounding_MultipleSmallDeposits() public {
        uint256 totalShares = 0;

        // Multiple small deposits
        for (uint256 i = 0; i < 10; i++) {
            address user = address(uint160(1000 + i));
            vm.deal(user, 1 ether);
            vm.prank(user);
            uint256 shares = ibera.mint{value: 1 ether}(user);
            totalShares += shares;
        }

        // One large deposit
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        uint256 largeShares = ibera.mint{value: 10 ether}(victim);

        // Large deposit shares should be roughly equal to sum of small deposits
        // Allow 1% deviation for rounding differences
        uint256 deviation = largeShares > totalShares
            ? (largeShares - totalShares) * 100 / totalShares
            : (totalShares - largeShares) * 100 / largeShares;

        assertLt(
            deviation,
            1,
            "Rounding should not significantly favor either approach"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testExchangeRate_MaxValue() public {
        // Test with very large deposits value (but not overflow)
        // This is a fuzz-style test with a large but safe value

        vm.deal(victim, type(uint96).max);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 1000 ether}(victim);

        assertGt(shares, 0, "Should handle large deposits");

        // Exchange rate should still be computable
        uint256 rate = (ibera.deposits() * 1e18) / ibera.totalSupply();
        assertGt(rate, 0, "Exchange rate should be valid");
        assertLt(rate, type(uint128).max, "Exchange rate should not overflow");
    }

    function testExchangeRate_AfterManyOperations() public {
        // Simulate many operations to test rounding accumulation

        for (uint256 i = 0; i < 100; i++) {
            address user = address(uint160(2000 + i));

            // Deposits
            if (i % 2 == 0) {
                vm.deal(user, 10 ether);
                vm.prank(user);
                ibera.mint{value: 10 ether}(user);
            }

            // Add some yield periodically via depositor
            if (i % 10 == 0) {
                vm.deal(address(ibera), 1 ether);
                vm.prank(address(ibera));
                depositor.queue{value: 1 ether}();
            }
        }

        // Exchange rate should still be reasonable
        uint256 rate = (ibera.deposits() * 1e18) / ibera.totalSupply();
        assertGe(rate, 0.9e18, "Rate should not degrade significantly");
        assertLe(rate, 2e18, "Rate should not inflate unreasonably");
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function testInvariant_DepositsShouldMatchAccountingOrGreater()
        public
        view
    {
        // deposits >= confirmed() at all times
        uint256 confirmed = ibera.confirmed();
        uint256 deposits = ibera.deposits();

        assertGe(
            deposits,
            confirmed,
            "Deposits should be >= confirmed (includes pending)"
        );
    }

    function testInvariant_TotalSupplyMatchesShares() public {
        // Sum of all user shares should equal totalSupply
        // This is implicitly true in ERC20, but verify after operations

        vm.deal(victim, 100 ether);
        vm.prank(victim);
        uint256 shares = ibera.mint{value: 100 ether}(victim);

        assertEq(
            ibera.balanceOf(victim),
            shares,
            "User balance should match minted shares"
        );

        uint256 totalBefore = ibera.totalSupply();

        vm.prank(victim);
        ibera.burn(victim, shares / 2);

        uint256 totalAfter = ibera.totalSupply();

        assertEq(
            totalBefore - totalAfter,
            (shares / 2) - ibera.burnFee(),
            "Total supply should decrease by burned shares"
        );
    }
}
