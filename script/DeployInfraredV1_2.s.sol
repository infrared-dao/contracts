// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredV1_2} from "src/core/InfraredV1_2.sol";

contract DeployInfraredV1_2 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeInfrared` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new InfraredV1_2();
        vm.stopBroadcast();
    }
}
