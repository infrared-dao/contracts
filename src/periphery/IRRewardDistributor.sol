// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {InfraredUpgradeable} from "src/core/InfraredUpgradeable.sol";
import {IInfraredV1_10 as IInfrared} from "src/interfaces/IInfraredV1_10.sol";
import {Errors} from "src/utils/Errors.sol";

/**
 * @title IRRewardDistributor
 * @notice Distributes IR emissions to Infrared vaults based on governance/keeper configured weights
 * @dev Integrates with Infrared.addIncentives() for vault reward distribution
 * @dev Maintains a list of eligible stakingTokens (added by governor) for distribution
 * @dev Mandatory minimum allocation to iBGT vault (siBGT stakers); iBGT cannot be weighted or excluded
 */
contract IRRewardDistributor is InfraredUpgradeable {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CONSTANTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Basis points denominator (100%)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Maximum iBGT vault allocation (50%)
    uint256 public constant MAX_IBGT_ALLOCATION = 5000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice IR token for rewards
    ERC20 private _irToken;

    /// @notice Start timestamp of current epoch
    uint256 public lastEpochTimestamp;

    /// @notice Total IR to distribute per epoch
    uint256 public totalRewardsPerEpoch;

    /// @notice Current epoch number
    uint256 public currentEpoch;

    /// @notice Minimum allocation to iBGT vault in basis points (e.g., 2000 = 20%)
    uint256 public minIBGTAllocation;

    /// @notice Set of excluded vaults (not eligible for distribution)
    EnumerableSet.AddressSet private _excludedVaults;

    /// @notice Set of eligible vaults (maintained by governor; excludes iBGT and excluded vaults)
    EnumerableSet.AddressSet private _eligibleVaults;

    /// @notice stakingToken => weight (basis points) - configurable by governance/keeper
    mapping(address => uint256) public defaultVaultWeights;

    /// @notice Sum of default weights
    uint256 public totalDefaultWeight;

    /// @notice Reward distribution period
    uint256 public epochDuration;

    /// @notice Accumulated undistributed rewards from previous failed distributions per vault
    mapping(address => uint256) public carryOverRewards;

    // Reserve storage space for upgrades
    uint256[40] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EVENTS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RewardsDistributed(address indexed stakingToken, uint256 amount);
    event VaultExcluded(address indexed stakingToken);
    event VaultIncluded(address indexed stakingToken);
    event EligibleVaultAdded(address indexed stakingToken);
    event EligibleVaultRemoved(address indexed stakingToken);
    event EpochStarted(
        uint256 indexed epoch, uint256 timestamp, uint256 totalRewards
    );
    event EpochFinalized(uint256 indexed epoch);
    event WeightsUpdated(address indexed stakingToken, uint256 weight);
    event RewardsPerEpochUpdated(uint256 oldAmount, uint256 newAmount);
    event EpochDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event MinIBGTAllocationUpdated(
        uint256 oldAllocation, uint256 newAllocation
    );
    event TokensRecovered(address indexed token, uint256 amount);
    event DistributionFailed(
        address indexed stakingToken, uint256 amount, bytes errorData
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERRORS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidVault();
    error InvalidAmount();
    error EpochNotEnded();
    error NoRewardsAvailable();
    error InvalidWeights();
    error NoWeightsSet();
    error InsufficientIRBalance();
    error InvalidArrayLength();
    error ZeroAddress();
    error InvalidAllocation();

    /// @notice Initialize the contract
    /// @param _infrared Infrared protocol address
    /// @param _gov Governance address
    /// @param irToken IR token address
    /// @param _minIBGTAllocation Minimum allocation to iBGT vault in basis points
    function initialize(
        address _infrared,
        address _gov,
        address irToken,
        uint256 _minIBGTAllocation
    ) external initializer {
        if (
            _infrared == address(0) || irToken == address(0)
                || _gov == address(0)
        ) {
            revert ZeroAddress();
        }
        if (_minIBGTAllocation > MAX_IBGT_ALLOCATION) {
            revert InvalidAllocation();
        }

        // grant admin access roles
        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);

        // init upgradeable components
        __InfraredUpgradeable_init(_infrared);

        _irToken = ERC20(irToken);
        lastEpochTimestamp = block.timestamp;
        currentEpoch = 1;
        minIBGTAllocation = _minIBGTAllocation;
        epochDuration = 7 days;

        emit EpochStarted(currentEpoch, block.timestamp, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Exclude a stakingToken from distribution and voting
    /// @param stakingToken The stakingToken address to exclude
    function excludeVault(address stakingToken) external virtual onlyGovernor {
        if (stakingToken == address(0)) revert InvalidVault();
        if (stakingToken == address(infrared.ibgt())) revert InvalidVault();
        if (!_excludedVaults.add(stakingToken)) revert InvalidVault();
        _eligibleVaults.remove(stakingToken);
        emit VaultExcluded(stakingToken);
    }

    /// @notice Include a previously excluded stakingToken (does not auto-add to eligible)
    /// @param stakingToken The stakingToken address to include
    function includeVault(address stakingToken) external virtual onlyGovernor {
        if (!_excludedVaults.remove(stakingToken)) revert InvalidVault();
        emit VaultIncluded(stakingToken);
    }

    /// @notice Add an eligible stakingToken for distribution (must be a valid Infrared vault)
    /// @param stakingToken The stakingToken address to add
    function addEligibleVault(address stakingToken)
        external
        virtual
        onlyGovernor
    {
        if (stakingToken == address(0)) revert InvalidVault();
        if (_excludedVaults.contains(stakingToken)) revert InvalidVault();
        if (stakingToken == address(infrared.ibgt())) revert InvalidVault();
        if (address(infrared.vaultRegistry(stakingToken)) == address(0)) {
            revert InvalidVault();
        }
        if (!_eligibleVaults.add(stakingToken)) revert InvalidVault();
        emit EligibleVaultAdded(stakingToken);
    }

    /// @notice Remove an eligible stakingToken
    /// @param stakingToken The stakingToken address to remove
    function removeEligibleVault(address stakingToken)
        external
        virtual
        onlyGovernor
    {
        if (!_eligibleVaults.remove(stakingToken)) revert InvalidVault();
        emit EligibleVaultRemoved(stakingToken);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set total rewards per epoch
    /// @param amount Total IR tokens to distribute per epoch
    function setRewardsPerEpoch(uint256 amount) external virtual onlyGovernor {
        uint256 old = totalRewardsPerEpoch;
        totalRewardsPerEpoch = amount;
        emit RewardsPerEpochUpdated(old, amount);
    }

    /// @notice Set epoch duration (time between distrubtions)
    /// @param _newDuration Duration, in seconds, between distribution events
    function setEpochDuration(uint256 _newDuration)
        external
        virtual
        onlyGovernor
    {
        if (_newDuration == 0) revert InvalidAmount();
        uint256 old = epochDuration;
        epochDuration = _newDuration;
        emit EpochDurationUpdated(old, _newDuration);
    }

    /// @notice Set minimum iBGT vault allocation
    /// @param allocation Minimum allocation in basis points (max 50%)
    function setMinIBGTAllocation(uint256 allocation)
        external
        virtual
        onlyGovernor
    {
        if (allocation > MAX_IBGT_ALLOCATION) revert InvalidAllocation();
        uint256 old = minIBGTAllocation;
        minIBGTAllocation = allocation;
        emit MinIBGTAllocationUpdated(old, allocation);
    }

    /// @notice Update vault weights (sum must be BASIS_POINTS)
    /// @dev Callable by governance or keeper for operational flexibility
    /// @param stakingTokens_ Array of stakingToken addresses
    /// @param weights Array of weights in basis points
    function updateDefaultWeights(
        address[] calldata stakingTokens_,
        uint256[] calldata weights
    ) external virtual onlyKeeper {
        if (stakingTokens_.length != weights.length) {
            revert InvalidArrayLength();
        }
        if (_eligibleVaults.length() != stakingTokens_.length) {
            revert InvalidArrayLength();
        }

        address ibgt = address(infrared.ibgt());
        uint256 newTotalWeight = 0;
        for (uint256 i = 0; i < stakingTokens_.length; i++) {
            address stakingToken = stakingTokens_[i];
            if (stakingToken == address(0)) revert InvalidVault();
            if (stakingToken == ibgt) revert InvalidVault();
            if (!_eligibleVaults.contains(stakingToken)) revert InvalidVault();

            defaultVaultWeights[stakingToken] = weights[i];
            newTotalWeight += weights[i];
            emit WeightsUpdated(stakingToken, weights[i]);
        }

        if (newTotalWeight != BASIS_POINTS) revert InvalidWeights();
        totalDefaultWeight = newTotalWeight;
    }

    /// @notice Recover ERC20 tokens sent to this contract (governor only)
    /// @param token The ERC20 token to recover
    /// @param amount The amount to recover (or max balance if 0)
    function recoverERC20(address token, uint256 amount)
        external
        virtual
        onlyGovernor
    {
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = ERC20(token).balanceOf(address(this));
        if (amount == 0) amount = balance;
        if (amount > balance) revert InvalidAmount();
        if (
            token == address(_irToken)
                && amount > _irToken.balanceOf(address(this)) - totalRewardsPerEpoch
        ) revert InvalidAmount();
        ERC20(token).safeTransfer(msg.sender, amount);
        emit TokensRecovered(token, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       DISTRIBUTION                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Distribute rewards to vaults based on configured weights
    /// @dev Can only be called after epoch ends
    function distributeRewards() external virtual {
        if (block.timestamp < lastEpochTimestamp + epochDuration) {
            revert EpochNotEnded();
        }

        // cache to save sloads
        ERC20 irToken = _irToken;
        IInfrared _infrared = infrared;

        uint256 prevEpoch = currentEpoch;
        if (totalRewardsPerEpoch == 0) revert NoRewardsAvailable();

        {
            // Check we have enough IR tokens including carry-overs
            uint256 totalCarryOver = _calculateTotalCarryOver();
            uint256 balance = irToken.balanceOf(address(this));
            if (balance < totalRewardsPerEpoch + totalCarryOver) {
                revert InsufficientIRBalance();
            }
        }

        if (totalDefaultWeight == 0) revert NoWeightsSet();

        emit EpochFinalized(prevEpoch);

        // Get iBGT vault address
        address ibgt = address(_infrared.ibgt());

        // Calculate mandatory iBGT allocation
        uint256 ibgtAmount =
            (totalRewardsPerEpoch * minIBGTAllocation) / BASIS_POINTS;
        uint256 remainingRewards = totalRewardsPerEpoch - ibgtAmount;

        // adjust for carry over
        ibgtAmount += carryOverRewards[ibgt];

        // Distribute mandatory iBGT allocation
        if (ibgtAmount > 0 && ibgt != address(0)) {
            irToken.safeApprove(address(_infrared), ibgtAmount);
            try _infrared.addIncentives(ibgt, address(irToken), ibgtAmount) {
                emit RewardsDistributed(ibgt, ibgtAmount);
                carryOverRewards[ibgt] = 0;
            } catch (bytes memory errorData) {
                emit DistributionFailed(ibgt, ibgtAmount, errorData);
                carryOverRewards[ibgt] = ibgtAmount;
            }
        }

        // Get all eligible vaults (excluding iBGT and excluded)
        address[] memory allVaults = _getEligibleVaults();
        uint256 len = allVaults.length;

        if (len > 0 && remainingRewards > 0) {
            // Distribute remaining rewards based on configured weights
            for (uint256 i = 0; i < len; i++) {
                address stakingToken = allVaults[i];
                uint256 weight = defaultVaultWeights[stakingToken];

                if (weight == 0) continue;

                uint256 rewardAmount =
                    (remainingRewards * weight) / totalDefaultWeight;
                // adjust for carry over
                rewardAmount += carryOverRewards[stakingToken];

                if (rewardAmount > 0) {
                    irToken.safeApprove(address(_infrared), rewardAmount);
                    try _infrared.addIncentives(
                        stakingToken, address(irToken), rewardAmount
                    ) {
                        emit RewardsDistributed(stakingToken, rewardAmount);
                        carryOverRewards[stakingToken] = 0;
                    } catch (bytes memory errorData) {
                        emit DistributionFailed(
                            stakingToken, rewardAmount, errorData
                        );
                        carryOverRewards[stakingToken] = rewardAmount;
                    }
                }
            }
        }

        // Start new epoch
        currentEpoch++;
        lastEpochTimestamp = block.timestamp;
        emit EpochStarted(currentEpoch, block.timestamp, totalRewardsPerEpoch);
    }

    /// @notice Get all eligible vaults for distribution
    /// @return Array of eligible stakingToken addresses
    function _getEligibleVaults()
        internal
        view
        virtual
        returns (address[] memory)
    {
        return _eligibleVaults.values();
    }

    /// @notice Calculate the total carry-over rewards across iBGT and all eligible vaults
    /// @return The sum of all carry-over amounts
    function _calculateTotalCarryOver()
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 sum = carryOverRewards[address(infrared.ibgt())];
        address[] memory allVaults = _eligibleVaults.values();
        for (uint256 i = 0; i < allVaults.length; i++) {
            sum += carryOverRewards[allVaults[i]];
        }
        return sum;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get IR token address
    /// @return The IR token address
    function IR_TOKEN() external view virtual returns (address) {
        return address(_irToken);
    }

    /// @notice Get all excluded vaults
    /// @return Array of excluded stakingToken addresses
    function getExcludedVaults()
        external
        view
        virtual
        returns (address[] memory)
    {
        return _excludedVaults.values();
    }

    /// @notice Get all eligible vaults
    /// @return Array of eligible stakingToken addresses
    function getEligibleVaults()
        external
        view
        virtual
        returns (address[] memory)
    {
        return _eligibleVaults.values();
    }

    /// @notice Check if vault is excluded
    /// @param stakingToken The stakingToken address
    /// @return True if vault is excluded
    function isVaultExcluded(address stakingToken)
        external
        view
        virtual
        returns (bool)
    {
        return _excludedVaults.contains(stakingToken);
    }

    /// @notice Get time until next epoch
    /// @return Seconds until next epoch (0 if epoch has ended)
    function timeUntilNextEpoch() external view virtual returns (uint256) {
        if (block.timestamp >= lastEpochTimestamp + epochDuration) return 0;
        return (lastEpochTimestamp + epochDuration) - block.timestamp;
    }

    /// @notice Preview the allocation for a specific vault in the next distribution
    /// @param stakingToken The stakingToken address
    /// @return The estimated reward amount for the vault
    function getVaultAllocation(address stakingToken)
        external
        view
        virtual
        returns (uint256)
    {
        if (totalRewardsPerEpoch == 0) return 0;
        address ibgt = address(infrared.ibgt());
        uint256 baseIbgtAmount =
            (totalRewardsPerEpoch * minIBGTAllocation) / BASIS_POINTS;
        uint256 baseRemaining = totalRewardsPerEpoch - baseIbgtAmount;
        if (stakingToken == ibgt) {
            return baseIbgtAmount + carryOverRewards[ibgt];
        }
        if (
            !_eligibleVaults.contains(stakingToken)
                || _excludedVaults.contains(stakingToken)
        ) return 0;
        uint256 weight = defaultVaultWeights[stakingToken];
        if (weight == 0 || totalDefaultWeight == 0) return 0;
        uint256 baseShare = (baseRemaining * weight) / totalDefaultWeight;
        return baseShare + carryOverRewards[stakingToken];
    }

    /// @notice Get the total rewards for the next epoch
    /// @return The total rewards per epoch (pending distribution)
    function getNextEpochRewards() external view virtual returns (uint256) {
        return totalRewardsPerEpoch + _calculateTotalCarryOver();
    }
}
