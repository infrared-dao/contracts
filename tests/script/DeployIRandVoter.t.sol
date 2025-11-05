// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from "src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/depreciated/core/Infrared.sol";

contract DeployIRandVoterTest is Helper {
    function testDeployments() public {
        ir = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        // gov only (i.e. this needs to be run by gov)
        vm.startPrank(infraredGovernance);
        infrared.setIR(address(ir));
        vm.stopPrank();
    }

    function isProxy(address proxy) internal view returns (bool) {
        (bool success, bytes memory data) =
            proxy.staticcall(abi.encodeWithSignature("implementation()"));
        return success && data.length > 0;
    }
}
