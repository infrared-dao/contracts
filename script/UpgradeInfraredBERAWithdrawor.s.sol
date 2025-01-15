// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERAWithdraworLite} from
    "src/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";

contract UpgradeInfraredBERAWithdrawor is Script {
    InfraredBERAWithdraworLite public withdraworLite;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAClaimor public claimor;

    function run(
        address _gov,
        address _keeper,
        address _withdraworLite,
        address _withdrawalPrecompile
    ) external {
        withdraworLite = InfraredBERAWithdraworLite(payable(_withdraworLite));

        vm.startBroadcast();
        // deploy new implementation
        withdrawor = new InfraredBERAWithdrawor();
        // deploy claimor with proxy
        claimor =
            InfraredBERAClaimor(setupProxy(address(new InfraredBERAClaimor())));

        // perform upgrade
        (bool success,) = address(withdraworLite).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(withdrawor), ""
            )
        );
        require(success, "Upgrade failed");

        // point at proxy
        withdrawor = InfraredBERAWithdrawor(payable(address(withdraworLite)));
        // initialize
        claimor.initialize(_gov, _keeper, address(withdrawor.InfraredBERA()));
        withdrawor.initializeV2(address(claimor), _withdrawalPrecompile);

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
