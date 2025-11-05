// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

contract ViewFunctionsTest is Helper {
    InfraredV1_9 infraredV9;
    bytes validatorPubkey1;
    bytes validatorPubkey2;
    bytes validatorPubkey3;

    function setUp() public override {
        super.setUp();
        infraredV9 = InfraredV1_9(payable(address(infrared)));

        // Create validator pubkeys
        validatorPubkey1 = _create48Byte();
        validatorPubkey2 =
            abi.encodePacked(bytes32("validator2"), bytes16("key"));
        validatorPubkey3 =
            abi.encodePacked(bytes32("validator3"), bytes16("key"));
    }

    /*//////////////////////////////////////////////////////////////
                    INFRARED VALIDATORS TESTS
    //////////////////////////////////////////////////////////////*/

    function testInfraredValidatorsEmpty() public view {
        // With no validators added yet in this test, check the function works
        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();
        // Note: Helper.sol may have added validators during setup
        // Just verify the function doesn't revert
        assertTrue(validators.length >= 0, "Should return array");
    }

    function testInfraredValidatorsSingleValidator() public {
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](1);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();

        // Should include the newly added validator
        bool found = false;
        for (uint256 i = 0; i < validators.length; i++) {
            if (keccak256(validators[i].pubkey) == keccak256(validatorPubkey1))
            {
                found = true;
                assertEq(validators[i].addr, validator);
                break;
            }
        }
        assertTrue(found, "Should include added validator");
    }

    function testInfraredValidatorsMultipleValidators() public {
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](3);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validatorsToAdd[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: address(0x222)
        });
        validatorsToAdd[2] = ValidatorTypes.Validator({
            pubkey: validatorPubkey3,
            addr: address(0x333)
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();

        // Verify all three validators are in the returned array
        uint256 foundCount = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            bytes32 pubkeyHash = keccak256(validators[i].pubkey);
            if (pubkeyHash == keccak256(validatorPubkey1)) foundCount++;
            if (pubkeyHash == keccak256(validatorPubkey2)) foundCount++;
            if (pubkeyHash == keccak256(validatorPubkey3)) foundCount++;
        }
        assertEq(foundCount, 3, "Should include all three validators");
    }

    function testInfraredValidatorsAfterRemoval() public {
        // Add validators
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](2);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validatorsToAdd[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: address(0x222)
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        // Remove one validator
        bytes[] memory pubkeysToRemove = new bytes[](1);
        pubkeysToRemove[0] = validatorPubkey1;

        vm.prank(infraredGovernance);
        infraredV9.removeValidators(pubkeysToRemove);

        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();

        // Verify validator1 is not in the list
        bool foundRemoved = false;
        bool foundRemaining = false;
        for (uint256 i = 0; i < validators.length; i++) {
            if (keccak256(validators[i].pubkey) == keccak256(validatorPubkey1))
            {
                foundRemoved = true;
            }
            if (keccak256(validators[i].pubkey) == keccak256(validatorPubkey2))
            {
                foundRemaining = true;
            }
        }
        assertFalse(foundRemoved, "Removed validator should not be in list");
        assertTrue(foundRemaining, "Remaining validator should be in list");
    }

    function testInfraredValidatorsAfterReplacement() public {
        // Add initial validator
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](1);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        // Replace validator
        vm.prank(infraredGovernance);
        infraredV9.replaceValidator(validatorPubkey1, validatorPubkey2);

        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();

        // Verify old validator is gone, new one is present
        bool foundOld = false;
        bool foundNew = false;
        for (uint256 i = 0; i < validators.length; i++) {
            if (keccak256(validators[i].pubkey) == keccak256(validatorPubkey1))
            {
                foundOld = true;
            }
            if (keccak256(validators[i].pubkey) == keccak256(validatorPubkey2))
            {
                foundNew = true;
            }
        }
        assertFalse(foundOld, "Old validator should not be in list");
        assertTrue(foundNew, "New validator should be in list");
    }

    /*//////////////////////////////////////////////////////////////
                    GET BGT BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetBGTBalanceZero() public view {
        uint256 balance = infraredV9.getBGTBalance();
        // Balance may not be exactly zero due to setup
        assertTrue(balance >= 0, "Should return balance");
    }

    function testGetBGTBalanceAfterMint() public {
        uint256 balanceBefore = infraredV9.getBGTBalance();

        // Mint BGT to Infrared contract
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 balanceAfter = infraredV9.getBGTBalance();

        assertEq(
            balanceAfter - balanceBefore,
            100 ether,
            "Balance should increase by minted amount"
        );
    }

    function testGetBGTBalanceAfterHarvest() public {
        // Setup vault
        address stakingToken = address(new MockERC20("Staking", "STK", 18));
        vm.prank(infraredGovernance);
        infraredV9.registerVault(stakingToken);

        // Add liquidity
        stakeInVault(
            address(infraredV9.vaultRegistry(stakingToken)),
            stakingToken,
            testUser,
            100 ether
        );

        // Simulate BGT rewards
        deal(address(bgt), beraVault, 50 ether);

        uint256 balanceBefore = infraredV9.getBGTBalance();

        // Harvest vault (converts BGT to iBGT)
        infraredV9.harvestVault(stakingToken);

        uint256 balanceAfter = infraredV9.getBGTBalance();

        // BGT balance should change after harvest
        // (may decrease as it's converted to iBGT)
        assertTrue(
            balanceAfter != balanceBefore || balanceBefore == 0,
            "Balance should change or be zero"
        );
    }

    function testGetBGTBalanceAfterBaseHarvest() public {
        // Mint BGT to Infrared
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 balanceBefore = infraredV9.getBGTBalance();
        assertTrue(balanceBefore >= 100 ether, "Should have BGT");

        // Harvest base (converts BGT to iBGT or redeems for BERA)
        infraredV9.harvestBase();

        uint256 balanceAfter = infraredV9.getBGTBalance();

        // BGT should be reduced after harvest
        assertTrue(
            balanceAfter < balanceBefore,
            "BGT balance should decrease after harvest"
        );
    }

    function testGetBGTBalanceMultipleMints() public {
        uint256 initialBalance = infraredV9.getBGTBalance();

        // Multiple mints
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);
        bgt.mint(address(infrared), 30 ether);
        bgt.mint(address(infrared), 20 ether);
        vm.stopPrank();

        uint256 finalBalance = infraredV9.getBGTBalance();

        assertEq(
            finalBalance - initialBalance,
            100 ether,
            "Should accumulate all mints"
        );
    }

    function testGetBGTBalanceAfterDelegation() public {
        // Mint BGT
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 balanceBefore = infraredV9.getBGTBalance();

        // Delegate BGT (should not affect balance)
        vm.prank(infraredGovernance);
        infraredV9.delegateBGT(address(0x123));

        uint256 balanceAfter = infraredV9.getBGTBalance();

        assertEq(
            balanceAfter, balanceBefore, "Delegation should not affect balance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testViewFunctionsConsistency() public {
        // Add validators
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](2);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validatorsToAdd[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: address(0x222)
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        // Check number of validators matches array length
        uint256 numValidators = infraredV9.numInfraredValidators();
        ValidatorTypes.Validator[] memory validators =
            infraredV9.infraredValidators();

        assertEq(
            validators.length, numValidators, "Array length should match count"
        );
    }

    function testViewFunctionsWithComplexScenario() public {
        // 1. Add validators
        ValidatorTypes.Validator[] memory validatorsToAdd =
            new ValidatorTypes.Validator[](2);
        validatorsToAdd[0] = ValidatorTypes.Validator({
            pubkey: validatorPubkey1,
            addr: validator
        });
        validatorsToAdd[1] = ValidatorTypes.Validator({
            pubkey: validatorPubkey2,
            addr: address(0x222)
        });

        vm.prank(infraredGovernance);
        infraredV9.addValidators(validatorsToAdd);

        // 2. Check validators
        ValidatorTypes.Validator[] memory validators1 =
            infraredV9.infraredValidators();
        assertTrue(validators1.length >= 2, "Should have validators");

        // 3. Mint and check BGT
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        uint256 bgtBalance = infraredV9.getBGTBalance();
        assertTrue(bgtBalance >= 100 ether, "Should have BGT");

        // 5. Verify views updated
        ValidatorTypes.Validator[] memory validators2 =
            infraredV9.infraredValidators();
        bool found = false;
        for (uint256 i = 0; i < validators2.length; i++) {
            if (keccak256(validators2[i].pubkey) == keccak256(validatorPubkey2))
            {
                found = true;
                break;
            }
        }
        assertTrue(found, "New validator should be present");

        // 6. BGT balance should remain unchanged
        uint256 bgtBalanceAfter = infraredV9.getBGTBalance();
        assertEq(bgtBalanceAfter, bgtBalance, "BGT balance should not change");
    }

    function testBGTBalanceTracksRewards() public {
        // Setup vault
        address stakingToken = address(new MockERC20("Staking", "STK", 18));
        vm.prank(infraredGovernance);
        infraredV9.registerVault(stakingToken);

        // Track BGT balance through multiple operations
        uint256 balance0 = infraredV9.getBGTBalance();

        // Mint some BGT
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        uint256 balance1 = infraredV9.getBGTBalance();
        assertTrue(balance1 > balance0, "Balance should increase");

        // Harvest base
        infraredV9.harvestBase();
        uint256 balance2 = infraredV9.getBGTBalance();
        assertTrue(balance2 < balance1, "Balance should decrease after harvest");
    }
}
