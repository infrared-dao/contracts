// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {HarvestBaseCollectorV1_2} from
    "src/staking/HarvestBaseCollectorV1_2.sol";

contract UpgradeBaseCollector is BatchScript {
    function run(address safe, address _baseCollectorProxy)
        external
        isBatch(safe)
    {
        // input check
        if (safe == address(0) || _baseCollectorProxy == address(0)) {
            revert();
        }

        // deploy new implementation
        vm.startBroadcast();
        address _baseCollectorV1_2Implementation =
            address(new HarvestBaseCollectorV1_2());
        vm.stopBroadcast();

        // upgrade proxy
        // upgrade bribe collector
        bytes memory data1 = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            _baseCollectorV1_2Implementation,
            ""
        );
        addToBatch(_baseCollectorProxy, 0, data1);

        executeBatch(true);
    }
}
