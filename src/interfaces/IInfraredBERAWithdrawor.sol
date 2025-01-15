// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfraredBERAWithdrawor {
    event Queue(address indexed receiver, uint256 nonce, uint256 amount);
    event Execute(bytes pubkey, uint256 start, uint256 end, uint256 amount);
    event Process(address indexed receiver, uint256 nonce, uint256 amount);
    event Sweep(address indexed receiver, uint256 amount);

    /// @notice The address of InfraredBERA
    function InfraredBERA() external view returns (address);

    /// @notice Sweeps forced withdrawals to InfraredBERA to re-stake principal
    function sweep(bytes calldata pubkey) external;

    /// @notice Outstanding requests for claims on previously burnt ibera
    /// @param nonce The nonce associated with the claim
    /// @return receiver The address of the receiver of bera funds to be claimed
    /// @return timestamp The block.timestamp at which withdraw request was issued
    /// @return fee The fee escrow amount set aside for withdraw precompile request
    /// @return amountSubmit The amount of bera left to be submitted for withdraw request
    /// @return amountProcess The amount of bera left to be processed for withdraw request
    function requests(uint256 nonce)
        external
        view
        returns (
            address receiver,
            uint96 timestamp,
            uint256 fee,
            uint256 amountSubmit,
            uint256 amountProcess
        );

    /// @notice Amount of BERA internally set aside for withdraw precompile request fees
    function fees() external view returns (uint256);

    /// @notice Amount of BERA internally set aside to process withdraw compile requests from funds received on successful requests
    function reserves() external view returns (uint256);

    /// @notice Amount of BERA internally rebalancing amongst Infrared validators
    function rebalancing() external view returns (uint256);

    /// @notice The next nonce to issue withdraw request for
    function nonceRequest() external view returns (uint256);

    /// @notice The next nonce to submit withdraw request for
    function nonceSubmit() external view returns (uint256);

    /// @notice The next nonce in queue to process claims for
    function nonceProcess() external view returns (uint256);

    /// @notice Queues a withdraw from InfraredBERA for chain withdraw precompile escrowing minimum fees for request to withdraw precompile
    /// @param receiver The address to receive withdrawn funds
    /// @param amount The amount of funds to withdraw
    /// @return nonce The nonce created when queueing the withdraw
    function queue(address receiver, uint256 amount)
        external
        payable
        returns (uint256 nonce);

    /// @notice Executes a withdraw request to withdraw precompile
    /// @dev Payable in case excess bera required to satisfy withdraw precompile fee
    /// @param pubkey The pubkey to withdraw validator funds from
    /// @param amount The amount of funds to withdraw from validator
    function execute(bytes calldata pubkey, uint256 amount) external payable;

    /// @notice Processes the funds received from withdraw precompile to next-to-process request receiver
    /// @dev Reverts if balance has not increased by full amount of request for next-to-process request nonce
    function process() external;
}
