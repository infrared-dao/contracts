// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {HarvestForkTest} from "./HarvestForkTest.t.sol";

contract HarvestBaseForkTest is HarvestForkTest {
    function testHarvestBase() public {
        uint256 protocolFeeRate = FEE_UNIT / 2;
        vm.startPrank(infraredGovernance);

        // set protocol fee rate
        infrared.updateFee(
            ConfigTypes.FeeType.HarvestOperatorFeeRate, protocolFeeRate
        );
        assertEq(infrared.fees(0), protocolFeeRate);

        // IInfraredVault wiberaVault = infrared.ibgtVault();

        // uint256 ibgtTotalSupply = ibgt.totalSupply();
        // uint256 ibgtBalanceVault = ibgt.balanceOf(address(wiberaVault));
        // uint256 ibgtBalanceInfrared = ibgt.balanceOf(address(infrared));
        // uint256 bgtBalance = bgt.balanceOf(address(infrared));
        // uint256 protocolFeeAmount = infrared.protocolFeeAmounts(address(ibgt));

        // assertTrue(ibgtTotalSupply == 0);
        // assertTrue(bgtBalance > 0);

        // uint256 amount = bgtBalance - ibgtTotalSupply;
        // uint256 fees = (amount * protocolFeeRate) / FEE_UNIT;

        // infrared.harvestBase();

        // // check balances
        // assertEq(bgt.balanceOf(address(infrared)), bgtBalance);
        // assertEq(ibgt.totalSupply(), ibgtTotalSupply + amount);
        // assertEq(
        //     ibgt.balanceOf(address(wiberaVault)),
        //     ibgtBalanceVault + amount - fees
        // );
        // assertEq(ibgt.balanceOf(address(infrared)), ibgtBalanceInfrared + fees);
        // assertEq(bgt.balanceOf(address(infrared)), ibgt.totalSupply());

        // // check protocol fee amounts updated
        // assertEq(
        //     infrared.protocolFeeAmounts(address(ibgt)), protocolFeeAmount + fees
        // );

        // check reward notified in vault
        // (, uint256 rewardDuration,, uint256 rewardRate, uint256 lastUpdateTime,)
        // = IMultiRewards(address(wiberaVault)).rewardData(address(ibgt));
        // assertEq(rewardRate, (amount - fees) / rewardDuration);
        // assertEq(lastUpdateTime, block.timestamp);

        vm.stopPrank();
    }
}
