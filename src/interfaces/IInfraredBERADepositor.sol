// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfraredBERADepositor {
    event Queue(uint256 amount);
    event Execute(bytes pubkey, uint256 amount);

    /// @notice The address of InfraredBERA
    function InfraredBERA() external view returns (address);

    /// @notice Amount of BERA internally set aside to execute deposit contract requests
    function reserves() external view returns (uint256);

    /// @notice Queues a deposit from InfraredBERA for chain deposit precompile escrowing msg.value in contract
    /// @param amount The amount of funds to deposit
    function queue(uint256 amount) external payable;

    /// @notice Executes a deposit to deposit precompile using escrowed funds
    /// @param pubkey The pubkey to deposit validator funds to
    /// @param amount The amount of funds to use from escrow to deposit to validator
    function execute(bytes calldata pubkey, uint256 amount) external;
}
