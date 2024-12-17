// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {Infrared, ValidatorTypes} from "src/core/Infrared.sol";

contract InfraredGovernance is Script {
    Infrared infrared = Infrared(0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219);

    function addValidators() public {
        ValidatorTypes.Validator[] memory _validators = new ValidatorTypes.Validator[](1);
        _validators[0] = ValidatorTypes.Validator({
            pubkey: hex"ad8af2d381461965e08126e48bc95646c2ca74867255381397dc70e711bab07015551a8904c167459f5e6da4db436300",
            addr: 0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926
        });
        vm.startBroadcast();
        infrared.addValidators(_validators);
        vm.stopBroadcast();
    }
}