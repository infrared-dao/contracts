// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {InfraredV1_9} from "src/core/upgrades/InfraredV1_9.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "lib/contracts/src/pol/interfaces/IRewardVault.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";

/// @title BatchClaimerV2_2
/// @notice Enables batch claiming of rewards for multiple staking assets for a given user.
/// @dev This contract interacts with the InfraredV1_9 contract and InfraredVaults to claim rewards.
/// @dev This contract is upgradeable using the UUPS proxy pattern.
contract BatchClaimerV2_2 is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @notice Reference to the InfraredV1_9 contract used to fetch vaults and manage reward claims.
    InfraredV1_9 internal constant infrared =
        InfraredV1_9(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));

    /// @notice wBYUSD ERC4626 vault constant
    ERC4626 public constant wBYUSD =
        ERC4626(0x334404782aB67b4F6B2A619873E579E971f9AAB7);

    /// @notice IBerachainRewardsVaultFactory instance of the rewards factory contract address
    /// @dev Changed from immutable to storage variable for upgradeability
    IBerachainRewardsVaultFactory public rewardsFactory;

    /// @notice wiBGT ERC4626 wrapper for iBGT
    ERC4626 public wiBGT;

    /// @notice Error indicating the provided address was the zero address.
    error ZeroAddress();

    /// @notice Error indicating that the provided inputs are invalid (e.g., empty array).
    error InvalidInputs();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The address of the contract owner
    /// @param _wibgt The address of wrapped ibgt contract
    /// @dev This function replaces the constructor for upgradeable contracts
    function initialize(address _owner, address _wibgt) public initializer {
        if (_owner == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        rewardsFactory =
            IBerachainRewardsVaultFactory(infrared.rewardsFactory());
        wiBGT = ERC4626(_wibgt);
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
        // special case for wiBGT, auto unwrap if approved
        uint256 wibgtBal = wiBGT.balanceOf(user);
        if (wiBGT.previewRedeem(wibgtBal) > 0) {
            uint256 wibgtAllowance = wiBGT.allowance(user, address(this));
            if (wibgtAllowance >= wibgtBal) {
                wiBGT.redeem(wibgtBal, user, user);
            }
        }
    }

    /// @notice Updates the rewards factory address
    /// @param _newRewardsFactory The new rewards factory address
    /// @dev Only callable by the owner
    function updateRewardsFactory(address _newRewardsFactory)
        external
        onlyOwner
    {
        if (_newRewardsFactory == address(0)) revert ZeroAddress();
        rewardsFactory = IBerachainRewardsVaultFactory(_newRewardsFactory);
    }

    /// @notice Required by UUPSUpgradeable to authorize upgrades
    /// @param newImplementation Address of the new implementation
    /// @dev Only the owner can authorize upgrades
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @notice Returns the current version of the contract
    /// @return The version string
    function version() external pure returns (string memory) {
        return "2.2.0";
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps
     */
    uint256[49] private __gap;
}
