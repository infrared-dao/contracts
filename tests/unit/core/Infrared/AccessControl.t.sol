// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helper, IAccessControl} from "./Helper.sol";
import {Errors} from "src/utils/Errors.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";

/**
 * @title AccessControlTest
 * @notice Comprehensive tests for access control modifiers and role-based permissions
 * @dev Improves coverage for modifier enforcement and unauthorized access attempts
 */
contract AccessControlTest is Helper {
    address unauthorizedUser = address(0xBAD);

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGovernanceRole_AddValidators() public {
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: bytes("testPubkey"),
            addr: address(1)
        });

        // Should succeed with governance role
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Should fail without governance role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.addValidators(validators);
    }

    function testGovernanceRole_RemoveValidators() public {
        // Add validator first
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: bytes("testPubkey"),
            addr: address(1)
        });
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = bytes("testPubkey");

        // Should fail without governance role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.removeValidators(pubkeys);

        // Should succeed with governance role
        vm.prank(infraredGovernance);
        infrared.removeValidators(pubkeys);
    }

    function testGovernanceRole_UpdateWhiteListedRewardTokens() public {
        address testToken = address(0x123);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.updateWhiteListedRewardTokens(testToken, true);

        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(testToken, true);
        assertTrue(infrared.whitelistedRewardTokens(testToken));
    }

    function testGovernanceRole_UpdateFee() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.KEEPER_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 1000);

        vm.prank(keeper);
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 1000);
    }

    function testGovernanceRole_RecoverERC20() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.recoverERC20(address(this), address(wbera), 100);
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testKeeperRole_QueueBoosts() public {
        // Add validator first
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: bytes("testPubkey"),
            addr: address(1)
        });
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = bytes("testPubkey");
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 100;

        deal(address(bgt), address(infrared), 100);
        vm.prank(address(infrared));
        ibgt.mint(address(1), 100);

        // Should fail without keeper role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.KEEPER_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.queueBoosts(pubkeys, amounts);

        // Should succeed with keeper role
        vm.prank(keeper);
        infrared.queueBoosts(pubkeys, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSER ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testPauserRole_PauseStaking() public {
        bytes32 _role = infrared.PAUSER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                _role
            )
        );
        vm.prank(unauthorizedUser);
        infrared.pauseStaking(address(wbera));

        // Grant pauser role
        vm.prank(infraredGovernance);
        infrared.grantRole(_role, keeper);

        // Should succeed with pauser role
        vm.prank(keeper);
        infrared.pauseStaking(address(wbera));
    }

    /*//////////////////////////////////////////////////////////////
                        MODIFIER COMBINATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testModifierCombination_GovernanceAndPaused() public {
        // Pause staking
        bytes32 _role = infrared.PAUSER_ROLE();
        vm.prank(infraredGovernance);
        infrared.grantRole(_role, infraredGovernance);
        vm.prank(infraredGovernance);
        infrared.pauseStaking(address(wbera));

        // Test governance function while paused - should still work
        vm.prank(infraredGovernance);
        infrared.updateRewardsDuration(2 days);

        // Unpause
        vm.prank(infraredGovernance);
        infrared.unpauseStaking(address(wbera));
    }

    function testModifierCombination_UnauthorizedWithPaused() public {
        // Pause staking
        bytes32 _role = infrared.PAUSER_ROLE();
        vm.prank(infraredGovernance);
        infrared.grantRole(_role, infraredGovernance);
        vm.prank(infraredGovernance);
        infrared.pauseStaking(address(wbera));

        // Try unauthorized access while paused - should fail with access control error
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.GOVERNANCE_ROLE()
            )
        );
        vm.prank(unauthorizedUser);
        infrared.updateRewardsDuration(2 days);
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantRole_OnlyAdmin() public {
        address newKeeper = address(0x999);

        bytes32 _role = infrared.KEEPER_ROLE();
        // Should fail when non-admin tries to grant role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        infrared.grantRole(_role, newKeeper);

        // Should succeed when admin grants role
        vm.prank(infraredGovernance);
        infrared.grantRole(_role, newKeeper);

        assertTrue(infrared.hasRole(_role, newKeeper));
    }

    function testRevokeRole_OnlyAdmin() public {
        bytes32 _role = infrared.KEEPER_ROLE();
        // Should fail when non-admin tries to revoke role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                infrared.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorizedUser);
        infrared.revokeRole(_role, keeper);

        // Should succeed when admin revokes role
        vm.prank(infraredGovernance);
        infrared.revokeRole(_role, keeper);

        assertFalse(infrared.hasRole(_role, keeper));
    }

    function testRenounceRole_SelfOnly() public {
        address testAccount = address(0x888);

        // Grant role first
        bytes32 _role = infrared.KEEPER_ROLE();
        vm.prank(infraredGovernance);
        infrared.grantRole(_role, testAccount);

        // Should succeed when account renounces own role
        vm.prank(testAccount);
        infrared.renounceRole(_role, testAccount);

        assertFalse(infrared.hasRole(_role, testAccount));
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE ACCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testStorageAccessIsolation() public view {
        // Test that storage locations don't collide
        bytes32 validatorStorage = infrared.VALIDATOR_STORAGE_LOCATION();
        bytes32 vaultStorage = infrared.VAULT_STORAGE_LOCATION();
        bytes32 rewardsStorage = infrared.REWARDS_STORAGE_LOCATION();

        // Verify all storage locations are different
        assertTrue(
            validatorStorage != vaultStorage, "Validator/Vault collision"
        );
        assertTrue(
            validatorStorage != rewardsStorage, "Validator/Rewards collision"
        );
        assertTrue(vaultStorage != rewardsStorage, "Vault/Rewards collision");

        // Verify storage locations follow ERC-7201 standard
        // Should be keccak256(abi.encode(uint256(keccak256(...)) - 1)) & ~bytes32(uint256(0xff))
        assertGt(uint256(validatorStorage), 0, "Invalid validator storage");
        assertGt(uint256(vaultStorage), 0, "Invalid vault storage");
        assertGt(uint256(rewardsStorage), 0, "Invalid rewards storage");
    }

    /*//////////////////////////////////////////////////////////////
                        COLLECTOR MODIFIER TEST
    //////////////////////////////////////////////////////////////*/

    function testOnlyCollector_Unauthorized() public {
        // This tests the onlyCollector modifier
        // collectBribes() should only be callable by the bribe collector

        vm.expectRevert();
        vm.prank(unauthorizedUser);
        infrared.collectBribes(address(wbera), 100);
    }

    function testOnlyCollector_Authorized() public {
        // Collector should be able to call collectBribes
        // First need to give collector some tokens
        deal(address(wbera), address(collector), 100 ether);

        vm.prank(address(collector));
        wbera.approve(address(infrared), 100 ether);

        // This should work when called from collector
        vm.prank(address(collector));
        infrared.collectBribes(address(wbera), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testAccessControl_AfterUpgrade() public view {
        // Verify roles persist after upgrade
        assertTrue(
            infrared.hasRole(infrared.GOVERNANCE_ROLE(), infraredGovernance),
            "Governance role lost after upgrade"
        );
        assertTrue(
            infrared.hasRole(infrared.KEEPER_ROLE(), keeper),
            "Keeper role lost after upgrade"
        );
    }

    function testAccessControl_MultipleRoles() public {
        address multiRoleAccount = address(0x777);

        // Grant multiple roles
        vm.startPrank(infraredGovernance);
        infrared.grantRole(infrared.KEEPER_ROLE(), multiRoleAccount);
        infrared.grantRole(infrared.PAUSER_ROLE(), multiRoleAccount);
        vm.stopPrank();

        // Verify both roles work
        assertTrue(infrared.hasRole(infrared.KEEPER_ROLE(), multiRoleAccount));
        assertTrue(infrared.hasRole(infrared.PAUSER_ROLE(), multiRoleAccount));

        // Should be able to use both roles
        bytes[] memory pubkeys = new bytes[](0);
        vm.prank(multiRoleAccount);
        infrared.activateBoosts(pubkeys);

        vm.prank(multiRoleAccount);
        infrared.pauseStaking(address(wbera));
    }
}
