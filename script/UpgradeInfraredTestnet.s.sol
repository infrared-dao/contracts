// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {InfraredV1_2} from "src/core/upgrades/InfraredV1_2.sol";

contract UpgradeInfraredTestnet is Script {
    /// @dev requires InfraredV1.2 implementation to be deployed separately
    function run(
        address _infraredProxy,
        address _infraredV1_2Implementation,
        address[] calldata _stakingTokens
    ) external {
        // input check
        if (
            _infraredProxy == address(0)
                || _infraredV1_2Implementation == address(0)
        ) {
            revert();
        }

        vm.startBroadcast();

        // upgrade proxy
        (bool success,) = _infraredProxy.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                _infraredV1_2Implementation,
                ""
            )
        );

        if (!success) revert();

        // init new contract
        (success,) = _infraredProxy.call(
            abi.encodeWithSignature("initializeV1_2(address[])", _stakingTokens)
        );

        if (!success) revert();

        vm.stopBroadcast();
    }
}
