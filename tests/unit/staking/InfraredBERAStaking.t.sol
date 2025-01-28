// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IInfraredBERAClaimor} from "src/interfaces/IInfraredBERAClaimor.sol";
import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {Errors} from "src/utils/Errors.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {ValidatorTypes} from "src/core/Infrared.sol";

contract InfraredBERAStakingTest is InfraredBERABaseTest {
    bytes public validatorPubkey;

    function setUp() public virtual override {
        super.setUp();

        // Setup mock validator pubkey (48 bytes length)
        validatorPubkey =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Register validator through Infrared contract
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey,
            addr: address(this)
        });

        vm.startPrank(infraredGovernance);
        // Setup signature
        ibera.setDepositSignature(
            validatorPubkey,
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        );

        // Add validator
        infrared.addValidators(validators);

        // Setup roles for withdraworLite
        withdraworLite.grantRole(
            withdraworLite.DEFAULT_ADMIN_ROLE(), infraredGovernance
        );
        withdraworLite.grantRole(withdraworLite.KEEPER_ROLE(), keeper);
        withdraworLite.grantRole(
            withdraworLite.GOVERNANCE_ROLE(), infraredGovernance
        );

        // Disable withdrawals
        ibera.setWithdrawalsEnabled(false);
        vm.stopPrank();
    }

    function testFuzz_Execute(uint256 amount) public {
        // Bound amount between minimum deposit and max effective balance
        amount = bound(
            amount,
            InfraredBERAConstants.INITIAL_DEPOSIT,
            InfraredBERAConstants.MAX_EFFECTIVE_BALANCE
        );
        amount = (amount / 1 gwei) * 1 gwei;

        // Since validator is not staked, first deposit will be INITIAL_DEPOSIT
        uint256 expectedStake = InfraredBERAConstants.INITIAL_DEPOSIT;

        // Fund both ibera and depositor
        vm.deal(address(ibera), amount);
        vm.deal(address(depositor), amount);

        // Queue from ibera
        vm.prank(address(ibera));
        depositor.queue{value: amount}();

        // Execute deposit as keeper
        vm.prank(keeper);
        depositor.execute(validatorPubkey, amount);

        // Verify stake is registered correctly
        assertEq(ibera.stakes(validatorPubkey), expectedStake);
        assertTrue(ibera.staked(validatorPubkey));
    }

    function testFuzz_ExecuteFailsWithInvalidAmount(uint256 _amount) public {
        // Attempting to execute with an amount more than what's queued should fail
        uint256 queueAmount = 10 ether + depositor.reserves();
        // Make sure test amount is greater than queued
        _amount = bound(_amount, queueAmount + 1, type(uint128).max);

        // Fund both contracts with the smaller amount
        vm.deal(address(ibera), queueAmount);
        vm.deal(address(depositor), queueAmount);

        // Queue the smaller amount from ibera
        vm.prank(address(ibera));
        depositor.queue{value: queueAmount}();

        // Try to execute with larger amount - should fail with InvalidAmount
        uint256 reserves = depositor.reserves();
        vm.startPrank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        depositor.execute(validatorPubkey, reserves + _amount);
    }
}
