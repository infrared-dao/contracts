// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {BeraChef} from "@berachain/pol/rewards/BeraChef.sol";
import {BribeCollectorV1_2} from "src/core/upgrades/BribeCollectorV1_2.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {InfraredV1_3 as Infrared} from "src/core/upgrades/InfraredV1_3.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from
    "src/staking/upgrades/InfraredBERAWithdrawor.sol";
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
    BeraChef chef = BeraChef(0xdf960E8F3F19C481dDE769edEDD439ea1a63426a);
    BribeCollectorV1_2 collector =
        BribeCollectorV1_2(0x8d44170e120B80a7E898bFba8cb26B01ad21298C);

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

    function harvestBribes(address[] calldata _incentiveTokens) external {
        vm.startBroadcast();

        // Harvest base rewards
        infrared.harvestBribes(_incentiveTokens);

        vm.stopBroadcast();
    }

    function claimIncentives(
        address recipient,
        address[] calldata _incentiveTokens,
        uint256[] calldata _amounts
    ) external {
        vm.startBroadcast();

        // Harvest base rewards
        collector.claimFees(recipient, _incentiveTokens, _amounts);

        vm.stopBroadcast();
    }

    function sweepPayoutToken() external {
        vm.startBroadcast();

        // Harvest base rewards
        collector.sweepPayoutToken();

        vm.stopBroadcast();
    }

    function activateValCommissions(bytes[] calldata _pubkeys) external {
        vm.startBroadcast();
        uint256 len = _pubkeys.length;
        for (uint256 i; i < len; i++) {
            bytes memory _pubkey = _pubkeys[i];
            // check if queue to activate
            IBeraChef.QueuedCommissionRateChange memory qcr =
                chef.getValQueuedCommissionOnIncentiveTokens(_pubkey);
            (uint32 blockNumberLast, uint96 commissionRate) =
                (qcr.blockNumberLast, qcr.commissionRate);
            uint32 activationBlock =
                uint32(blockNumberLast + chef.commissionChangeDelay());
            if (blockNumberLast == 0 || block.number < activationBlock) {
                continue;
            }
            // check commission is 100%
            if (commissionRate != 10000) {
                continue;
            }
            // activate queued commission rate
            infrared.activateQueuedValCommission(_pubkey);
        }
        vm.stopBroadcast();
    }

    function activateQueuedCuttingBoard(bytes[] calldata _pubkeys) external {
        vm.startBroadcast();
        uint256 len = _pubkeys.length;
        for (uint256 i; i < len; i++) {
            bytes memory _pubkey = _pubkeys[i];
            // check if queue to activate
            if (!chef.isQueuedRewardAllocationReady(_pubkey, block.number)) {
                continue;
            }

            // activate queued cutting board
            infrared.activateQueuedValCommission(_pubkey);
        }
        vm.stopBroadcast();
    }

    function harvestOldVaults(
        address safe,
        address[] calldata _vaults,
        address[] calldata _assets
    ) external isBatch(safe) {
        uint256 len = _vaults.length;
        if (_assets.length != len) revert();
        for (uint256 i; i < len; i++) {
            bytes memory data = abi.encodeWithSignature(
                "harvestOldVault(address,address)", _vaults[i], _assets[i]
            );
            addToBatch(address(infrared), 0, data);
        }

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

    // function sweep(bytes calldata pubkey, address _safe)
    //     external
    //     isBatch(_safe)
    // {
    //     bytes memory data =
    //         abi.encodeWithSelector(iberaWithdrawer.sweep.selector, pubkey);
    //     addToBatch(address(iberaWithdrawer), 0, data);
    //     vm.startBroadcast();
    //     executeBatch(true);
    //     vm.stopBroadcast();
    // }

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
