// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {Infrared} from "src/core/Infrared.sol";
import {IBGT as IBerachainBGT} from "@berachain/pol/interfaces/IBGT.sol";

contract InfraredKeeperScript is Script {
    address[] stakingAssets = [
        0x1306D3c36eC7E38dd2c128fBe3097C2C2449af64,
        0x1339503343be5626B40Ee3Aee12a4DF50Aa4C0B9,
        0xd28d852cbcc68DCEC922f6d5C7a8185dBaa104B7
    ];

    address[] rewardTokens = [
        0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03,
        0x7507c1dc16935B82698e4C63f2746A2fCf994dF8,
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    ];

    function run() external {
        vm.startBroadcast();

        Infrared infrared =
            Infrared(payable(0xe41779952f5485db5440452DFa43350556AA4673));
        IBerachainBGT bgt =
            IBerachainBGT(0xbDa130737BDd9618301681329bF2e46A016ff9Ad);

        // infrared.grantRole(keccak256("KEEPER_ROLE"), 0xF5d5F236DA47553e2fDcC88d5C37dfAd8d96a268);
        // infrared.grantRole(keccak256("GOVERNANCE_ROLE"), 0xF5d5F236DA47553e2fDcC88d5C37dfAd8d96a268);

        // require(
        //     infrared.hasRole(keccak256("KEEPER_ROLE"), 0xF5d5F236DA47553e2fDcC88d5C37dfAd8d96a268) &&
        //     infrared.hasRole(keccak256("GOVERNANCE_ROLE"), 0xF5d5F236DA47553e2fDcC88d5C37dfAd8d96a268),
        //     "roles not set"
        // );

        // loop over infrared vaults and call harvestVault on infrared wiht address
        for (uint256 i = 0; i < stakingAssets.length; i++) {
            infrared.harvestVault(stakingAssets[i]);
        }

        // checl unallocated bgt balance and queue boosts
        // TODO: fix
        bytes[] memory validators = new bytes[](1);
        // validators[0] = 0x2D764DFeaAc00390c69985631aAA7Cc3fcfaFAfF;

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = uint128(bgt.balanceOf(address(infrared)))
            - bgt.queuedBoost(address(infrared)) - bgt.boosts(address(infrared));

        infrared.queueBoosts(validators, amounts);

        infrared.harvestBoostRewards();
        // infrared.harvestBase();

        // Infrared(0xe41779952f5485db5440452DFa43350556AA4673).harvestBribes(rewardTokens);

        vm.stopBroadcast();
    }
}
