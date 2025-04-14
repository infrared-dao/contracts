// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Helper} from "./Helper.sol";
// Import the specific interface for V1_4 events/functions
import {IInfraredV1_4} from "src/interfaces/upgrades/IInfraredV1_4.sol";
import {InfraredV1_4} from "src/core/upgrades/InfraredV1_4.sol"; // Import implementation for casting
import {Errors} from "src/utils/Errors.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {IInfraredV1_2} from "src/interfaces/upgrades/IInfraredV1_2.sol";
import {BGT} from "@berachain/pol/BGT.sol";

contract InfraredV1_4_Test is Helper {
    /// Test queueing a boost for an external (non-registered) validator.
    function testQueueBoostExternalValidator() public {
        // --- Arrange ---
        bytes memory externalPubKey =
            abi.encodePacked("external-validator-pubkey-123");
        // Ensure the check in ValidatorManagerLibV1_4::queueBoosts IS REMOVED for this test to pass!
        assertFalse(infrared.isInfraredValidator(externalPubKey));

        uint128 boostAmount = 100 ether;
        deal(address(bgt), address(infrared), boostAmount);

        uint256 fakeTotalSupply = 1_000_000 ether;
        vm.mockCall(
            address(ibgt),
            abi.encodeWithSelector(ibgt.totalSupply.selector),
            abi.encode(fakeTotalSupply)
        );

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = externalPubKey;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = boostAmount;

        vm.prank(keeper);
        infrared.queueBoosts(pubkeys, amounts);

        (uint32 blockNumberLast, uint128 boostedQueueBalance) =
            bgt.boostedQueue(address(infrared), externalPubKey);

        assertEq(
            boostedQueueBalance, boostAmount, "Queued boost balance mismatch"
        );
    }

    /// Test queueing boost works for registered validator.
    function testQueueBoostRegisteredValidator() public {
        bytes memory registeredPubKey =
            abi.encodePacked("registered-validator-pubkey-456");
        address validatorAddr = address(0xABC);
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](1);
        validatorsToAdd[0] =
            ValidatorTypes.Validator(registeredPubKey, validatorAddr);
        vm.prank(infraredGovernance);
        infrared.addValidators(validatorsToAdd);
        assertTrue(infrared.isInfraredValidator(registeredPubKey));

        uint128 boostAmount = 50 ether;
        deal(address(bgt), address(infrared), boostAmount);

        uint256 fakeTotalSupply = 1_000_000 ether;
        vm.mockCall(
            address(ibgt),
            abi.encodeWithSelector(ibgt.totalSupply.selector),
            abi.encode(fakeTotalSupply)
        );

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = registeredPubKey;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = boostAmount;

        vm.prank(keeper);
        vm.expectEmit(true, false, false, true, address(infrared));
        // Use an interface that defines QueuedBoosts, e.g., IInfraredV1_2 or base IInfrared
        emit IInfraredV1_2.QueuedBoosts(keeper, pubkeys, amounts);

        infrared.queueBoosts(pubkeys, amounts);

        (uint32 blockNumberLast, uint128 boostedQueueBalance) =
            bgt.boostedQueue(address(infrared), registeredPubKey);

        assertEq(
            boostedQueueBalance, boostAmount, "Queued boost balance mismatch"
        );
    }
}
