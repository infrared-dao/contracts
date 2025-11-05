// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredV1_4} from "src/depreciated/core/InfraredV1_4.sol";

contract DeployInfraredV1_4 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeInfrared` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new InfraredV1_4();
        vm.stopBroadcast();
    }
}
