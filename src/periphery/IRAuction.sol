// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Errors} from "src/utils/Errors.sol";
import {IStakedIR} from "src/interfaces/IStakedIR.sol";
import {InfraredUpgradeable} from "src/core/InfraredUpgradeable.sol";

/**
 * @title IRAuction
 * @notice Auctions portion of iBGT vault rewards to IR, then compounds in sIR
 * @dev Similar to BribeCollector pattern but for sIR reward auto-compounding
 * @dev Auction mechanism: Pay IR tokens to claim non-IR reward tokens
 */
contract IRAuction is InfraredUpgradeable {
    using SafeTransferLib for ERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice IR token that must be paid to claim auction rewards
    ERC20 internal IR_TOKEN;

    /// @notice sIR vault that receives compounded IR
    IStakedIR internal SIR_VAULT;

    /// @notice Amount of IR required per auction claim
    uint256 public payoutAmount;

    // Reserve storage slots for future upgrades for safety
    uint256[40] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EVENTS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event AuctionClaimed(
        address indexed claimer,
        address indexed rewardToken,
        uint256 rewardAmount,
        uint256 irPaid
    );
    event PayoutAmountSet(uint256 oldAmount, uint256 newAmount);
    event TokensRecovered(
        address indexed token, address indexed to, uint256 amount
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(
        address _infrared,
        address _gov,
        address _keeper,
        address _irToken,
        address _sirVault,
        uint256 _payoutAmount
    ) external initializer {
        if (
            _infrared == address(0) || _gov == address(0)
                || _irToken == address(0) || _sirVault == address(0)
        ) {
            revert Errors.ZeroAddress();
        }
        if (_payoutAmount == 0) revert Errors.ZeroAmount();

        IR_TOKEN = ERC20(_irToken);
        SIR_VAULT = IStakedIR(_sirVault);
        payoutAmount = _payoutAmount;
        emit PayoutAmountSet(0, _payoutAmount);

        // grant admin access roles
        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);

        // init upgradeable components
        __InfraredUpgradeable_init(_infrared);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       AUCTION                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Claim auction rewards by paying IR
    /// @dev Converts paid IR to sIR shares via compounding (increases share value)
    /// @param _recipient Address to receive rewardTokens
    /// @param rewardTokens Array of reward token addresses to claim
    /// @param amounts Array of amounts for each reward token
    function claimFees(
        address _recipient,
        address[] calldata rewardTokens,
        uint256[] calldata amounts
    ) external virtual onlyKeeper {
        if (rewardTokens.length != amounts.length) {
            revert Errors.InvalidArrayLength();
        }
        if (payoutAmount == 0) revert Errors.ZeroAmount();
        if (_recipient == address(0)) revert Errors.ZeroAddress();

        uint256 senderBalance = IR_TOKEN.balanceOf(msg.sender);
        if (senderBalance < payoutAmount) {
            revert Errors.InsufficientBalance();
        }

        // Transfer IR from caller
        IR_TOKEN.safeTransferFrom(msg.sender, address(this), payoutAmount);

        // Approve sIR vault to spend IR for compounding
        IR_TOKEN.safeApprove(address(SIR_VAULT), payoutAmount);

        // Compound into sIR vault (increases share value for all holders)
        SIR_VAULT.compound(payoutAmount);

        // Transfer reward tokens to caller
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            ERC20 _token = ERC20(rewardTokens[i]);
            uint256 _amount = amounts[i];
            if (_amount == 0) continue;
            if (address(_token) == address(IR_TOKEN)) {
                revert Errors.InvalidFeeToken();
            }
            if (!infrared.whitelistedRewardTokens(address(_token))) {
                revert Errors.FeeTokenNotWhitelisted();
            }
            uint256 contractBalance = _token.balanceOf(address(this));
            if (_amount > contractBalance) {
                revert Errors.InsufficientFeeTokenBalance();
            }

            _token.safeTransfer(_recipient, _amount);
            emit AuctionClaimed(
                _recipient, address(_token), _amount, payoutAmount
            );
        }
    }

    function sweepPayoutToken() external {
        uint256 balance = IR_TOKEN.balanceOf(address(this));
        if (balance == 0) revert Errors.InsufficientBalance();
        // Approve sIR vault to spend IR for compounding
        IR_TOKEN.safeApprove(address(SIR_VAULT), balance);

        // Compound into sIR vault (increases share value for all holders)
        SIR_VAULT.compound(balance);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update payout amount (governance function)
    /// @param _newAmount New amount of IR required per auction claim
    function setPayoutAmount(uint256 _newAmount)
        external
        virtual
        onlyGovernor
    {
        if (_newAmount == 0) revert Errors.ZeroAmount();

        uint256 old = payoutAmount;
        payoutAmount = _newAmount;
        emit PayoutAmountSet(old, _newAmount);
    }

    /// @notice Recover stuck tokens (governance function)
    /// @dev Emergency function to recover tokens sent to contract by mistake
    /// @param token Token address to recover
    /// @param to Recipient address
    /// @param amount Amount to recover
    function recoverERC20(address token, address to, uint256 amount)
        external
        virtual
        onlyGovernor
    {
        if (to == address(0) || token == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (amount == 0) revert Errors.ZeroAmount();

        ERC20(token).safeTransfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get balance of a specific token held by this contract
    /// @param token Token address to check
    /// @return The token balance
    function getTokenBalance(address token)
        external
        view
        virtual
        returns (uint256)
    {
        return ERC20(token).balanceOf(address(this));
    }

    /// @notice Get payout token address
    /// @return payout token address
    function payoutToken() external view virtual returns (address) {
        return address(IR_TOKEN);
    }
}
