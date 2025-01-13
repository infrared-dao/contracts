// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";

import {HarvestForkTest} from "./HarvestForkTest.t.sol";

contract HarvestBoostRewardsForkTest is HarvestForkTest {
/*
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);

        // harvest base rewards for some bgt
        infrared.harvestBase();

        // queue boost to validator
        uint256 unboostedBalance = bgt.unboostedBalanceOf(address(infrared));

        address[] memory _validators = new address[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = infraredValidator;
        _amts[0] = uint128(unboostedBalance); // dont care about unsafe cast
        infrared.queueBoosts(_validators, _amts);

        // move forward beyond buffer length so enough time passed through buffer
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        // activate boost
        infrared.activateBoosts(_validators);

        // donate to the fee collector for BGT staking to have rewards
        uint256 donateAmt = feeCollector.payoutAmount();
        deal(address(honey), admin, type(uint256).max);

        honey.approve(address(feeCollector), donateAmt);
        feeCollector.donate(donateAmt);

        // move foward in time so boosted BGT accumulates some earned boost rewards
        uint256 dt = bgtStaker.rewardsDuration() / 2;
        vm.warp(block.timestamp + dt);

        vm.stopPrank();
    }

    function testSetUp() public virtual override {
        super.testSetUp();

        assertTrue(bgt.balanceOf(address(infrared)) > 0);
        assertEq(ibgt.totalSupply(), bgt.balanceOf(address(infrared)));
        assertEq(bgt.unboostedBalanceOf(address(infrared)), 0);

        assertTrue(honey.balanceOf(address(bgtStaker)) > 0);
        assertTrue(bgtStaker.balanceOf(address(infrared)) > 0);
        assertTrue(bgtStaker.earned(address(infrared)) > 0);
    }

    function testHarvestBoostRewards(uint256 protocolFeeRate) public {
        vm.assume(protocolFeeRate < FEE_UNIT);
        vm.startPrank(admin);

        // set protocol fee rate
        infrared.updateProtocolFeeRate(address(honey), protocolFeeRate);
        assertEq(infrared.protocolFeeRates(address(honey)), protocolFeeRate);

        IInfraredVault ibgtVault = infrared.ibgtVault();
        uint256 earned = bgtStaker.earned(address(infrared));
        uint256 fees = (earned * protocolFeeRate) / FEE_UNIT;

        uint256 balanceIbgtVault = honey.balanceOf(address(ibgtVault));
        uint256 balanceInfrared = honey.balanceOf(address(infrared));
        uint256 protocolFeeAmount = infrared.protocolFeeAmounts(address(honey));

        // harvest staked bgt boost rewards
        infrared.harvestBoostRewards();

        // check balances updated
        assertEq(
            honey.balanceOf(address(ibgtVault)),
            balanceIbgtVault + earned - fees
        );
        assertEq(honey.balanceOf(address(infrared)), balanceInfrared + fees);

        // check protocol fee amounts updated
        assertEq(
            infrared.protocolFeeAmounts(address(honey)),
            protocolFeeAmount + fees
        );

        // check reward notified in vault
        (, uint256 rewardDuration,, uint256 rewardRate, uint256 lastUpdateTime,)
        = IMultiRewards(address(ibgtVault)).rewardData(address(honey));
        assertEq(rewardRate, (earned - fees) / rewardDuration);
        assertEq(lastUpdateTime, block.timestamp);

        vm.stopPrank();
    }
    */
}
