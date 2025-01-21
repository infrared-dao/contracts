// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {Errors} from "src/utils/Errors.sol";
import {InfraredVaultDeployer} from "src/utils/InfraredVaultDeployer.sol";

library VaultManagerLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeTransferLib for ERC20;

    struct VaultStorage {
        bool pausedVaultRegistration;
        mapping(address => IInfraredVault) vaultRegistry; // Maps asset to its vault
        EnumerableSet.AddressSet whitelistedRewardTokens; // Set of whitelisted reward tokens
        uint256 rewardsDuration; // Default duration for rewards
    }

    /**
     * @dev Ensures that new vaults can only be registered while the register vaults are not paused
     */
    modifier notPaused(VaultStorage storage $) {
        if ($.pausedVaultRegistration) {
            revert Errors.RegistrationPaused();
        }
        _;
    }

    /// @notice Registers a new vault for a specific asset.
    function registerVault(VaultStorage storage $, address asset)
        external
        notPaused($)
        returns (address)
    {
        if (asset == address(0)) revert Errors.ZeroAddress();

        // Check for duplicate staking asset address
        if (address($.vaultRegistry[asset]) != address(0)) {
            revert Errors.DuplicateAssetAddress();
        }

        address newVault =
            InfraredVaultDeployer.deploy(asset, $.rewardsDuration);
        $.vaultRegistry[asset] = IInfraredVault(newVault);
        return newVault;
    }

    /**
     * @notice Sets new vault registration paused or not
     * @param pause True to pause, False to un pause
     */
    function setVaultRegistrationPauseStatus(VaultStorage storage $, bool pause)
        external
    {
        $.pausedVaultRegistration = pause;
    }

    /// @notice Toggles the pause status of a specific vault.
    function toggleVault(VaultStorage storage $, address asset) external {
        IInfraredVault vault = $.vaultRegistry[asset];
        if (address(vault) == address(0)) revert Errors.NoRewardsVault();

        vault.togglePause();
    }

    /// @notice Updates the whitelist status of a reward token.
    function updateWhitelistedRewardTokens(
        VaultStorage storage $,
        address token,
        bool whitelisted
    ) external {
        if (whitelisted) {
            $.whitelistedRewardTokens.add(token);
        } else {
            $.whitelistedRewardTokens.remove(token);
        }
    }

    function addReward(
        VaultStorage storage $,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        if (!isWhitelisted($, _rewardsToken)) {
            revert Errors.RewardTokenNotWhitelisted();
        }
        if (address($.vaultRegistry[_stakingToken]) == address(0)) {
            revert Errors.NoRewardsVault();
        }

        IInfraredVault vault = $.vaultRegistry[_stakingToken];
        vault.addReward(_rewardsToken, _rewardsDuration);
    }

    function addIncentives(
        VaultStorage storage $,
        address _stakingToken,
        address _rewardsToken,
        uint256 _amount
    ) external {
        if (address($.vaultRegistry[_stakingToken]) == address(0)) {
            revert Errors.NoRewardsVault();
        }

        IInfraredVault vault = $.vaultRegistry[_stakingToken];

        (
            ,
            uint256 _vaultRewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            ,
            ,
            uint256 rewardResidual
        ) = vault.rewardData(_rewardsToken);
        if (_vaultRewardsDuration == 0) {
            revert Errors.RewardTokenNotWhitelisted();
        }

        if (block.timestamp < periodFinish) {
            // enforce externally added incentives cannot reduce current rate
            // calc new reward residual
            _amount = _amount + rewardResidual;
            rewardResidual = _amount % _vaultRewardsDuration;
            _amount = _amount - rewardResidual;
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            // Calculate total and its residual
            uint256 totalAmount = _amount + leftover + rewardResidual;
            rewardResidual = totalAmount % _vaultRewardsDuration;
            // Remove residual before setting rate
            totalAmount = totalAmount - rewardResidual;
            uint256 newRewardRate = totalAmount / _vaultRewardsDuration;
            if (newRewardRate < rewardRate) {
                revert Errors.RewardRateDecreased();
            }
        }

        ERC20(_rewardsToken).safeTransferFrom(
            msg.sender, address(this), _amount
        );
        ERC20(_rewardsToken).safeApprove(address(vault), _amount);

        vault.notifyRewardAmount(_rewardsToken, _amount);
    }

    /// @notice Updates the global rewards duration for new vaults.
    function updateRewardsDuration(VaultStorage storage $, uint256 newDuration)
        external
    {
        if (newDuration == 0) revert Errors.ZeroAmount();
        $.rewardsDuration = newDuration;
    }

    /// @notice Checks if a token is whitelisted as a reward token.
    function isWhitelisted(VaultStorage storage $, address token)
        public
        view
        returns (bool)
    {
        return $.whitelistedRewardTokens.contains(token);
    }

    function recoverERC20FromVault(
        VaultStorage storage $,
        address _asset,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        if (address($.vaultRegistry[_asset]) == address(0)) {
            revert Errors.NoRewardsVault();
        }

        IInfraredVault vault = $.vaultRegistry[_asset];
        vault.recoverERC20(_to, _token, _amount);
    }

    function updateRewardsDurationForVault(
        VaultStorage storage $,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        if ($.vaultRegistry[_stakingToken] == IInfraredVault(address(0))) {
            revert Errors.NoRewardsVault();
        }
        IInfraredVault vault = $.vaultRegistry[_stakingToken];
        (, uint256 rewardsDuration,,,,,) = vault.rewardData(_rewardsToken);
        if (rewardsDuration == 0) {
            revert Errors.RewardTokenNotWhitelisted();
        }
        vault.updateRewardsDuration(_rewardsToken, _rewardsDuration);
    }

    function claimLostRewardsOnVault(VaultStorage storage $, address _asset)
        external
    {
        IInfraredVault vault = $.vaultRegistry[_asset];
        if (address(vault) == address(0)) {
            revert Errors.NoRewardsVault();
        }
        // unclaimed rewards will end up split between IBERA shareholders
        vault.getReward();
    }
}
