// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "lib/contracts/src/pol/interfaces/IRewardVault.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";

/// @title BatchClaimerV2_1
/// @notice Enables batch claiming of rewards for multiple staking assets for a given user.
/// @dev This contract interacts with the InfraredV1_5 contract and InfraredVaults to claim rewards.
contract BatchClaimerV2_1 {
    /// @notice Reference to the InfraredV1_5 contract used to fetch vaults and manage reward claims.
    InfraredV1_5 internal constant infrared =
        InfraredV1_5(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));

    ERC4626 public constant wBYUSD =
        ERC4626(0x334404782aB67b4F6B2A619873E579E971f9AAB7);

    /// @notice IBerachainRewardsVaultFactory instance of the rewards factory contract address
    IBerachainRewardsVaultFactory internal immutable rewardsFactory;

    /// @notice Error indicating the provided address was the zero address.
    error ZeroAddress();

    /// @notice Error indicating that the provided inputs are invalid (e.g., empty array).
    error InvalidInputs();

    constructor() {
        rewardsFactory =
            IBerachainRewardsVaultFactory(infrared.rewardsFactory());
    }

    /// @notice Allows batch claiming of staking rewards from multiple vaults for a user.
    /// @param user The address of the user for whom rewards are to be claimed.
    /// @param stakingAssets An array of addresses representing staking asset vaults to process.
    /// @dev This function iterates over the stakingAssets array and attempts to:
    /// - Claim rewards from the InfraredVault if it exists.
    /// - Claim external vault rewards if available.
    function batchClaim(address user, address[] calldata stakingAssets)
        external
    {
        if (user == address(0)) revert ZeroAddress();
        uint256 lenAssets = stakingAssets.length;
        if (lenAssets == 0) revert InvalidInputs();

        for (uint256 i; i < lenAssets; i++) {
            // check infrared and berachain vaults
            IInfraredVault infraVault = infrared.vaultRegistry(stakingAssets[i]);
            if (address(infraVault) != address(0)) {
                infraVault.getRewardForUser(user);
            }
            // check external reward claims
            IBerachainRewardsVault vault = IBerachainRewardsVault(
                rewardsFactory.getVault(stakingAssets[i])
            );
            if (
                address(vault) != address(0)
                    && vault.operator(user) == address(infrared)
            ) {
                if (infrared.externalVaultRewards(stakingAssets[i], user) > 0) {
                    infrared.claimExternalVaultRewards(stakingAssets[i], user);
                }
            }
        }
        // special case for wBYUSD, auto unwrap if approved
        uint256 wbyusdBal = wBYUSD.balanceOf(user);
        if (wBYUSD.previewRedeem(wbyusdBal) > 0) {
            uint256 wbyusdAllowance = wBYUSD.allowance(user, address(this));
            if (wbyusdAllowance >= wbyusdBal) {
                wBYUSD.redeem(wbyusdBal, user, user);
            }
        }
    }
}
