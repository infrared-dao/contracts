// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helper, IAccessControl, IInfraredVault, MockERC20} from "./Helper.sol";
import {Errors} from "src/utils/Errors.sol";

contract InfraredRegisterVaultTest is Helper {
    /*//////////////////////////////////////////////////////////////
                Vault Registration Tests (registerVault)
    //////////////////////////////////////////////////////////////*/
    function testSuccessfulVaultRegistration() public {
        stakingAsset = address(ir); // Assuming you have a mock iRED token

        // Mock data for the test
        address[] memory _rewardTokens = new address[](2); // Assuming you have reward token addresses
        _rewardTokens[0] = address(ibgt);
        _rewardTokens[1] = address(ir);

        /*
        // Expect the NewVault event to be emitted with correct parameters
        vm.expectEmit();
        emit IInfrared.NewVault(
            address(this), stakingAsset, expectedNewVaultAddress, _rewardTokens
        );
        */

        // Register the vault and capture the return value
        IInfraredVault newVault = infrared.registerVault(stakingAsset);
        address newVaultAddress = address(newVault);

        // Validate that the returned vault address matches the expected new vault address
        assertEq(
            address(newVault), newVaultAddress, "Vault not registered correctly"
        );

        // Validate that the vault is correctly registered in the vaultRegistry with the asset address
        assertEq(
            address(infrared.vaultRegistry(stakingAsset)),
            newVaultAddress,
            "Vault registry does not contain the new vault under the asset address"
        );
    }

    function testFailVaultRegistrationWithZeroAsset() public {
        // Define reward tokens assuming you have them set up for the test
        address[] memory _rewardTokens = new address[](1); // Modify as per your test setup
        _rewardTokens[0] = address(ir); // Example reward token address

        // Expect a revert due to passing a zero asset address to registerVault
        vm.expectRevert(Errors.ZeroAddress.selector);
        try infrared.registerVault(address(0)) {
            revert("Zero address should revert");
        } catch {
            revert();
        }
    }

    function testFailVaultRegistrationWithInvalid_rewardTokens() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MAS", 18); // Mock asset token
        // Setup for the asset and reward tokens
        address assetAddress = address(mockAsset); // Your mock asset address
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0); // Assuming zero address is an unsupported reward token

        // Pre-define the reward tokens as unsupported in your contract setup or mock accordingly
        // This step depends on your contract's logic for whitelisting reward tokens

        // Expect a revert due to invalid (unsupported) reward tokens
        vm.expectRevert(Errors.RewardTokenNotSupported.selector);
        infrared.registerVault(assetAddress);
        vm.expectRevert(Errors.RewardTokenNotSupported.selector);
    }

    function testFailVaultRegistrationDuplicateAsset() public {
        address[] memory _rewardTokens; // Assuming you've defined _rewardTokens somewhere
        _rewardTokens[0] = address(ibgt); // Example reward token address
        _rewardTokens[1] = address(ir);

        // Because stakingAsset is already registered, expect a revert
        vm.expectRevert(Errors.DuplicateAssetAddress.selector);
        infrared.registerVault(address(stakingAsset));
    }

    function testRolePersistencePostVaultRegistration() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MAS", 18);
        // Prepare the reward tokens array; assuming it's already initialized and filled as needed
        address[] memory _rewardTokens = new address[](2); // example initialization
        _rewardTokens[0] = address(ibgt); // Assuming mockRewardToken has been defined elsewhere
        _rewardTokens[1] = address(ir);

        // Register the vault without specifying a pool address, adhering to the updated function signature
        infrared.registerVault(address(mockAsset));

        // Assert that the test contract still holds the KEEPER_ROLE after registering the vault
        assertTrue(
            infrared.hasRole(infrared.KEEPER_ROLE(), keeper),
            "Keeper role should persist post registration"
        );
    }

    function testRecoverERC20FromVault() public {
        testSuccessfulVaultRegistration();
        address vault = address(infrared.vaultRegistry(address(stakingAsset)));
        address token = address(honey);
        uint256 amount = 1000;
        uint256 balanceBefore = honey.balanceOf(vault);
        assertEq(balanceBefore, 0);
        honey.mint(vault, amount);
        vm.prank(infraredGovernance);
        infrared.recoverERC20FromVault(
            address(stakingAsset), address(this), token, amount
        );
        uint256 balanceAfter = honey.balanceOf(vault);
        assertEq(balanceAfter, 0);
        uint256 balanceReceiver = honey.balanceOf(address(this));
        assertEq(balanceReceiver, amount);
    }
}
