// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from
    "../src/vendors/ERC20PresetMinterPauser.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

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

contract InfraredMultisigDeployer is BatchScript {
    uint256 nonce;
    address proxyInfrared;
    address proxyCollector;
    address proxyDistributor;
    address proxyIberaDepositor;
    address proxyIbera;
    address proxyIberaWithdrawor;
    address proxyIberaReceivor;
    address proxyVoter;
    address ibgt;
    address red;
    address veIRED;
    bytes proxyBytecode;
    bytes initializeData;
    Infrared.InitializationData data;

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
        nonce = vm.getNonce(_gov);

        // deploy contracts and proxies
        deployInfrared(_gov);
        deployBribeCollector(_gov, _wbera, _bribeCollectorPayoutAmount);
        deployDistributor(_gov);
        deployInfraredBera(_gov, _wbera);
        deployInfraredBeraDepositor(_gov);
        deployInfraredBeraWithdrawor(_gov);
        deployInfraredBeraReceivor(_gov);
        deployVoter(_gov);

        // initialize proxies
        initializeCollector(_gov, _wbera, _bribeCollectorPayoutAmount);
        initializeDistributor(_gov);
        initializeInfrared(
            _gov,
            _keeper,
            _bgt,
            _berachainRewardsFactory,
            _beraChef,
            _wbera,
            _honey,
            _rewardsDuration
        );

        // deploy tokens
        deployIbgt(_gov, _bgt);
        deployRed(_gov);

        // set tokens

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
            abi.encodeWithSelector(Infrared.setIR.selector, red)
        );

        deployVeIred(_gov, _keeper);

        initializeVoter(_gov, _keeper);

        // initialize ibera proxies
        initializeIberaDepositor(_gov, _keeper, _beaconDeposit);
        initializeIberaWithdrawor(_gov, _keeper);
        initializeIberaReceivor(_gov, _keeper);
        initializeIbera(_gov, _keeper);

        // Execute the batch
        vm.startBroadcast();
        executeBatch(true); // Execute all at once
        vm.stopBroadcast();
    }

    function deployInfrared(address _gov) internal {
        // infrared = Infrared(payable(setupProxy(address(new Infrared()))));

        // Step 1: Deploy `Infrared` implementation
        addToBatch(address(0), 0, type(Infrared).creationCode); // Empty `to`, deployment bytecode in `data`

        // Step 2: Deploy `ERC1967Proxy` linked to `Infrared`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyInfrared = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployBribeCollector(
        address _gov,
        address _wbera,
        uint256 _bribeCollectorPayoutAmount
    ) internal {
        // collector = BribeCollector(
        //     setupProxy(address(new BribeCollector(address(infrared))))
        // );

        // Batch deploy `BribeCollector`
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(BribeCollector).creationCode, abi.encode(proxyInfrared)
            )
        );

        // Deploy `BribeCollector` and set up proxy
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyCollector = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployDistributor(address _gov) internal {
        // distributor = InfraredDistributor(
        //     setupProxy(address(new InfraredDistributor(address(infrared))))
        // );

        // Batch deploy `Distributor`
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(InfraredDistributor).creationCode,
                abi.encode(proxyInfrared)
            )
        );

        // Deploy `BribeCollector` and set up proxy
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyDistributor = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployInfraredBera(address _gov, address _wbera) internal {
        // InfraredBERA
        // ibera = InfraredBERA(setupProxy(address(new InfraredBERA())));

        // Deploy `InfraredBERA` implementation
        addToBatch(address(0), 0, type(InfraredBERA).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERA`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyIbera = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployInfraredBeraDepositor(address _gov) internal {
        // depositor = InfraredBERADepositor(
        //     setupProxy(address(new InfraredBERADepositor()))
        // );

        // Deploy `InfraredBERADepositor` implementation
        addToBatch(address(0), 0, type(InfraredBERADepositor).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERADepositor`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyIberaDepositor = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployInfraredBeraWithdrawor(address _gov) internal {
        // withdrawor = InfraredBERAWithdraworLite(
        //     payable(setupProxy(address(new InfraredBERAWithdraworLite())))
        // );

        // Deploy `InfraredBERAWithdraworLite` implementation
        addToBatch(address(0), 0, type(InfraredBERAWithdraworLite).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERAWithdraworLite`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyIberaWithdrawor = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployInfraredBeraReceivor(address _gov) internal {
        // receivor = InfraredBERAFeeReceivor(
        //     payable(setupProxy(address(new InfraredBERAFeeReceivor())))
        // );

        // Deploy `InfraredBERAFeeReceivor` implementation
        addToBatch(address(0), 0, type(InfraredBERAFeeReceivor).creationCode); // Empty `to`, deployment bytecode in `data`

        // Deploy `ERC1967Proxy` linked to `InfraredBERAFeeReceivor`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyIberaReceivor = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function deployVoter(address _gov) internal {
        // voter = Voter(setupProxy(address(new Voter(address(infrared)))));

        // Deploy Voter
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(Voter).creationCode, abi.encode(proxyInfrared)
            )
        );

        // Deploy `ERC1967Proxy` linked to `Voter`
        proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(vm.computeCreateAddress(_gov, nonce++), "") // Constructor args: implementation and optional init data
        );
        proxyVoter = vm.computeCreateAddress(_gov, nonce++);
        addToBatch(address(0), 0, proxyBytecode); // Empty `to`, deployment bytecode in `data`
    }

    function initializeCollector(
        address _gov,
        address _wbera,
        uint256 _bribeCollectorPayoutAmount
    ) internal {
        // collector.initialize(_gov, _wbera, _bribeCollectorPayoutAmount);

        initializeData = abi.encodeWithSelector(
            BribeCollector.initialize.selector,
            _gov,
            _wbera,
            _bribeCollectorPayoutAmount
        );
        addToBatch(proxyCollector, 0, initializeData);
    }

    function initializeDistributor(address _gov) internal {
        // distributor.initialize(_gov, address(ibera));

        initializeData = abi.encodeWithSelector(
            InfraredDistributor.initialize.selector, _gov, proxyIbera
        );
        addToBatch(proxyDistributor, 0, initializeData);
    }

    function initializeInfrared(
        address _gov,
        address _keeper,
        address _bgt,
        address _berachainRewardsFactory,
        address _beraChef,
        address _wbera,
        address _honey,
        uint256 _rewardsDuration
    ) internal {
        data = Infrared.InitializationData(
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
    }

    function deployIbgt(address _gov, address _bgt) internal {
        // ibgt = new InfraredBGT(
        //     address(_bgt), data._gov, address(infrared), data._gov
        // );

        // Batch deploy `InfraredBGT`
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(InfraredBGT).creationCode,
                abi.encode(_bgt, _gov, proxyInfrared, _gov)
            )
        );
        ibgt = vm.computeCreateAddress(_gov, nonce++);
    }

    function deployRed(address _gov) internal {
        // red = new RED(
        //     address(ibgt), address(infrared), data._gov, data._gov, data._gov
        // );

        // Batch deploy `RED`
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(InfraredBGT).creationCode,
                abi.encode(ibgt, proxyInfrared, _gov, _gov, _gov)
            )
        );
        red = vm.computeCreateAddress(_gov, nonce++);
    }

    function deployVeIred(address _gov, address _keeper) internal {
        // veIRED = new VotingEscrow(
        //     _keeper, address(red), address(voter), address(infrared)
        // );

        // Deploy VotingEscrow
        addToBatch(
            address(0),
            0,
            abi.encodePacked(
                type(VotingEscrow).creationCode,
                abi.encode(_keeper, red, proxyVoter, proxyInfrared)
            )
        );
        veIRED = vm.computeCreateAddress(_gov, nonce++);
    }

    function initializeVoter(address _gov, address _keeper) internal {
        // voter.initialize(address(veIRED), data._gov, data._keeper);

        addToBatch(
            proxyVoter,
            0,
            abi.encodeWithSelector(
                Voter.initialize.selector, veIRED, _gov, _keeper
            )
        );
    }

    function initializeIberaDepositor(
        address _gov,
        address _keeper,
        address _beaconDeposit
    ) internal {
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
    }

    function initializeIberaWithdrawor(address _gov, address _keeper)
        internal
    {
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
    }

    function initializeIberaReceivor(address _gov, address _keeper) internal {
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
    }

    function initializeIbera(address _gov, address _keeper) internal {
        // init deposit to avoid inflation attack
        // uint256 _value = InfraredBERAConstants.MINIMUM_DEPOSIT
        //     + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;

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
            InfraredBERAConstants.MINIMUM_DEPOSIT
                + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE,
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
    }
}
