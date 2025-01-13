// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRewardVault} from "@berachain/pol/interfaces/IRewardVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

import {HarvestForkTest} from "./HarvestForkTest.t.sol";

contract HarvestVaultForkTest is HarvestForkTest {
/*
    function testHarvestVault(uint256 protocolFeeRate) public {
        vm.assume(protocolFeeRate < FEE_UNIT);

        // stake lp token in vault to prep to earn rewards
        lpToken.approve(address(lpVault), type(uint256).max);
        lpVault.stake(100 ether);

        vm.startPrank(admin);

        // set protocol fee rate
        infrared.updateProtocolFeeRate(address(ibgt), protocolFeeRate);
        assertEq(infrared.protocolFeeRates(address(ibgt)), protocolFeeRate);

        // move timestamp forward to accumulate berachain vault rewards
        vm.warp(block.timestamp + 1 days);

        IRewardVault lpRewardsVault = lpVault.rewardsVault();
        uint256 reward = lpRewardsVault.earned(address(lpVault));
        uint256 fees = (reward * protocolFeeRate) / FEE_UNIT;

        uint256 bgtBalanceInfraredBefore = bgt.balanceOf(address(infrared));
        uint256 ibgtTotalSupplyBefore = ibgt.totalSupply();
        uint256 ibgtBalanceVaultBefore = ibgt.balanceOf(address(lpVault));
        uint256 ibgtBalanceInfraredBefore = ibgt.balanceOf(address(infrared));
        uint256 protocolFeeAmount = infrared.protocolFeeAmounts(address(ibgt));

        infrared.harvestVault(address(lpToken));

        // check balances updated
        assertEq(
            bgt.balanceOf(address(infrared)), bgtBalanceInfraredBefore + reward
        );
        assertEq(ibgt.totalSupply(), ibgtTotalSupplyBefore + reward);
        assertEq(
            ibgt.balanceOf(address(lpVault)),
            ibgtBalanceVaultBefore + reward - fees
        );
        assertEq(
            ibgt.balanceOf(address(infrared)), ibgtBalanceInfraredBefore + fees
        );

        // check protocol fee amounts updated
        assertEq(
            infrared.protocolFeeAmounts(address(ibgt)), protocolFeeAmount + fees
        );

        // check reward notified in vault
        (, uint256 rewardDuration,, uint256 rewardRate, uint256 lastUpdateTime,)
        = IMultiRewards(address(lpVault)).rewardData(address(ibgt));
        assertEq(rewardRate, (reward - fees) / rewardDuration);
        assertEq(lastUpdateTime, block.timestamp);

        vm.stopPrank();
    }
    */
}
