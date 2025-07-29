// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";

contract DeployWrappedRewardToken is Script {
    function run() external {
        vm.startBroadcast();
        // hard code for BYUSD
        new WrappedRewardToken(
            ERC20(0x688e72142674041f8f6Af4c808a4045cA1D6aC82),
            "Wrapped BYUSD",
            "wBYUSD"
        );
        vm.stopBroadcast();
    }
}
