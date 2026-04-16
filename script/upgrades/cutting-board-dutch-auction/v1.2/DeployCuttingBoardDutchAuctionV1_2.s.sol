// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {CuttingBoardDutchAuctionV1_2} from
    "src/periphery/CuttingBoardDutchAuctionV1_2.sol";

/// @notice Deploys the CuttingBoardDutchAuctionV1_2 implementation contract.
/// @dev    Run this first on the target network, then pass the resulting
///         implementation address to the corresponding Upgrade script.
contract DeployCuttingBoardDutchAuctionV1_2 is Script {
    function run() external {
        vm.startBroadcast();
        new CuttingBoardDutchAuctionV1_2();
        vm.stopBroadcast();
    }
}
