// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
// import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import "../InfraredForkTest.t.sol";

contract ValidatorMgmtForkTest is InfraredForkTest {
    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        ValidatorTypes.Validator memory infraredValidator = ValidatorTypes
            .Validator({pubkey: _create48Byte(), addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        // BeaconDeposit(address(beaconDepositContract)).setOperator(infraredValidator.pubkey, infraredValidator.addr);
    }

    function testAddValidators() public {
        vm.startPrank(infraredGovernance);

        // priors checked
        assertEq(infrared.numInfraredValidators(), 0);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), false
        );

        infrared.addValidators(infraredValidators);

        // check validator added to infrared set
        assertEq(infrared.numInfraredValidators(), 1);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), true
        );

        vm.stopPrank();
    }

    function testRemoveValidators() public {
        testAddValidators();

        // move forward beyond buffer length so enough time passed
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = infraredValidators[0].pubkey;
        vm.startPrank(infraredGovernance);

        infrared.removeValidators(pubkeys);

        // check valdiator removed from infrared set
        assertEq(infrared.numInfraredValidators(), 0);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), false
        );

        vm.stopPrank();
    }

    function testReplaceValidator() public {
        testAddValidators();

        ValidatorTypes.Validator memory infraredValidator = ValidatorTypes
            .Validator({pubkey: bytes("dummy"), addr: address(0x99872876234876)});

        // move forward beyond buffer length so enough time passed
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);
        vm.startPrank(infraredGovernance);

        infrared.replaceValidator(
            infraredValidators[0].pubkey, infraredValidator.pubkey
        );

        // check validator replaced in infrared set
        assertEq(infrared.numInfraredValidators(), 1);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), false
        );
        assertEq(infrared.isInfraredValidator(infraredValidator.pubkey), true);

        vm.stopPrank();
    }

    function testDeposit() public {
        // add validator to infrared
        testAddValidators();

        // deposit to ibera
        vm.deal(address(this), 32 ether);
        ibera.mint{value: 32 ether}(address(this));

        // set deposit signature from admin account
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(infraredValidators[0].pubkey, _create96Byte());

        // keeper call to execute beacon deposit
        vm.prank(keeper);
        depositor.execute(infraredValidators[0].pubkey, 32 ether);
    }

    function testQueueNewCuttingBoard() public {
        testDeposit();

        // weight 100% of distributed rewards to lp vault
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

        vm.startPrank(keeper);
        infrared.queueNewCuttingBoard(
            infraredValidators[0].pubkey, _startBlock, _weights
        );

        // check cutting board queued for validator
        IBeraChef.RewardAllocation memory qcb =
            beraChef.getQueuedRewardAllocation(infraredValidators[0].pubkey);
        assertEq(qcb.startBlock, _startBlock);
        assertEq(qcb.weights.length, 1);
        assertEq(qcb.weights[0].receiver, lpRewardsVaultAddress);
        assertEq(qcb.weights[0].percentageNumerator, 1e4);

        // move forward beyond buffer length so enough time passed through buffer
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        // roll with pol now over single block
        // rollPol(block.number + 1);

        // // check cutting board activates for validator once roll pol again
        // IBeraChef.RewardAllocation memory acb =
        //     beraChef.getActiveRewardAllocation(infraredValidators[0].pubkey);
        // assertEq(acb.startBlock, qcb.startBlock);
        // assertEq(acb.weights.length, 1);
        // assertEq(acb.weights[0].receiver, lpRewardsVaultAddress);
        // assertEq(acb.weights[0].percentageNumerator, 1e4);

        // // check queued cutting board deleted
        // qcb = beraChef.getQueuedRewardAllocation(infraredValidators[0].pubkey);
        // assertEq(qcb.startBlock, 0);
        // assertEq(qcb.weights.length, 0);
    }
}
