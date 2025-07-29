// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {Redeemer} from "src/periphery/Redeemer.sol";

contract DeployRedeemer is Script {
    address bgt = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
    address gov = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
    address[] redemmers = [
        0x9FbD14Bbd64d2EE00cEFc28164A0be66CFFfbe1C,
        0xCc8FdAdAF10dFE23bf589FbC8e989Cd4EDf03b59
    ];
    address infrared = 0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126;

    function run() external {
        // constructor(
        //     address _governance,
        //     address _bgt,
        //     address _infrared,
        //     address[] memory _redeemers
        // ) {
        vm.startBroadcast();
        new Redeemer(gov, bgt, infrared, redemmers);
        vm.stopBroadcast();
    }
}
