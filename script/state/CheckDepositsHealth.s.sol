// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

/// @notice Script to check deposits accounting health for InfraredBERAV2
/// @dev Calculates expected deposits and compares against actual deposits variable
contract CheckDepositsHealth is Script {
    function run(address iberaProxy, address infraredProxy) external view {
        IInfraredBERAV2 ibera = IInfraredBERAV2(iberaProxy);
        IInfrared infrared = IInfrared(infraredProxy);

        console2.log("\n=== Deposits Health Check ===\n");

        // Get current deposits value
        uint256 currentDeposits = ibera.deposits();
        console2.log("Current Deposits:     ", currentDeposits);

        // Get pending deposits (not yet sent to CL)
        uint256 pendingDeposits = ibera.pending();
        console2.log("Pending Deposits:     ", pendingDeposits);

        // Sum all validator stakes
        ValidatorTypes.Validator[] memory validators =
            infrared.infraredValidators();
        uint256 sumStakes = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            bytes memory pubkey = validators[i].pubkey;
            uint256 stake = ibera.stakes(pubkey);
            sumStakes += stake;
            console2.log("  Validator", i, "stake:", stake);
        }
        console2.log("Sum Validator Stakes: ", sumStakes);

        // Calculate expected deposits
        // Expected = sumStakes + pendingDeposits + pendingRebalance
        // Pending rebalance = funds requested from CL that will be redeployed
        uint256 expectedDeposits = sumStakes + pendingDeposits;
        console2.log("\nExpected Deposits:    ", expectedDeposits);

        // Check health
        console2.log("\n=== Health Status ===\n");
        if (
            currentDeposits < expectedDeposits + 1 gwei
                && currentDeposits > expectedDeposits - 1 gwei
        ) {
            console2.log("Status: HEALTHY");
            console2.log("Discrepancy: 0");
        } else {
            console2.log("Status: UNHEALTHY - Accounting discrepancy detected");
            uint256 discrepancy = currentDeposits > expectedDeposits
                ? currentDeposits - expectedDeposits
                : expectedDeposits - currentDeposits;
            console2.log("Discrepancy:", discrepancy);

            if (currentDeposits < expectedDeposits) {
                console2.log(
                    "\nIssue: Deposits variable is LOWER than expected"
                );
                console2.log("Possible causes: Bypass deposits not yet synced");
            } else {
                console2.log(
                    "\nIssue: Deposits variable is HIGHER than expected"
                );
                console2.log(
                    "Possible causes: Rejected withdrawals not yet synced"
                );
            }
        }

        console2.log("\n=== Summary ===");
        console2.log(
            "Formula: Expected = SumStakes + PendingDeposits + PendingRebalance"
        );
        console2.log("SumStakes:             ", sumStakes);
        console2.log("Pending Deposits:      ", pendingDeposits);
        console2.log("Expected Deposits:     ", expectedDeposits);
        console2.log("Current Deposits:      ", currentDeposits);
        console2.log("");
    }
}
