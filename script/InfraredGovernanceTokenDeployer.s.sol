// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from
    "../src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/core/Infrared.sol";

contract InfraredGovernanceTokenDeployer is Script {
    InfraredBGT public ibgt;
    ERC20PresetMinterPauser public ir;

    Infrared public infrared;

    Voter public voter;
    VotingEscrow public sIR;

    function run(address _gov, address _keeper, address _infrared) external {
        vm.startBroadcast();

        infrared = Infrared(payable(_infrared));
        ibgt = infrared.ibgt();

        voter = Voter(setupProxy(address(new Voter(address(infrared)))));

        ir = new InfraredGovernanceToken(
            address(infrared), _gov, _gov, _gov, address(0)
        );

        // gov only (i.e. this needs to be run by gov)
        infrared.setIR(address(ir));
        infrared.setVoter(address(voter));

        sIR = new VotingEscrow(
            _keeper, address(ir), address(voter), address(infrared)
        );
        voter.initialize(address(sIR), _gov, _keeper);

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
