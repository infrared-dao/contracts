// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {BribeCollectorV1_2} from "src/core/upgrades/BribeCollectorV1_2.sol";

contract DeployBribeCollectorV1_2 is Script {
    /// @dev deployemnt address needs to be passed to `UpgradeBribeCollector` to upgrade proxy
    function run() external {
        vm.startBroadcast();
        new BribeCollectorV1_2();
        vm.stopBroadcast();
    }
}
