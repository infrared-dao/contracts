// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {Infrared} from "src/core/Infrared.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {IBGT as IBerachainBGT} from "@berachain/pol/interfaces/IBGT.sol";

contract InfraredKeeperScript is Script {
    // cArtio addresses
    Infrared infrared =
        Infrared(payable(0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219));
    IBerachainBGT bgt =
        IBerachainBGT(0x289274787bAF083C15A45a174b7a8e44F0720660);
    InfraredBERAWithdrawor iberaWithdrawer = InfraredBERAWithdrawor(
        payable(0xb4fe1c9a7068586f377eCaD40632347be2372E6C)
    );
    InfraredBERAFeeReceivor rec = InfraredBERAFeeReceivor(
        payable(0x7bbe85eC33EdBD1F875C887b44d9dAa28a8141B6)
    );

    address[] stakingAssets = [0x7D6e08fe0d56A7e8f9762E9e65daaC491A0B475b];

    address[] rewardTokens = [
        0x5bDc3CAE6fB270ef07579c428bb630E73C8d623b,
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    ];

    bytes[] pubkeys;

    function setUp() public {
        pubkeys.push(
            hex"ad8af2d381461965e08126e48bc95646c2ca74867255381397dc70e711bab07015551a8904c167459f5e6da4db436300"
        );
    }

    function harvest() external {
        vm.startBroadcast();

        // iBERA rewards compound
        rec.sweep();

        // loop over infrared vaults and call harvestVault on infrared with address
        for (uint256 i = 0; i < stakingAssets.length; i++) {
            infrared.harvestVault(stakingAssets[i]);
        }

        infrared.harvestBase();

        // iBERA rewards compound
        rec.sweep();

        infrared.harvestOperatorRewards();
        // infrared.harvestBribes(rewardTokens);

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = uint128(bgt.balanceOf(address(infrared)))
            - bgt.queuedBoost(address(infrared)) - bgt.boosts(address(infrared));

        if (amounts[0] > uint128(0)) {
            infrared.queueBoosts(pubkeys, amounts);
        }

        infrared.harvestBoostRewards();

        vm.stopBroadcast();
    }

    function queueNewCuttingBoard(
        bytes calldata _pubkey,
        uint64 _startBlock,
        IBeraChef.Weight[] calldata _weights
    ) external {
        infrared.queueNewCuttingBoard(_pubkey, _startBlock, _weights);
    }

    function queueBoosts(bytes[] calldata _pubkeys, uint128[] calldata _amts)
        external
    {
        infrared.queueBoosts(_pubkeys, _amts);
    }

    function cancelBoosts(bytes[] calldata _pubkeys, uint128[] calldata _amts)
        external
    {
        infrared.cancelBoosts(_pubkeys, _amts);
    }

    function activateBoosts(bytes[] calldata _pubkeys) external {
        infrared.activateBoosts(_pubkeys);
    }

    function queueDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts
    ) external {
        infrared.queueDropBoosts(_pubkeys, _amts);
    }

    function cancelDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts
    ) external {
        infrared.cancelDropBoosts(_pubkeys, _amts);
    }

    function dropBoosts(bytes[] calldata _pubkeys) external {
        infrared.dropBoosts(_pubkeys);
    }

    function sweep(bytes calldata pubkey) external {
        iberaWithdrawer.sweep(pubkey);
    }
}
