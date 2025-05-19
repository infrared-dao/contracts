// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BribeCollectorV1_3} from "src/core/upgrades/BribeCollectorV1_3.sol";

contract UpgradeBribeCollectorV1_3Testnet is Script {
    /// @dev requires BribeCollectorV1.2 implementation to be deployed separately
    function run(
        address _bribeCollectorProxy,
        address _bribeCollectorV1_3Implementation
    ) external {
        // input check
        if (
            _bribeCollectorProxy == address(0)
                || _bribeCollectorV1_3Implementation == address(0)
        ) {
            revert();
        }
        // upgrade proxy
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            _bribeCollectorV1_3Implementation,
            ""
        );

        vm.startBroadcast();
        (bool success,) = _bribeCollectorProxy.call(data);
        if (!success) revert();

        vm.stopBroadcast();
    }
}
