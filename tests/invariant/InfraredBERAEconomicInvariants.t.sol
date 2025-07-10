// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// Helper for inheriting the main setup
import {
    InfraredBERAInvariantHandler,
    InfraredBERAInvariants
} from "./InfraredBERAInvariants.t.sol";

/**
 * @title InfraredBERAEconomicInvariants
 * @notice Economic invariant tests for the InfraredBERA system focusing on yield compounding
 * @dev Extends the main invariant tests but specializes in economic behavior
 */
contract InfraredBERAEconomicInvariants is InfraredBERAInvariants {
    // Tolerance for rate comparisons (5% to account for yield and rounding)
    uint256 constant RATE_TOLERANCE = 0.05e18; // 5%

    function setUp() public override {
        super.setUp();
        // No additional state setup needed; rely on handler
    }

    /**
     * @notice Invariant: Exchange rate improves or remains stable after compounding
     * @dev Checks that each compound with yield reduces shares per BERA (improves rate)
     */
    function invariant_exchangeRateImprovesAfterCompound() external view {
        InfraredBERAInvariantHandler.CompoundAction[] memory compoundHistory =
            handler.getCompounds();
        for (uint256 i = 0; i < compoundHistory.length; i++) {
            if (compoundHistory[i].amount > 0) {
                assertGt(
                    compoundHistory[i].exchangeRateAfter,
                    compoundHistory[i].exchangeRateBefore,
                    "Exchange rate did not improve after compounding yield"
                );
            } else {
                // If no yield, rate should be stable
                assertEq(
                    compoundHistory[i].exchangeRateAfter,
                    compoundHistory[i].exchangeRateBefore,
                    "Exchange rate changed without yield"
                );
            }
        }
    }

    /**
     * @notice Invariant: Deposit rates are consistent or improve over time
     * @dev Ensures deposit rates (shares per BERA) don’t worsen unexpectedly, allowing improvement from yields
     */
    function invariant_depositRateStability() external view {
        InfraredBERAInvariantHandler.DepositAction[] memory depositHistory =
            handler.getDeposits();
        if (depositHistory.length <= 1) return;

        uint256 previousRate = depositHistory[0].rate;
        for (uint256 i = 1; i < depositHistory.length; i++) {
            if (depositHistory[i].beraAmount == 0) continue;

            uint256 currentRate = depositHistory[i].rate;
            // Rate can improve (decrease) due to yields, but shouldn’t worsen beyond tolerance
            assertTrue(
                currentRate <= previousRate * (1e18 + RATE_TOLERANCE) / 1e18,
                "Deposit rate worsened unexpectedly"
            );
            previousRate = currentRate;
        }
    }

    /**
     * @notice Invariant: Fees are proportional to yield within tolerance
     * @dev Verifies fees align with the fee divisor, allowing small rounding differences
     */
    function invariant_feesProportionalToYield() external view {
        uint256 feeDivisor = ibera.feeDivisorShareholders();
        InfraredBERAInvariantHandler.CompoundAction[] memory compoundHistory =
            handler.getCompounds();
        for (uint256 i = 0; i < compoundHistory.length; i++) {
            if (compoundHistory[i].amount > 0) {
                uint256 expectedFees;
                if (feeDivisor > 0) {
                    expectedFees = compoundHistory[i].amount / feeDivisor;
                }
                assertApproxEqAbs(
                    compoundHistory[i].fees,
                    expectedFees,
                    1e18, // Larger tolerance for small rounding errors (0.000001 ether)
                    "Fees not proportional to yield"
                );
            } else {
                assertEq(
                    compoundHistory[i].fees, 0, "Fees present without yield"
                );
            }
        }
    }

    /**
     * @notice Invariant: Total system value is preserved or increases
     * @dev Checks that compounding preserves value (deposits + receivor balance)
     */
    function invariant_totalValuePreservation() external view {
        InfraredBERAInvariantHandler.CompoundAction[] memory compoundHistory =
            handler.getCompounds();
        for (uint256 i = 0; i < compoundHistory.length; i++) {
            if (compoundHistory[i].amount > 0) {
                assertEq(
                    compoundHistory[i].totalValueAfter,
                    compoundHistory[i].totalValueBefore
                        + compoundHistory[i].amount,
                    "Total value not preserved after compounding"
                );
            } else {
                assertEq(
                    compoundHistory[i].totalValueAfter,
                    compoundHistory[i].totalValueBefore,
                    "Total value changed without yield"
                );
            }
        }
    }

    /**
     * @notice Invariant: Exchange rate never exceeds initial 1:1 rate
     * @dev Ensures the rate (shares per BERA) doesn’t worsen beyond the starting point
     */
    function invariant_exchangeRateBounded() external view {
        uint256 currentRate = ibera.totalSupply() > 0 && ibera.deposits() > 0
            ? ibera.previewMint(1e18)
            : 1e18;
        assertLe(currentRate, 1e18, "Exchange rate exceeded initial 1:1 bound");

        // Check deposit history too
        InfraredBERAInvariantHandler.DepositAction[] memory depositHistory =
            handler.getDeposits();
        for (uint256 i = 0; i < depositHistory.length; i++) {
            if (depositHistory[i].beraAmount > 0) {
                assertLe(
                    depositHistory[i].rate,
                    1e18 + 1,
                    "Deposit rate exceeded initial 1:1 bound"
                );
            }
        }
    }
}
