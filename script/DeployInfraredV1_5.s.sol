// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";

contract DeployInfraredV1_5 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeInfrared` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new InfraredV1_5();
        vm.stopBroadcast();
    }
}
