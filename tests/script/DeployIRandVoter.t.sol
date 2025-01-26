// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from "src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/core/Infrared.sol";

contract DeployIRandVoterTest is Helper {
    function testDeployments() public {
        voter = Voter(setupProxy(address(new Voter(address(infrared)))));

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
        infrared.setVoter(address(voter));
        vm.stopPrank();

        sIR = new VotingEscrow(
            keeper, address(ir), address(voter), address(infrared)
        );
        voter.initialize(address(sIR), infraredGovernance, keeper);
    }

    function isProxy(address proxy) internal view returns (bool) {
        (bool success, bytes memory data) =
            proxy.staticcall(abi.encodeWithSignature("implementation()"));
        return success && data.length > 0;
    }
}
