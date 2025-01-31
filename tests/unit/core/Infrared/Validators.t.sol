// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helper} from "./Helper.sol";
import {Errors} from "src/utils/Errors.sol";

import {DataTypes} from "src/utils/DataTypes.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

contract ValidatorManagment is Helper {
    /*//////////////////////////////////////////////////////////////
               Validator Set Management Tests
    //////////////////////////////////////////////////////////////*/

    function testAddValidatorsRevertsOnZeroAddress() public {
        // Setup
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            addr: address(0), // Zero address to trigger the revert
            pubkey: bytes("somePubKey")
        });

        // Expect the addValidators function to revert with Errors.ZeroAddress
        vm.startPrank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAddress.selector);
        infrared.addValidators(validators);
        vm.stopPrank();
    }

    function testAddValidatorsSuccess() public {
        // Setup
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            addr: address(1), // Valid address
            pubkey: bytes("somePubKey")
        });

        // Start the prank as the governance address
        vm.startPrank(infraredGovernance);

        // Verify that the ValidatorsAdded event was emitted
        vm.expectEmit(true, true, true, true);
        emit IInfrared.ValidatorsAdded(infraredGovernance, validators);

        // Add validators successfully
        infrared.addValidators(validators);

        // Stop the prank
        vm.stopPrank();

        // Verify that the validator was added
        // Check if the validator's public key is stored
        bool isValidatorAdded =
            infrared.isInfraredValidator(validators[0].pubkey);
        assertTrue(isValidatorAdded, "Validator should be added");
    }

    function testFailAddValidatorUnauthorized() public {
        // Set up a new mock validator
        ValidatorTypes.Validator[] memory newValidators =
            new ValidatorTypes.Validator[](1);
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey"),
            addr: address(this)
        });

        // Simulate the call from an unauthorized address
        vm.prank(address(2));

        // Expect a revert due to unauthorized access
        vm.expectRevert("Unauthorized");
        // Attempt to add the new validator
        infrared.addValidators(newValidators);
    }

    function testAddValidatorEmptySet() public {
        /// @notice, we are going to be donating 100 ether to the system via bgt,
        /// simulating a claim into infrared when there are no validators set, then adding another validator.
        /// this should skip on first then compound once vals are added.
        /// on second add 100 ether -> current fee of 4=25%, 75 ether to users, 25 ether to operators.
        /// this should increase the overall ether backing of the system by 100ether.

        uint256 donatedAmount = 100 ether;
        uint256 ts = ibera.totalSupply();
        (uint256 prevBacking,) = ibera.previewBurn(ts);

        // 1. simulate someone claiming their bgt to the contract causing harvest base to be called.
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), donatedAmount);
        vm.stopPrank();

        // 2. call the add validators method with 1 validator, should skip the harvest methods.
        ValidatorTypes.Validator[] memory newValidators =
            new ValidatorTypes.Validator[](1);
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey"),
            addr: address(this)
        });
        vm.startPrank(infraredGovernance);
        infrared.addValidators(newValidators);
        vm.stopPrank();

        // 3. the balance of BGT in the `infrared` contract should be the same as the donated amount.
        assertEq(bgt.balanceOf(address(infrared)), donatedAmount);

        // 4. add another validator, calling the harvestBase and harvestOperatorRewards methods.
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: bytes("someOtherValidPubKey2"), // diff pubkek
            addr: address(this)
        });
        vm.startPrank(infraredGovernance);
        infrared.addValidators(newValidators);
        vm.stopPrank();

        // 5. the backing of iBERA should have increased by 100 ether.
        ts = ibera.totalSupply();
        (uint256 currentBacking,) = ibera.previewBurn(ts);
        assertEq(currentBacking - prevBacking, donatedAmount);
    }

    function testRemoveValidators() public {
        // Set up a new mock validator
        ValidatorTypes.Validator[] memory newValidators =
            new ValidatorTypes.Validator[](2);
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey"),
            addr: address(this)
        });
        newValidators[1] = ValidatorTypes.Validator({
            pubkey: bytes("someOtherValidPubKey2"),
            addr: address(this)
        });

        vm.startPrank(infraredGovernance);
        // Add the new validators
        infrared.addValidators(newValidators);

        // Assert that the validator was added
        assertTrue(
            infrared.isInfraredValidator(newValidators[0].pubkey),
            "Validator not added correctly"
        );

        bytes[] memory pubkeysToRemove = new bytes[](1);
        pubkeysToRemove[0] = newValidators[0].pubkey;

        // Prepare for the removal event
        vm.expectEmit(true, true, false, true);
        emit IInfrared.ValidatorsRemoved(infraredGovernance, pubkeysToRemove);

        // Remove the validator
        infrared.removeValidators(pubkeysToRemove);

        // Assert that the validator was removed
        assertFalse(
            infrared.isInfraredValidator(newValidators[0].pubkey),
            "Validator not removed correctly"
        );
        vm.stopPrank();
    }

    function testFailRemoveValidatorUnauthorized() public {
        // Create a new validator struct with sample data
        ValidatorTypes.Validator[] memory newValidators =
            new ValidatorTypes.Validator[](1);
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: "somePublicKey",
            addr: address(this)
        });

        vm.startPrank(infraredGovernance);
        // Add the new validator
        infrared.addValidators(newValidators);
        vm.stopPrank();

        // Assert that the validator was added successfully
        assertTrue(
            infrared.isInfraredValidator(newValidators[0].pubkey),
            "Validator not added correctly"
        );

        bytes[] memory pubkeysToRemove = new bytes[](1);
        pubkeysToRemove[0] = newValidators[0].pubkey;

        // Attempt to remove the validator as an unauthorized user
        vm.prank(address(2)); // Simulate call from an unauthorized address
        vm.expectRevert("Unauthorized");
        infrared.removeValidators(pubkeysToRemove);
    }

    function testReplaceValidator() public {
        // Set up a new mock validator
        ValidatorTypes.Validator[] memory newValidators =
            new ValidatorTypes.Validator[](1);
        newValidators[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey777"),
            addr: address(this)
        });

        // Add the new validator
        vm.startPrank(infraredGovernance);
        infrared.addValidators(newValidators);

        // Assert that the validator was added
        assertTrue(
            infrared.isInfraredValidator(newValidators[0].pubkey),
            "Validator not added correctly"
        );

        // Prepare for validator replacement
        ValidatorTypes.Validator[] memory replacementValidator =
            new ValidatorTypes.Validator[](1);
        replacementValidator[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey45454"),
            addr: address(this)
        });

        // Emitting event for replacing validator
        vm.expectEmit(true, true, false, true);
        emit IInfrared.ValidatorReplaced(
            infraredGovernance,
            newValidators[0].pubkey,
            replacementValidator[0].pubkey
        );

        // Replace the original validator with the new one
        infrared.replaceValidator(
            newValidators[0].pubkey, replacementValidator[0].pubkey
        );

        // Stop impersonating the governance address
        vm.stopPrank();

        // Assert that the original validator was replaced
        assertFalse(
            infrared.isInfraredValidator(newValidators[0].pubkey),
            "Original validator was not removed correctly"
        );
        assertTrue(
            infrared.isInfraredValidator(replacementValidator[0].pubkey),
            "New validator was not added correctly"
        );
    }

    function testFailReplaceValidatorWithInvalidPubKey() public {
        // Set up a new mock validator with valid details
        ValidatorTypes.Validator[] memory originalValidator =
            new ValidatorTypes.Validator[](1);
        originalValidator[0] = ValidatorTypes.Validator({
            pubkey: bytes("someValidPubKey777"),
            addr: address(this)
        });

        // Attempt to add the original validator
        vm.prank(infraredGovernance);
        infrared.addValidators(originalValidator);

        // Assert that the original validator was added
        assertTrue(
            infrared.isInfraredValidator(originalValidator[0].pubkey),
            "Original validator not added correctly"
        );

        // Prepare an invalid new validator with zero-length public key
        ValidatorTypes.Validator[] memory invalidNewValidator =
            new ValidatorTypes.Validator[](1);
        invalidNewValidator[0] =
            ValidatorTypes.Validator({pubkey: bytes(""), addr: address(this)});

        // Attempt to replace the original validator with the invalid new validator
        vm.prank(infraredGovernance);
        vm.expectRevert();
        infrared.replaceValidator(
            originalValidator[0].pubkey, invalidNewValidator[0].pubkey
        );
    }

    function testFailReplaceValidatorUnauthorized() public {
        bytes memory pubkey777 = abi.encodePacked(address(777));
        bytes memory pubkey888 = abi.encodePacked(address(888));

        // Set up a new mock validator with valid details
        ValidatorTypes.Validator[] memory originalValidator =
            new ValidatorTypes.Validator[](1);
        originalValidator[0] =
            ValidatorTypes.Validator({pubkey: pubkey777, addr: address(this)});

        // Add the original validator with governance privileges
        vm.prank(infraredGovernance);
        infrared.addValidators(originalValidator);

        // Assert that the original validator was added
        assertTrue(
            infrared.isInfraredValidator(originalValidator[0].pubkey),
            "Original validator not added correctly"
        );

        // Attempt to replace the validator without authorization
        vm.prank(address(2)); // Simulating a call from an unauthorized address
        vm.expectRevert("Unauthorized");
        infrared.replaceValidator(originalValidator[0].pubkey, pubkey888);
    }
}
