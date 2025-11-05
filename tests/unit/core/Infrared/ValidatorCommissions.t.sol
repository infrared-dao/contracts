// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

contract ValidatorCommissionsTest is Helper {
    InfraredV1_9 infraredV9;
    IBeraChef infraredChef;
    bytes validatorPubkey1;
    bytes validatorPubkey2;
    bytes validatorPubkey3;

    address tempReward;
    address tempReward2;
    address tempReward3;

    address vault1;
    address vault2;
    address vault3;

    function setUp() public override {
        super.setUp();
        infraredV9 = InfraredV1_9(payable(address(infrared)));
        infraredChef = infraredV9.chef();

        // Create validator pubkeys
        validatorPubkey1 = _create48Byte();
        validatorPubkey2 =
            abi.encodePacked(bytes32("validator2"), bytes16("key"));
        validatorPubkey3 =
            abi.encodePacked(bytes32("validator3"), bytes16("key"));

        // Add validators
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](3);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validators[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: address(0x222)
        });
        validators[2] = ValidatorTypes.Validator({
            pubkey: validatorPubkey3,
            addr: address(0x333)
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validators);

        BeaconDepositMock(beaconDepositContract).setOperator(
            validatorPubkey1, address(infrared)
        );
        BeaconDepositMock(beaconDepositContract).setOperator(
            validatorPubkey2, address(infrared)
        );
        BeaconDepositMock(beaconDepositContract).setOperator(
            validatorPubkey3, address(infrared)
        );

        tempReward = address(new MockERC20("Temp", "TMP", 18));
        tempReward2 = address(new MockERC20("Temp", "TMP", 18));
        tempReward3 = address(new MockERC20("Temp", "TMP", 18));

        vault1 = address(
            IInfraredVault(infraredV9.registerVault(tempReward)).rewardsVault()
        );
        vault2 = address(
            IInfraredVault(infraredV9.registerVault(tempReward2)).rewardsVault()
        );
        vault3 = address(
            IInfraredVault(infraredV9.registerVault(tempReward3)).rewardsVault()
        );

        vm.startPrank(beraChef.owner());
        beraChef.setVaultWhitelistedStatus(vault1, true, "");
        beraChef.setVaultWhitelistedStatus(vault2, true, "");
        beraChef.setVaultWhitelistedStatus(vault3, true, "");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    QUEUE NEW CUTTING BOARD TESTS
    //////////////////////////////////////////////////////////////*/

    function testQueueNewCuttingBoard() public {
        uint64 startBlock = uint64(block.number + 100);

        // Create weights for reward distribution
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight({
            receiver: vault1,
            percentageNumerator: 10000 // 100%
        });

        // Queue new cutting board
        vm.prank(keeper);
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);
    }

    function testQueueNewCuttingBoardOnlyKeeper() public {
        uint64 startBlock = uint64(block.number + 100);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);

        vm.expectRevert();
        vm.prank(infraredGovernance);
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);
    }

    function testQueueNewCuttingBoardRevertsInvalidValidator() public {
        bytes memory invalidPubkey =
            abi.encodePacked(bytes32("invalid"), bytes16("validator"));
        uint64 startBlock = uint64(block.number + 100);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(keeper);
        infraredV9.queueNewCuttingBoard(invalidPubkey, startBlock, weights);
    }

    function testQueueNewCuttingBoardMultipleWeights() public {
        uint64 startBlock = uint64(block.number + 100);

        // Create multiple reward receivers
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](3);
        weights[0] = IBeraChef.Weight({
            receiver: vault1,
            percentageNumerator: 5000 // 50%
        });
        weights[1] = IBeraChef.Weight({
            receiver: vault2,
            percentageNumerator: 3000 // 30%
        });
        weights[2] = IBeraChef.Weight({
            receiver: vault3,
            percentageNumerator: 2000 // 20%
        });

        vm.prank(keeper);
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);
    }

    function testQueueNewCuttingBoardForMultipleValidators() public {
        uint64 startBlock = uint64(block.number + 100);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.startPrank(keeper);

        // Queue for validator 1
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);

        // Queue for validator 2
        infraredV9.queueNewCuttingBoard(validatorPubkey2, startBlock, weights);

        // Queue for validator 3
        infraredV9.queueNewCuttingBoard(validatorPubkey3, startBlock, weights);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    QUEUE VAL COMMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    function testQueueValCommission() public {
        uint96 commissionRate = 2000; // 50% (assuming 10000 = 100%)

        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);
    }

    function testQueueValCommissionOnlyGovernor() public {
        uint96 commissionRate = 2000;

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);
    }

    function testQueueValCommissionRevertsInvalidValidator() public {
        bytes memory invalidPubkey =
            abi.encodePacked(bytes32("invalid"), bytes16("validator"));
        uint96 commissionRate = 2000;

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(invalidPubkey, commissionRate);
    }

    function testQueueValCommissionDifferentRates() public {
        vm.startPrank(infraredGovernance);

        // Queue different commission rates for different validators
        infraredV9.queueValCommission(validatorPubkey1, 1000); // 10%
        infraredV9.queueValCommission(validatorPubkey2, 2000); // 20%
        infraredV9.queueValCommission(validatorPubkey3, 500); // 5%

        vm.stopPrank();
    }

    function testQueueValCommissionZeroRate() public {
        uint96 commissionRate = 0;

        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);
    }

    function testQueueValCommissionMaxRate() public {
        uint96 commissionRate = 2000; // 20%

        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);
    }

    /*//////////////////////////////////////////////////////////////
                QUEUE MULTIPLE VAL COMMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testQueueMultipleValCommissions() public {
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;
        pubkeys[2] = validatorPubkey3;

        uint96 commissionRate = 2000;

        vm.prank(infraredGovernance);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);
    }

    function testQueueMultipleValCommissionsOnlyGovernor() public {
        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;

        uint96 commissionRate = 2000;

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);
    }

    function testQueueMultipleValCommissionsRevertsInvalidValidator() public {
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = abi.encodePacked(bytes32("invalid"), bytes16("key")); // Invalid
        pubkeys[2] = validatorPubkey3;

        uint96 commissionRate = 2000;

        // Should revert on the second (invalid) validator
        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(infraredGovernance);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);
    }

    function testQueueMultipleValCommissionsSingleValidator() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validatorPubkey1;

        uint96 commissionRate = 2000;

        vm.prank(infraredGovernance);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);
    }

    function testQueueMultipleValCommissionsEmptyArray() public {
        bytes[] memory pubkeys = new bytes[](0);
        uint96 commissionRate = 2000;

        // Should not revert with empty array
        vm.prank(infraredGovernance);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);
    }

    /*//////////////////////////////////////////////////////////////
                ACTIVATE QUEUED VAL COMMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    function testActivateQueuedValCommission() public {
        uint96 commissionRate = 2000;

        // First queue a commission
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);

        // Wait for the delay period (if any)
        // Note: This depends on the BeraChef implementation
        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // Anyone can activate
        infraredV9.activateQueuedValCommission(validatorPubkey1);

        // Verify the commission is now active
        uint96 activeCommission =
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1);
        assertEq(
            activeCommission, commissionRate, "Commission should be activated"
        );
    }

    function testActivateQueuedValCommissionAnyoneCanCall() public {
        uint96 commissionRate = 2000;

        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);

        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // Test various callers
        vm.prank(testUser);
        infraredV9.activateQueuedValCommission(validatorPubkey1);
    }

    function testActivateQueuedValCommissionRevertsInvalidValidator() public {
        bytes memory invalidPubkey =
            abi.encodePacked(bytes32("invalid"), bytes16("validator"));

        vm.expectRevert(Errors.InvalidValidator.selector);
        infraredV9.activateQueuedValCommission(invalidPubkey);
    }

    function testActivateQueuedValCommissionMultipleValidators() public {
        uint96 commissionRate = 2000;

        vm.startPrank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);
        infraredV9.queueValCommission(validatorPubkey2, commissionRate);
        infraredV9.queueValCommission(validatorPubkey3, commissionRate);
        vm.stopPrank();

        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // Activate all
        infraredV9.activateQueuedValCommission(validatorPubkey1);
        infraredV9.activateQueuedValCommission(validatorPubkey2);
        infraredV9.activateQueuedValCommission(validatorPubkey3);

        // Verify all are active
        assertEq(
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1),
            commissionRate
        );
        assertEq(
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey2),
            commissionRate
        );
        assertEq(
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey3),
            commissionRate
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteCommissionWorkflow() public {
        uint96 commissionRate = 2000; // 30%

        // 1. Queue commission
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);

        // 2. Wait for activation delay
        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // 3. Activate commission
        infraredV9.activateQueuedValCommission(validatorPubkey1);

        // 4. Verify active
        uint96 activeCommission =
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1);
        assertEq(activeCommission, commissionRate);
    }

    function testQueueAndActivateMultipleCommissions() public {
        uint96 commissionRate = 2000;

        // Queue for multiple validators using batch function
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = validatorPubkey1;
        pubkeys[1] = validatorPubkey2;
        pubkeys[2] = validatorPubkey3;

        vm.prank(infraredGovernance);
        infraredV9.queueMultipleValCommissions(pubkeys, commissionRate);

        // Wait for delay
        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // Activate all
        for (uint256 i = 0; i < pubkeys.length; i++) {
            infraredV9.activateQueuedValCommission(pubkeys[i]);
        }

        // Verify all active
        for (uint256 i = 0; i < pubkeys.length; i++) {
            uint96 activeCommission =
                infraredChef.getValCommissionOnIncentiveTokens(pubkeys[i]);
            assertEq(activeCommission, commissionRate);
        }
    }

    function testCuttingBoardAndCommissionTogether() public {
        // Set up cutting board
        uint64 startBlock = uint64(block.number + 100);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] =
            IBeraChef.Weight({receiver: vault1, percentageNumerator: 10000});

        vm.prank(keeper);
        infraredV9.queueNewCuttingBoard(validatorPubkey1, startBlock, weights);

        // Set up commission
        uint96 commissionRate = 2000;
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, commissionRate);

        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);

        // Activate commission
        infraredV9.activateQueuedValCommission(validatorPubkey1);

        // Both should be configured
        uint96 activeCommission =
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1);
        assertEq(activeCommission, commissionRate);
    }

    function testCommissionUpdateWorkflow() public {
        // Initial commission
        uint96 initialRate = 2000;
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, initialRate);

        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);
        infraredV9.activateQueuedValCommission(validatorPubkey1);

        assertEq(
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1),
            initialRate
        );

        // Update commission
        uint96 newRate = 1000;
        vm.prank(infraredGovernance);
        infraredV9.queueValCommission(validatorPubkey1, newRate);

        vm.roll(block.number + beraChef.commissionChangeDelay() + 1);
        infraredV9.activateQueuedValCommission(validatorPubkey1);

        assertEq(
            infraredChef.getValCommissionOnIncentiveTokens(validatorPubkey1),
            newRate
        );
    }
}
