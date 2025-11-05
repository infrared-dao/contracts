// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {InfraredV1_8} from "src/depreciated/core/InfraredV1_8.sol";

/// @title Redeemer Contract
/// @notice Permissionless contract for redeeming iBGT tokens for BERA via the Infrared protocol.
contract Redeemer {
    using SafeTransferLib for ERC20;

    /// @notice Address of the BGT token.
    address public immutable bgt;
    /// @notice Address of the iBGT token.
    address public immutable ibgt;
    /// @notice Address of the Infrared protocol contract.
    InfraredV1_8 public immutable infrared;

    /// @notice Event emitted when iBGT is redeemed for BERA.
    /// @param user The user who redeemed.
    /// @param amount The amount of iBGT redeemed.
    event IbgtRedeemed(address indexed user, uint256 amount);

    /// @notice Error thrown for zero amount
    error InvalidAmount();
    /// @notice Error thrown for invalid address
    error InvalidAddress();
    /// @notice Error thrown when insufficient unboosted BGT is available for redemption.
    error InsufficientUnboostedBGT();

    /// @notice Constructor to initialize the contract.
    /// @param _bgt Address of the BGT token.
    /// @param _infrared Address of the Infrared protocol.
    constructor(address _bgt, address _infrared) {
        if (_bgt == address(0) || _infrared == address(0)) {
            revert InvalidAddress();
        }
        infrared = InfraredV1_8(payable(_infrared));
        ibgt = address(infrared.ibgt());
        bgt = _bgt;
    }

    /// @notice Redeems iBGT for BERA.
    /// @param amount The amount of iBGT to redeem.
    /// @dev Caller must approve this contract for iBGT. Checks unboosted BGT availability on Infrared.
    ///      Burns iBGT, calls Infrared to redeem, and transfers BERA to the caller.
    function redeemIbgtForBera(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        // amount to be redeemed must be available on infrared as unboosted BGT
        uint256 unboostedBalance = IInfraredBGT(ibgt).totalSupply()
            - (
                IBerachainBGT(bgt).boosts(address(infrared))
                    + IBerachainBGT(bgt).queuedBoost(address(infrared))
            );
        if (unboostedBalance < amount) revert InsufficientUnboostedBGT();
        // user must approve contract to pull ibgt for redemption
        ERC20(ibgt).safeTransferFrom(msg.sender, address(this), amount);
        // approve infrared to burn ibgt
        ERC20(ibgt).safeApprove(address(infrared), amount);
        // call redeem
        infrared.redeemIbgtForBera(amount);
        // transfer redeemed bera to user
        SafeTransferLib.safeTransferETH(msg.sender, amount);
        // record event
        emit IbgtRedeemed(msg.sender, amount);
    }

    /// @notice Fallback to receive BERA from Infrared.
    receive() external payable {}
}
