// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {Infrared} from "src/core/Infrared.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
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
    IInfraredBGT ibgt = IInfraredBGT(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    InfraredBERAWithdrawor iberaWithdrawer = InfraredBERAWithdrawor(
        payable(0x8c0E122960dc2E97dc0059c07d6901Dce72818E1)
    );
    InfraredBERAFeeReceivor rec = InfraredBERAFeeReceivor(
        payable(0xf6a4A6aCECd5311327AE3866624486b6179fEF97)
    );
    InfraredBERADepositor depositor = InfraredBERADepositor(
        payable(0x04CddC538ea65908106416986aDaeCeFD4CAB7D7)
    );

    function harvest(address[] calldata _stakingTokens) external {
        vm.startBroadcast();

        // Harvest each vault
        for (uint256 i = 0; i < _stakingTokens.length; i++) {
            address _stakingToken = _stakingTokens[i];
            IInfraredVault _vault = infrared.vaultRegistry(_stakingToken);
            if (_vault.totalSupply() > 1) {
                infrared.harvestVault(_stakingToken);
            }
        }

        // Harvest base rewards
        infrared.harvestBase();

        (uint256 amount,) = rec.distribution();
        if (amount > 0) {
            // Harvest operator rewards
            infrared.harvestOperatorRewards();
        }

        // Harvest boost rewards
        infrared.harvestBoostRewards();

        vm.stopBroadcast();
    }

    function harvestOldVault(address safe, address _vault, address _asset)
        external
        isBatch(safe)
    {
        bytes memory data = abi.encodeWithSignature(
            "harvestOldVault(address,address)", _vault, _asset
        );
        addToBatch(address(infrared), 0, data);
        vm.startBroadcast();
        executeBatch(true);
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

    function activateAndMaxBoost(bytes[] calldata _pubkeys, address _safe)
        external
        isBatch(_safe)
    {
        // First add activateBoosts to batch
        bytes memory activateData =
            abi.encodeWithSelector(infrared.activateBoosts.selector, _pubkeys);
        addToBatch(address(infrared), 0, activateData);

        uint256 maxBoost = ibgt.totalSupply()
            - (bgt.boosts(address(infrared)) + bgt.queuedBoost(address(infrared)));

        uint256 len = _pubkeys.length;
        uint256[] memory amts = new uint256[](len);
        for (uint256 i; i < len; i++) {
            amts[i] = maxBoost / len;
        }

        // Then add queueBoosts to batch
        bytes memory boostData = abi.encodeWithSelector(
            infrared.queueBoosts.selector, _pubkeys, amts
        );
        addToBatch(address(infrared), 0, boostData);

        // Execute both transactions in the batch
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function activateAndMaxBoost(bytes[] calldata _pubkeys) external {
        vm.startBroadcast();
        infrared.activateBoosts(_pubkeys);

        uint256 maxBoost = ibgt.totalSupply()
            - (bgt.boosts(address(infrared)) + bgt.queuedBoost(address(infrared)));

        uint256 len = _pubkeys.length;
        uint128[] memory amts = new uint128[](len);
        for (uint256 i; i < len; i++) {
            amts[i] = uint128(maxBoost / len);
        }

        infrared.queueBoosts(_pubkeys, amts);

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

    function depositValidator(
        bytes calldata pubkey,
        uint256 amount,
        address _safe
    ) external isBatch(_safe) {
        // function execute(bytes calldata pubkey, uint256 amount) external;
        bytes memory data =
            abi.encodeWithSelector(depositor.execute.selector, pubkey, amount);
        addToBatch(address(depositor), 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
