//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WBERA} from "@berachain/WBERA.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {InfraredUpgradeable} from "src/core/InfraredUpgradeable.sol";
import {Errors} from "src/utils/Errors.sol";

/**
 * @title HarvestBaseCollector
 * @notice Auction contract for iBGT to WBERA conversion for base fees to compound to iBERA holders
 * @dev Simplified version of BribeCollector. This contract allows keepers to claim iBGT fees by paying a fixed WBERA amount,
 *      which is converted to native BERA and sent to the fee receiver for compounding.
 * @custom:oz-upgrades
 */
contract HarvestBaseCollector is InfraredUpgradeable {
    using SafeTransferLib for ERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        STORAGE                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice the addres of the fee recivor contract that compounds BERA to iBERA.
    address public feeReceivor;

    /// @notice the addres of iBGT, the expected fee token
    ERC20 public ibgt;

    /// @notice WBERA token that is used instead of native BERA token.
    WBERA public wbera;

    /// @notice Payout amount is a constant value that is paid by the caller of the `claimFees` function.
    uint256 public payoutAmount;

    // Reserve storage slots for future upgrades for safety
    uint256[20] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EVENTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when the payout amount is updated by the governor
     * @param oldPayoutAmount Previous payout amount
     * @param newPayoutAmount New payout amount set
     */
    event PayoutAmountSet(
        uint256 indexed oldPayoutAmount, uint256 indexed newPayoutAmount
    );

    /**
     * @notice Emitted when the fees are claimed
     * @param caller Caller of the `claimFees` function
     * @param recipient The address to which collected POL bribes will be transferred
     * @param amount The amount of fee token to transfer
     */
    event FeeClaimed(
        address indexed caller, address indexed recipient, uint256 amount
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INITIALIZE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Initializes the contract with required parameters and roles.
     * @param _infrared Address of the Infrared contract.
     * @param _gov Address of the governance.
     * @param _keeper Address of the keeper.
     * @param _ibgt Address of the iBGT token.
     * @param _wbera Address of the WBERA token.
     * @param _feeReceivor Address of the fee receiver.
     * @param _payoutAmount Initial payout amount.
     * @dev Reverts if any address is zero or payout amount is zero. Grants roles and initializes upgradeable components.
     */
    function initialize(
        address _infrared,
        address _gov,
        address _keeper,
        address _ibgt,
        address _wbera,
        address _feeReceivor,
        uint256 _payoutAmount
    ) external initializer {
        // input sanity check
        if (
            _infrared == address(0) || _gov == address(0)
                || _feeReceivor == address(0) || _keeper == address(0)
                || _wbera == address(0) || _ibgt == address(0)
        ) {
            revert Errors.ZeroAddress();
        }
        if (_payoutAmount == 0) revert Errors.ZeroAmount();

        // set storage vars
        feeReceivor = _feeReceivor;
        ibgt = ERC20(_ibgt);
        payoutAmount = _payoutAmount;
        wbera = WBERA(payable(_wbera));
        emit PayoutAmountSet(0, _payoutAmount);

        // grant admin access roles
        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);

        // init upgradeable components
        __InfraredUpgradeable_init(_infrared);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Set the payout amount for the bribe collector.
     * @param _newPayoutAmount updated payout amount
     * @dev Only callable by the governor. Reverts if amount is zero. Emits PayoutAmountSet.
     */
    function setPayoutAmount(uint256 _newPayoutAmount) external onlyGovernor {
        if (_newPayoutAmount == 0) revert Errors.ZeroAmount();
        uint256 oldPayoutAmount = payoutAmount;
        payoutAmount = _newPayoutAmount;
        emit PayoutAmountSet(oldPayoutAmount, _newPayoutAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WRITE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Claims fees by transferring WBERA payout from caller, converting to native BERA, sending to fee receiver,
     *         and transferring iBGT to recipient.
     * @param _recipient The address to receive the iBGT fees.
     * @param _feeAmount The amount of iBGT to transfer.
     * @dev Only callable by keeper. Reverts on insufficient balances or zero recipient. Emits FeeClaimed.
     */
    function claimFee(address _recipient, uint256 _feeAmount)
        external
        onlyKeeper
    {
        // input sanity check
        if (_recipient == address(0)) revert Errors.ZeroAddress();

        uint256 _payoutAmount = payoutAmount; // Cache for gas efficiency
        uint256 senderBalance = wbera.balanceOf(msg.sender);
        if (senderBalance < _payoutAmount) {
            revert Errors.InsufficientBalance();
        }

        // Transfer WBERA tokens from the sender to the contract corresponding to the payoutAmount.
        ERC20(address(wbera)).safeTransferFrom(
            msg.sender, address(this), _payoutAmount
        );

        // redeem WBERA tokens from the contract to native token.
        wbera.withdraw(_payoutAmount);

        // Transfer native token from the contract to the fee receiver
        SafeTransferLib.safeTransferETH(feeReceivor, _payoutAmount);

        // For all the specified fee tokens, transfer them to the recipient.
        uint256 contractBalance = ibgt.balanceOf(address(this));
        if (_feeAmount > contractBalance) {
            revert Errors.InsufficientFeeTokenBalance();
        }
        ibgt.safeTransfer(_recipient, _feeAmount);
        emit FeeClaimed(msg.sender, _recipient, _feeAmount);
    }

    /**
     * @notice Sweeps any WBERA or native BERA balances to the fee receiver.
     * @dev Only callable by keeper. Useful for recovering stuck funds.
     */
    function sweep() external onlyKeeper {
        address me = address(this);
        uint256 bal = wbera.balanceOf(me);
        if (bal > 0) {
            // redeem WBERA tokens from the contract to native token.
            wbera.withdraw(bal);
        }

        bal = me.balance;
        if (bal > 0) {
            SafeTransferLib.safeTransferETH(feeReceivor, bal);
        }
    }

    /// @notice Fallback function to receive BERA
    receive() external payable {}
}
