// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/**
 * @title IIRRewardDistributor
 * @notice Interface for the IR Reward Distributor contract
 * @dev Manages IR token distribution to Infrared vaults based on governance/keeper configured weights
 * @dev Maintains list of eligible vaults for distribution
 * @dev Mandatory minimum allocation to iBGT vault (siBGT stakers)
 */
interface IIRRewardDistributor {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EVENTS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when rewards are distributed to a vault
    event RewardsDistributed(address indexed vault, uint256 amount);

    /// @notice Emitted when a vault is excluded from distribution
    event VaultExcluded(address indexed vault);

    /// @notice Emitted when a vault is included in distribution
    event VaultIncluded(address indexed vault);

    /// @notice Emitted when an eligible vault is added
    event EligibleVaultAdded(address indexed vault);

    /// @notice Emitted when an eligible vault is removed
    event EligibleVaultRemoved(address indexed vault);

    /// @notice Emitted when a new epoch starts
    event EpochStarted(
        uint256 indexed epoch, uint256 timestamp, uint256 totalRewards
    );

    /// @notice Emitted when an epoch is finalized
    event EpochFinalized(uint256 indexed epoch);

    /// @notice Emitted when vault weights are updated
    event WeightsUpdated(address indexed vault, uint256 weight);

    /// @notice Emitted when rewards per epoch is updated
    event RewardsPerEpochUpdated(uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when minimum iBGT allocation is updated
    event MinIBGTAllocationUpdated(
        uint256 oldAllocation, uint256 newAllocation
    );

    /// @notice Emitted when token addresses are updated
    event TokensUpdated(address indexed irToken, address indexed sirToken);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERRORS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when vault address is invalid
    error InvalidVault();

    /// @notice Thrown when amount is invalid
    error InvalidAmount();

    /// @notice Thrown when trying to distribute before epoch ends
    error EpochNotEnded();

    /// @notice Thrown when no rewards are available for distribution
    error NoRewardsAvailable();

    /// @notice Thrown when weights are invalid
    error InvalidWeights();

    /// @notice Thrown when no weights are set
    error NoWeightsSet();

    /// @notice Thrown when contract has insufficient IR balance
    error InsufficientIRBalance();

    /// @notice Thrown when array lengths don't match
    error InvalidArrayLength();

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when allocation is invalid
    error InvalidAllocation();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initialize the contract
    /// @param _infrared Infrared protocol address
    /// @param irToken IR token address
    /// @param sirToken sIR token address
    /// @param _minIBGTAllocation Minimum allocation to iBGT vault in basis points
    function initialize(
        address _infrared,
        address irToken,
        address sirToken,
        uint256 _minIBGTAllocation
    ) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Exclude a vault from distribution
    /// @param vault The vault address to exclude
    function excludeVault(address vault) external;

    /// @notice Include a previously excluded vault
    /// @param vault The vault address to include
    function includeVault(address vault) external;

    /// @notice Add an eligible vault for distribution
    /// @param vault The vault address to add
    function addEligibleVault(address vault) external;

    /// @notice Remove an eligible vault
    /// @param vault The vault address to remove
    function removeEligibleVault(address vault) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set total rewards per epoch
    /// @param amount Total IR tokens to distribute per epoch
    function setRewardsPerEpoch(uint256 amount) external;

    /// @notice Set minimum iBGT vault allocation
    /// @param allocation Minimum allocation in basis points (max 50%)
    function setMinIBGTAllocation(uint256 allocation) external;

    /// @notice Update IR and sIR token addresses (for upgrades)
    /// @param irToken New IR token address
    /// @param sirToken New sIR token address
    function updateTokens(address irToken, address sirToken) external;

    /// @notice Update vault weights (sum must be BASIS_POINTS)
    /// @dev Callable by governance or keeper for operational flexibility
    /// @param vaults Array of vault addresses
    /// @param weights Array of weights in basis points
    function updateDefaultWeights(
        address[] calldata vaults,
        uint256[] calldata weights
    ) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       DISTRIBUTION                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Distribute rewards to vaults based on configured weights
    /// @dev Can only be called after epoch ends
    function distributeRewards() external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get IR token address
    /// @return The IR token address
    function IR_TOKEN() external view returns (address);

    /// @notice Get sIR token address
    /// @return The sIR token address
    function SIR_TOKEN() external view returns (address);

    /// @notice Get all excluded vaults
    /// @return Array of excluded vault addresses
    function getExcludedVaults() external view returns (address[] memory);

    /// @notice Get all eligible vaults
    /// @return Array of eligible vault addresses
    function getEligibleVaults() external view returns (address[] memory);

    /// @notice Check if vault is excluded
    /// @param vault The vault address
    /// @return True if vault is excluded
    function isVaultExcluded(address vault) external view returns (bool);

    /// @notice Get time until next epoch
    /// @return Seconds until next epoch (0 if epoch has ended)
    function timeUntilNextEpoch() external view returns (uint256);

    /// @notice Get current epoch number
    /// @return The current epoch
    function currentEpoch() external view returns (uint256);

    /// @notice Get total rewards per epoch
    /// @return The total rewards per epoch
    function totalRewardsPerEpoch() external view returns (uint256);

    /// @notice Get last epoch timestamp
    /// @return The last epoch timestamp
    function lastEpochTimestamp() external view returns (uint256);

    /// @notice Get minimum iBGT vault allocation
    /// @return The minimum iBGT allocation in basis points
    function minIBGTAllocation() external view returns (uint256);

    /// @notice Get weight for a vault
    /// @param vault The vault address
    /// @return The vault weight
    function defaultVaultWeights(address vault)
        external
        view
        returns (uint256);

    /// @notice Get total weight
    /// @return The total weight
    function totalDefaultWeight() external view returns (uint256);

    /// @notice Get Infrared protocol address
    /// @return The Infrared protocol address
    function infrared() external view returns (address);
}
