// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {BribeCollectorV1_3} from "src/depreciated/core/BribeCollectorV1_3.sol";

contract UpgradeBribeCollectorV1_3 is BatchScript {
    /// @dev requires BribeCollectorV1.3 implementation to be deployed separately

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    function run(
        address safe,
        address _bribeCollectorProxy,
        address _bribeCollectorV1_3Implementation,
        address[] calldata _keepers
    ) external isBatch(safe) {
        // input check
        if (
            safe == address(0) || _bribeCollectorProxy == address(0)
                || _bribeCollectorV1_3Implementation == address(0)
        ) {
            revert();
        }
        // upgrade proxy
        // upgrade bribe collector
        bytes memory data1 = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            _bribeCollectorV1_3Implementation,
            ""
        );
        addToBatch(_bribeCollectorProxy, 0, data1);

        for (uint256 i; i < _keepers.length; i++) {
            address _keeper = _keepers[i];
            if (_keeper == address(0)) continue;
            // grant KEEPER_ROLE to addresses that need to call claimFees
            bytes memory data2 = abi.encodeWithSignature(
                "grantRole(bytes32,address)", KEEPER_ROLE, _keeper
            );
            addToBatch(_bribeCollectorProxy, 0, data2);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
