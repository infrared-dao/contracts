// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {InfraredV1_3} from "src/depreciated/core/InfraredV1_3.sol";

contract UpgradeInfraredV1_3 is BatchScript {
    /// @dev requires InfraredV1.3 implementation to be deployed separately
    function run(
        address safe,
        address _infraredProxy,
        address _infraredV1_3Implementation,
        bytes[] calldata _pubkeys
    ) external isBatch(safe) {
        // input check
        if (
            safe == address(0) || _infraredProxy == address(0)
                || _infraredV1_3Implementation == address(0)
        ) {
            revert();
        }
        // upgrade proxy
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", _infraredV1_3Implementation, ""
        );
        addToBatch(_infraredProxy, 0, data);

        // queue validator incentive commissions
        uint256 len = _pubkeys.length;
        uint96 maxCommissionRate = 10000; // 100% = 10000 in BeraChef
        for (uint256 i; i < len; i++) {
            data = abi.encodeWithSignature(
                "queueValCommission(bytes,uint96)",
                _pubkeys[i],
                maxCommissionRate
            );
            addToBatch(_infraredProxy, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
