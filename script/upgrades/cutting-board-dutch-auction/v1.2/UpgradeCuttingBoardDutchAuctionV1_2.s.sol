// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

/// @notice Upgrades the CuttingBoardDutchAuction proxy to V1_2 via Safe multisig.
/// @dev    Batches upgradeToAndCall into the Safe transaction queue so the
///         multisig UI can review and confirm.
///         No re-initialisation is required — V1_2 only overrides setMinimumPrice.
contract UpgradeCuttingBoardDutchAuctionV1_2 is BatchScript {
    function run(address safe, address _proxy, address _implementation)
        external
        isBatch(safe)
    {
        if (
            safe == address(0) || _proxy == address(0)
                || _implementation == address(0)
        ) revert();

        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", _implementation, ""
        );
        addToBatch(_proxy, 0, data);

        executeBatch(true);
    }
}
