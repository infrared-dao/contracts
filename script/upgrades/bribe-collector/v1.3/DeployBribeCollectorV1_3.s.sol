// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {BribeCollectorV1_3} from "src/depreciated/core/BribeCollectorV1_3.sol";

contract DeployBribeCollectorV1_3 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeBribeCollector` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new BribeCollectorV1_3();
        vm.stopBroadcast();
    }
}
