// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from
    "../src/vendors/ERC20PresetMinterPauser.sol";

import {RED} from "src/core/RED.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/core/Infrared.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";

import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

contract InfraredDeployer is Script {
    InfraredBGT public ibgt;
    ERC20PresetMinterPauser public red;

    InfraredBERA public ibera;
    InfraredBERADepositor public depositor;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAClaimor public claimor;
    InfraredBERAFeeReceivor public receivor;

    BribeCollector public collector;
    InfraredDistributor public distributor;
    Infrared public infrared;

    Voter public voter;
    VotingEscrow public veIRED;

    function run(
        address _admin,
        address _votingKeeper,
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

        ibgt = new InfraredBGT(_bgt);

        infrared = Infrared(
            payable(
                setupProxy(
                    address(
                        new Infrared(
                            address(ibgt),
                            _berachainRewardsFactory,
                            _beraChef,
                            payable(_wbera),
                            _honey
                        )
                    )
                )
            )
        );
        collector = BribeCollector(
            setupProxy(address(new BribeCollector(address(infrared))))
        );
        distributor = InfraredDistributor(
            setupProxy(address(new InfraredDistributor(address(infrared))))
        );

        // IRED voting
        red = new RED(address(ibgt), address(infrared));
        voter = Voter(setupProxy(address(new Voter(address(infrared)))));
        veIRED = new VotingEscrow(
            _votingKeeper, address(red), address(voter), address(infrared)
        );

        // InfraredBERA
        ibera = InfraredBERA(setupProxy(address(new InfraredBERA())));

        depositor = InfraredBERADepositor(
            setupProxy(address(new InfraredBERADepositor()))
        );
        withdrawor = InfraredBERAWithdrawor(
            payable(setupProxy(address(new InfraredBERAWithdrawor())))
        );
        claimor =
            InfraredBERAClaimor(setupProxy(address(new InfraredBERAClaimor())));
        receivor = InfraredBERAFeeReceivor(
            payable(setupProxy(address(new InfraredBERAFeeReceivor())))
        );

        // initialize proxies
        collector.initialize(_admin, _wbera, _bribeCollectorPayoutAmount);
        distributor.initialize(address(ibera));
        infrared.initialize(
            _admin,
            address(collector),
            address(distributor),
            address(voter),
            address(ibera),
            _rewardsDuration
        );
        voter.initialize(address(veIRED));

        // initialize ibera proxies
        depositor.initialize(_admin, address(ibera), _beaconDeposit);
        withdrawor.initialize(_admin, address(ibera));
        claimor.initialize(_admin);
        receivor.initialize(_admin, address(ibera), address(infrared));

        // init deposit to avoid inflation attack
        uint256 _value = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;

        ibera.initialize{value: _value}(
            _admin,
            address(infrared),
            address(depositor),
            address(withdrawor),
            address(claimor),
            address(receivor)
        );

        // grant infrared ibgt minter role
        ibgt.grantRole(ibgt.MINTER_ROLE(), address(infrared));

        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
