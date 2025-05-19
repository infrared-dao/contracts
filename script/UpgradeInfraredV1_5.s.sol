// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";

contract UpgradeInfraredV1_5 is BatchScript {
    /// @dev requires InfraredV1.4 implementation to be deployed separately
    function run(
        address safe,
        address _infraredProxy,
        address _infraredV1_5Implementation
    ) external isBatch(safe) {
        // input check
        if (
            safe == address(0) || _infraredProxy == address(0)
                || _infraredV1_5Implementation == address(0)
        ) {
            revert();
        }
        // upgrade proxy
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", _infraredV1_5Implementation, ""
        );
        addToBatch(_infraredProxy, 0, data);

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
