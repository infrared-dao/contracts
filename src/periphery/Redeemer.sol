// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {InfraredV1_7} from "src/core/upgrades/InfraredV1_7.sol";

/// @title Redeemer Contract
/// @notice Permissioned contract for redeeming iBGT tokens for BERA via the Infrared protocol.
/// @dev Only authorized redeemers can call the redemption function. Assumes 1:1 iBGT to BGT ratio and BERA as native token.
contract Redeemer {
    using SafeTransferLib for ERC20;

    /// @notice Address of the BGT token.
    address public immutable bgt;
    /// @notice Address of the iBGT token.
    address public immutable ibgt;
    /// @notice Address of the Infrared protocol contract.
    InfraredV1_7 public immutable infrared;
    /// @notice Governance address for managing redeemers.
    address public immutable governance;
    /// @notice Mapping of authorized redeemers.
    mapping(address user => bool isRedeemer) public redeemers;

    /// @notice Event emitted when iBGT is redeemed for BERA.
    /// @param user The user who redeemed.
    /// @param amount The amount of iBGT redeemed.
    event IbgtRedeemed(address indexed user, uint256 amount);
    /// @notice Event emitted when a redeemer is added.
    /// @param redeemer The added redeemer address.
    event RedeemerAdded(address indexed redeemer);
    /// @notice Event emitted when a redeemer is removed.
    /// @param redeemer The removed redeemer address.
    event RedeemerRemoved(address indexed redeemer);

    /// @notice Error thrown when caller is not authorized.
    error Unauthorized();
    /// @notice Error thrown for zero amount
    error InvalidAmount();
    /// @notice Error thrown for invalid address
    error InvalidAddress();
    /// @notice Error thrown when insufficient unboosted BGT is available for redemption.
    error InsufficientUnboostedBGT();

    /// @notice Modifier to restrict access to authorized redeemers.
    modifier onlyRedeemer() {
        if (!redeemers[msg.sender]) revert Unauthorized();
        _;
    }

    /// @notice Modifier to restrict access to governance.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert Unauthorized();
        _;
    }

    /// @notice Constructor to initialize the contract.
    /// @param _governance Address of the governance controller.
    /// @param _bgt Address of the BGT token.
    /// @param _infrared Address of the Infrared protocol.
    /// @param _redeemers Array of initial authorized redeemers.
    constructor(
        address _governance,
        address _bgt,
        address _infrared,
        address[] memory _redeemers
    ) {
        if (
            _governance == address(0) || _bgt == address(0)
                || _infrared == address(0)
        ) revert InvalidAddress();
        uint256 len = _redeemers.length;
        for (uint256 i; i < len; i++) {
            redeemers[_redeemers[i]] = true;
            emit RedeemerAdded(_redeemers[i]);
        }
        infrared = InfraredV1_7(payable(_infrared));
        ibgt = address(infrared.ibgt());
        bgt = _bgt;
        governance = _governance;
    }

    /// @notice Redeems iBGT for BERA.
    /// @param amount The amount of iBGT to redeem.
    /// @dev Caller must approve this contract for iBGT. Checks unboosted BGT availability on Infrared.
    ///      Burns iBGT, calls Infrared to redeem, and transfers BERA to the caller.
    function redeemIbgtForBera(uint256 amount) external onlyRedeemer {
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

    /// @notice Adds a new redeemer.
    /// @param redeemer The address to add as a redeemer.
    function addRedeemer(address redeemer) external onlyGovernance {
        if (redeemer == address(0)) revert InvalidAddress();
        redeemers[redeemer] = true;
        emit RedeemerAdded(redeemer);
    }

    /// @notice Removes an existing redeemer.
    /// @param redeemer The address to remove as a redeemer.
    function removeRedeemer(address redeemer) external onlyGovernance {
        if (redeemer == address(0)) revert InvalidAddress();
        redeemers[redeemer] = false;
        emit RedeemerRemoved(redeemer);
    }

    /// @notice Fallback to receive BERA from Infrared.
    receive() external payable {}
}
