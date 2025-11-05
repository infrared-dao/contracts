// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {InfraredV1_5} from "src/depreciated/core/InfraredV1_5.sol";

contract UpgradeInfraredTestnetV1_5 is Script {
    /// @dev requires InfraredV1.4 implementation to be deployed separately
    function run(address _infraredProxy, address _infraredV1_5Implementation)
        external
    {
        // input check
        if (
            _infraredProxy == address(0)
                || _infraredV1_5Implementation == address(0)
        ) {
            revert();
        }

        vm.startBroadcast();

        // upgrade proxy
        (bool success,) = _infraredProxy.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                _infraredV1_5Implementation,
                ""
            )
        );

        if (!success) revert();

        vm.stopBroadcast();
    }
}
