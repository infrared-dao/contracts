// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfraredBERAWithdrawor {
    /// @notice Emitted when a withdrawal is queued
    /// @param receiver The address that will receive the withdrawn BERA
    /// @param nonce The unique identifier for this withdrawal request
    /// @param amount The amount of BERA to be withdrawn
    event Queue(address indexed receiver, uint256 nonce, uint256 amount);

    /// @notice Emitted when a withdrawal is executed
    /// @param pubkey The validator's public key
    /// @param amount The amount of BERA withdrawn
    event Execute(bytes pubkey, uint256 amount);

    /// @notice Emitted when a queue is processed
    /// @param receiver The address receiving the withdrawn BERA
    /// @param nonce The nonce of the processed withdrawal
    /// @param amount The amount of BERA processed
    event Process(address indexed receiver, uint256 nonce, uint256 amount);

    /// @notice Emitted when a withdrawal request range is processed
    /// @param startRequestId First request processed
    /// @param finishRequestId Last request processed
    event ProcessRange(uint256 startRequestId, uint256 finishRequestId);

    /// @notice Emitted when a claim is processed
    /// @param receiver The address receiving the withdrawn BERA
    /// @param nonce The nonce of the processed withdrawal
    /// @param amount The amount of BERA processed
    event Claimed(address indexed receiver, uint256 nonce, uint256 amount);

    /// @notice Emitted when funds are swept from a force-exited validator
    /// @param receiver The address receiving the swept BERA
    /// @param amount The amount of BERA swept
    event Sweep(address indexed receiver, uint256 amount);

    /// @notice Emitted when min activation balance is updated by governance
    /// @param newMinActivationBalance New value for min activation balance to maintain activity
    event MinActivationBalanceUpdated(uint256 newMinActivationBalance);

    /// @notice The address of the InfraredBERA contract
    function InfraredBERA() external view returns (address);

    /// @notice Sweeps forced withdrawals to InfraredBERA to re-stake principal
    /// @param pubkey The validator's public key to sweep funds from
    /// @dev Only callable when withdrawals are disabled and by keeper
    // function sweep(bytes calldata pubkey) external;

    /// @notice State of a withdrawal request ticket.
    /// @dev QUEUED: Ticket is queued and awaiting processing. PROCESSED: Ticket is finalized and claimable (or rebalanced for depositor). CLAIMED: Ticket has been claimed by the receiver.
    enum RequestState {
        QUEUED,
        PROCESSED,
        CLAIMED
    }

    /// @notice The request struct for withdrawal requests.
    /// @param state records whether queued, processed or claimed
    /// @param timestamp The block.timestamp at which the withdraw request was issued.
    /// @param receiver The address of the receiver of the withdrawn BERA funds.
    /// @param amount The amount of BERA to be claimed by receiver.
    /// @param accumulatedAmount Running total amount withdrawn inclusive of this ticket.
    struct WithdrawalRequest {
        RequestState state;
        uint88 timestamp;
        address receiver;
        uint128 amount;
        uint128 accumulatedAmount;
    }

    /// @notice Mapping of request IDs to withdrawal request tickets.
    /// @dev Key is the `requestId` (starting at 1), and value is the `WithdrawalRequest` struct.
    function requests(uint256 nonce)
        external
        view
        returns (
            RequestState state,
            uint88 timestamp,
            address receiver,
            uint128 amount,
            uint128 accumulatedAmount
        );

    /// @notice Struct to track pending withdrawals with expiry
    struct PendingWithdrawal {
        uint160 amount;
        uint96 expiryBlock;
        bytes32 pubkeyHash;
    }

    /// @notice Sums all current pending withdrawals as helper for keeper to calculate how much needs to be executed next
    /// @param pubkeyHash keccak256 of public key for validator to get pending withdrawals for
    /// @return total Sum amount in bera, pending on CL to return to contract
    /// @dev Iterates through pending withdrawals, counting only those that have not expired (fulfilled)
    function getTotalPendingWithdrawals(bytes32 pubkeyHash)
        external
        view
        returns (uint256 total);

    /// @notice Amount of BERA internally set aside to process withdraw compile requests from funds received on successful requests
    function reserves() external view returns (uint256);

    /// @notice Retrieves the current fee required by the withdrawal precompile.
    /// @return fee The fee (in wei) required for a withdrawal request.
    /// @dev Performs a static call to the precompile. Reverts if the call fails or the response is invalid (not 32 bytes).
    function getFee() external view returns (uint256 fee);

    /// @notice Returns the total amount of BERA queued for withdrawal across all unprocessed tickets.
    /// @return queuedAmount The total amount of BERA (in wei) in `QUEUED` tickets from `requestsFinalisedUntil + 1` to `requestLength`.
    /// @dev Calculates the difference between the cumulative amount at `requestLength` and `requestsFinalisedUntil`.
    /// @dev Returns 0 if `requestLength == requestsFinalisedUntil` (no unprocessed tickets) or `requestLength == 0` (no tickets queued).
    /// @dev Assumes tickets from `requestsFinalisedUntil + 1` to `requestLength` are in `QUEUED` state, as enforced by `process`.
    function getQueuedAmount() external view returns (uint256 queuedAmount);

    /// @notice Calculates the highest request ID that can be finalized by `process` given the current reserves.
    /// @return newRequestsFinalisedUntil The highest `requestId` (inclusive) that can be processed without exceeding available reserves, or 0 if no tickets can be processed.
    /// @dev Iterates through unprocessed tickets (`requestsFinalisedUntil + 1` to `requestLength`) to find the maximum number of requests whose cumulative amount does not exceed `reserves()`.
    /// @dev Returns `requestsFinalisedUntil` if no additional tickets can be processed due to insufficient reserves.
    function getRequestsToProcess()
        external
        view
        returns (uint256 newRequestsFinalisedUntil);

    /// @notice Queues a withdraw request from InfraredBERA
    /// @param receiver The address to receive withdrawn funds
    /// @param amount The amount of funds to withdraw
    /// @return nonce The unique identifier for this withdrawal request
    /// @dev Requires msg.value to cover minimum withdrawal fee
    function queue(address receiver, uint256 amount)
        external
        returns (uint256 nonce);

    /// @notice Executes a withdraw request to withdraw precompile
    /// @param pubkey The validator's public key to withdraw from
    /// @param amount The amount of BERA to withdraw
    /// @dev Payable to cover any additional fees required by precompile
    /// @dev Only callable by keeper
    // function execute(bytes calldata pubkey, uint256 amount) external payable;

    /// @notice Finalizes a range of withdrawal requests, marking them as claimable or rebalancing to the depositor.
    /// @param newRequestsFinalisedUntil The highest `requestId` to finalize (inclusive).
    /// @dev Reverts if:
    /// - `newRequestsFinalisedUntil` exceeds `requestLength`.
    /// - `newRequestsFinalisedUntil` is less than or equal to `requestsFinalisedUntil`.
    /// - Available reserves are insufficient for the total amount to finalize.
    /// @dev Accumulates amounts for depositor rebalancing into a single call to `InfraredBERADepositor.queue`.
    /// @dev Updates `totalClaimable` for non-depositor tickets.
    function process(uint256 newRequestsFinalisedUntil) external;

    /// @notice Claims a finalized withdrawal request for a user.
    /// @param requestId The ID of the withdrawal request to claim.
    /// @dev Reverts if:
    /// - `requestId` exceeds `requestsFinalisedUntil` (not finalized).
    /// - Ticket is not in `PROCESSED` state or belongs to the depositor.
    /// @dev Transitions the ticket to `CLAIMED` and transfers the amount to the receiver.
    function claim(uint256 requestId) external;

    /// @notice Claims multiple finalized withdrawal requests in a single transaction.
    /// @param requestIds An array of request IDs to claim.
    /// @param receiver recipient address of all requestId's
    /// @dev Reverts if:
    /// - Any `requestId` exceeds `requestsFinalisedUntil` (not finalized).
    /// - Any ticket is not in `PROCESSED` state or belongs to the depositor.
    /// @dev Transitions each ticket to `CLAIMED` and transfers the total amount to the caller.
    /// @dev Emits a `Claimed` event for each claimed ticket.
    function claimBatch(uint256[] calldata requestIds, address receiver)
        external;
}
