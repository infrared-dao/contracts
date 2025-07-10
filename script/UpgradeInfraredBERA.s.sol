// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {InfraredBERAWithdraworLite} from
    "src/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAWithdrawor} from
    "src/staking/upgrades/InfraredBERAWithdrawor.sol";
import {InfraredBERAV2} from "src/staking/upgrades/InfraredBERAV2.sol";
import {InfraredBERADepositorV2} from
    "src/staking/upgrades/InfraredBERADepositorV2.sol";

contract UpgradeInfraredBERA is BatchScript {
    function deploy() external {
        vm.startBroadcast();
        // deploy new implementations
        new InfraredBERAWithdrawor();
        new InfraredBERADepositorV2();
        new InfraredBERAV2();
        vm.stopBroadcast();
    }

    function run(
        address safe,
        address _withdraworLite,
        address _withdrawalPrecompile,
        address _ibera,
        address _depositor,
        address withdraworImp,
        address depositorImp,
        address iberaImp
    ) external isBatch(safe) {
        if (
            safe == address(0) || _withdraworLite == address(0)
                || _withdrawalPrecompile == address(0) || _ibera == address(0)
                || _depositor == address(0) || withdraworImp == address(0)
                || depositorImp == address(0) || iberaImp == address(0)
        ) {
            revert();
        }

        // upgrade proxies
        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", withdraworImp, ""
        );
        addToBatch(_withdraworLite, 0, data);

        data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", depositorImp, ""
        );
        addToBatch(_depositor, 0, data);

        data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", iberaImp, ""
        );
        addToBatch(_ibera, 0, data);

        // initialize
        data = abi.encodeWithSignature(
            "initializeV2(address)", _withdrawalPrecompile
        );
        addToBatch(_withdraworLite, 0, data);

        data = abi.encodeWithSignature("initializeV2()");
        addToBatch(_depositor, 0, data);

        data = abi.encodeWithSignature("initializeV2()");
        addToBatch(_ibera, 0, data);

        // add keystore eoa account as keeper for depositor and withdrawor (already keeper for ibera)
        address keystoreKeeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;
        bytes32 role = InfraredBERAV2(_ibera).KEEPER_ROLE();
        data = abi.encodeWithSignature(
            "grantRole(bytes32,address)", role, keystoreKeeper
        );
        addToBatch(_depositor, 0, data);
        addToBatch(_withdraworLite, 0, data);

        // broadcast batch
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
