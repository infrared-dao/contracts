// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {IInfraredBERAClaimor} from "src/interfaces/IInfraredBERAClaimor.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";

import {InfraredBERAConstants} from "./InfraredBERAConstants.sol";

/// @title InfraredBERAWithdraworLite
/// @notice Withdrawor Lite to be upgraded when voluntary exits are enabled
contract InfraredBERAWithdraworLite is Upgradeable, IInfraredBERAWithdrawor {
    uint8 public constant WITHDRAW_REQUEST_TYPE = 0x01;
    address public WITHDRAW_PRECOMPILE; // @dev: EIP7002

    /// @inheritdoc IInfraredBERAWithdrawor
    address public InfraredBERA;

    address public claimor;

    struct Request {
        /// receiver of withdrawn bera funds
        address receiver;
        /// block.timestamp at which withdraw request issued
        uint96 timestamp;
        /// fee escrow for withdraw precompile request
        uint256 fee;
        /// amount of withdrawn bera funds left to submit request to withdraw precompile
        uint256 amountSubmit;
        /// amount of withdrawn bera funds left to process from funds received via withdraw request
        uint256 amountProcess;
    }

    /// @inheritdoc IInfraredBERAWithdrawor
    mapping(uint256 => Request) public requests;

    /// @inheritdoc IInfraredBERAWithdrawor
    uint256 public fees;

    /// @inheritdoc IInfraredBERAWithdrawor
    uint256 public rebalancing;

    /// @inheritdoc IInfraredBERAWithdrawor
    uint256 public nonceRequest;
    /// @inheritdoc IInfraredBERAWithdrawor
    uint256 public nonceSubmit;
    /// @inheritdoc IInfraredBERAWithdrawor
    uint256 public nonceProcess;

    /// @notice Initialize the contract (replaces the constructor)
    /// @param _gov Address for admin / gov to upgrade
    /// @param _keeper Address for keeper
    /// @param ibera The initial InfraredBERA address
    function initialize(address _gov, address _keeper, address ibera)
        public
        initializer
    {
        if (_gov == address(0) || _keeper == address(0) || ibera == address(0))
        {
            revert Errors.ZeroAddress();
        }
        __Upgradeable_init();
        InfraredBERA = ibera;

        nonceRequest = 1;
        nonceSubmit = 1;
        nonceProcess = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);
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

    /// @inheritdoc IInfraredBERAWithdrawor
    function reserves() public view returns (uint256) {
        return address(this).balance - fees;
    }

    /// @inheritdoc IInfraredBERAWithdrawor
    function queue(address, uint256) external payable returns (uint256) {
        revert Errors.WithdrawalsNotEnabled();
    }

    /// @inheritdoc IInfraredBERAWithdrawor
    function execute(bytes calldata, uint256) external payable {
        revert Errors.WithdrawalsNotEnabled();
    }

    /// @inheritdoc IInfraredBERAWithdrawor
    function process() external pure {
        revert Errors.WithdrawalsNotEnabled();
    }

    /// @inheritdoc IInfraredBERAWithdrawor
    function sweep(bytes calldata pubkey) external onlyGovernor {
        // only callable when withdrawals are not enabled
        if (IInfraredBERA(InfraredBERA).withdrawalsEnabled()) {
            revert Errors.Unauthorized(msg.sender);
        }
        // Check if validator has already exited - do this before checking stake
        if (IInfraredBERA(InfraredBERA).hasExited(pubkey)) {
            revert Errors.ValidatorForceExited();
        }
        // forced exit always withdraw entire stake of validator
        uint256 amount = IInfraredBERA(InfraredBERA).stakes(pubkey);

        // do nothing if InfraredBERA deposit would revert
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        if (amount < min) return;
        // revert if insufficient balance
        if (amount > address(this).balance) revert Errors.InvalidAmount();

        // todo: verfiy forced withdrawal against beacon roots

        // register new validator delta
        IInfraredBERA(InfraredBERA).register(pubkey, -int256(amount));

        // re-stake amount back to ibera depositor
        IInfraredBERADepositor(IInfraredBERA(InfraredBERA).depositor()).queue{
            value: amount
        }(amount - InfraredBERAConstants.MINIMUM_DEPOSIT_FEE);

        emit Sweep(InfraredBERA, amount);
    }

    /// @notice Handles excess stake that was refunded from a validator due to non-IBERA deposits exceeding MAX_EFFECTIVE_BALANCE
    /// @dev RESTRICTED USAGE: This function should ONLY be called when:
    /// - A non-IBERA entity deposits to our validator, pushing total stake above MAX_EFFECTIVE_BALANCE
    /// - The excess stake is refunded by the CL to this contract
    /// @dev The funds will enter the IBERA system as yield via the FeeReceivor
    /// @dev This should NEVER be used for:
    /// - Validators exited due to falling out of the validator set
    /// @param amount The amount of excess stake to sweep
    /// @custom:access Only callable by governance
    function sweepDust(uint256 amount) external onlyGovernor {
        // only callable when withdrawals are not enabled
        if (IInfraredBERA(InfraredBERA).withdrawalsEnabled()) {
            revert Errors.Unauthorized(msg.sender);
        }

        // revert if amount exceeds balance
        if (amount > address(this).balance) {
            revert Errors.InvalidAmount();
        }

        address receivor = IInfraredBERA(InfraredBERA).receivor();
        // transfer amount to ibera receivor
        SafeTransferLib.safeTransferETH(receivor, amount);

        emit Sweep(receivor, amount);
    }

    receive() external payable {}
}
