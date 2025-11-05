// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {RewardDistributor} from "src/periphery/RewardDistributor.sol";

contract DeployRewardDistributor is Script {
    uint256 constant INITIAL_TARGET_APR = 700; // 7%
    uint256 constant INITIAL_DISTRIBUTION_INTERVAL = 12 hours;

    function run(
        address infraredGovernance,
        address infrared,
        address stakingAsset,
        address rewardsToken,
        address keeper
    ) external {
        vm.startBroadcast();
        new RewardDistributor(
            infraredGovernance,
            infrared,
            stakingAsset,
            rewardsToken,
            keeper,
            INITIAL_TARGET_APR,
            INITIAL_DISTRIBUTION_INTERVAL
        );
        vm.stopBroadcast();
    }
}
