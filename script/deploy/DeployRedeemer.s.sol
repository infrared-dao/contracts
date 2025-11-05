// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {Redeemer} from "src/periphery/Redeemer.sol";

contract DeployRedeemer is Script {
    address bgt = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
    address infrared = 0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126;

    function run() external {
        // constructor(
        //     address _bgt,
        //     address _infrared
        // ) {
        vm.startBroadcast();
        new Redeemer(bgt, infrared);
        vm.stopBroadcast();
    }
}
