// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {InfraredBERARateProvider} from
    "src/beraswap/InfraredBERARateProvider.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";

contract InfraredBERARateProviderDeployer is Script {
    function run(IInfraredBERA _ibera) external {
        vm.startBroadcast();
        new InfraredBERARateProvider(_ibera);
        vm.stopBroadcast();
    }
}
