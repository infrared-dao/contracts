// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {InfraredBERAV2_1} from "src/staking/InfraredBERAV2_1.sol";

contract UpgradeInfraredBERAV2_1 is BatchScript {
    function run(bool _send, address safe, address _ibera)
        external
        isBatch(safe)
    {
        if (safe == address(0) || _ibera == address(0)) {
            revert("Zero address");
        }

        vm.startBroadcast();
        // deploy new implementation
        address iberaImp = address(new InfraredBERAV2_1());
        vm.stopBroadcast();

        // upgrade proxy
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", iberaImp, ""
        );
        addToBatch(_ibera, 0, data);

        executeBatch(_send);
    }
}
