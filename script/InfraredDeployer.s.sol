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
import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";

import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdraworLite} from
    "src/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

contract InfraredDeployer is Script {
    InfraredBGT public ibgt;
    ERC20PresetMinterPauser public ir;

    InfraredBERA public ibera;
    InfraredBERADepositor public depositor;
    InfraredBERAWithdraworLite public withdrawor;
    InfraredBERAFeeReceivor public receivor;

    BribeCollector public collector;
    InfraredDistributor public distributor;
    Infrared public infrared;

    Voter public voter;
    VotingEscrow public sIR;

    function run(
        address _gov,
        address _keeper,
        address _bgt,
        address _berachainRewardsFactory,
        address _beraChef,
        address _beaconDeposit,
        address _wbera,
        address _honey,
        uint256 _rewardsDuration,
        uint256 _bribeCollectorPayoutAmount
    ) external {
        vm.startBroadcast();

        infrared = Infrared(payable(setupProxy(address(new Infrared()))));

        collector = BribeCollector(
            setupProxy(address(new BribeCollector(address(infrared))))
        );
        distributor = InfraredDistributor(
            setupProxy(address(new InfraredDistributor(address(infrared))))
        );

        // InfraredBERA
        ibera = InfraredBERA(setupProxy(address(new InfraredBERA())));

        depositor = InfraredBERADepositor(
            setupProxy(address(new InfraredBERADepositor()))
        );
        withdrawor = InfraredBERAWithdraworLite(
            payable(setupProxy(address(new InfraredBERAWithdraworLite())))
        );

        receivor = InfraredBERAFeeReceivor(
            payable(setupProxy(address(new InfraredBERAFeeReceivor())))
        );

        // initialize proxies
        collector.initialize(_gov, _wbera, _bribeCollectorPayoutAmount);
        distributor.initialize(_gov, address(ibera));

        voter = Voter(setupProxy(address(new Voter(address(infrared)))));

        Infrared.InitializationData memory data = Infrared.InitializationData(
            _gov,
            _keeper,
            _bgt,
            _berachainRewardsFactory,
            _beraChef,
            payable(_wbera),
            _honey,
            address(collector),
            address(distributor),
            address(voter),
            address(ibera),
            _rewardsDuration
        );
        infrared.initialize(data);

        ibgt = new InfraredBGT(data._gov, address(infrared), data._gov);

        ir = new InfraredGovernanceToken(
            address(infrared), data._gov, data._gov, data._gov
        );

        infrared.setIBGT(address(ibgt));
        infrared.setIR(address(ir));

        sIR = new VotingEscrow(
            _keeper, address(ir), address(voter), address(infrared)
        );
        voter.initialize(address(sIR), data._gov, data._keeper);

        // initialize ibera proxies
        depositor.initialize(_gov, _keeper, address(ibera), _beaconDeposit);
        withdrawor.initialize(_gov, _keeper, address(ibera));

        receivor.initialize(_gov, _keeper, address(ibera), address(infrared));

        // init deposit to avoid inflation attack
        uint256 _value = InfraredBERAConstants.MINIMUM_DEPOSIT;
        ibera.initialize{value: _value}(
            _gov,
            _keeper,
            address(infrared),
            address(depositor),
            address(withdrawor),
            address(receivor)
        );

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
