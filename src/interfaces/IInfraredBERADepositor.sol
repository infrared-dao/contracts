// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfraredBERADepositor {
    event Queue(uint256 nonce, uint256 amount);
    event Execute(bytes pubkey, uint256 start, uint256 end, uint256 amount);

    /// @notice The address of InfraredBERA
    function InfraredBERA() external view returns (address);

    /// @notice Outstanding slips for deposits on previously minted ibera
    /// @param nonce The nonce associated with the slip
    /// @return timestamp The block.timestamp at which deposit slip was issued
    /// @return fee The fee escrow amount set aside for deposit contract request
    /// @return amount The amount of bera left to be submitted for deposit slip
    function slips(uint256 nonce)
        external
        view
        returns (uint96 timestamp, uint256 fee, uint256 amount);

    /// @notice Amount of BERA internally set aside for deposit contract request fees
    function fees() external view returns (uint256);

    /// @notice Amount of BERA internally set aside to execute deposit contract requests
    function reserves() external view returns (uint256);

    /// @notice The next nonce to issue deposit slip for
    function nonceSlip() external view returns (uint256);

    /// @notice The next nonce to submit deposit slip for
    function nonceSubmit() external view returns (uint256);

    /// @notice Queues a deposit from InfraredBERA for chain deposit precompile escrowing msg.value in contract
    /// @param amount The amount of funds to deposit
    /// @return nonce The nonce created when queueing the deposit
    function queue(uint256 amount) external payable returns (uint256 nonce);

    /// @notice Executes a deposit to deposit precompile using escrowed funds
    /// @param pubkey The pubkey to deposit validator funds to
    /// @param amount The amount of funds to use from escrow to deposit to validator
    function execute(bytes calldata pubkey, uint256 amount) external;
}
