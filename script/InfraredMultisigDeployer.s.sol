// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from
    "../src/vendors/ERC20PresetMinterPauser.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

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
import {InfraredBERAWithdraworLite} from
    "src/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

contract InfraredDeployer is BatchScript {
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
    ) external isBatch(_gov) {
        // Start with nonce tracking for address computation
        uint256 nonce = vm.getNonce(_gov);

        // infrared = Infrared(payable(setupProxy(address(new Infrared()))));

        // Step 1: Deploy `Infrared` implementation
        address infraredImpl = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, type(Infrared).creationCode); // Empty `to`, deployment bytecode in `data`

        // Step 2: Deploy `ERC1967Proxy` linked to `Infrared`
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(infraredImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyInfrared = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // collector = BribeCollector(
        //     setupProxy(address(new BribeCollector(address(infrared))))
        // );

        // Batch deploy `BribeCollector`
        bytes memory collectorBytecode = abi.encodePacked(
            type(BribeCollector).creationCode, abi.encode(proxyInfrared)
        );
        addToBatch(address(0), 0, collectorBytecode);
        address collectorImpl = computeCreateAddress(_gov, nonce++);

        // Deploy `BribeCollector` and set up proxy
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(collectorImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyCollector = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // distributor = InfraredDistributor(
        //     setupProxy(address(new InfraredDistributor(address(infrared))))
        // );

        // Batch deploy `Distributor`
        bytes memory distributorBytecode = abi.encodePacked(
            type(InfraredDistributor).creationCode, abi.encode(proxyInfrared)
        );
        addToBatch(address(0), 0, distributorBytecode);
        address distributorImpl = computeCreateAddress(_gov, nonce++);

        // Deploy `BribeCollector` and set up proxy
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(distributorImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyDistributor = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // // InfraredBERA
        // ibera = InfraredBERA(setupProxy(address(new InfraredBERA())));

        // Deploy `InfraredBERA` implementation
        address iberaImpl = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, type(InfraredBERA).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERA`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(iberaImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyIbera = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // depositor = InfraredBERADepositor(
        //     setupProxy(address(new InfraredBERADepositor()))
        // );

        // Deploy `InfraredBERADepositor` implementation
        address depositorImpl = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, type(InfraredBERADepositor).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERADepositor`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(depositorImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyIberaDepositor = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // withdrawor = InfraredBERAWithdraworLite(
        //     payable(setupProxy(address(new InfraredBERAWithdraworLite())))
        // );

        // Deploy `InfraredBERAWithdraworLite` implementation
        address withdraworImpl = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, type(InfraredBERAWithdraworLite).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERAWithdraworLite`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(withdraworImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyIberaWithdrawor = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // receivor = InfraredBERAFeeReceivor(
        //     payable(setupProxy(address(new InfraredBERAFeeReceivor())))
        // );

        // Deploy `InfraredBERAFeeReceivor` implementation
        address receivorImpl = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, type(InfraredBERAFeeReceivor).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERAFeeReceivor`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(receivorImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyIberaReceivor = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        // initialize proxies
        // collector.initialize(_gov, _wbera, _bribeCollectorPayoutAmount);

        bytes memory initializeData = abi.encodeWithSelector(
            BribeCollector.initialize.selector,
            _gov,
            _wbera,
            _bribeCollectorPayoutAmount
        );
        addToBatch(proxyCollector, 0, initializeData);

        // distributor.initialize(_gov, address(ibera));

        initializeData = abi.encodeWithSelector(
            InfraredDistributor.initialize.selector, _gov, proxyIbera
        );
        addToBatch(proxyDistributor, 0, initializeData);

        // voter = Voter(setupProxy(address(new Voter(address(infrared)))));

        // Deploy Voter
        bytes memory voterBytecode = abi.encodePacked(
            type(Voter).creationCode, abi.encode(proxyInfrared)
        );
        addToBatch(address(0), 0, voterBytecode);
        address voterImpl = computeCreateAddress(_gov, nonce++);

        // Deploy `ERC1967Proxy` linked to `Voter`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(voterImpl, "") // Constructor args: implementation and optional init data
        );
        address proxyVoter = computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`

        Infrared.InitializationData memory data = Infrared.InitializationData(
            _gov,
            _keeper,
            _bgt,
            _berachainRewardsFactory,
            _beraChef,
            payable(_wbera),
            _honey,
            proxyCollector,
            proxyDistributor,
            proxyVoter,
            proxyIbera,
            _rewardsDuration
        );

        // infrared.initialize(data);

        addToBatch(
            proxyInfrared,
            0,
            abi.encodeWithSelector(Infrared.initialize.selector, data)
        );

        // ibgt = new InfraredBGT(
        //     address(_bgt), data._gov, address(infrared), data._gov
        // );

        // Batch deploy `InfraredBGT`
        bytes memory ibgtBytecode = abi.encodePacked(
            type(InfraredBGT).creationCode,
            abi.encode(address(_bgt), _gov, proxyInfrared, _gov)
        );
        addToBatch(address(0), 0, ibgtBytecode);
        address ibgt = computeCreateAddress(_gov, nonce++);

        // red = new RED(
        //     address(ibgt), address(infrared), data._gov, data._gov, data._gov
        // );

        // Batch deploy `RED`
        bytes memory redBytecode = abi.encodePacked(
            type(InfraredBGT).creationCode,
            abi.encode(ibgt, proxyInfrared, _gov, _gov, _gov)
        );
        addToBatch(address(0), 0, redBytecode);
        address red = computeCreateAddress(_gov, nonce++);

        // infrared.setIBGT(address(ibgt));
        addToBatch(
            proxyInfrared,
            0,
            abi.encodeWithSelector(Infrared.setIBGT.selector, ibgt)
        );

        // infrared.setRed(address(red));
        addToBatch(
            proxyInfrared,
            0,
            abi.encodeWithSelector(Infrared.setRed.selector, red)
        );

        // veIRED = new VotingEscrow(
        //     _keeper, address(red), address(voter), address(infrared)
        // );

        // Deploy VotingEscrow
        bytes memory veIREDBytecode = abi.encodePacked(
            type(VotingEscrow).creationCode,
            abi.encode(_keeper, red, proxyVoter, proxyInfrared)
        );
        addToBatch(address(0), 0, veIREDBytecode);
        address veIRED = computeCreateAddress(_gov, nonce++);

        // voter.initialize(address(veIRED), data._gov, data._keeper);

        addToBatch(
            proxyVoter,
            0,
            abi.encodeWithSelector(
                Voter.initialize.selector, veIRED, _gov, _keeper
            )
        );

        // // initialize ibera proxies
        // depositor.initialize(_gov, _keeper, address(ibera), _beaconDeposit);

        addToBatch(
            proxyIberaDepositor,
            0,
            abi.encodeWithSelector(
                InfraredBERADepositor.initialize.selector,
                _gov,
                _keeper,
                proxyIbera,
                _beaconDeposit
            )
        );

        // withdrawor.initialize(_gov, _keeper, address(ibera));

        addToBatch(
            proxyIberaWithdrawor,
            0,
            abi.encodeWithSelector(
                InfraredBERAWithdraworLite.initialize.selector,
                _gov,
                _keeper,
                proxyIbera
            )
        );

        // receivor.initialize(_gov, _keeper, address(ibera), address(infrared));

        addToBatch(
            proxyIberaReceivor,
            0,
            abi.encodeWithSelector(
                InfraredBERAFeeReceivor.initialize.selector,
                _gov,
                _keeper,
                proxyIbera,
                proxyInfrared
            )
        );

        // init deposit to avoid inflation attack
        uint256 _value = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;

        // ibera.initialize{value: _value}(
        //     _gov,
        //     _keeper,
        //     address(infrared),
        //     address(depositor),
        //     address(withdrawor),
        //     address(receivor)
        // );

        addToBatch(
            proxyIbera,
            _value,
            abi.encodeWithSelector(
                InfraredBERA.initialize.selector,
                _gov,
                _keeper,
                proxyInfrared,
                proxyIberaDepositor,
                proxyIberaWithdrawor,
                proxyIberaReceivor
            )
        );

        // Execute the batch
        vm.startBroadcast();
        executeBatch(true); // Execute all at once
        vm.stopBroadcast();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
