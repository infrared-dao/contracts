// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {Infrared} from "src/core/Infrared.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {IBGT as IBerachainBGT} from "@berachain/pol/interfaces/IBGT.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

contract InfraredKeeperScript is BatchScript {
    // cArtio addresses
    Infrared infrared =
        Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    IBerachainBGT bgt =
        IBerachainBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    InfraredBERAWithdrawor iberaWithdrawer = InfraredBERAWithdrawor(
        payable(0x8c0E122960dc2E97dc0059c07d6901Dce72818E1)
    );
    InfraredBERAFeeReceivor rec = InfraredBERAFeeReceivor(
        payable(0xf6a4A6aCECd5311327AE3866624486b6179fEF97)
    );

    function harvest(address[] calldata _stakingTokens) external {
        vm.startBroadcast();

        // Harvest each vault
        for (uint256 i = 0; i < _stakingTokens.length; i++) {
            infrared.harvestVault(_stakingTokens[i]);
        }

        // Harvest base rewards
        infrared.harvestBase();

        // Second sweep to compound additional iBERA rewards
        rec.sweep();

        // Harvest operator rewards
        infrared.harvestOperatorRewards();

        // Harvest boost rewards
        infrared.harvestBoostRewards();

        vm.stopBroadcast();
    }

    function queueNewCuttingBoard(
        bytes calldata _pubkey,
        uint64 _startBlock,
        IBeraChef.Weight[] calldata _weights,
        address _safe
    ) external isBatch(_safe) {
        bytes memory data = abi.encodeWithSelector(
            infrared.queueNewCuttingBoard.selector,
            _pubkey,
            _startBlock,
            _weights
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function queueBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts,
        address _safe
    ) external isBatch(_safe) {
        bytes memory data = abi.encodeWithSelector(
            infrared.queueBoosts.selector, _pubkeys, _amts
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function cancelBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts,
        address _safe
    ) external isBatch(_safe) {
        bytes memory data = abi.encodeWithSelector(
            infrared.cancelBoosts.selector, _pubkeys, _amts
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function activateBoosts(bytes[] calldata _pubkeys, address _safe)
        external
        isBatch(_safe)
    {
        bytes memory data =
            abi.encodeWithSelector(infrared.activateBoosts.selector, _pubkeys);
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function activateAndBoost(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts,
        address _safe
    ) external isBatch(_safe) {
        // First add activateBoosts to batch
        bytes memory activateData =
            abi.encodeWithSelector(infrared.activateBoosts.selector, _pubkeys);
        addToBatch(address(infrared), 0, activateData);

        // Then add queueBoosts to batch
        bytes memory boostData = abi.encodeWithSelector(
            infrared.queueBoosts.selector, _pubkeys, _amts
        );
        addToBatch(address(infrared), 0, boostData);

        // Execute both transactions in the batch
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function queueDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts,
        address _safe
    ) external isBatch(_safe) {
        bytes memory data = abi.encodeWithSelector(
            infrared.queueDropBoosts.selector, _pubkeys, _amts
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function cancelDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts,
        address _safe
    ) external isBatch(_safe) {
        bytes memory data = abi.encodeWithSelector(
            infrared.cancelDropBoosts.selector, _pubkeys, _amts
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function dropBoosts(bytes[] calldata _pubkeys, address _safe)
        external
        isBatch(_safe)
    {
        bytes memory data =
            abi.encodeWithSelector(infrared.dropBoosts.selector, _pubkeys);
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function sweep(bytes calldata pubkey, address _safe)
        external
        isBatch(_safe)
    {
        bytes memory data =
            abi.encodeWithSelector(iberaWithdrawer.sweep.selector, pubkey);
        addToBatch(address(iberaWithdrawer), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
