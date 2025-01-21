// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

//external

import {Helper, IAccessControl, IInfrared} from "./Helper.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {Errors} from "src/utils/Errors.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

contract InfraredInitializationTest is Helper {
    /*//////////////////////////////////////////////////////////////
                Initialization and Setup Tests
    //////////////////////////////////////////////////////////////*/

    function testInitializationParameters() public view {
        assertEq(
            address(infrared.ibgt()),
            address(ibgt),
            "Incorrect InfraredBGT address"
        );

        assertEq(
            address(infrared.rewardsFactory()),
            address(factory),
            "Incorrect Bera Chain Rewards Factory address"
        );
        // assertEq(     // TODO: wait until the distribution contract is implemented
        //     address(infrared.distributionPrecompile()),
        //     address(distribution),
        //     "Incorrect Distribution Precompile address"
        // );
        assertEq(
            address(infrared.wbera()), address(wbera), "Incorrect Wbera address"
        );

        assertTrue(
            infrared.hasRole(infrared.DEFAULT_ADMIN_ROLE(), infraredGovernance),
            "Incorrect Admin address"
        );
        assertEq(
            infrared.rewardsDuration(), 1 days, "Incorrect rewards duration"
        );
    }

    function testRoleAssignments() public view {
        assertTrue(
            infrared.hasRole(infrared.DEFAULT_ADMIN_ROLE(), infraredGovernance),
            "Admin should have DEFAULT_ADMIN_ROLE"
        );
        assertTrue(
            infrared.hasRole(infrared.KEEPER_ROLE(), keeper),
            "Keeper should have KEEPER_ROLE"
        );
        assertTrue(
            infrared.hasRole(infrared.GOVERNANCE_ROLE(), infraredGovernance),
            "Governance should have GOVERNANCE_ROLE"
        );
    }

    function testFailRoleAssignmentsUnauthorizedAccess() public {
        // Trying to access a role with an unauthorized address
        address unauthorizedUser = address(3);

        // Expecting a revert when unauthorizedUser tries to access a role-specific function
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.KEEPER_ROLE()
            )
        );
        infrared.registerVault(address(stakingAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.KEEPER_ROLE()
            )
        );
        // infrared.harvestValidator(address(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.updateWhiteListedRewardTokens(address(12345), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.updateRewardsDuration(2 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.toggleVault(address(infraredVault));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.recoverERC20(address(12345), address(this), 100);
    }

    function testUpdateWhiteListedRewardTokens() public {
        vm.expectEmit();
        emit IInfrared.WhiteListedRewardTokensUpdated(
            infraredGovernance, address(12345), false, true
        );
        // Update the whitelist
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(12345), true);

        // Check that the whitelist was updated
        assertTrue(
            infrared.whitelistedRewardTokens(address(12345)),
            "Wbera should be whitelisted"
        );
    }

    function testUpdateRewardsDuration() public {
        vm.expectEmit();
        emit IInfrared.RewardsDurationUpdated(
            infraredGovernance, infrared.rewardsDuration(), 123
        );
        // Update the rewards duration
        vm.prank(infraredGovernance);
        infrared.updateRewardsDuration(123);

        // Check that the rewards duration was updated
        assertEq(
            infrared.rewardsDuration(), 123, "Rewards duration not updated"
        );
    }

    function testUpdateRewardsDurationForVault() public {
        // Set up initial conditions
        address stakingToken = address(wbera);
        address rewardsToken = address(ibgt);
        uint256 newRewardsDuration = 2 days;

        // Update the rewards duration for the vault
        vm.expectEmit(true, true, true, true, address(infraredVault));
        emit IMultiRewards.RewardsDurationUpdated(
            rewardsToken, newRewardsDuration
        );
        vm.prank(infraredGovernance);
        infrared.updateRewardsDurationForVault(
            stakingToken, rewardsToken, newRewardsDuration
        );

        // Verify that the rewards duration was updated
        (, uint256 updatedRewardsDuration,,,,,) =
            infraredVault.rewardData(rewardsToken);
        assertEq(
            updatedRewardsDuration,
            newRewardsDuration,
            "Rewards duration not updated correctly"
        );

        // Test unauthorized access
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(666),
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(address(666));
        infrared.updateRewardsDurationForVault(stakingToken, rewardsToken, 0);

        // Test for zero rewards duration
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(infraredGovernance);
        infrared.updateRewardsDurationForVault(stakingToken, rewardsToken, 0);

        // Test for unsupported vault
        address unsupportedStakingToken = address(0x123);
        vm.expectRevert(Errors.NoRewardsVault.selector);
        vm.prank(infraredGovernance);
        infrared.updateRewardsDurationForVault(
            unsupportedStakingToken, rewardsToken, newRewardsDuration
        );

        // Test for non-whitelisted reward token
        address nonWhitelistedToken = address(0x456);
        vm.expectRevert(Errors.RewardTokenNotWhitelisted.selector);
        vm.prank(infraredGovernance);
        infrared.updateRewardsDurationForVault(
            stakingToken, nonWhitelistedToken, newRewardsDuration
        );
    }

    function testRewardsStorageLayout() public {
        // Get base slot from contract
        bytes32 baseSlot = infrared.REWARDS_STORAGE_LOCATION();

        // Test Slot 9 in separate function testRewardsStorageLayoutSlot9();

        // Test redMintRate (slot 10)
        uint256 testRate = 500_000;
        vm.prank(infraredGovernance);
        infrared.updateIRMintRate(testRate);
        assertEq(
            uint256(vm.load(address(infrared), bytes32(uint256(baseSlot) + 1))),
            testRate,
            "redMintRate slot mismatch"
        );

        // Test collectBribesWeight (slot 12)
        uint256 testWeight = 5000;
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribesWeight(testWeight);
        assertEq(
            uint256(vm.load(address(infrared), bytes32(uint256(baseSlot) + 2))),
            testWeight,
            "collectBribesWeight slot mismatch"
        );
    }

    function testRewardsStorageLayoutSlot9() public {
        bytes32 baseSlot = infrared.REWARDS_STORAGE_LOCATION();

        // Test fees mapping for all fee types
        uint256[] memory testFees = new uint256[](8);
        testFees[0] = 1000; // 10% for operator fee
        testFees[1] = 2000; // 20% for operator protocol
        testFees[2] = 500; // 5% for vault fee
        testFees[3] = 1500; // 15% for vault protocol
        testFees[4] = 800; // 8% for bribes fee
        testFees[5] = 1200; // 12% for bribes protocol
        testFees[6] = 300; // 3% for boost fee
        testFees[7] = 700; // 7% for boost protocol

        // Set and verify each fee type
        for (uint256 i = 0; i < 8; i++) {
            ConfigTypes.FeeType feeType = ConfigTypes.FeeType(i);

            // Set the fee
            vm.prank(infraredGovernance);
            infrared.updateFee(feeType, testFees[i]);

            // Calculate the slot for this fee in the mapping
            bytes32 feeSlot = keccak256(abi.encode(i, uint256(baseSlot) + 3));

            // Verify the stored value
            assertEq(
                uint256(vm.load(address(infrared), feeSlot)),
                testFees[i],
                string.concat("Fee mismatch for type ", getFeeTypeName(feeType))
            );

            // Double verify through the public getter
            assertEq(
                infrared.fees(i),
                testFees[i],
                string.concat(
                    "Public getter mismatch for type ", getFeeTypeName(feeType)
                )
            );
        }
    }

    // Helper function to get fee type names for error messages
    function getFeeTypeName(ConfigTypes.FeeType feeType)
        internal
        pure
        returns (string memory)
    {
        if (feeType == ConfigTypes.FeeType.HarvestOperatorFeeRate) {
            return "HarvestOperatorFeeRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestOperatorProtocolRate) {
            return "HarvestOperatorProtocolRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestVaultFeeRate) {
            return "HarvestVaultFeeRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestVaultProtocolRate) {
            return "HarvestVaultProtocolRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestBribesFeeRate) {
            return "HarvestBribesFeeRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestBribesProtocolRate) {
            return "HarvestBribesProtocolRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestBoostFeeRate) {
            return "HarvestBoostFeeRate";
        }
        if (feeType == ConfigTypes.FeeType.HarvestBoostProtocolRate) {
            return "HarvestBoostProtocolRate";
        }
        return "Unknown";
    }

    // Helper function for clarity
    function getStructSlot(bytes32 baseSlot, uint256 offset)
        public
        pure
        returns (bytes32)
    {
        return bytes32(uint256(baseSlot) + offset);
    }

    function testValidatorStorageLayout() public {
        bytes32 baseSlot = infrared.VALIDATOR_STORAGE_LOCATION();

        // Add a validator to test EnumerableSet storage
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            addr: address(888),
            pubkey: bytes("somePubKey")
        });

        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // For EnumerableSet.Bytes32Set, we need to:
        // 1. Find the array's length slot (the base slot of _values array in the inner Set)
        // 2. Find where the values are stored (keccak256 of the length slot)

        // The _values array length is at the first slot
        bytes32 valuesArraySlot = bytes32(uint256(baseSlot));
        uint256 length = uint256(vm.load(address(infrared), valuesArraySlot));
        assertEq(length, 1, "validator set length mismatch");

        // The array values start at keccak256(slot)
        bytes32 valuesStorageSlot = keccak256(abi.encode(valuesArraySlot));
        bytes32 firstValue = vm.load(address(infrared), valuesStorageSlot);

        // First value should be the hash of our validator's pubkey
        assertEq(
            firstValue, keccak256(validators[0].pubkey), "validator id mismatch"
        );

        // Check the positions mapping
        // The mapping is at slot baseSlot + 1
        bytes32 positionsSlot = bytes32(uint256(baseSlot) + 1);
        bytes32 positionKey = keccak256(
            abi.encode(keccak256(validators[0].pubkey), positionsSlot)
        );

        // Position should be 1 (index + 1)
        assertEq(
            uint256(vm.load(address(infrared), positionKey)),
            1,
            "validator position mismatch"
        );

        // Verify through the public interface as well
        assertTrue(
            infrared.isInfraredValidator(validators[0].pubkey),
            "validator not found through public interface"
        );
    }

    function testVaultStorageLayout() public {
        bytes32 baseSlot = infrared.VAULT_STORAGE_LOCATION();

        // Test pausedVaultRegistration bool (slot 0)
        assertEq(
            uint256(vm.load(address(infrared), baseSlot)),
            0, // Should be false by default
            "vault registration should not be paused"
        );

        // vaultRegistry mapping is at slot 1
        address testAsset = address(wbera);
        bytes32 vaultSlot =
            keccak256(abi.encode(testAsset, uint256(baseSlot) + 1));
        assertEq(
            address(uint160(uint256(vm.load(address(infrared), vaultSlot)))),
            address(infraredVault),
            "vault registry mapping mismatch"
        );

        // whitelistedRewardTokens EnumerableSet.AddressSet is at slot 2
        bytes32 whitelistSetSlot = bytes32(uint256(baseSlot) + 2);

        // Check initial whitelisted tokens (we know wbera, ibgt, and honey are whitelisted in setUp)
        uint256 whitelistLength =
            uint256(vm.load(address(infrared), whitelistSetSlot));
        assertEq(whitelistLength, 3, "whitelist length mismatch");

        // Verify the whitelisted tokens
        address[] memory expectedTokens = new address[](3);
        expectedTokens[0] = address(wbera);
        expectedTokens[1] = address(ibgt);
        expectedTokens[2] = address(honey);

        for (uint256 i = 0; i < expectedTokens.length; i++) {
            // Check through public interface
            assertTrue(
                infrared.whitelistedRewardTokens(expectedTokens[i]),
                string.concat(
                    "token should be whitelisted: ",
                    vm.toString(expectedTokens[i])
                )
            );

            // Check positions mapping (at slot 3)
            bytes32 positionsSlot = bytes32(uint256(whitelistSetSlot) + 1);
            bytes32 positionKey = keccak256(
                abi.encode(
                    bytes32(uint256(uint160(expectedTokens[i]))), positionsSlot
                )
            );
            assertTrue(
                uint256(vm.load(address(infrared), positionKey)) > 0,
                string.concat(
                    "token should have position: ",
                    vm.toString(expectedTokens[i])
                )
            );
        }

        // Test rewardsDuration (slot 4)
        assertEq(
            uint256(vm.load(address(infrared), bytes32(uint256(baseSlot) + 4))),
            1 days, // Set in initialize()
            "rewards duration mismatch"
        );

        // Test updating values

        // Test pausing vault registration
        vm.prank(infraredGovernance);
        infrared.setVaultRegistrationPauseStatus(true);
        assertEq(
            uint256(vm.load(address(infrared), baseSlot)),
            1, // Should be true now
            "vault registration should be paused"
        );

        // Test updating rewards duration
        uint256 newDuration = 2 days;
        vm.prank(infraredGovernance);
        infrared.updateRewardsDuration(newDuration);
        assertEq(
            uint256(vm.load(address(infrared), bytes32(uint256(baseSlot) + 4))),
            newDuration,
            "updated rewards duration mismatch"
        );

        // Test adding new whitelisted token
        address newToken = address(0x123);
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(newToken, true);

        // Verify updated whitelist length
        assertEq(
            uint256(vm.load(address(infrared), whitelistSetSlot)),
            4,
            "updated whitelist length mismatch"
        );

        // Verify through public interface
        assertTrue(
            infrared.whitelistedRewardTokens(newToken),
            "new token should be whitelisted"
        );
    }
}
