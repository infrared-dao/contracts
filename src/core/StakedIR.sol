// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC4626Upgradeable} from
    "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Upgradeable} from "src/utils/Upgradeable.sol";
import {Errors} from "src/utils/Errors.sol";

/**
 * @title StakedIR
 * @notice ERC4626 vault for staking IR tokens with withdrawal ticket system
 * @dev Rewards are auto-compounded (IR only after auction conversion)
 * @dev Ticket system: Queued, time-based unlocks become claimable
 */
contract StakedIR is
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    Upgradeable
{
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRUCTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Represents a withdrawal request in the global queue
    /// @dev Uses packed storage to optimize gas costs
    struct WithdrawalRequest {
        /// @notice Whether the withdrawal has been claimed
        bool claimed;
        /// @notice Timestamp when the withdrawal becomes claimable
        uint88 unlockTime;
        /// @notice Address that will receive the withdrawn assets
        address receiver;
        /// @notice Amount of shares that were burned
        uint128 shares;
        /// @notice Amount of assets reserved for withdrawal
        uint128 assets;
    }

    /// @notice Storage struct for StakedIR using ERC-7201 pattern
    /// @custom:storage-location erc7201:infrared.stakedIRStorage
    struct StakedIRStorage {
        /// @notice Total rewards compounded (for accounting)
        uint256 totalCompounded;
        /// @notice Fixed withdrawal period (default 7 days)
        uint256 withdrawalPeriod;
        /// @notice The current number of withdrawal requests queued (next requestId to be assigned)
        uint256 requestLength;
        /// @notice Mapping of request IDs to withdrawal request tickets
        mapping(uint256 => WithdrawalRequest) requests;
        /// @notice Total assets reserved for pending withdrawals (queued + processed)
        uint256 totalReserved;
        /// @notice Mapping of user addresses to their withdrawal request IDs
        mapping(address => uint256[]) userRequests;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ERC-7201 storage location for StakedIR
    /// @dev keccak256(abi.encode(uint256(keccak256(bytes("infrared.stakedIRStorage"))) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STAKED_IR_STORAGE_LOCATION =
        0xe37d8c878a50f0326695af34a6b5c1ac8f3bc817d7b9727cc43175799b685e00;

    /// @notice Reserve storage space for upgrades
    uint256[40] private __gap;

    /// @return s The StakedIR storage struct
    function _stakedIRStorage()
        private
        pure
        returns (StakedIRStorage storage s)
    {
        bytes32 position = STAKED_IR_STORAGE_LOCATION;
        assembly {
            s.slot := position
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EVENTS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when rewards are compounded into the vault
    /// @param compounder Address that triggered the compound
    /// @param amount Amount of IR tokens compounded
    /// @param newTotalAssets New total assets after compounding
    event Compounded(
        address indexed compounder, uint256 amount, uint256 newTotalAssets
    );

    /// @notice Emitted when the withdrawal period is updated
    /// @param oldPeriod Previous withdrawal period in seconds
    /// @param newPeriod New withdrawal period in seconds
    event WithdrawalPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /// @notice Emitted when a user requests a withdrawal
    /// @param user Address of the user requesting withdrawal
    /// @param requestId ID of the withdrawal request
    /// @param shares Amount of shares burned
    /// @param unlockTime Timestamp when the withdrawal becomes claimable
    event WithdrawalRequested(
        address indexed user,
        uint256 indexed requestId,
        uint256 shares,
        uint256 unlockTime
    );

    /// @notice Emitted when a withdrawal request is claimed
    /// @param user Address that received the withdrawn assets
    /// @param requestId ID of the withdrawal request
    /// @param shares Amount of shares that were burned
    /// @param assets Amount of assets transferred
    event WithdrawalClaimed(
        address indexed user,
        uint256 indexed requestId,
        uint256 shares,
        uint256 assets
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERRORS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when attempting to claim a withdrawal before unlock time
    error WithdrawalNotReady();

    /// @notice Thrown when an invalid request ID is provided
    error InvalidRequestId();

    /// @notice Thrown when a withdrawal request is in an invalid state
    error InvalidState();

    /// @notice Thrown when amount exceeds uint128 max
    error AmountTooLarge();

    /// @notice Thrown when timestamp calculation would overflow uint88
    error TimestampOverflow();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the StakedIR contract
    /// @param _ir The IR token address (asset)
    /// @param _governance The Governance multisig address
    function initialize(IERC20 _ir, address _governance) external initializer {
        if (address(_ir) == address(0) || _governance == address(0)) {
            revert Errors.ZeroAddress();
        }

        // Initialize parent contracts
        __ERC4626_init(_ir);
        __ERC20_init("Staked IR", "sIR");
        __ReentrancyGuard_init();
        __Upgradeable_init();

        // Grant roles to governance
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(GOVERNANCE_ROLE, _governance);
        _grantRole(PAUSER_ROLE, _governance);

        // Initialize storage
        StakedIRStorage storage $ = _stakedIRStorage();
        $.withdrawalPeriod = 7 days; // Default fixed withdrawal period

        // Inflation attack prevention - mint initial shares to the contract itself
        // Note: This requires the IR token to have approved this contract for at least 10 ether
        deposit(10 ether, address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       COMPOUNDING                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Compound rewards (convert non-IR rewards via auction, then deposit)
    /// @dev Increases share value for all sIR holders
    /// @param amount Amount of IR tokens to compound
    function compound(uint256 amount) external virtual nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();

        StakedIRStorage storage $ = _stakedIRStorage();

        // Transfer IR from compounder (which has already auctioned non-IR rewards)
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        $.totalCompounded += amount;
        emit Compounded(msg.sender, amount, totalAssets());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update fixed withdrawal period
    /// @dev Only callable by governance
    /// @param _newPeriod The new withdrawal period in seconds
    function setWithdrawalPeriod(uint256 _newPeriod)
        external
        virtual
        onlyGovernor
    {
        StakedIRStorage storage $ = _stakedIRStorage();

        uint256 old = $.withdrawalPeriod;
        $.withdrawalPeriod = _newPeriod;
        emit WithdrawalPeriodUpdated(old, _newPeriod);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WITHDRAWAL TICKETS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Request withdrawal by burning shares and queuing a ticket
    /// @dev Burns shares immediately and reserves assets
    /// @param shares Amount of shares to withdraw
    /// @param receiver Address of recipient for withdrawn tokens
    /// @param owner Address of token owner
    /// @return assets Amount of assets reserved in the withdrawal request
    function _requestWithdraw(uint256 shares, address receiver, address owner)
        internal
        virtual
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert Errors.ZeroAmount();

        StakedIRStorage storage $ = _stakedIRStorage();

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = previewRedeem(shares);
        // safety check (should not get here)
        if (assets == 0) revert Errors.ZeroAmount();

        // Check for overflow before downcasting
        if (shares > type(uint128).max) revert AmountTooLarge();
        if (assets > type(uint128).max) revert AmountTooLarge();

        _burn(owner, shares);

        // Reserve assets for withdrawal
        $.totalReserved += assets;

        // Create withdrawal ticket in global queue
        $.requestLength++;
        uint256 requestId = $.requestLength;

        // Check timestamp overflow before downcasting
        uint256 unlockTimestamp = block.timestamp + $.withdrawalPeriod;
        if (unlockTimestamp > type(uint88).max) revert TimestampOverflow();

        $.requests[requestId] = WithdrawalRequest({
            claimed: false,
            unlockTime: uint88(unlockTimestamp),
            receiver: receiver,
            shares: uint128(shares),
            assets: uint128(assets)
        });

        $.userRequests[owner].push(requestId);

        emit WithdrawalRequested(owner, requestId, shares, unlockTimestamp);
    }

    /// @notice Internal claim logic without reentrancy guard
    /// @param requestId The ID of the withdrawal request to claim
    /// @return assets Amount of assets received
    function _claimWithdraw(uint256 requestId)
        internal
        virtual
        returns (uint256 assets)
    {
        StakedIRStorage storage $ = _stakedIRStorage();

        if (requestId > $.requestLength || requestId == 0) {
            revert InvalidRequestId();
        }

        WithdrawalRequest memory ticket = $.requests[requestId];
        if (ticket.claimed) revert InvalidState();
        if (block.timestamp < ticket.unlockTime) revert WithdrawalNotReady();

        assets = ticket.assets;

        // Mark as claimed
        $.requests[requestId].claimed = true;
        // Unreserve the assets
        $.totalReserved -= assets;

        // Transfer assets to user
        IERC20(asset()).safeTransfer(ticket.receiver, assets);

        emit WithdrawalClaimed(
            ticket.receiver, requestId, ticket.shares, assets
        );
    }

    /// @notice Claim a matured withdrawal request
    /// @dev Auto-processes if still claimable
    /// @param requestId The ID of the withdrawal request to claim
    /// @return assets Amount of assets received
    function claimWithdraw(uint256 requestId)
        public
        virtual
        nonReentrant
        returns (uint256 assets)
    {
        assets = _claimWithdraw(requestId);
    }

    /// @notice Claim multiple matured withdrawal requests in one transaction
    /// @param requestIds Array of request IDs to claim
    /// @return total Total assets received
    function claimBatch(uint256[] calldata requestIds)
        external
        virtual
        nonReentrant
        returns (uint256 total)
    {
        for (uint256 i = 0; i < requestIds.length; i++) {
            total += _claimWithdraw(requestIds[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC4626 OVERRIDES                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Request withdrawal of assets (ERC4626 override)
    /// @dev Creates a withdrawal request instead of instant withdrawal
    /// @param assets Amount of assets to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param owner Address of the share owner
    /// @return shares Amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets);
        _requestWithdraw(shares, receiver, owner);
    }

    /// @notice Request redemption of shares (ERC4626 override)
    /// @dev Creates a withdrawal request instead of instant redemption
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive the withdrawn assets
    /// @param owner Address of the share owner
    /// @return assets Amount of assets reserved for withdrawal
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 assets)
    {
        assets = _requestWithdraw(shares, receiver, owner);
    }

    /// @dev override to add whenNotPaused modifier
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /// @dev override to add whenNotPaused modifier
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /// @notice Total assets excluding reserved amounts for pending withdrawals
    /// @dev Returns liquid assets available for share calculations
    /// @return Total IR tokens held by vault minus reserved amounts
    function totalAssets() public view virtual override returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return IERC20(asset()).balanceOf(address(this)) - $.totalReserved;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get total rewards compounded since inception
    /// @return Total IR tokens compounded
    function totalCompounded() external view virtual returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.totalCompounded;
    }

    /// @notice Get fixed withdrawal period
    /// @return The withdrawal period in seconds
    function withdrawalPeriod() external view virtual returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.withdrawalPeriod;
    }

    /// @notice Get total assets reserved for pending withdrawals
    /// @return Total reserved assets
    function totalReserved() external view virtual returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.totalReserved;
    }

    /// @notice Get the current request length
    /// @return The number of withdrawal requests created
    function requestLength() external view virtual returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.requestLength;
    }

    /// @notice Get withdrawal request by ID
    /// @param requestId The request ID
    /// @return The withdrawal request struct
    function requests(uint256 requestId)
        external
        view
        virtual
        returns (WithdrawalRequest memory)
    {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.requests[requestId];
    }

    /// @notice Returns the total amount of assets queued for withdrawal across all unprocessed tickets
    /// @dev Checks for queued tckets and sums amounts
    /// @dev An edge case exists where this could be temporarily out if unlock time is decreased
    /// @return queuedAmount The total assets in queue, not yet claimable
    function getQueuedAmount() public view returns (uint256 queuedAmount) {
        StakedIRStorage storage $ = _stakedIRStorage();

        uint256 len = $.requestLength;
        // reverse loop as time based, can exit loop as soon as it finds a ticket that is unlockable
        for (uint256 i = len; i > 0; i--) {
            WithdrawalRequest memory ticket = $.requests[i];
            // break loop if unlock time has passed
            if (ticket.unlockTime <= block.timestamp) break;
            queuedAmount += ticket.assets;
        }
    }

    /// @notice Returns the total amount of assets ready to be claimed
    /// @dev Calculated as total reserved minus queued amounts
    /// @return claimable The total assets that have passed unlock time and can be claimed
    function getClaimableAmount() external view returns (uint256 claimable) {
        StakedIRStorage storage $ = _stakedIRStorage();
        claimable = $.totalReserved - getQueuedAmount();
    }

    /// @notice Get withdrawal request details
    /// @param requestId The request ID
    /// @return claimed The state of the request
    /// @return shares Amount of shares
    /// @return assets Amount of assets
    /// @return unlockTime When the request can be claimed
    /// @return receiver The receiver address
    function getWithdrawalRequest(uint256 requestId)
        external
        view
        virtual
        returns (
            bool claimed,
            uint256 shares,
            uint256 assets,
            uint256 unlockTime,
            address receiver
        )
    {
        StakedIRStorage storage $ = _stakedIRStorage();

        if (requestId > $.requestLength || requestId == 0) {
            revert InvalidRequestId();
        }

        WithdrawalRequest memory ticket = $.requests[requestId];
        claimed = ticket.claimed;
        shares = ticket.shares;
        assets = ticket.assets;
        unlockTime = ticket.unlockTime;
        receiver = ticket.receiver;
    }

    /// @notice Check if a withdrawal request is ready to claim
    /// @param requestId The request ID
    /// @return ready True if the request can be claimed
    function isWithdrawalReady(uint256 requestId)
        external
        view
        virtual
        returns (bool ready)
    {
        StakedIRStorage storage $ = _stakedIRStorage();

        if (requestId > $.requestLength || requestId == 0) return false;

        WithdrawalRequest memory ticket = $.requests[requestId];
        return ticket.assets > 0 && block.timestamp >= ticket.unlockTime
            && !ticket.claimed;
    }

    /// @notice Preview the unlock time for a new request
    /// @return The estimated unlock time
    function previewUnlockTime() external view returns (uint256) {
        StakedIRStorage storage $ = _stakedIRStorage();
        return block.timestamp + $.withdrawalPeriod;
    }

    /// @notice Get all withdrawal request IDs for a user
    /// @param user Address of the user
    /// @return Array of request IDs belonging to the user
    function getUserRequests(address user)
        external
        view
        returns (uint256[] memory)
    {
        StakedIRStorage storage $ = _stakedIRStorage();
        return $.userRequests[user];
    }
}
