// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";

import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {InfraredBERAConstants} from "./InfraredBERAConstants.sol";

/// @title InfraredBERADepositor
/// @notice Depositor to deposit BERA to CL for Infrared liquid staking token
contract InfraredBERADepositor is Upgradeable, IInfraredBERADepositor {
    uint8 public constant ETH1_ADDRESS_WITHDRAWAL_PREFIX = 0x01;
    address public DEPOSIT_CONTRACT;

    /// @inheritdoc IInfraredBERADepositor
    address public InfraredBERA;

    struct Slip {
        /// block.timestamp at which deposit slip issued
        uint96 timestamp;
        /// fee escrow for beacon deposit request
        uint256 fee;
        /// amount of BERA to be deposited to deposit contract at execute
        uint256 amount;
    }

    /// @inheritdoc IInfraredBERADepositor
    mapping(uint256 => Slip) public slips;

    /// @inheritdoc IInfraredBERADepositor
    uint256 public fees;

    /// @inheritdoc IInfraredBERADepositor
    uint256 public nonceSlip;
    /// @inheritdoc IInfraredBERADepositor
    uint256 public nonceSubmit;

    /// @notice Initialize the contract (replaces the constructor)
    /// @param _gov Address for admin / gov to upgrade
    /// @param _keeper Address for keeper
    /// @param ibera The initial IBERA address
    /// @param _depositContract The ETH2 (Berachain) Deposit Contract Address
    function initialize(
        address _gov,
        address _keeper,
        address ibera,
        address _depositContract
    ) public initializer {
        if (
            _gov == address(0) || _keeper == address(0) || ibera == address(0)
                || _depositContract == address(0)
        ) revert Errors.ZeroAddress();
        __Upgradeable_init();
        InfraredBERA = ibera;
        nonceSlip = 1;
        nonceSubmit = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);
        DEPOSIT_CONTRACT = _depositContract;
    }

    /// @notice Checks whether enough time has passed beyond min delay
    /// @param then The block timestamp in past
    /// @param current The current block timestamp now
    /// @return has Whether time between then and now exceeds forced min delay
    function _enoughtime(uint96 then, uint96 current)
        private
        pure
        returns (bool has)
    {
        unchecked {
            has = (current - then) >= InfraredBERAConstants.FORCED_MIN_DELAY;
        }
    }

    /// @inheritdoc IInfraredBERADepositor
    function reserves() public view returns (uint256) {
        return address(this).balance - fees;
    }

    /// @inheritdoc IInfraredBERADepositor
    function queue(uint256 amount) external payable returns (uint256 nonce) {
        // @dev can be called by withdrawor when rebalancing and sweeping
        if (
            msg.sender != InfraredBERA
                && msg.sender != IInfraredBERA(InfraredBERA).withdrawor()
        ) {
            revert Errors.Unauthorized(msg.sender);
        }

        if (amount == 0 || msg.value < amount) revert Errors.InvalidAmount();
        uint256 fee = msg.value - amount;
        if (fee < InfraredBERAConstants.MINIMUM_DEPOSIT_FEE) {
            revert Errors.InvalidFee();
        }
        fees += fee;

        nonce = nonceSlip++;
        slips[nonce] =
            Slip({timestamp: uint96(block.timestamp), fee: fee, amount: amount});
        emit Queue(nonce, amount);
    }

    /// @inheritdoc IInfraredBERADepositor
    function execute(bytes calldata pubkey, uint256 amount) external {
        bool kpr = IInfraredBERA(InfraredBERA).keeper(msg.sender);
        // check if in *current* validator set on Infrared
        if (!IInfraredBERA(InfraredBERA).validator(pubkey)) {
            revert Errors.InvalidValidator();
        }
        // check stake + amount divided by 1 gwei fits in uint64
        if (
            amount == 0 || (amount % 1 gwei) != 0
                || ((IInfraredBERA(InfraredBERA).stakes(pubkey) + amount) / 1 gwei)
                    > type(uint64).max
        ) {
            revert Errors.InvalidAmount();
        }

        address operator = IInfraredBERA(InfraredBERA).infrared(); // infrared operator for validator
        address currentOperator =
            IBeaconDeposit(DEPOSIT_CONTRACT).getOperator(pubkey);
        // Add first deposit validation
        if (currentOperator == address(0)) {
            if (amount != InfraredBERAConstants.INITIAL_DEPOSIT) {
                revert Errors.InvalidAmount();
            }
        } else {
            // Verify subsequent deposit requirements
            if (currentOperator != operator) {
                revert Errors.UnauthorizedOperator();
            }
        }

        // check if governor has added a valid deposit signature to avoid keeper mistakenly burning
        bytes memory signature = IInfraredBERA(InfraredBERA).signatures(pubkey);
        if (signature.length == 0) revert Errors.InvalidSignature();

        // cache for event after the bundling while loop
        address withdrawor = IInfraredBERA(InfraredBERA).withdrawor();
        uint256 _nonce = nonceSubmit; // start
        uint256 nonce; // end (inclusive)
        uint256 fee;

        // bundle nonces to meet up to amount
        // @dev care should be taken with choice of amount parameter not to reach gas limit
        uint256 remaining = amount;
        while (remaining > 0) {
            nonce = nonceSubmit;
            Slip memory s = slips[nonce];
            if (s.amount == 0) revert Errors.InvalidAmount();

            // @dev allow user to force stake into infrared validator if enough time has passed
            // TODO: check signature not needed (ignored) on second deposit to pubkey (think so)
            if (!kpr && !_enoughtime(s.timestamp, uint96(block.timestamp))) {
                revert Errors.Unauthorized(msg.sender);
            }

            // first time loop ever hits slip dedicate fee to this call
            // @dev for large slip requiring multiple separate calls to execute, keeper must front fee in subsequent calls
            // @dev but should make up for fronting via protocol fees on size
            if (s.fee > 0) {
                fee += s.fee;
                s.fee = 0;
            }

            // either use all of slip amount and increment nonce if remaining > slip amount or use remaining
            // not fully filling slip in this call
            uint256 delta = remaining > s.amount ? s.amount : remaining;
            s.amount -= delta;
            if (s.amount == 0) nonceSubmit++;
            slips[nonce] = s;

            // always >= 0 due to delta ternary
            remaining -= delta;
        }

        // remove accumulated escrowed fee from each request in bundled deposits and refund to keeper
        fees -= fee;

        // @dev ethereum/consensus-specs/blob/dev/specs/phase0/validator.md#eth1_address_withdrawal_prefix
        bytes memory credentials = abi.encodePacked(
            ETH1_ADDRESS_WITHDRAWAL_PREFIX,
            uint88(0), // 11 zero bytes
            withdrawor
        ); // TODO: check correct
        // if operator already exists on BeaconDeposit, it must be set to zero for new deposits
        if (IBeaconDeposit(DEPOSIT_CONTRACT).getOperator(pubkey) == operator) {
            operator = address(0);
        }
        IBeaconDeposit(DEPOSIT_CONTRACT).deposit{value: amount}(
            pubkey, credentials, signature, operator
        );

        // register update to stake
        IInfraredBERA(InfraredBERA).register(pubkey, int256(amount)); // safe as max fits in uint96

        // sweep fee back to keeper to cover gas
        if (fee > 0) SafeTransferLib.safeTransferETH(msg.sender, fee);

        emit Execute(pubkey, _nonce, nonce, amount);
    }
}
