// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {CuttingBoardManagerV1_1} from
    "src/periphery/CuttingBoardManagerV1_1.sol";

/// @notice Deploys the CuttingBoardManagerV1_1 implementation contract.
/// @dev    Run this first on the target network, then pass the resulting
///         implementation address to the corresponding Upgrade script.
contract DeployCuttingBoardManagerV1_1 is Script {
    function run() external {
        vm.startBroadcast();
        new CuttingBoardManagerV1_1();
        vm.stopBroadcast();
    }
}
