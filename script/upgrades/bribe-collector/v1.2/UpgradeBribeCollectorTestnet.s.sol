// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BribeCollectorV1_2} from "src/depreciated/core/BribeCollectorV1_2.sol";

contract UpgradeBribeCollectorTestnet is Script {
    /// @dev requires BribeCollectorV1.2 implementation to be deployed separately
    function run(
        address _bribeCollectorProxy,
        address _bribeCollectorV1_2Implementation
    ) external {
        // input check
        if (
            _bribeCollectorProxy == address(0)
                || _bribeCollectorV1_2Implementation == address(0)
        ) {
            revert();
        }
        // upgrade proxy
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            _bribeCollectorV1_2Implementation,
            ""
        );

        vm.startBroadcast();
        (bool success,) = _bribeCollectorProxy.call(data);
        if (!success) revert();

        vm.stopBroadcast();
    }
}
