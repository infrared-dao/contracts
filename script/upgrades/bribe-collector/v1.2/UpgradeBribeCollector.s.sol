// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {BribeCollectorV1_2} from "src/depreciated/core/BribeCollectorV1_2.sol";

contract UpgradeBribeCollector is BatchScript {
    /// @dev requires BribeCollectorV1.2 implementation to be deployed separately
    function run(
        address safe,
        address _bribeCollectorProxy,
        address _bribeCollectorV1_2Implementation
    ) external isBatch(safe) {
        // input check
        if (
            safe == address(0) || _bribeCollectorProxy == address(0)
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
        addToBatch(_bribeCollectorProxy, 0, data);

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
