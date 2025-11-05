// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from "src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {InfraredV1_9} from "src/core/InfraredV1_9.sol";

contract InfraredGovernanceTokenDeployer is Script {
    InfraredBGT public ibgt;
    ERC20PresetMinterPauser public ir;

    InfraredV1_9 public infrared;

    function run(address _gov, address _infrared) external {
        vm.startBroadcast();

        infrared = InfraredV1_9(payable(_infrared));
        ibgt = infrared.ibgt();

        ir = new InfraredGovernanceToken(
            address(infrared), _gov, _gov, _gov, address(0)
        );

        // gov only (i.e. this needs to be run by gov)
        // infrared.setIR(address(ir));

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
