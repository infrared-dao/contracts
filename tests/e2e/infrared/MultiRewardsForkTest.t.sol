// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import "../InfraredForkTest.t.sol";

contract MultiRewardsForkTest is InfraredForkTest {
    address alice = address(12);

    function setUp() public virtual override {
        super.setUp();

        deal(address(stakingToken), alice, 1e18);
        deal(address(honey), alice, 1e20);
        deal(address(weth), alice, 1e20);
        deal(address(usdc), alice, 1e20);

        // Set up users
        vm.startPrank(alice);
        honey.approve(address(infrared), type(uint256).max);
        weth.approve(address(infrared), type(uint256).max);
        usdc.approve(address(infrared), type(uint256).max);

        vm.stopPrank();
    }

    function testMultipleRewardEarnings() public {
        vm.startPrank(infraredGovernance);
        infrared.addReward(address(stakingToken), address(honey), 3600);
        infrared.updateWhiteListedRewardTokens(address(weth), true);
        infrared.addReward(address(stakingToken), address(weth), 3600);
        infrared.updateWhiteListedRewardTokens(address(usdc), true);
        infrared.addReward(address(stakingToken), address(usdc), 3600);
        vm.stopPrank();

        vm.startPrank(alice);
        infrared.addIncentives(address(stakingToken), address(honey), 1e20);
        infrared.addIncentives(address(stakingToken), address(weth), 1e20);
        infrared.addIncentives(address(stakingToken), address(usdc), 1e20);
        vm.stopPrank();

        stakeAndApprove(alice, 1e18);

        // Check total supply
        assertGt(lpVault.totalSupply(), 1e18);

        // Simulate time passage
        skip(60);

        // Verify reward per token for rewardToken
        uint256 rewardPerToken = lpVault.rewardPerToken(address(honey));
        assertGt(rewardPerToken, 0);

        // Verify earnings for Bob
        uint256 earningsAlice = lpVault.earned(alice, address(honey));
        assertGt(earningsAlice, 0);

        vm.prank(alice);
        lpVault.getReward();

        assertGt(honey.balanceOf(alice), 0);
        assertGt(weth.balanceOf(alice), 0);
        assertGt(usdc.balanceOf(alice), 0);
    }

    function stakeAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        stakingToken.approve(address(lpVault), amount);
        lpVault.stake(amount);
        vm.stopPrank();
    }
}
