// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {InfraredForkTest} from "../InfraredForkTest.t.sol";
import {Errors} from "src/utils/Errors.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";

interface SmolBGT {
    function owner() external view returns (address);

    function setMinter(address _minter) external;
}

import {ERC20PresetMinterPauser} from "src/vendors/ERC20PresetMinterPauser.sol";
import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";

contract BGTMgmtForkTest is InfraredForkTest {
    ValidatorTypes.Validator[] public validators;
    bytes public validatorPubkey;

    /*

    function setUp() public virtual override {
        super.setUp();

        validatorPubkey = _create48Byte();
        ValidatorTypes.Validator memory validator = ValidatorTypes
            .Validator({pubkey: validatorPubkey, addr: address(infrared)});
        validators.push(validator);

        vm.startPrank(infraredGovernance);
        infrared.addValidators(validators);
        vm.stopPrank();

        // First give BGT minting rights to ourselves
        vm.startPrank(SmolBGT(address(bgt)).owner());
        SmolBGT(address(bgt)).setMinter(address(this));
        vm.stopPrank();

        // Now mint BGT directly
        bgt.mint(address(infrared), 100 ether);
        
        // Move forward a block
        vm.roll(block.number + 1);
        
        // Harvest base rewards
        vm.prank(keeper);
        infrared.harvestBase();
    }

    function testSetUp() public virtual override {
        super.testSetUp();
        assertTrue(infrared.getBGTBalance() > 0);
        assertTrue(bgt.unboostedBalanceOf(address(infrared)) > 0);
    }

    function testQueueBoosts() public {
        vm.startPrank(keeper);

        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = validatorPubkey;
        uint256 unboostedBalance = bgt.unboostedBalanceOf(address(infrared));
        require(unboostedBalance > 0, "No BGT balance to boost with");
        _amts[0] = uint128(unboostedBalance);

        infrared.queueBoosts(_validators, _amts);

        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (uint32 blockNumberLast, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        assertEq(queuedBoostAfter, queuedBoostBefore + _amts[0]);
        assertEq(boostedQueueBalanceAfter, boostedQueueBalanceBefore + _amts[0]);
        assertEq(blockNumberLast, block.number);
        assertEq(bgt.unboostedBalanceOf(address(infrared)), 0);

        vm.stopPrank();
    }

    function testCancelBoosts() public {
        testQueueBoosts();

        vm.startPrank(keeper);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));

        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        require(queuedBoostBefore > 0, "No queued boosts to cancel");
        
        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = validatorPubkey;
        _amts[0] = queuedBoostBefore;

        infrared.cancelBoosts(_validators, _amts);

        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (uint32 blockNumberLast, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        assertEq(queuedBoostAfter, queuedBoostBefore - _amts[0]);
        assertEq(boostedQueueBalanceAfter, boostedQueueBalanceBefore - _amts[0]);
        assertEq(blockNumberLast, block.number);
        assertEq(
            bgt.unboostedBalanceOf(address(infrared)),
            unboostedBGTBalanceBefore + uint256(_amts[0])
        );

        vm.stopPrank();
    }

    function testActivateBoosts() public {
        testQueueBoosts();

        // move forward beyond buffer length so enough time passed through buffer
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        vm.startPrank(keeper);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsBefore = bgt.boosts(address(infrared));
        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        require(queuedBoostBefore > 0, "No queued boosts to activate");

        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        bytes[] memory _validators = new bytes[](1);
        _validators[0] = validatorPubkey;

        infrared.activateBoosts(_validators);

        uint256 unboostedBGTBalanceAfter =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsAfter = bgt.boosts(address(infrared));
        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), validatorPubkey);

        assertEq(queuedBoostAfter, 0);
        assertEq(boostedQueueBalanceAfter, 0);
        assertEq(unboostedBGTBalanceAfter, unboostedBGTBalanceBefore);
        assertEq(boostsAfter, boostsBefore + queuedBoostBefore);

        vm.stopPrank();
    }

    function testDropBoosts() public {
        testActivateBoosts();

        vm.startPrank(keeper);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsBefore = bgt.boosts(address(infrared));
        require(boostsBefore > 0, "No active boosts to drop");

        bytes[] memory _validators = new bytes[](1);
        _validators[0] = validatorPubkey;

        infrared.dropBoosts(_validators);

        uint256 unboostedBGTBalanceAfter =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsAfter = bgt.boosts(address(infrared));

        assertEq(unboostedBGTBalanceAfter, unboostedBGTBalanceBefore + boostsBefore);
        assertEq(boostsAfter, 0);

        vm.stopPrank();
    }

    function testCancelBoostsForRemovedValidator() public {
        testQueueBoosts();
        
        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        require(queuedBoostBefore > 0, "No queued boosts before removal");

        // Remove validator
        vm.startPrank(infraredGovernance);
        bytes[] memory validatorsToRemove = new bytes[](1);
        validatorsToRemove[0] = validatorPubkey;
        infrared.removeValidators(validatorsToRemove);
        vm.stopPrank();

        // Should still be able to cancel boosts
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);
        _validators[0] = validatorPubkey;
        _amts[0] = queuedBoostBefore;
        
        infrared.cancelBoosts(_validators, _amts);
        vm.stopPrank();

        assertEq(bgt.queuedBoost(address(infrared)), 0, "Queued boosts not cancelled");
    }

    function testQueueDropBoostsForRemovedValidator() public {
        // Setup: Queue and activate boosts
        testActivateBoosts();

        uint128 activatedBoosts = bgt.boosts(address(infrared));
        require(activatedBoosts > 0, "No active boosts before removal");

        // Remove validator
        vm.startPrank(infraredGovernance);
        bytes[] memory validatorsToRemove = new bytes[](1);
        validatorsToRemove[0] = validatorPubkey;
        infrared.removeValidators(validatorsToRemove);
        vm.stopPrank();

        // Should still be able to queue drop boosts
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);
        _validators[0] = validatorPubkey;
        _amts[0] = activatedBoosts;

        infrared.queueDropBoosts(_validators, _amts);
        vm.stopPrank();
    }

    function testDropBoostsForRemovedValidator() public {
        // Setup: Queue and activate boosts
        testActivateBoosts();
        
        uint128 activatedBoosts = bgt.boosts(address(infrared));
        require(activatedBoosts > 0, "No active boosts before removal");

        // Remove validator
        vm.startPrank(infraredGovernance);
        bytes[] memory validatorsToRemove = new bytes[](1);
        validatorsToRemove[0] = validatorPubkey;
        infrared.removeValidators(validatorsToRemove);
        vm.stopPrank();

        // Should still be able to drop boosts
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        _validators[0] = validatorPubkey;

        infrared.dropBoosts(_validators);
        vm.stopPrank();

        assertEq(bgt.boosts(address(infrared)), 0, "Boosts not dropped");
    }

    function testQueueBoostsFailsForRemovedValidator() public {
        // Remove validator
        vm.startPrank(infraredGovernance);
        bytes[] memory validatorsToRemove = new bytes[](1);
        validatorsToRemove[0] = validatorPubkey;
        infrared.removeValidators(validatorsToRemove);
        vm.stopPrank();

        // Should fail to queue boosts
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);
        _validators[0] = validatorPubkey;
        _amts[0] = uint128(bgt.unboostedBalanceOf(address(infrared)));

        vm.expectRevert(Errors.InvalidValidator.selector);
        infrared.queueBoosts(_validators, _amts);
        vm.stopPrank();
    }

    function testActivateBoostsFailsForRemovedValidator() public {
        // First queue boosts
        testQueueBoosts();

        uint128 queuedBoosts = bgt.queuedBoost(address(infrared));
        require(queuedBoosts > 0, "No queued boosts before removal");
        
        // Remove validator
        vm.startPrank(infraredGovernance);
        bytes[] memory validatorsToRemove = new bytes[](1);
        validatorsToRemove[0] = validatorPubkey;
        infrared.removeValidators(validatorsToRemove);
        vm.stopPrank();

        // Should fail to activate boosts
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        _validators[0] = validatorPubkey;

        vm.expectRevert(Errors.InvalidValidator.selector);
        infrared.activateBoosts(_validators);
        vm.stopPrank();
    }

    function testCancelDropBoostsFailsForRemovedValidator() public {
        // Setup: Queue drop boosts
        testQueueDropBoostsForRemovedValidator();
        
        // Attempt to cancel drop boosts (should fail)
        vm.startPrank(keeper);
        bytes[] memory _validators = new bytes[](1);
        uint128[] memory _amts = new uint128[](1);
        _validators[0] = validatorPubkey;
        _amts[0] = uint128(bgt.boosts(address(infrared)));

        vm.expectRevert(Errors.InvalidValidator.selector);
        infrared.cancelDropBoosts(_validators, _amts);
        vm.stopPrank();
    } */
}
