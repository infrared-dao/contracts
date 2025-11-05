// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {WrappedVault} from "src/core/WrappedVault.sol";

contract WrappedVaultDeployer is Script {
    function run(
        address _multisig,
        address _infrared,
        address _stakingToken,
        string memory _name,
        string memory _symbol
    ) external {
        vm.startBroadcast();
        new WrappedVault(_multisig, _infrared, _stakingToken, _name, _symbol);
        vm.stopBroadcast();
    }
}
