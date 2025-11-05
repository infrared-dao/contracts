// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

/// @title InfraredBERAWithdrawor
/// @notice Manages withdrawal requests for BERA tokens from the consensus layer in the Infrared liquid staking protocol.
/// @dev Assumes BERA is returned via the EIP-7002 withdrawal precompile and credited to the contract. Inherits from `Upgradeable` for governance and upgradability.
/// @dev Tickets start at `requestId = 1`, and `requestLength` is incremented before assignment.
contract InfraredBERAWithdrawor is Upgradeable, IInfraredBERAWithdrawor {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the Withdraw Precompile settable in the next upgrade.
    address public WITHDRAW_PRECOMPILE; // @dev: EIP7002

    /// @notice The address of the `InfraredBERA.sol` contract.
    address public InfraredBERA;

    /// @notice The current number of withdrawal requests queued (next `requestId` to be assigned).
    uint256 public requestLength;

    /// @notice Mapping of request IDs to withdrawal request tickets.
    /// @dev Key is the `requestId` (starting at 1), and value is the `WithdrawalRequest` struct.
    mapping(uint256 => WithdrawalRequest) public requests;

    /// @notice The highest `requestId` that has been finalized by `process`.
    uint256 public requestsFinalisedUntil;

    /// @notice Total amount of BERA (in wei) marked as claimable (in `PROCESSED` state, non-depositor tickets).
    uint256 public totalClaimable;

    /// @notice Minimum balance for a validator to stay active.
    uint256 public minActivationBalance;

    /// @notice Length of pending withdrawals queue
    uint256 public pendingWithdrawalsLength;

    /// @dev holding slot for withdraworLite storage var
    uint256 public nonceProcess;

    /// @notice Mapping to track individual pending withdrawal amounts
    mapping(uint256 => PendingWithdrawal) public pendingWithdrawals;

    /// Reserve storage slots for future upgrades for safety
    uint256[39] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the contract for the next version, setting the withdrawal precompile address.
    /// @param _withdraw_precompile The address of the EIP-7002 withdrawal precompile.
    /// @dev Only callable by the governance role (`onlyGovernor`). Reverts if `_withdraw_precompile` is zero.
    function initializeV2(address _withdraw_precompile) external onlyGovernor {
        if (_withdraw_precompile == address(0)) {
            revert Errors.ZeroAddress();
        }
        WITHDRAW_PRECOMPILE = _withdraw_precompile;
        minActivationBalance = 250_000 ether;

        // reset overwritten storage vars
        delete pendingWithdrawalsLength;
        delete nonceProcess;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEWS                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the amount of BERA available for new withdrawals (excluding claimable funds).
    /// @return The contract’s balance minus `totalClaimable` (in wei).
    function reserves() public view returns (uint256) {
        return address(this).balance - totalClaimable;
    }

    /// @notice Retrieves the current fee required by the withdrawal precompile.
    /// @return fee The fee (in wei) required for a withdrawal request.
    /// @dev Performs a static call to the precompile. Reverts if the call fails or the response is invalid (not 32 bytes).
    function getFee() public view returns (uint256 fee) {
        // Read current fee from the contract.
        (bool success, bytes memory feeData) =
            WITHDRAW_PRECOMPILE.staticcall("");
        if (!success || feeData.length != 32) {
            revert Errors.InvalidPrecompileResponse();
        }
        fee = uint256(bytes32(feeData));
    }

    /// @notice Returns the total amount of BERA queued for withdrawal across all unprocessed tickets.
    /// @return queuedAmount The total amount of BERA (in wei) in `QUEUED` tickets from `requestsFinalisedUntil + 1` to `requestLength`.
    /// @dev Calculates the difference between the cumulative amount at `requestLength` and `requestsFinalisedUntil`.
    /// @dev Returns 0 if `requestLength == requestsFinalisedUntil` (no unprocessed tickets) or `requestLength == 0` (no tickets queued).
    /// @dev Assumes tickets from `requestsFinalisedUntil + 1` to `requestLength` are in `QUEUED` state, as enforced by `process`.
    function getQueuedAmount() public view returns (uint256 queuedAmount) {
        queuedAmount = uint256(
            requests[requestLength].accumulatedAmount
                - requests[requestsFinalisedUntil].accumulatedAmount
        );
    }

    /// @notice Calculates the highest request ID that can be finalized by `process` given the current reserves.
    /// @return newRequestsFinalisedUntil The highest `requestId` (inclusive) that can be processed without exceeding available reserves, or 0 if no tickets can be processed.
    /// @dev Iterates through unprocessed tickets (`requestsFinalisedUntil + 1` to `requestLength`) to find the maximum number of requests whose cumulative amount does not exceed `reserves()`.
    /// @dev Returns `requestsFinalisedUntil` if no additional tickets can be processed due to insufficient reserves.
    function getRequestsToProcess()
        external
        view
        returns (uint256 newRequestsFinalisedUntil)
    {
        uint256 finalised = requestsFinalisedUntil;
        uint256 len = requestLength;
        if (finalised == len) return 0;
        uint256 bal = reserves();
        uint256 accum = uint256(requests[finalised].accumulatedAmount);
        for (uint256 i = finalised + 1; i <= len; i++) {
            WithdrawalRequest memory ticket = requests[i];
            if (ticket.state != RequestState.QUEUED) continue;
            uint256 amount = uint256(ticket.accumulatedAmount) - accum;
            if (amount > bal) break;
            newRequestsFinalisedUntil = i;
        }
    }

    /// @notice Sums all current pending withdrawals as helper for keeper to calculate how much needs to be executed next
    /// @param pubkeyHash keccak256 of public key for validator to get pending withdrawals for
    /// @return total Sum amount in bera, pending on CL to return to contract
    /// @dev Iterates through pending withdrawals, counting only those that have not expired (fulfilled)
    function getTotalPendingWithdrawals(bytes32 pubkeyHash)
        public
        view
        returns (uint256 total)
    {
        // clean expired pending and total valid
        uint256 len = pendingWithdrawalsLength;
        uint256 currentBlock = block.number;

        // Iterate through all pending
        for (uint256 i = 0; i < len; i++) {
            PendingWithdrawal memory pending = pendingWithdrawals[i];
            if (
                uint256(pending.expiryBlock) >= currentBlock
                    && pending.pubkeyHash == pubkeyHash
            ) {
                // Add to total and keep non-expired withdrawal
                total += uint256(pending.amount);
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*        TICKETS - QUEUE, EXECUTE, PROCESS, CLAIM            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Queues a withdrawal request for BERA from the consensus layer.
    /// @param receiver The address to receive the withdrawn BERA (user or depositor for rebalancing).
    /// @param amount The amount of BERA to withdraw (in wei).
    /// @return requestId The unique ID assigned to the withdrawal request (starts at 1).
    /// @dev Only callable by the `InfraredBERA` contract or a keeper. Reverts if:
    /// - Caller is unauthorized (`msg.sender` is neither `InfraredBERA` nor a keeper).
    /// - Receiver is invalid (keeper cannot queue for non-depositor, non-keeper cannot queue for depositor).
    /// - Amount is zero for non-depositor or exceeds `InfraredBERA.confirmed()` balance.
    function queue(address receiver, uint256 amount)
        external
        whenNotPaused
        returns (uint256 requestId)
    {
        bool kpr = IInfraredBERAV2(InfraredBERA).keeper(msg.sender);
        address depositor = IInfraredBERAV2(InfraredBERA).depositor();
        // @dev rebalances can be queued by keeper but receiver must be depositor and amount must exceed deposit fee
        // sender must be iBERA or keeper
        if (msg.sender != InfraredBERA && !kpr) {
            revert Errors.Unauthorized(msg.sender);
        }
        // if keeper, it must be a rebalance call i.e. depositor is the receiver
        // only keeper can make rebalance calls
        if ((kpr && receiver != depositor) || (!kpr && receiver == depositor)) {
            revert Errors.InvalidReceiver();
        }
        if (amount == 0) {
            revert Errors.InvalidAmount();
        }
        // note: tickets start at 1
        requestLength++;
        requestId = requestLength;
        uint128 accumulated =
            uint128(requests[requestId - 1].accumulatedAmount + amount);
        requests[requestId] = WithdrawalRequest({
            state: RequestState.QUEUED,
            timestamp: uint88(block.timestamp),
            receiver: receiver,
            amount: uint128(amount),
            accumulatedAmount: accumulated
        });
        emit Queue(receiver, requestId, amount);
    }

    /// @notice Executes a withdrawal request via the EIP-7002 precompile.
    /// @param header The Beacon block header data
    /// @param validator The full validator struct to deposit for
    /// @param validatorMerkleWitness Merkle witness for validator
    /// @param balanceMerkleWitness Merkle witness for balance container
    /// @param validatorIndex index of validator in beacon state tree
    /// @param balanceLeaf 32 bytes chunk including packed balance
    /// @param amount The amount of BERA to withdraw (in wei).
    /// @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
    /// @dev Rules for withdrawals:
    /// - Pass 0 amount for full exit
    /// - If not full exit withdrawal amount must leave validator in active state, which means stake must remain above 250k
    /// @dev Only callable by a keeper (`onlyKeeper`). Reverts if:
    /// - Exceeds validator stake, is not divisible by 1 gwei, or exceeds `uint64` max.
    /// - Precompile call fails or returns invalid fee data.
    /// - Provided `msg.value` is less than the precompile fee.
    /// @dev Refunds excess `msg.value` to the keeper after the precompile call.
    /// @dev References:
    /// - https://eips.ethereum.org/EIPS/eip-7002
    /// - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4788.md
    function execute(
        BeaconRootsVerify.BeaconBlockHeader calldata header,
        BeaconRootsVerify.Validator calldata validator,
        bytes32[] calldata validatorMerkleWitness,
        bytes32[] calldata balanceMerkleWitness,
        uint256 validatorIndex,
        bytes32 balanceLeaf,
        uint256 amount,
        uint256 nextBlockTimestamp
    ) external payable onlyKeeper whenNotPaused {
        // cahce pubkey
        bytes memory pubkey = validator.pubkey;
        // cache internal account of validator stake
        uint256 stake = IInfraredBERAV2(InfraredBERA).stakes(pubkey);
        // sanity checks (stake > withdrawal amount, amount is divisible by 1 gwei, amount does not exceed theoretical max)
        if (
            stake < amount || (amount % 1 gwei) != 0
                || (amount / 1 gwei) > type(uint64).max
        ) {
            revert Errors.InvalidAmount();
        }

        // check proof data is not stale
        if (
            block.timestamp
                > nextBlockTimestamp
                    + IInfraredBERAV2(InfraredBERA).proofTimestampBuffer()
        ) revert Errors.StaleProof();

        // verify stake amount againt CL via beacon roots proof (include pending withdrawals)
        if (
            !BeaconRootsVerify.verifyValidatorBalance(
                header,
                balanceMerkleWitness,
                validatorIndex,
                stake + getTotalPendingWithdrawals(keccak256(pubkey)),
                balanceLeaf,
                nextBlockTimestamp
            )
        ) {
            revert Errors.BalanceMissmatch();
        }

        // verify validator and withdrawal address againt CL via beacon roots proof
        if (
            // note: beaconroots call above, so we can now internally verify against state root
            !BeaconRootsVerify.verifyValidatorWithdrawalAddress(
                header.stateRoot,
                validator,
                validatorMerkleWitness,
                validatorIndex,
                address(this)
            )
        ) {
            revert Errors.InvalidValidator();
        }

        // Verify validator has not been exited
        // Default state for all epoch values is type(uint64).max (https://eth2book.info/latest/part3/config/constants/)
        if (validator.exitEpoch != type(uint64).max) {
            revert Errors.AlreadyExited();
        }

        // check min active balance edge case
        // The withdrawal API will silently adjust the withdrawal amount to maintain a minimum stake of 250,000 $BERA. For instance, a validator with 350,000 $BERA staked that requests a withdrawal of 300,000 $BERA will only withdraw 100,000 $BERA.
        if (amount > 0 && stake - amount < minActivationBalance) {
            revert Errors.WithdrawMustLeaveMoreThanMinActivationBalance();
        }

        {
            // cap amount to outstanding queued amount
            // any validator rebalances will have to be queued by a keeper
            uint256 queuedAmount = getQueuedAmount();
            uint256 _reserves = reserves() - msg.value;
            uint256 _pending = totalPendingWithdrawals();
            if (queuedAmount < _reserves) {
                revert Errors.ProcessReserves();
            }
            if (queuedAmount < _reserves + _pending) {
                revert Errors.WaitForPending();
            }
            uint256 _amount = amount;
            // account for special case of full exit where amount = 0
            if (amount == 0) {
                _amount = stake;
            }
            // allow 1 gwei tolerance for dust
            if (_amount > (queuedAmount - _reserves - _pending + 1 gwei)) {
                revert Errors.InvalidAmount();
            }

            // track pending withdrawal to not double withdraw
            // ref: https://docs.berachain.com/nodes/guides/withdraw-stake#withdrawal-rules-process
            pendingWithdrawals[pendingWithdrawalsLength] = PendingWithdrawal({
                amount: uint160(_amount),
                expiryBlock: uint96(((block.number / 192) + 256) * 192),
                pubkeyHash: keccak256(pubkey)
            });
            pendingWithdrawalsLength += 1;
        }

        // cache balance prior to withdraw compile to calculate refund on fee
        uint256 _balance = address(this).balance;

        // static call precompile for dynamic fee
        uint256 feePayable = getFee();
        // fee is payable by caller (expectation is that they call `getFee` before calling `execute`)
        if (feePayable > msg.value) revert Errors.ExcessiveFee();

        // prepare RLP encoded data (ref: https://docs.berachain.com/nodes/guides/withdraw-stake#step-3-create-withdrawal-request)
        bytes memory encoded = abi.encodePacked(
            pubkey, // validator_pubkey
            uint64(amount / 1 gwei) // amount in gwei
        );
        // call precompile with encoded data to trigger exit amounts on CL
        (bool success,) = WITHDRAW_PRECOMPILE.call{value: feePayable}(encoded);
        if (!success) revert Errors.CallFailed();

        // calculate excess from withdraw precompile call to refund
        uint256 excess = msg.value - (_balance - address(this).balance);

        // special case amount = 0 represents full exit
        if (amount == 0) {
            // adjust amount to correct amount for internal accounting registration and event data
            amount = stake;
        }

        // register update to stake
        IInfraredBERAV2(InfraredBERA).register(pubkey, -int256(amount));

        // sweep excess fee back to keeper to cover gas
        if (excess > 0) SafeTransferLib.safeTransferETH(msg.sender, excess);

        emit Execute(pubkey, amount);
    }

    /// @notice Finalizes a range of withdrawal requests, marking them as claimable or rebalancing to the depositor.
    /// @param newRequestsFinalisedUntil The highest `requestId` to finalize (inclusive).
    /// @dev Reverts if:
    /// - `newRequestsFinalisedUntil` exceeds `requestLength`.
    /// - `newRequestsFinalisedUntil` is less than or equal to `requestsFinalisedUntil`.
    /// - Available reserves are insufficient for the total amount to finalize.
    /// @dev Accumulates amounts for depositor rebalancing into a single call to `InfraredBERADepositor.queue`.
    /// @dev Updates `totalClaimable` for non-depositor tickets.
    function process(uint256 newRequestsFinalisedUntil)
        external
        onlyKeeper
        whenNotPaused
    {
        if (newRequestsFinalisedUntil == 0) revert Errors.InvalidAmount();
        if (newRequestsFinalisedUntil > requestLength) {
            revert Errors.ExceedsRequestLength();
        }

        uint256 finalised = requestsFinalisedUntil;
        if (newRequestsFinalisedUntil <= finalised) {
            revert Errors.AlreadyFinalised();
        }

        uint256 delta = finalised == 0
            ? uint256(requests[newRequestsFinalisedUntil].accumulatedAmount)
            : uint256(
                requests[newRequestsFinalisedUntil].accumulatedAmount
                    - requests[finalised].accumulatedAmount
            );
        if (reserves() < delta) revert Errors.InsufficientBalance();

        address depositor = IInfraredBERAV2(InfraredBERA).depositor();
        uint256 depositorAmount = 0;
        uint256 claims = 0;
        uint256 lastProcessed = finalised;

        for (uint256 i = finalised + 1; i <= newRequestsFinalisedUntil; i++) {
            WithdrawalRequest memory ticket = requests[i];
            if (ticket.state == RequestState.QUEUED) {
                if (ticket.receiver == depositor) {
                    // deposit rebalances are sent within this func so can now be set as claimed
                    requests[i].state = RequestState.CLAIMED;
                    // queue up rebalance to depositor
                    depositorAmount += ticket.amount;
                    emit Claimed(ticket.receiver, i, ticket.amount);
                } else {
                    // set ticket as processed, can subsequently be claimed
                    requests[i].state = RequestState.PROCESSED;
                    // queue up claim amounts
                    claims += ticket.amount;
                    emit Process(ticket.receiver, i, ticket.amount);
                }
                lastProcessed = i;
            }
        }

        // store claim amounts
        if (claims > 0) {
            totalClaimable += claims;
        }
        // update storage requests finalised
        requestsFinalisedUntil = lastProcessed;

        // send rebalances to depositor
        if (depositorAmount > 0) {
            InfraredBERADepositorV2(depositor).queue{value: depositorAmount}();
        }

        emit ProcessRange(finalised + 1, lastProcessed);
    }

    /// @notice Claims a finalized withdrawal request for a user.
    /// @param requestId The ID of the withdrawal request to claim.
    /// @dev Reverts if:
    /// - `requestId` exceeds `requestsFinalisedUntil` (not finalized).
    /// - sender is not receiver or keeper
    /// - Ticket is not in `PROCESSED` state or belongs to the depositor.
    /// @dev Transitions the ticket to `CLAIMED` and transfers the amount to the receiver.
    function claim(uint256 requestId) external whenNotPaused {
        bool kpr = IInfraredBERAV2(InfraredBERA).keeper(msg.sender);
        // requests must have been processed before claiming
        if (requestId > requestsFinalisedUntil) revert Errors.NotFinalised();
        // load ticket from storage
        WithdrawalRequest storage ticket = requests[requestId];
        // authorized calls are limited to ticket receiver or protocol keepers
        if (!kpr && ticket.receiver != msg.sender) {
            revert Errors.Unauthorized(msg.sender);
        }
        if (ticket.state != RequestState.PROCESSED) {
            revert Errors.InvalidState();
        }
        // change ticket state to claimed
        ticket.state = RequestState.CLAIMED;
        // reduce reserved amount for claims
        totalClaimable -= ticket.amount;
        // transfer bera to receiver
        SafeTransferLib.safeTransferETH(ticket.receiver, ticket.amount);
        emit Claimed(ticket.receiver, requestId, ticket.amount);
    }

    /// @notice Claims multiple finalized withdrawal requests for same receiver in a single transaction.
    /// @param requestIds An array of request IDs to claim.
    /// @param receiver recipient address of all requestIds
    /// @dev Reverts if:
    /// - Any `requestId` exceeds `requestsFinalisedUntil` (not finalized).
    /// - Any ticket receiver is not the same as the others
    /// - Any ticket is not in `PROCESSED` state or belongs to the depositor.
    /// - sender is not receiver or keeper
    /// @dev Transitions each ticket to `CLAIMED` and transfers the total amount to the caller.
    /// @dev Emits a `Claimed` event for each claimed ticket.
    function claimBatch(uint256[] calldata requestIds, address receiver)
        external
        whenNotPaused
    {
        // authorized calls are limited to ticket receiver or protocol keepers
        bool kpr = IInfraredBERAV2(InfraredBERA).keeper(msg.sender);
        if (!kpr && receiver != msg.sender) {
            revert Errors.Unauthorized(msg.sender);
        }
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestId = requestIds[i];
            // requests must have been processed before claiming
            if (requestId > requestsFinalisedUntil) {
                revert Errors.NotFinalised();
            }
            // load ticket from storage
            WithdrawalRequest memory ticket = requests[requestId];
            // batch claims must have the same receiver
            if (ticket.receiver != receiver) {
                revert Errors.InvalidReceiver();
            }
            if (ticket.state != RequestState.PROCESSED) {
                revert Errors.InvalidState();
            }
            // change ticket state to claimed
            requests[requestId].state = RequestState.CLAIMED;
            // sum amounts for single transfer
            totalAmount += ticket.amount;
            emit Claimed(ticket.receiver, requestId, ticket.amount);
        }
        // reduce reserved amount for claims
        totalClaimable -= totalAmount;
        // transfer bera to receiver
        SafeTransferLib.safeTransferETH(receiver, totalAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EDGE CASES                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Handles Forced withdrawals from the CL.
    /// @param header The Beacon block header data
    /// @param validator The full validator struct to deposit for
    /// @param validatorIndex index of validator
    /// @param validatorMerkleWitness Merkle witness for validator
    /// @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
    /// @dev RESTRICTED USAGE: This function should ONLY be called when:
    /// - A validator has been forced to exit from the CL.
    /// @dev The funds will enter the IBERA system as a deposit via the InfraredBERADepositor.
    function sweepForcedExit(
        BeaconRootsVerify.BeaconBlockHeader calldata header,
        BeaconRootsVerify.Validator calldata validator,
        uint256 validatorIndex,
        bytes32[] calldata validatorMerkleWitness,
        uint256 nextBlockTimestamp
    ) external onlyGovernor {
        // Check if validator has already exited
        if (IInfraredBERAV2(InfraredBERA).hasExited(validator.pubkey)) {
            revert Errors.ValidatorForceExited();
        }
        // forced exit always withdraw entire stake of validator
        uint256 amount = IInfraredBERAV2(InfraredBERA).stakes(validator.pubkey);

        // verify stake amount againt CL must be zero for full exit
        // note: all subsequent validator info checks can be assumed correct as this check hashes all validator info
        if (
            !BeaconRootsVerify.verifyValidatorEffectiveBalance(
                header,
                validator,
                validatorMerkleWitness,
                validatorIndex,
                0,
                nextBlockTimestamp
            )
        ) {
            revert Errors.EffectiveBalanceMissmatch();
        }

        // verify exited
        // Default state for all epoch values is type(uint64).max (https://eth2book.info/latest/part3/config/constants/)
        if (validator.exitEpoch == type(uint64).max) {
            // not exited
            revert Errors.NotExited();
        }

        // revert if insufficient balance
        if (amount > reserves()) revert Errors.InvalidAmount();

        // register new validator delta
        IInfraredBERAV2(InfraredBERA).register(
            validator.pubkey, -int256(amount)
        );

        // re-stake amount back to ibera depositor
        InfraredBERADepositorV2(IInfraredBERAV2(InfraredBERA).depositor()).queue{
            value: amount
        }();

        emit Sweep(InfraredBERA, amount);
    }

    /// @notice Handles excess stake that was refunded from a validator due to non-IBERA (bypass) deposits exceeding MAX_EFFECTIVE_BALANCE
    /// @dev RESTRICTED USAGE: This function should ONLY be called when:
    /// - A non-IBERA entity deposits to our validator, pushing total stake above MAX_EFFECTIVE_BALANCE
    /// - The excess stake is refunded by the CL to this contract
    /// @dev The funds will enter the IBERA system as yield via the FeeReceivor
    /// @dev This should NEVER be used for:
    /// - Validators exited due to falling out of the validator set
    /// @param amount The amount of excess stake to sweep
    /// @custom:access Only callable by governance
    function sweepUnaccountedForFunds(uint256 amount) external onlyGovernor {
        // revert if amount exceeds balance available
        if (amount > reserves()) {
            revert Errors.InvalidAmount();
        }

        address receivor = IInfraredBERAV2(InfraredBERA).receivor();
        // transfer amount to ibera receivor
        SafeTransferLib.safeTransferETH(receivor, amount);

        emit Sweep(receivor, amount);
    }

    receive() external payable {}

    function setMinActivationBalance(uint256 _minActivationBalance)
        external
        onlyGovernor
    {
        minActivationBalance = _minActivationBalance;
        emit MinActivationBalanceUpdated(_minActivationBalance);
    }

    /// @dev Internal function to get total pending withdrawals over all validators and remove outdated ones
    function totalPendingWithdrawals() internal returns (uint256 total) {
        // clean expired pending and total valid
        uint256 len = pendingWithdrawalsLength;
        uint256 currentBlock = block.number;
        uint256 writeIndex = 0; // Tracks position for non-expired entries

        // Iterate through all pending
        for (uint256 i = 0; i < len; i++) {
            PendingWithdrawal memory pending = pendingWithdrawals[i];
            if (uint256(pending.expiryBlock) >= currentBlock) {
                // Add to total
                total += uint256(pending.amount);
                //  keep non-expired withdrawal
                if (writeIndex != i) {
                    pendingWithdrawals[writeIndex] = pending;
                }
                writeIndex++;
            }
        }
        // Update queue length to reflect only non-expired withdrawals
        pendingWithdrawalsLength = writeIndex;

        // Clear remaining slots (optional, for safety)
        for (uint256 i = writeIndex; i < len; i++) {
            delete pendingWithdrawals[i];
        }
    }
}
