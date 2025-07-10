// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredBERARateProvider} from
    "src/beraswap/InfraredBERARateProvider.sol";
import {IInfraredBERAV2} from "src/interfaces/upgrades/IInfraredBERAV2.sol";

contract InfraredBERARateProviderDeployer is Script {
    function run(IInfraredBERAV2 _ibera) external {
        vm.startBroadcast();
        new InfraredBERARateProvider(_ibera);
        vm.stopBroadcast();
    }
}
