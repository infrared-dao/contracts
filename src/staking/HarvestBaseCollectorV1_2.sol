//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WBERA} from "@berachain/WBERA.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {HarvestBaseCollector} from
    "src/depreciated/staking/HarvestBaseCollector.sol";
import {Errors} from "src/utils/Errors.sol";

/**
 * @title HarvestBaseCollectorV1_2
 * @notice Auction contract for iBGT to WBERA conversion for base fees to compound to iBERA holders
 * @dev Simplified version of BribeCollector. This contract allows keepers to claim iBGT fees by paying a fixed WBERA amount,
 *      which is converted to native BERA and sent to the fee receiver for compounding.
 * @dev Upgrade to have same interface as Bribe Collector, specifically adding payoutToken and claimFees
 * @custom:oz-upgrades-from src/staking/HarvestBaseCollector.sol:HarvestBaseCollector
 */
contract HarvestBaseCollectorV1_2 is HarvestBaseCollector {
    using SafeTransferLib for ERC20;

    /// @notice Payout token, required to be WBERA token as its unwrapped and used to compound rewards in the `iBera` system.
    address constant payoutToken = 0x6969696969696969696969696969696969696969;

    /**
     * @notice Emitted when the fees are claimed
     * @param caller Caller of the `claimFees` function
     * @param recipient The address to which collected POL bribes will be transferred
     * @param feeToken The address of the fee token to collect
     * @param amount The amount of fee token to transfer
     */
    event FeesClaimed(
        address indexed caller,
        address indexed recipient,
        address indexed feeToken,
        uint256 amount
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WRITE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Claims accumulated bribes in exchange for payout token
     * @dev Caller must approve payoutAmount of payout token to this contract.
     * @param _recipient The Address to receive claimed tokens
     * @param _feeTokens Array of token addresses to claim
     * @param _feeAmounts Array of amounts to claim for each fee token
     */
    function claimFees(
        address _recipient,
        address[] calldata _feeTokens,
        uint256[] calldata _feeAmounts
    ) external onlyKeeper {
        if (_feeTokens.length != _feeAmounts.length) {
            revert Errors.InvalidArrayLength();
        }
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
        for (uint256 i; i < _feeTokens.length; i++) {
            address feeToken = _feeTokens[i];
            uint256 feeAmount = _feeAmounts[i];
            if (feeToken == payoutToken) {
                revert Errors.InvalidFeeToken();
            }

            uint256 contractBalance = ERC20(feeToken).balanceOf(address(this));
            if (feeAmount > contractBalance) {
                revert Errors.InsufficientFeeTokenBalance();
            }
            ERC20(feeToken).safeTransfer(_recipient, feeAmount);
            emit FeesClaimed(msg.sender, _recipient, feeToken, feeAmount);
        }
    }
}
