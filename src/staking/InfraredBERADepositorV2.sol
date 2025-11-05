// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

/// @title InfraredBERADepositorV2
/// @notice Depositor to deposit BERA to CL for Infrared liquid staking token
contract InfraredBERADepositorV2 is Upgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice https://eth2book.info/capella/part2/deposits-withdrawals/withdrawal-processing/
    uint8 public constant ETH1_ADDRESS_WITHDRAWAL_PREFIX = 0x01;
    /// @notice The Deposit Contract Address for Berachain
    address public DEPOSIT_CONTRACT;
    /// @notice the main InfraredBERA contract address
    address public InfraredBERA;
    /// @notice the queued amount of BERA to be deposited
    uint256 public reserves;

    /// @notice Minimum deposit for a validator to become active.
    uint256 public minActivationDeposit;

    /// Reserve storage slots for future upgrades for safety
    uint256[39] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new deposit queued
    /// @param amount New deposit amount in BERA
    event Queue(uint256 amount);

    /// @notice Emitted when a consensus layer deposit queued to a validator
    /// @param pubkey Public key af validator to deposit to
    /// @param amount Validator deposit amount
    event Execute(bytes pubkey, uint256 amount);

    /// @notice Emitted when min activation deposit is updated by governance
    /// @param newMinActivationDeposit New value for min activation deposit to guarentee set inclusion
    event MinActivationDepositUpdated(uint256 newMinActivationDeposit);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initialize V2
    function initializeV2() external onlyGovernor {
        // needs to be enough to guarentee activation (250k) + inclusion in active set (depends on competition)
        minActivationDeposit = 500_000 ether;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      QUEUE, EXECUTE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Queues a deposit by sending BERA to this contract and storing the amount
    /// in reserves account for beacon deposits on batch
    function queue() external payable {
        /// @dev can only be called by InfraredBERA for adding to the reserves and by withdrawor for rebalancing
        /// when validators get kicked out of the set, TODO: link the set kickout code.
        if (
            msg.sender != InfraredBERA
                && msg.sender != IInfraredBERAV2(InfraredBERA).withdrawor()
        ) {
            revert Errors.Unauthorized(msg.sender);
        }

        // @dev accumulate the amount of BERA to be deposited with `execute`
        reserves += msg.value;

        emit Queue(msg.value);
    }

    /// @notice Executes initial deposit for 10k bera to the specified pubkey.
    /// @param pubkey The pubkey of the validator to deposit for
    /// @dev Only callable by the keeper
    /// @dev Only callable if the deposits are enabled
    /// @dev Only callable for initial deposit
    function executeInitialDeposit(bytes calldata pubkey) external onlyKeeper {
        // check if pubkey is a valid validator being tracked by InfraredBERA
        if (!IInfraredBERAV2(InfraredBERA).validator(pubkey)) {
            revert Errors.InvalidValidator();
        }

        // The validator balance must be zero
        if (IInfraredBERAV2(InfraredBERA).stakes(pubkey) != 0) {
            revert Errors.AlreadyInitiated();
        }

        // @dev determin what to set the operator, if the operator is not set we know this is the first deposit and we should set it to infrared.
        // if not we know this is the second or subsequent deposit (subject to internal test below) and we should set the operator to address(0).
        address operatorBeacon =
            IBeaconDeposit(DEPOSIT_CONTRACT).getOperator(pubkey);
        address operator = IInfraredBERAV2(InfraredBERA).infrared();
        // check if first beacon deposit by checking if the registered operator is set
        if (operatorBeacon != address(0)) {
            revert Errors.AlreadyInitiated();
        }

        uint256 amount = InfraredBERAConstants.INITIAL_DEPOSIT;

        // @notice load the signature for the pubkey. This is only used for the first deposit but can be re-used safley since this is checked only on the first deposit.
        // https://github.com/berachain/beacon-kit/blob/395085d18667e48395503a20cd1b367309fe3d11/state-transition/core/state_processor_staking.go#L101
        bytes memory signature =
            IInfraredBERAV2(InfraredBERA).signatures(pubkey);
        if (signature.length == 0) {
            revert Errors.InvalidSignature();
        }

        // @notice ethereum/consensus-specs/blob/dev/specs/phase0/validator.md#eth1_address_withdrawal_prefix
        // @dev similar to the signiture above, this is only used for the first deposit but can be re-used safley since this is checked only on the first deposit.
        bytes memory credentials = abi.encodePacked(
            ETH1_ADDRESS_WITHDRAWAL_PREFIX,
            uint88(0), // 11 zero bytes
            IInfraredBERAV2(InfraredBERA).withdrawor()
        );

        /// @dev reduce the reserves by the amount deposited.
        reserves -= amount;

        /// @dev register the increase in stake to the validator.
        IInfraredBERAV2(InfraredBERA).register(pubkey, int256(amount));

        // @dev deposit the BERA to the deposit contract.
        // @dev the amount being divided by 1 gwei is checked inside.
        IBeaconDeposit(DEPOSIT_CONTRACT).deposit{value: amount}(
            pubkey, credentials, signature, operator
        );

        emit Execute(pubkey, amount);
    }

    /// @notice Executes a deposit to the deposit contract for the specified pubkey and amount.
    /// @param header The Beacon block header data
    /// @param validator The full validator struct to deposit for
    /// @param validatorMerkleWitness Merkle witness for validator
    /// @param balanceMerkleWitness Merkle witness for balance container
    /// @param validatorIndex index of validator
    /// @param balanceLeaf 32 bytes chunk including packed balance
    /// @param amount The amount of BERA to deposit
    /// @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
    /// @dev Only callable by the keeper
    /// @dev Only callable if the deposits are enabled
    /// @dev Only for deposits subsequent to initialization
    function execute(
        BeaconRootsVerify.BeaconBlockHeader calldata header,
        BeaconRootsVerify.Validator calldata validator,
        bytes32[] calldata validatorMerkleWitness,
        bytes32[] calldata balanceMerkleWitness,
        uint256 validatorIndex,
        bytes32 balanceLeaf,
        uint256 amount,
        uint256 nextBlockTimestamp
    ) external onlyKeeper {
        // cache pubkey
        bytes memory pubkey = validator.pubkey;

        // check if pubkey is a valid validator being tracked by InfraredBERA
        if (!IInfraredBERAV2(InfraredBERA).validator(pubkey)) {
            revert Errors.InvalidValidator();
        }

        // The amount must be a multiple of 1 gwei as per the deposit contract, cannot be more eth than we have, and must be at least the minimum deposit amount.
        if (amount == 0 || (amount % 1 gwei) != 0 || amount > reserves) {
            revert Errors.InvalidAmount();
        }

        // check proof data is not stale
        if (
            block.timestamp
                > nextBlockTimestamp
                    + IInfraredBERAV2(InfraredBERA).proofTimestampBuffer()
        ) revert Errors.StaleProof();

        // Verify stake
        uint256 stake = IInfraredBERAV2(InfraredBERA).stakes(pubkey);
        // verify stake amount againt CL via beacon roots proof
        if (
            !BeaconRootsVerify.verifyValidatorBalance(
                header,
                balanceMerkleWitness,
                validatorIndex,
                stake
                    + IInfraredBERAWithdrawor(
                        IInfraredBERAV2(InfraredBERA).withdrawor()
                    ).getTotalPendingWithdrawals(keccak256(pubkey)),
                balanceLeaf,
                nextBlockTimestamp
            )
        ) {
            revert Errors.BalanceMissmatch();
        }

        // cache the withdrawor address since we will be using it multiple times.
        address withdrawor = IInfraredBERAV2(InfraredBERA).withdrawor();

        // verify withdrawal address is set correctly against consensus layer
        // note: since this verifies all validator info, all subsequent validator checks in this call can be assumed to match CL
        if (
            // note: beaconroots call above, so we can now internally verify against state root
            !BeaconRootsVerify.verifyValidatorWithdrawalAddress(
                header.stateRoot,
                validator,
                validatorMerkleWitness,
                validatorIndex,
                withdrawor
            )
        ) revert Errors.InvalidWithdrawalAddress();

        // Verify validator has not been exited
        // Default state for all epoch values is type(uint64).max (https://eth2book.info/latest/part3/config/constants/)
        if (validator.exitEpoch != type(uint64).max) {
            revert Errors.AlreadyExited();
        }

        // The validator balance + amount must not surpase MaxEffectiveBalance of 10 million BERA.
        if (stake + amount > InfraredBERAConstants.MAX_EFFECTIVE_BALANCE) {
            revert Errors.ExceedsMaxEffectiveBalance();
        }

        address operator = IInfraredBERAV2(InfraredBERA).infrared();
        {
            // @dev determin what to set the operator, if the operator is not set we know this is the first deposit and we should set it to infrared.
            // if not we know this is the second or subsequent deposit (subject to internal test below) and we should set the operator to address(0).
            address operatorBeacon =
                IBeaconDeposit(DEPOSIT_CONTRACT).getOperator(pubkey);

            // check if first beacon deposit by checking if the registered operator is set
            if (operatorBeacon == address(0)) {
                revert Errors.NotInitialized();
            }
            // Not first deposit. Ensure the correct operator is set for subsequent deposits
            if (operatorBeacon != operator) {
                revert Errors.UnauthorizedOperator();
            }
        }

        // check whether first deposit via internal logic to protect against bypass beacon deposit attack
        if (!IInfraredBERAV2(InfraredBERA).staked(pubkey)) {
            revert Errors.OperatorAlreadySet();
        }

        // ensure second deposit is enough to meet active validator set
        if (stake < minActivationDeposit) {
            if (amount < minActivationDeposit - stake) {
                revert Errors.DepositMustBeGreaterThanMinActivationBalance();
            }
        }

        // A nuance of berachain is that subsequent deposits set operator to address(0)
        operator = address(0);

        // @notice load the signature for the pubkey. This is only used for the first deposit but can be re-used safley since this is checked only on the first deposit.
        // https://github.com/berachain/beacon-kit/blob/395085d18667e48395503a20cd1b367309fe3d11/state-transition/core/state_processor_staking.go#L101
        bytes memory signature =
            IInfraredBERAV2(InfraredBERA).signatures(pubkey);
        if (signature.length == 0) {
            revert Errors.InvalidSignature();
        }

        // @notice ethereum/consensus-specs/blob/dev/specs/phase0/validator.md#eth1_address_withdrawal_prefix
        // @dev similar to the signiture above, this is only used for the first deposit but can be re-used safley since this is checked only on the first deposit.
        bytes memory credentials = abi.encodePacked(
            ETH1_ADDRESS_WITHDRAWAL_PREFIX,
            uint88(0), // 11 zero bytes
            withdrawor
        );

        /// @dev reduce the reserves by the amount deposited.
        reserves -= amount;

        /// @dev register the increase in stake to the validator.
        IInfraredBERAV2(InfraredBERA).register(pubkey, int256(amount));

        // @dev deposit the BERA to the deposit contract.
        // @dev the amount being divided by 1 gwei is checked inside.
        IBeaconDeposit(DEPOSIT_CONTRACT).deposit{value: amount}(
            pubkey, credentials, signature, operator
        );

        emit Execute(pubkey, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMinActivationDeposit(uint256 _minActivationDeposit)
        external
        onlyGovernor
    {
        if (
            _minActivationDeposit
                >= InfraredBERAConstants.MAX_EFFECTIVE_BALANCE
                    - InfraredBERAConstants.INITIAL_DEPOSIT
        ) revert Errors.ExceedsMaxEffectiveBalance();
        minActivationDeposit = _minActivationDeposit;
        emit MinActivationDepositUpdated(_minActivationDeposit);
    }
}
