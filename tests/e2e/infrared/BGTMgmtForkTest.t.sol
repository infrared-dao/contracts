// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {InfraredForkTest} from "../InfraredForkTest.t.sol";

contract BGTMgmtForkTest is InfraredForkTest {
    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        ValidatorTypes.Validator memory infraredValidator = ValidatorTypes
            .Validator({pubkey: _create48Byte(), addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        vm.startPrank(infraredGovernance);

        infrared.addValidators(infraredValidators);

        // roll with pol now over single block to accumulate some base + commission BGT rewards
        // rollPol(infraredValidator, block.number + 1);

        // harvest base rewards for some bgt
        // infrared.harvestBase();

        vm.stopPrank();
    }
    /* 

    function testSetUp() public virtual override {
        super.testSetUp();
        assertTrue(infrared.getBGTBalance() > 0);
        assertTrue(bgt.unboostedBalanceOf(address(infrared)) > 0);
    }

    function testQueueBoosts() public {
        vm.startPrank(admin);

        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), infraredValidator);

        address[] memory _validators = new address[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = infraredValidator;
        _amts[0] = uint128(bgt.unboostedBalanceOf(address(infrared)));

        infrared.queueBoosts(_validators, _amts);

        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (uint32 blockNumberLast, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), infraredValidator);

        assertEq(queuedBoostAfter, queuedBoostBefore + _amts[0]);
        assertEq(boostedQueueBalanceAfter, boostedQueueBalanceBefore + _amts[0]);
        assertEq(blockNumberLast, block.number);
        assertEq(bgt.unboostedBalanceOf(address(infrared)), 0);

        vm.stopPrank();
    }

    function testCancelBoosts() public {
        testQueueBoosts();

        vm.startPrank(admin);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));

        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), infraredValidator);

        address[] memory _validators = new address[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = infraredValidator;
        _amts[0] = queuedBoostBefore;

        infrared.cancelBoosts(_validators, _amts);

        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (uint32 blockNumberLast, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), infraredValidator);

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

        vm.startPrank(admin);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsBefore = bgt.boosts(address(infrared));
        uint128 queuedBoostBefore = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceBefore) =
            bgt.boostedQueue(address(infrared), infraredValidator);

        address[] memory _validators = new address[](1);
        _validators[0] = infraredValidator;

        infrared.activateBoosts(_validators);

        uint256 unboostedBGTBalanceAfter =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsAfter = bgt.boosts(address(infrared));
        uint128 queuedBoostAfter = bgt.queuedBoost(address(infrared));
        (, uint128 boostedQueueBalanceAfter) =
            bgt.boostedQueue(address(infrared), infraredValidator);

        assertEq(queuedBoostAfter, 0);
        assertEq(boostedQueueBalanceAfter, 0);
        assertEq(unboostedBGTBalanceAfter, unboostedBGTBalanceBefore);
        assertEq(boostsAfter, boostsBefore + queuedBoostBefore);

        vm.stopPrank();
    }

    function testDropBoosts() public {
        testActivateBoosts();

        vm.startPrank(admin);

        uint256 unboostedBGTBalanceBefore =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsBefore = bgt.boosts(address(infrared));

        address[] memory _validators = new address[](1);
        uint128[] memory _amts = new uint128[](1);

        _validators[0] = infraredValidator;
        _amts[0] = boostsBefore;

        infrared.dropBoosts(_validators, _amts);

        uint256 unboostedBGTBalanceAfter =
            bgt.unboostedBalanceOf(address(infrared));
        uint128 boostsAfter = bgt.boosts(address(infrared));

        assertEq(unboostedBGTBalanceAfter, unboostedBGTBalanceBefore + _amts[0]);
        assertEq(boostsAfter, boostsBefore - _amts[0]);

        vm.stopPrank();
    }
    */
}
