// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IRewardVault} from "@berachain/pol/interfaces/IRewardVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {InfraredForkTest} from "../../InfraredForkTest.t.sol";

contract HarvestForkTest is InfraredForkTest {
    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        ValidatorTypes.Validator memory infraredValidator = ValidatorTypes
            .Validator({pubkey: _create48Byte(), addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        vm.prank(infraredGovernance);
        infrared.addValidators(infraredValidators);

        // deposit to ibera
        vm.deal(address(this), 32 ether);
        ibera.mint{value: 32 ether}(address(this));

        // set deposit signature from admin account
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(infraredValidators[0].pubkey, _create96Byte());

        // keeper call to execute beacon deposit
        vm.prank(keeper);
        depositor.execute(infraredValidators[0].pubkey, 32 ether);

        // queue cutting board
        address lpRewardsVaultAddress = address(lpVault.rewardsVault());
        IBeraChef.Weight[] memory _weights = new IBeraChef.Weight[](1);
        _weights[0] = IBeraChef.Weight({
            receiver: lpRewardsVaultAddress,
            percentageNumerator: 1e4
        });
        uint64 _startBlock =
            uint64(block.number) + beraChef.rewardAllocationBlockDelay() + 1;

        vm.prank(beraChef.owner());
        beraChef.setVaultWhitelistedStatus(lpRewardsVaultAddress, true, "");

        vm.prank(keeper);
        infrared.queueNewCuttingBoard(
            infraredValidators[0].pubkey, _startBlock, _weights
        );

        // move forward beyond buffer length so enough time passed through buffer
        // vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        // activate cutting board by rolling with pol now over single block
        // rollPol(infraredValidator, block.number + 1);

        // vm.stopPrank();
    }

    function testSetUp() public virtual override {
        super.testSetUp();

        assertEq(infrared.numInfraredValidators(), 1);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), true
        );

        // IBeraChef.RewardAllocation memory acb =
        //     beraChef.getActiveRewardAllocation(infraredValidators[0].pubkey);
        // assertTrue(acb.startBlock > 0);
        // assertEq(acb.weights.length, 1);
        // assertEq(acb.weights[0].receiver, address(lpVault.rewardsVault()));
        // assertEq(acb.weights[0].percentageNumerator, 1e4);

        // assertTrue(infrared.getBGTBalance() > 0);
    }
}
