// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {BatchClaimerV2_1} from "src/periphery/BatchClaimerV2_1.sol";

contract DeployBatchClaimer is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeInfrared` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new BatchClaimerV2_1();
        vm.stopBroadcast();
    }
}
