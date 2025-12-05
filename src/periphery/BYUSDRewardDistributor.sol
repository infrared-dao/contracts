// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {WrappedRewardToken} from "./WrappedRewardToken.sol";

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
 * @title BYUSDRewardDistributor
 * @notice Automatically distributes wrapped rewards to maintain the highest sustainable APR
 *         based on current contract balance. Accepts underlying token (e.g. BYUSD) deposits
 *         that unlock linearly + one full reward period ahead to pre-fund the next cycle.
 * @dev Key features:
 *      • Linear vesting with forward unlock (can distribute next full period immediately)
 *      • Distribution amount = max APR the current balance can sustain
 *      • Full anti-dilution + sandwich protection
 *      • Single `distribute()` call from keeper does everything
 */
contract BYUSDRewardDistributor is Owned {
    using SafeTransferLib for ERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
     * @notice The ERC20 token for underlying rewards.
     */
    ERC20 public immutable underlyingToken;

    WrappedRewardToken public immutable wrapper;

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

    uint256 internal _totalUnderlyingDeposited;
    uint256 internal _totalUnderlyingUnlocked; // cumulative unlocked & wrapped

    struct Vest {
        uint128 amount;
        uint64 start;
        uint64 duration;
    }

    Vest[] public vests;

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

    event UnderlyingDeposited(
        address indexed from, uint256 amount, uint256 duration
    );
    event UnlockedAndWrapped(uint256 underlyingUnlocked);

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

    error APRWouldDecrease();

    error InvalidAmount();
    error InvalidDuration();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONSTRUCTION                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Initializes the RewardDistributor contract.
     * @param _gov The address of the contract owner/governance.
     * @param _infrared The address of the Infrared controller contract.
     * @param _stakingToken The address of the staking token associated with the vault.
     * @param _rewardsToken The address of the ERC20 token used for rewards.
     * @param _underlyingToken The address of the ERC20 token for underlying rewards.
     * @param _keeper Initial keeper address
     * @param _initialDistributionInterval The initial interval between distributions in seconds
     */
    constructor(
        address _gov,
        address _infrared,
        address _stakingToken,
        address _rewardsToken,
        address _underlyingToken,
        address _keeper,
        uint256 _initialDistributionInterval
    ) Owned(_gov) {
        if (_gov == address(0)) revert ZeroAddress();
        if (_infrared == address(0)) revert ZeroAddress();
        if (_stakingToken == address(0)) revert ZeroAddress();
        if (_rewardsToken == address(0)) revert ZeroAddress();
        if (_underlyingToken == address(0)) revert ZeroAddress();
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
        underlyingToken = ERC20(_underlyingToken);
        wrapper = WrappedRewardToken(_rewardsToken);
        require(address(wrapper.asset()) == _underlyingToken);

        distributionInterval = _initialDistributionInterval;

        underlyingToken.safeApprove(address(wrapper), type(uint256).max);

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
     */
    function getExpectedAmount() public view returns (uint256 amount) {
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

        uint256 totalRewardsNeeded = rewardsToken.balanceOf(address(this));

        // Subtract leftover rewards to find the additional amount needed
        amount = totalRewardsNeeded > (leftover + residual)
            ? totalRewardsNeeded - (leftover + residual)
            : 0;
    }

    /**
     * @notice Returns the current effective APR based on the vault's active reward rate
     * @dev Calculates APR from the current rewardRate and totalSupply
     *      Returns 0 if no active rewards period or zero total supply
     * @return apr The current APR in basis points (e.g., 1500 = 15%)
     * @custom:formula apr = (rewardRate * SECONDS_PER_YEAR * BASIS_POINTS) / totalSupply
     */
    function getCurrentAPR() public view returns (uint256 apr) {
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
        public
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

    // Vested underlying token
    /**
     * @notice Deposit underlying token that will unlock linearly over time
     * @param amount   Amount of underlying to lock
     * @param duration Total lock duration in seconds (e.g. 30 days)
     * @dev Only keeper (treasury/multisig) can fund rewards to prevent spam and retain control
     */
    function depositUnderlying(uint256 amount, uint256 duration)
        external
        onlyKeeper
    {
        if (amount == 0 || amount > type(uint128).max) revert InvalidAmount();
        if (duration == 0 || duration > 365 * 24 * 60 * 60) {
            revert InvalidDuration();
        }
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);

        vests.push(
            Vest(uint128(amount), uint64(block.timestamp), uint64(duration))
        );
        _totalUnderlyingDeposited += amount;

        emit UnderlyingDeposited(msg.sender, amount, duration);
    }

    /**
     * @notice Amount of underlying that can be unlocked right now
     * @dev Allows unlocking up to one full reward period into the future
     *      → ensures next cycle is always pre-funded
     * @return unlockable underlying amount
     */
    function unlockableUnderlying() public view returns (uint256) {
        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        (, uint256 rewardsDuration,,,,,) =
            vault.rewardData(address(rewardsToken));
        if (rewardsDuration == 0) return 0;

        uint256 future = block.timestamp + rewardsDuration;
        uint256 total = 0;
        uint256 len = vests.length;
        for (uint256 i; i < len; ++i) {
            Vest memory v = vests[i];
            uint256 end = v.start + v.duration;

            if (future >= end) {
                total += v.amount;
            } else if (future > v.start) {
                total += (v.amount * (future - v.start)) / v.duration;
            }
        }

        return total > _totalUnderlyingUnlocked
            ? total - _totalUnderlyingUnlocked
            : 0;
    }

    /**
     * @notice Unlock and wrap all currently available underlying
     * @dev Also cleans up fully vested entries to prevent storage growth
     */
    function _unlock() internal {
        uint256 toUnlock = unlockableUnderlying();
        if (toUnlock == 0) return;

        _totalUnderlyingUnlocked += toUnlock;

        wrapper.deposit(toUnlock, address(this));
        emit UnlockedAndWrapped(toUnlock);
    }

    /**
     * @notice One-call keeper function — does everything
     * @param maxTotalSupply Slippage protection parameter
     */
    function distribute(uint256 maxTotalSupply) external onlyKeeper {
        // 1. Unlock max possible (includes forward unlock)
        _unlock();

        uint256 expected = getExpectedAmount();
        if (expected == 0) return;

        // 2. Prevent dilution
        if (getAPRForAmount(expected) < getCurrentAPR()) {
            revert APRWouldDecrease();
        }

        // 3. Time + slippage checks
        if (block.timestamp < lastDistributionTime + distributionInterval) {
            revert DistributionTooSoon();
        }

        IInfraredVault vault = infrared.vaultRegistry(stakingToken);
        if (vault.totalSupply() > maxTotalSupply) revert TotalSupplySlippage();

        // 4. Distribute
        lastDistributionTime = block.timestamp;
        infrared.addIncentives(stakingToken, address(rewardsToken), expected);

        emit RewardsDistributed(address(vault), expected);
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

    function _getRewardsDuration() internal view returns (uint256) {
        (, uint256 d,,,,,) = _vault().rewardData(address(rewardsToken));
        return d;
    }

    function _vault() internal view returns (IInfraredVault) {
        return infrared.vaultRegistry(stakingToken);
    }
}
