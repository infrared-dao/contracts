// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

interface IInfrared {
    /**
     * @notice Adds reward incentives to a specific staking vault
     * @dev Transfers reward tokens from caller to this contract, then notifies vault of new rewards
     * @param _stakingToken The address of the staking token associated with the vault
     * @param _rewardsToken The address of the token being added as incentives
     * @param _amount The amount of reward tokens to add as incentives
     * @custom:error ZeroAmount if _amount is 0
     * @custom:error NoRewardsVault if vault doesn't exist for _stakingToken
     * @custom:error RewardTokenNotWhitelisted if reward token hasn't been configured for the vault
     * @custom:access Callable when contract is initialized
     * @custom:security Requires caller to have approved this contract to spend _rewardsToken
     */
    function addIncentives(
        address _stakingToken,
        address _rewardsToken,
        uint256 _amount
    ) external;

    /**
     * @notice Mapping of staking token addresses to their corresponding InfraredVault
     * @dev Each staking token can only have one vault
     */
    function vaultRegistry(address _stakingToken)
        external
        view
        returns (IInfraredVault vault);
}

interface IInfraredVault {
    /**
     * @notice Gets the reward data for a given rewards token
     * @param _rewardsToken The address of the rewards token
     * @return rewardsDistributor The address authorized to distribute rewards
     * @return rewardsDuration The duration of the reward period
     * @return periodFinish The timestamp when rewards finish
     * @return rewardRate The rate of rewards distributed per second
     * @return lastUpdateTime The last time rewards were updated
     * @return rewardPerTokenStored The last calculated reward per token
     */
    function rewardData(address _rewardsToken)
        external
        view
        returns (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        );

    /**
     * @notice Returns the total amount of staked tokens in the contract
     * @return uint256 The total supply of staked tokens
     */
    function totalSupply() external view returns (uint256);
}

/**
 * @title RewardDistributor
 * @notice Distributes reward tokens to the vault to maintain the target APR
 * @dev This contract integrates with the Infrared controller to distribute rewards to a specified vault.
 *      Calculates the reward amount based on the target APR, total staked supply, and reward duration.
 *      Uses the vault's rewardRate and periodFinish to compute remaining rewards, accounting for the
 *      vault's logic where periodFinish is updated to block.timestamp + rewardsDuration and rewardRate
 *      is set to (leftover + newAmount) / rewardsDuration. Protected against sandwich attacks through
 *      keeper restrictions and slippage protection on total supply.
 * @custom:security The contract grants unlimited approval to the Infrared controller for reward token transfers
 *                  during initialization. Uses keeper whitelist and slippage protection to prevent manipulation.
 *                  Only the owner can update configuration parameters or withdraw tokens.
 * @custom:access Only whitelisted keepers can call `distribute`. Only the owner can call `setTargetAPR`,
 *                `setDistributionInterval`, `updateKeeper`, `setMaxSupplyDeviation`, and `withdrawRewards`.
 */
