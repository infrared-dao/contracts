// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IStakedIR
 * @notice Interface for the StakedIR ERC4626 vault
 * @dev Extends ERC4626 with compounding functionality
 */
interface IStakedIR is IERC4626 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EVENTS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when rewards are compounded
    /// @param compounder Address that initiated the compound
    /// @param amount Amount of IR tokens compounded
    /// @param newTotalAssets New total assets after compounding
    event Compounded(
        address indexed compounder, uint256 amount, uint256 newTotalAssets
    );

    /// @notice Emitted when the compounder address is updated
    /// @param oldCompounder Previous compounder address
    /// @param newCompounder New compounder address
    event CompounderUpdated(
        address indexed oldCompounder, address indexed newCompounder
    );

    /// @notice Emitted when minimum lockup period is updated
    /// @param oldPeriod Previous lockup period
    /// @param newPeriod New lockup period
    event MinLockupPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERRORS                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when attempting to withdraw during lockup period
    error LockupPeriodActive();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       FUNCTIONS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Compound rewards (convert non-IR rewards via auction, then deposit)
    /// @dev Only callable by authorized compounder
    /// @dev Increases share value for all sIR holders
    /// @param amount Amount of IR tokens to compound
    function compound(uint256 amount) external;

    /// @notice Update compounder address
    /// @dev Only callable by Infrared protocol
    /// @param _newCompounder The new compounder address
    function setCompounder(address _newCompounder) external;

    /// @notice Update minimum lockup period
    /// @dev Only callable by Infrared protocol
    /// @param _newPeriod The new minimum lockup period in seconds
    function setMinLockupPeriod(uint256 _newPeriod) external;

    /// @notice Get the current compounder address
    /// @return The address authorized to compound rewards
    function compounder() external view returns (address);

    /// @notice Get total rewards compounded since inception
    /// @return Total IR tokens compounded
    function totalCompounded() external view returns (uint256);

    /// @notice Get Infrared protocol address
    /// @return The Infrared protocol address
    function infrared() external view returns (address);

    /// @notice Get minimum lockup period
    /// @return The minimum lockup period in seconds
    function minLockupPeriod() external view returns (uint256);

    /// @notice Get deposit timestamp for a user
    /// @param user The user address
    /// @return The timestamp when the user last deposited
    function depositTimestamp(address user) external view returns (uint256);

    /// @notice Get time remaining in lockup period for a user
    /// @param user The user address
    /// @return Seconds remaining (0 if lockup has expired)
    function lockupRemaining(address user) external view returns (uint256);
}
