// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfraredBERAFeeReceivor {
    event Sweep(address indexed receiver, uint256 amount, uint256 fees);
    event Collect(
        address indexed receiver, uint256 amount, uint256 sharesMinted
    );

    /// @notice The address of InfraredBERA
    function InfraredBERA() external view returns (address);

    /// @notice Accumulated protocol fees in contract to be claimed by governor
    function shareholderFees() external view returns (uint256);

    /// @notice Amount of BERA swept to InfraredBERA and fees taken for protool on next call to sweep
    /// @return amount THe amount of BERA forwarded to InfraredBERA on next sweep
    /// @return fees The protocol fees taken on next sweep
    function distribution()
        external
        view
        returns (uint256 amount, uint256 fees);

    /// @notice Sweeps accumulated coinbase priority fees + MEV to InfraredBERA to autocompound principal
    function sweep() external returns (uint256 amount, uint256 fees);

    /// @notice Collects accumulated shareholder fees
    /// @dev Reverts if msg.sender is not iBERA contract
    /// @return sharesMinted The amount of iBERA shares minted and sent to infrared
    function collect() external returns (uint256 sharesMinted);
}