contract RewardDistributor is Owned {
    using SafeTransferLib for ERC20;

    /**
     * @notice The number of seconds in a year for APR calculations
     */
    uint256 private constant SECONDS_PER_YEAR = 36525 * 24 * 60 * 60 / 100;

    /**
     * @notice The number of basis points in 100% (1% = 100 basis points)
     */
    uint256 private constant BASIS_POINTS = 10_000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice The address of the Infrared controller contract.
     */
    IInfrared public immutable infrared;

    /**
     * @notice The address of the staking token associated with the vault.
     */
    address public immutable stakingToken;

    /**
     * @notice The ERC20 token used for rewards distribution.
     */
    ERC20 public immutable rewardsToken;

    /**
     * @notice The target APR in basis points (e.g., 100 = 1%)
     */
    uint256 public targetAPR;

    /**
     * @notice Mapping of addresses authorized to call the distribute function
     * @dev Keepers are trusted entities that can trigger reward distributions
     */
    mapping(address => bool) public keepers;

    /**
     * @notice Maximum allowed deviation in total supply to prevent sandwich attacks
     * @dev Expressed in basis points (e.g., 200 = 2% allowed increase)
     */
    uint256 public maxSupplyDeviation = 100;

    /**
     * @notice The interval between distributions in seconds
     */
    uint256 public distributionInterval;

    /**
     * @notice The timestamp of the last reward distribution.
     */
    uint256 public lastDistributionTime;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EVENTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when rewards are successfully distributed to the vault.
     * @param vault The address of the Infrared vault receiving the rewards.
     * @param amount The amount of reward tokens distributed.
     */
    event RewardsDistributed(address vault, uint256 amount);

    /**
     * @notice Emitted when the target APR is updated
     * @param oldAPR The previous target APR in basis points
     * @param newAPR The new target APR in basis points
     */
    event TargetAPRUpdated(uint256 oldAPR, uint256 newAPR);

    /**
     * @notice Emitted when the distribution interval is updated
     * @param oldInterval The previous distribution interval in seconds
     * @param newInterval The new distribution interval in seconds
     */
    event DistributionIntervalUpdated(uint256 oldInterval, uint256 newInterval);

    /**
     * @notice Emitted when a keeper's status is updated
     * @param keeper The address of the keeper
     * @param active Whether the keeper is now active or inactive
     */
    event KeeperUpdated(address indexed keeper, bool active);

    /**
     * @notice Emitted when the maximum supply deviation is updated
     * @param oldDeviation The previous maximum deviation in basis points
     * @param newDeviation The new maximum deviation in basis points
     */
    event MaxSupplyDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);

    /**
     * @notice Emitted when tokens are withdrawn by the owner
     * @param token Address of token recovered
     * @param to Address of recipient
     * @param amount Tokens recovered
     */
    event TokensRecovered(address indexed token, address to, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ERRORS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Thrown when the reward duration from the vault is zero.
     */
    error ZeroRewardDuration();

    /**
     * @notice Thrown when a distribution is attempted before the reward duration has elapsed.
     */
    error DistributionTooSoon();

    /**
     * @notice Thrown when the contract has insufficient reward token balance for distribution.
     */
    error InsufficientRewardBalance();

    /**
     * @notice Thrown when attempting to set a zero fixed reward amount.
     */
    error ZeroFixedAmount();

    /**
     * @notice Thrown when attempting to set a zero address.
     */
    error ZeroAddress();

    /**
     * @notice Thrown when attempting to set a zero target APR
     */
    error ZeroTargetAPR();

    /**
     * @notice Thrown when attempting to set a zero distribution interval
     */
    error ZeroDistributionInterval();

    /**
     * @notice Thrown when the total staked supply in the vault is zero
     */
    error ZeroTotalSupply();

    /**
     * @notice Thrown when amount to distribute is zero
     */
    error NothingToAdd();

    /**
     * @notice Thrown when there is no vault for the staking token
     */
    error NoVault();

    /**
     * @notice Thrown when the current total supply exceeds the maximum allowed (slippage protection)
     * @dev Prevents distribution during potential sandwich attacks
     */
    error TotalSupplySlippage();

    /**
     * @notice Thrown when attempting to update a value that would not change
     */
    error NothingToUpdate();

    /**
     * @notice Thrown when attempting to call onlyKeeper function from non-keeper address
     */
    error NotKeeper();

    /**
     * @notice Thrown when using recoverERC20 for withdrawing reward tokens
     */
    error UseWithdrawRewards();

    /**
     * @notice Thrown when calling recoverERC20 with no token balance
     */
    error ZeroAmount();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTION                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Initializes the RewardDistributor contract.
     * @param _gov The address of the contract owner/governance.
     * @param _infrared The address of the Infrared controller contract.
     * @param _stakingToken The address of the staking token associated with the vault.
     * @param _rewardsToken The address of the ERC20 token used for rewards.
     * @param _keeper Initial keeper address
     * @param _initialTargetAPR The initial target APR in basis points (e.g., 100 = 1%)
     * @param _initialDistributionInterval The initial interval between distributions in seconds
     */
    constructor(
        address _gov,
        address _infrared,
        address _stakingToken,
        address _rewardsToken,
        address _keeper,
        uint256 _initialTargetAPR,
        uint256 _initialDistributionInterval
    ) Owned(_gov) {
        if (_gov == address(0)) revert ZeroAddress();
        if (_infrared == address(0)) revert ZeroAddress();
        if (_stakingToken == address(0)) revert ZeroAddress();
        if (_rewardsToken == address(0)) revert ZeroAddress();
        if (_initialTargetAPR == 0) revert ZeroTargetAPR();
        if (_initialDistributionInterval == 0) {
            revert ZeroDistributionInterval();
        }

        infrared = IInfrared(_infrared);
        // validate vault exists
        if (address(infrared.vaultRegistry(_stakingToken)) == address(0)) {
            revert NoVault();
        }
        stakingToken = _stakingToken;
        rewardsToken = ERC20(_rewardsToken);
        targetAPR = _initialTargetAPR;
        distributionInterval = _initialDistributionInterval;

        // Grant unlimited approval to Infrared for reward token transfers
        rewardsToken.safeApprove(_infrared, type(uint256).max);

        // Set owner as initial keeper
        keepers[_gov] = true;
        keepers[_keeper] = true;
    }

    /**
     * @notice Restricts function access to whitelisted keepers only
     * @dev Reverts if msg.sender is not an active keeper
     */
    modifier onlyKeeper() {
        if (!keepers[msg.sender]) revert NotKeeper();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    DISTRIBUTION                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Calculates the maximum acceptable total supply for slippage protection
     * @dev Returns current total supply plus the allowed deviation percentage
     * @return totalSupply The maximum acceptable total supply
     */
    function getMaxTotalSupply() external view returns (uint256 totalSupply) {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        totalSupply = vault.totalSupply();
        totalSupply += totalSupply * maxSupplyDeviation / BASIS_POINTS;
    }

    /**
     * @notice Calculates the expected reward amount to be distributed in the next distribution cycle
     * @dev Accounts for leftover rewards from incomplete periods and residual amounts in vault
     *      Returns 0 if distribution conditions are not met (too soon, zero supply, insufficient balance)
     * @return amount The amount of reward tokens expected to be distributed, or 0 if conditions not met
     * @custom:formula totalRewardsNeeded = (targetAPR * totalSupply * rewardsDuration) / (SECONDS_PER_YEAR * BASIS_POINTS)
     * @custom:formula amount = totalRewardsNeeded - (leftover + residual)
     */
    function getExpectedAmount() external view returns (uint256 amount) {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        (
            ,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            ,
            ,
            uint256 residual
        ) = vault.rewardData(address(rewardsToken));

        if (rewardsDuration == 0) return 0;
        if (block.timestamp < lastDistributionTime + distributionInterval) {
            return 0;
        }

        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return 0;

        // Calculate leftover rewards: (periodFinish - block.timestamp) * rewardRate
        uint256 leftover = block.timestamp >= periodFinish
            ? 0
            : (periodFinish - block.timestamp) * rewardRate;

        // Calculate the target reward rate to achieve the desired APR
        // APR = (rewardRate * SECONDS_PER_YEAR * 100) / totalSupply
        // rewardRate = (APR * totalSupply) / (SECONDS_PER_YEAR * 100)
        // Calculate the total rewards needed for the full duration
        uint256 totalRewardsNeeded = (targetAPR * totalSupply * rewardsDuration)
            / (SECONDS_PER_YEAR * BASIS_POINTS);

        // Subtract leftover rewards to find the additional amount needed
        amount = totalRewardsNeeded > (leftover + residual)
            ? totalRewardsNeeded - (leftover + residual)
            : 0;

        if (amount == 0) return 0;

        if (rewardsToken.balanceOf(address(this)) < amount) {
            return 0;
        }
    }

    /**
     * @notice Returns the current effective APR based on the vault's active reward rate
     * @dev Calculates APR from the current rewardRate and totalSupply
     *      Returns 0 if no active rewards period or zero total supply
     * @return apr The current APR in basis points (e.g., 1500 = 15%)
     * @custom:formula apr = (rewardRate * SECONDS_PER_YEAR * BASIS_POINTS) / totalSupply
     */
    function getCurrentAPR() external view returns (uint256 apr) {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        (, uint256 rewardsDuration, uint256 periodFinish, uint256 rewardRate,,,)
        = vault.rewardData(address(rewardsToken));

        if (rewardsDuration == 0) return 0;
        if (block.timestamp > periodFinish) {
            return 0;
        }

        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return 0;

        apr = (rewardRate * SECONDS_PER_YEAR * BASIS_POINTS) / totalSupply;
    }

    /**
     * @notice Calculates the APR that would result from distributing a specific amount of rewards
     * @dev Useful for determining how much rewards are needed to achieve a target APR
     * @param amount The amount of reward tokens to calculate APR for
     * @return apr The resulting APR in basis points if the amount were distributed
     * @custom:formula apr = (amount * SECONDS_PER_YEAR * BASIS_POINTS) / (rewardsDuration * totalSupply)
     */
    function getAPRForAmount(uint256 amount)
        external
        view
        returns (uint256 apr)
    {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        (, uint256 rewardsDuration,,,,,) =
            vault.rewardData(address(rewardsToken));

        if (rewardsDuration == 0) return 0;

        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return 0;

        apr = (amount * SECONDS_PER_YEAR * BASIS_POINTS)
            / (rewardsDuration * totalSupply);
    }

    /**
     * @notice Distributes reward tokens to the vault to maintain the target APR
     * @dev Calculates reward amount based on target APR and current supply, protected against
     *      sandwich attacks via keeper restriction and slippage check. Accounts for leftover
     *      rewards from previous periods and residual amounts in the vault.
     * @param _maxTotalSupply Maximum acceptable total supply (slippage protection)
     * @custom:security Requires msg.sender to be a whitelisted keeper
     * @custom:security Reverts if current totalSupply exceeds _maxTotalSupply (sandwich attack protection)
     * @custom:security Updates state before external calls to prevent reentrancy
     */
    function distribute(uint256 _maxTotalSupply) external onlyKeeper {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        (
            ,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            ,
            ,
            uint256 residual
        ) = vault.rewardData(address(rewardsToken));

        if (rewardsDuration == 0) revert ZeroRewardDuration();
        if (block.timestamp < lastDistributionTime + distributionInterval) {
            revert DistributionTooSoon();
        }

        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) revert ZeroTotalSupply();
        if (totalSupply > _maxTotalSupply) revert TotalSupplySlippage();

        // Calculate leftover rewards: (periodFinish - block.timestamp) * rewardRate
        uint256 leftover = block.timestamp >= periodFinish
            ? 0
            : (periodFinish - block.timestamp) * rewardRate;

        // Calculate the target reward rate to achieve the desired APR
        // APR = (rewardRate * SECONDS_PER_YEAR * 100) / totalSupply
        // rewardRate = (APR * totalSupply) / (SECONDS_PER_YEAR * 100)
        // Calculate the total rewards needed for the full duration
        uint256 totalRewardsNeeded = (targetAPR * totalSupply * rewardsDuration)
            / (SECONDS_PER_YEAR * BASIS_POINTS);

        // Subtract leftover rewards to find the additional amount needed
        uint256 additionalAmount = totalRewardsNeeded > (leftover + residual)
            ? totalRewardsNeeded - (leftover + residual)
            : 0;

        if (additionalAmount == 0) revert NothingToAdd();

        if (rewardsToken.balanceOf(address(this)) < additionalAmount) {
            revert InsufficientRewardBalance();
        }

        lastDistributionTime = block.timestamp;

        infrared.addIncentives(
            stakingToken, address(rewardsToken), additionalAmount
        );

        emit RewardsDistributed(address(vault), additionalAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ADMIN                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Updates the keeper status for a given address
     * @dev Only callable by owner, reverts if status would not change
     * @param _keeper The address to update keeper status for
     * @param _active Whether the address should be an active keeper
     * @custom:security Consider checking _keeper != address(0) to prevent accidents
     */
    function updateKeeper(address _keeper, bool _active) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        if (keepers[_keeper] == _active) revert NothingToUpdate();
        keepers[_keeper] = _active;
        emit KeeperUpdated(_keeper, _active);
    }

    /**
     * @notice Sets the target APR for reward distributions
     * @dev Updates the target APR after validating it is non-zero and emits a TargetAPRUpdated event
     * @param _apr The new target APR in basis points (e.g., 100 = 1%)
     */
    function setTargetAPR(uint256 _apr) external onlyKeeper {
        if (_apr == 0) revert ZeroTargetAPR();

        emit TargetAPRUpdated(targetAPR, _apr);
        targetAPR = _apr;
    }

    /**
     * @notice Sets the interval between reward distributions
     * @dev Updates the distribution interval after validating it is non-zero and emits a DistributionIntervalUpdated event
     * @param _interval The new distribution interval in seconds
     */
    function setDistributionInterval(uint256 _interval) external onlyOwner {
        if (_interval == 0) revert ZeroDistributionInterval();

        emit DistributionIntervalUpdated(distributionInterval, _interval);
        distributionInterval = _interval;
    }

    /**
     * @notice Sets the maximum allowed supply deviation for slippage protection
     * @dev Prevents distributions when supply increases beyond this threshold
     * @param _deviation The new maximum deviation in basis points (e.g., 200 = 2%)
     */
    function setMaxSupplyDeviation(uint256 _deviation) external onlyOwner {
        emit MaxSupplyDeviationUpdated(maxSupplyDeviation, _deviation);
        maxSupplyDeviation = _deviation;
    }

    /**
     * @notice Allows the owner to withdraw reward tokens from the contract.
     * @dev Transfers the specified amount of reward tokens to the owner using safe transfer.
     * @param _amount The amount of reward tokens to withdraw.
     */
    function withdrawRewards(uint256 _amount) external onlyOwner {
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (balance < _amount) revert InsufficientRewardBalance();
        rewardsToken.safeTransfer(owner, _amount);
        emit TokensRecovered(address(rewardsToken), owner, _amount);
    }

    /**
     * @notice Recover non-reward tokens sent to this contract by mistake
     * @dev Cannot be used to withdraw reward tokens - use withdrawRewards instead
     *      Transfers entire balance of the specified token to the recipient
     * @param tokenAddress Address of the ERC20 token to recover
     * @param to Address to send recovered tokens to
     * @custom:security Only callable by owner, prevents recovery of reward tokens
     * @custom:error UseWithdrawRewards if attempting to recover reward tokens
     * @custom:error ZeroAmount if token balance is zero
     */
    function recoverERC20(address tokenAddress, address to)
        external
        onlyOwner
    {
        if (tokenAddress == address(rewardsToken)) revert UseWithdrawRewards();

        ERC20 recoveryToken = ERC20(tokenAddress);
        uint256 balance = recoveryToken.balanceOf(address(this));

        if (balance == 0) revert ZeroAmount();

        recoveryToken.safeTransfer(to, balance);
        emit TokensRecovered(tokenAddress, to, balance);
    }
}
