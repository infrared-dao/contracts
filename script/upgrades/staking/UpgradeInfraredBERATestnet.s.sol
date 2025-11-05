// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {InfraredBERAWithdraworLite} from
    "src/depreciated/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";

contract UpgradeInfraredBERATestnet is Script {
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERADepositorV2 public depositor;
    InfraredBERAV2 public ibera;

    function run(
        address _withdraworLite,
        address _withdrawalPrecompile,
        address _ibera,
        address _depositor
    ) external {
        vm.startBroadcast();
        // deploy new implementation
        withdrawor = new InfraredBERAWithdrawor();
        depositor = new InfraredBERADepositorV2();
        ibera = new InfraredBERAV2();

        // perform upgrade
        (bool success,) = _withdraworLite.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(withdrawor), ""
            )
        );
        require(success, "Upgrade failed");

        (success,) = _depositor.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(depositor), ""
            )
        );
        require(success, "Upgrade failed");

        (success,) = _ibera.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(ibera), ""
            )
        );
        require(success, "Upgrade failed");

        // point at proxy
        withdrawor = InfraredBERAWithdrawor(payable(_withdraworLite));
        depositor = InfraredBERADepositorV2(_depositor);
        ibera = InfraredBERAV2(_ibera);
        // initialize
        withdrawor.initializeV2(_withdrawalPrecompile);
        depositor.initializeV2();
        ibera.initializeV2();

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
