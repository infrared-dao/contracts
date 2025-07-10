// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
// import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import "../HelperForkTest.t.sol";

contract ValidatorMgmtForkTest is HelperForkTest {
    ValidatorTypes.Validator public infraredValidator;
    ValidatorTypes.Validator[] public infraredValidators;
    uint256 public initNumberOfValidators;

    function setUp() public virtual override {
        super.setUp();

        infraredValidator = ValidatorTypes.Validator({
            pubkey: _create48Byte(),
            addr: address(infrared)
        });
        infraredValidators.push(infraredValidator);

        initNumberOfValidators = infrared.numInfraredValidators();

        // BeaconDeposit(address(beaconDepositContract)).setOperator(infraredValidator.pubkey, infraredValidator.addr);
    }

    function testAddValidators() public {
        vm.startPrank(infraredGovernance);

        // priors checked
        assertEq(infrared.numInfraredValidators(), initNumberOfValidators);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), false
        );

        infrared.addValidators(infraredValidators);

        // check validator added to infrared set
        assertEq(infrared.numInfraredValidators(), initNumberOfValidators + 1);
        assertEq(infrared.isInfraredValidator(infraredValidator.pubkey), true);

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
        assertEq(infrared.numInfraredValidators(), initNumberOfValidators);
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
        assertEq(infrared.numInfraredValidators(), initNumberOfValidators + 1);
        assertEq(
            infrared.isInfraredValidator(infraredValidators[0].pubkey), false
        );
        assertEq(infrared.isInfraredValidator(infraredValidator.pubkey), true);

        vm.stopPrank();
    }

    // function testDeposit() public {
    //     // add validator to infrared
    //     testAddValidators();

    //     // deposit to ibera
    //     vm.deal(address(this), InfraredBERAConstants.INITIAL_DEPOSIT);
    //     ibera.mint{value: InfraredBERAConstants.INITIAL_DEPOSIT}(address(this));

    //     // set deposit signature from admin account
    //     vm.prank(infraredGovernance);
    //     ibera.setDepositSignature(infraredValidators[0].pubkey, _create96Byte());

    //     // keeper call to execute beacon deposit
    //     vm.prank(keeper);
    //     depositor.execute(
    //         header,
    //         validatorStruct,
    //         gIndex,
    //         InfraredBERAConstants.INITIAL_DEPOSIT,
    //         proof
    //     );
    // }

    function testQueueNewCuttingBoard() public {
        // Verify the validator is registered with Infrared
        assertTrue(
            infrared.isInfraredValidator(valData.pubkey),
            "Validator should be registered with Infrared"
        );

        // Set up the cutting board with weights
        address lpRewardsVaultAddress = address(infraredVault.rewardsVault());
        IBeraChef.Weight[] memory _weights = new IBeraChef.Weight[](1);
        _weights[0] = IBeraChef.Weight({
            receiver: lpRewardsVaultAddress,
            percentageNumerator: 1e4
        });

        // Calculate start block for cutting board activation
        uint64 _startBlock =
            uint64(block.number) + beraChef.rewardAllocationBlockDelay() + 1;

        // Queue the new cutting board
        vm.prank(keeper);
        infrared.queueNewCuttingBoard(valData.pubkey, _startBlock, _weights);

        // Verify the cutting board was queued properly
        IBeraChef.RewardAllocation memory queuedAllocation =
            beraChef.getQueuedRewardAllocation(valData.pubkey);
        assertEq(queuedAllocation.startBlock, _startBlock);

        // Roll forward to the activation block
        vm.roll(_startBlock + 1);

        // DIRECTLY activate the queued allocation
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);

        // Verify that the cutting board was activated
        IBeraChef.RewardAllocation memory activeAllocationAfter =
            beraChef.getActiveRewardAllocation(valData.pubkey);

        // Assertions to verify activation
        assertEq(activeAllocationAfter.startBlock, _startBlock);
        assertEq(activeAllocationAfter.weights.length, 1);
        assertEq(
            activeAllocationAfter.weights[0].receiver, lpRewardsVaultAddress
        );
        assertEq(activeAllocationAfter.weights[0].percentageNumerator, 1e4);
    }
}
