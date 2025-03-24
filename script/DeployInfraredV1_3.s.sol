// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredV1_3} from "src/core/upgrades/InfraredV1_3.sol";

contract DeployInfraredV1_3 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeInfrared` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new InfraredV1_3();
        vm.stopBroadcast();
    }
}
