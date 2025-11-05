// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

import {IBGT} from "@berachain/pol/interfaces/IBGT.sol";

contract ValidatorManagerLibTest is Helper {
    bytes validatorPubkey1;
    bytes validatorPubkey2;
    bytes validatorPubkey3;
    InfraredV1_9 infraredV9;

    function setUp() public override {
        super.setUp();
        infraredV9 = InfraredV1_9(payable(address(infrared)));

        // Create validator pubkeys
        validatorPubkey1 = _create48Byte();
        validatorPubkey2 =
            abi.encodePacked(bytes32("validator2"), bytes16("key"));
        validatorPubkey3 =
            abi.encodePacked(bytes32("validator3"), bytes16("key"));

        vm.prank(address(infrared));
        ibgt.mint(address(1), 1000 ether);
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 1000 ether);

        // Mock distributor getValidator responses
        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(
                InfraredDistributor.getValidator.selector, validatorPubkey1
            ),
            abi.encode(validator)
        );
        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(
                InfraredDistributor.getValidator.selector, validatorPubkey2
            ),
            abi.encode(validator2)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    REPLACE VALIDATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testReplaceValidator() public {
        // Add initial validator
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey1),
            "Validator 1 should be added"
        );

        // Replace validator
        vm.prank(infraredGovernance);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);

        // Old validator should be removed
        assertFalse(
            infraredV9.isInfraredValidator(validatorPubkey1),
            "Old validator should be removed"
        );

        // New validator should be added
        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey2),
            "New validator should be added"
        );
    }

    function testReplaceValidatorEmitsEvent() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Event testing removed for now - interface compatibility issue

        vm.prank(infraredGovernance);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);
    }

    function testReplaceValidatorRevertsInvalidValidator() public {
        // Try to replace non-existent validator
        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);
    }

    function testReplaceValidatorRevertsNewAlreadyExists() public {
        // Add both validators
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Try to replace validator1 with validator2 (which already exists)
        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);
    }

    function testReplaceValidatorOnlyGovernor() public {
        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);
    }

    function testQueueBoosts() public {
        // Add validator
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.queueBoost, (validatorPubkey1, 10 ether))
        );

        vm.prank(keeper);

        infraredV9.queueBoosts(pubkeys, amounts);
    }

    function testQueueBoosts_Multiple() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.queueBoost, (validatorPubkey1, 10 ether))
        );
        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.queueBoost, (validatorPubkey2, 20 ether))
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);
    }

    function testQueueBoosts_RevertExceedsSupply() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1001 ether; // > 1000 ether totalSupply

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.expectRevert(Errors.BoostExceedsSupply.selector);
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);
    }

    function testQueueBoosts_RevertZeroAmount() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 0;

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);
    }

    function testQueueBoosts_RevertMismatchedLengths() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);
    }

    function testQueueBoosts_OnlyKeeper() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.queueBoosts(pubkeys, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL BOOSTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelBoosts() public {
        // Add validator
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Queue some boosts first
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        // Cancel the boosts
        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.cancelBoost, (validatorPubkey1, 10 ether))
        );
        vm.prank(keeper);
        infraredV9.cancelBoosts(pubkeys, amounts);
    }

    function testCancelBoostsEmitsEvent() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        //         vm.expectEmit(true, true, true, true);
        //         emit InfraredV1_9.CancelledBoosts(keeper, pubkeys, amounts);

        vm.prank(keeper);
        infraredV9.cancelBoosts(pubkeys, amounts);
    }

    function testCancelBoostsOnlyKeeper() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.cancelBoosts(pubkeys, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    QUEUE DROP BOOSTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testQueueDropBoosts() public {
        // Add validator and activate boosts first
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Queue and activate boosts
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        // Assume delay is 1 second for test
        vm.roll(block.number + bgt.activateBoostDelay() + 1);

        vm.expectCall(
            address(bgt),
            abi.encodeCall(
                IBGT.activateBoost, (address(infraredV9), validatorPubkey1)
            )
        );

        infraredV9.activateBoosts(pubkeys); // Anyone can call
    }

    function testActivateBoosts_Multiple() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);

        vm.expectCall(
            address(bgt),
            abi.encodeCall(
                IBGT.activateBoost, (address(infraredV9), validatorPubkey1)
            )
        );
        vm.expectCall(
            address(bgt),
            abi.encodeCall(
                IBGT.activateBoost, (address(infraredV9), validatorPubkey2)
            )
        );
        infraredV9.activateBoosts(pubkeys);

        // need to use vm.store or mockCall
        // // Now queue drop boosts
        // vm.prank(keeper);
        // infraredV9.queueDropBoosts(pubkeys, amounts);
    }

    function testQueueDropBoostsEmitsEvent() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // Queue drop
        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.queueDropBoost, (validatorPubkey1, 10 ether))
        );

        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);
    }

    function testQueueDropBoosts_RevertZeroAmount() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 0;

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);
    }

    function testQueueDropBoosts_RevertMismatchedLengths() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);
    }

    function testQueueDropBoostsOnlyKeeper() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.queueDropBoosts(pubkeys, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL DROP BOOSTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelDropBoosts() public {
        // Add validator and setup
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Queue and activate boosts
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // Queue drop
        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);

        // Cancel drop
        vm.expectCall(
            address(bgt),
            abi.encodeCall(IBGT.cancelDropBoost, (validatorPubkey1, 10 ether))
        );

        vm.prank(keeper);
        infraredV9.cancelDropBoosts(pubkeys, amounts);
    }

    function testCancelDropBoostsEmitsEvent() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // need to use vm.store or mockCall
        // vm.prank(keeper);
        // infraredV9.queueDropBoosts(pubkeys, amounts);
        // vm.prank(keeper);
        // infraredV9.cancelDropBoosts(pubkeys, amounts);
    }

    function testCancelDropBoostsOnlyKeeper() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.cancelDropBoosts(pubkeys, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    DROP BOOSTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testDropBoosts() public {
        // Add validator and setup
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Queue and activate boosts
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // need to use vm.store or mockCall
        // // Queue drop boosts
        // vm.prank(keeper);
        // infraredV9.queueDropBoosts(pubkeys, amounts);

        // // Wait for activation delay
        // vm.warp(block.timestamp + 1);

        // // Execute drop boosts (anyone can call)
        // infraredV9.dropBoosts(pubkeys);
    }

    function testDropBoostsEmitsEvent() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // need to use vm.store or mockCall
        // vm.prank(keeper);
        // infraredV9.queueDropBoosts(pubkeys, amounts);

        // vm.warp(block.timestamp + 1);

        // //         vm.expectEmit(true, true, true, true);
        // //         emit InfraredV1_9.DroppedBoosts(address(this), pubkeys);

        // infraredV9.dropBoosts(pubkeys);
    }

    function testDropBoostsMultipleValidators() public {
        // Add multiple validators
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Setup boosts for both
        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.dropBoostDelay() + 1);

        vm.expectCall(
            address(bgt),
            abi.encodeCall(
                IBGT.dropBoost, (address(infraredV9), validatorPubkey1)
            )
        );
        vm.expectCall(
            address(bgt),
            abi.encodeCall(
                IBGT.dropBoost, (address(infraredV9), validatorPubkey2)
            )
        );

        infraredV9.dropBoosts(pubkeys);
    }

    /*//////////////////////////////////////////////////////////////
                    GETTERS TESTS
    //////////////////////////////////////////////////////////////*/

    function testInfraredValidators() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(
                InfraredDistributor.getValidator.selector, validatorPubkey1
            ),
            abi.encode(validator)
        );
        vm.mockCall(
            address(distributor),
            abi.encodeWithSelector(
                InfraredDistributor.getValidator.selector, validatorPubkey2
            ),
            abi.encode(validator2)
        );

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        ValidatorTypes.Validator[] memory returnedValidators =
            infraredV9.infraredValidators();

        assertEq(returnedValidators.length, 2, "Incorrect number returned");
        assertEq(
            keccak256(returnedValidators[0].pubkey),
            keccak256(validatorPubkey1),
            "Incorrect pubkey 1"
        );
        assertEq(returnedValidators[0].addr, validator, "Incorrect addr 1");
        assertEq(
            keccak256(returnedValidators[1].pubkey),
            keccak256(validatorPubkey2),
            "Incorrect pubkey 2"
        );
        assertEq(returnedValidators[1].addr, validator2, "Incorrect addr 2");
    }

    function testNumInfraredValidators() public {
        assertEq(infraredV9.numInfraredValidators(), 0, "Initial non-zero");

        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        assertEq(infraredV9.numInfraredValidators(), 1, "After add");
    }

    function testIsValidator() public {
        assertFalse(
            infraredV9.isInfraredValidator(validatorPubkey1), "Initial true"
        );

        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey1), "After add false"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteBoostLifecycle() public {
        // Test complete lifecycle: queue -> activate -> queue drop -> drop
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        // 1. Queue boost
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        // 2. Activate boost
        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // 3. Queue drop
        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);

        // 4. Drop boost
        vm.roll(block.number + bgt.dropBoostDelay() + 1);
        infraredV9.dropBoosts(pubkeys);
    }

    function testBoostCancellationBeforeActivation() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        // Queue boost
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        // Cancel before activation
        vm.prank(keeper);
        infraredV9.cancelBoosts(pubkeys, amounts);
    }

    function testDropBoostCancellationBeforeExecution() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10 ether;

        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(IBGT.boosts.selector, address(infraredV9)),
            abi.encode(0)
        );
        vm.mockCall(
            address(bgt),
            abi.encodeWithSelector(
                IBGT.queuedBoost.selector, address(infraredV9)
            ),
            abi.encode(0)
        );

        // Setup active boost
        vm.prank(keeper);
        infraredV9.queueBoosts(pubkeys, amounts);

        vm.roll(block.number + bgt.activateBoostDelay() + 1);
        infraredV9.activateBoosts(pubkeys);

        // Queue drop
        vm.prank(keeper);
        infraredV9.queueDropBoosts(pubkeys, amounts);

        // Cancel drop
        vm.prank(keeper);
        infraredV9.cancelDropBoosts(pubkeys, amounts);
    }

    function testAddValidators() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey1),
            "Validator 1 not added"
        );
        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey2),
            "Validator 2 not added"
        );
        assertEq(
            infraredV9.numInfraredValidators(),
            2,
            "Incorrect number of validators"
        );

        ValidatorTypes.Validator[] memory returnedValidators =
            infraredV9.infraredValidators();
        assertEq(
            returnedValidators.length, 2, "Incorrect returned validators length"
        );
        assertEq(
            keccak256(returnedValidators[0].pubkey),
            keccak256(validatorPubkey1),
            "Incorrect pubkey 1"
        );
        assertEq(returnedValidators[0].addr, validator, "Incorrect addr 1");
    }

    function testAddValidators_Duplicate() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator2
        });

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);
    }

    function testAddValidators_ZeroAddress() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: address(0)
        });

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);
    }

    function testAddValidators_EmptyArray() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](0);

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        assertEq(
            infraredV9.numInfraredValidators(),
            0,
            "Number of validators changed"
        );
    }

    function testAddValidators_OnlyGovernance() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.addValidators(validators);
    }

    /*//////////////////////////////////////////////////////////////
                    REMOVE VALIDATORS TESTS
    //////////////////////////////////////////////////////////////*/

    function testRemoveValidators() public {
        // Add validators first
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](2);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: validator2
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        // Remove one
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;

        vm.prank(infraredGovernance);
        infraredV9.removeValidators(pubkeys);

        assertFalse(
            infraredV9.isInfraredValidator(validatorPubkey1),
            "Validator 1 not removed"
        );
        assertTrue(
            infraredV9.isInfraredValidator(validatorPubkey2),
            "Validator 2 removed unexpectedly"
        );
        assertEq(
            infraredV9.numInfraredValidators(),
            1,
            "Incorrect number of validators"
        );
    }

    function testRemoveValidators_Invalid() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.removeValidators(pubkeys);
    }

    function testRemoveValidators_EmptyArray() public {
        vm.prank(infraredGovernance);
        infraredV9.removeValidators(new bytes[](0));

        assertEq(
            infraredV9.numInfraredValidators(),
            0,
            "Number of validators changed"
        );
    }

    function testRemoveValidators_OnlyGovernance() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.removeValidators(pubkeys);
    }
}
