// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredGovernanceTokenV1_2} from
    "src/core/InfraredGovernanceTokenV1_2.sol";

contract InfraredGovernanceTokenDeployer is Script {
    function run(address _gov) external {
        vm.startBroadcast();

        new InfraredGovernanceTokenV1_2(_gov);

        vm.stopBroadcast();
    }
}
