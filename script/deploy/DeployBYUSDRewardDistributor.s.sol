// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {BYUSDRewardDistributor} from "src/periphery/BYUSDRewardDistributor.sol";

contract DeployBYUSDRewardDistributor is Script {
    uint256 constant INITIAL_DISTRIBUTION_INTERVAL = 12 hours;

    function run(
        address infraredGovernance,
        address infrared,
        address stakingAsset,
        address rewardsToken,
        address underlyingToken,
        address keeper
    ) external {
        vm.startBroadcast();
        // address _gov,
        // address _infrared,
        // address _stakingToken,
        // address _rewardsToken,
        // address _underlyingToken,
        // address _keeper,
        // uint256 _initialDistributionInterval
        new BYUSDRewardDistributor(
            infraredGovernance,
            infrared,
            stakingAsset,
            rewardsToken,
            underlyingToken,
            keeper,
            INITIAL_DISTRIBUTION_INTERVAL
        );
        vm.stopBroadcast();
    }
}
