// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IInfraredBERA is IERC20, IAccessControl {
    event Mint(address indexed receiver, uint256 amount, uint256 shares);
    event Burn(
        address indexed receiver,
        uint256 nonce,
        uint256 amount,
        uint256 shares,
        uint256 fee
    );
    event Sweep(uint256 amount);
    event Register(bytes pubkey, int256 delta, uint256 stake);
    event SetFeeShareholders(uint16 from, uint16 to);
    event SetDepositSignature(bytes pubkey, bytes from, bytes to);
    event WithdrawalFlagSet(bool flag);

    /// @notice Address of the Infrared operator contract
    function infrared() external view returns (address);

    /// @notice Address of the depositor that interacts with chain deposit precompile
    function depositor() external view returns (address);

    /// @notice Address of the withdrawor that interacts with chain withdraw precompile
    function withdrawor() external view returns (address);

    /// @notice Address of the fee receivor contract that receives tx priority fees + MEV on EL
    function receivor() external view returns (address);

    /// @notice Deposits of BERA backing InfraredBERA intended for use in CL by validators
    /// @return The amount of BERA for deposits to CL
    function deposits() external view returns (uint256);

    /// @notice Returns the amount of BERA staked in validator with given pubkey
    /// @return The amount of BERA staked in validator
    function stakes(bytes calldata pubkey) external view returns (uint256);

    /// @notice Returns whether initial deposit has been staked to validator with given pubkey
    /// @return Whethere initial deposit has been staked to validator
    function staked(bytes calldata pubkey) external view returns (bool);

    /// @notice Checks if a validator has been force exited from the Consensus Layer
    /// @param pubkey The public key of the validator to check
    /// @return bool True if the validator has been force exited, false otherwise
    /// @dev exited validators can no longer be deposited in.
    function hasExited(bytes calldata pubkey) external view returns (bool);

    /// @notice Returns the deposit signature to use for given pubkey
    /// @return The deposit signature for pubkey
    function signatures(bytes calldata pubkey)
        external
        view
        returns (bytes memory);

    /// @notice Fee taken by the shareholders on yield from EL coinbase priority fees + MEV, represented as an integer denominator (1/x)%
    /// @notice additional fees include POL base rewards, POL comission, POL bribes
    /// @return The fee taken by shareholders as an integer denominator (1/x)%, (25% = 4), (50% = 2), (100% = 1)
    function feeDivisorShareholders() external view returns (uint16);

    /// @notice Pending deposits yet to be forwarded to CL
    /// @return The amount of BERA yet to be deposited to CL
    function pending() external view returns (uint256);

    /// @notice Confirmed deposits sent to CL
    /// @return The amount of BERA confirmed to be deposited to CL
    function confirmed() external view returns (uint256);

    /// @notice Returns whether given account is an InfraredBERA keeper
    /// @return Whether account is a keeper
    function keeper(address account) external view returns (bool);

    /// @notice Returns whether given account is an InfraredBERA governor
    /// @return Whether account is a governor
    function governor(address account) external view returns (bool);

    /// @notice Returns whether given pubkey is in Infrared validator set
    /// @return Whether pubkey in Infrared validator set
    function validator(bytes calldata pubkey) external view returns (bool);

    /// @notice Previews the amount of InfraredBERA shares that would be minted for a given BERA amount
    /// @param beraAmount The amount of BERA to simulate depositing
    /// @return shares The amount of InfraredBERA shares that would be minted, returns 0 if the operation would fail
    function previewMint(uint256 beraAmount)
        external
        view
        returns (uint256 shares);

    /// @notice Previews the amount of BERA that would be received for burning InfraredBERA shares
    /// @param shares The amount of InfraredBERA shares to simulate burning
    /// @return beraAmount The amount of BERA that would be received, returns 0 if the operation would fail
    /// @return fee The fee that would be charged for the burn operation
    function previewBurn(uint256 shares)
        external
        view
        returns (uint256 beraAmount, uint256 fee);

    /// @notice Initializes InfraredBERA to allow for future mints and burns
    /// @dev Must be called before InfraredBERA can offer deposits and withdraws
    function initialize(
        address _gov,
        address _keeper,
        address _infrared,
        address _depositor,
        address _withdrawor,
        address _receivor
    ) external payable;

    /// @notice Compounds accumulated EL yield in fee receivor into deposits
    /// @dev Called internally at bof whenever InfraredBERA minted or burned
    /// @dev Only sweeps if amount transferred from fee receivor would exceed min deposit thresholds
    function compound() external;

    /// @notice Sweeps received funds in `msg.value` as yield into deposits
    /// @dev Fee receivor must call this function in its sweep function for autocompounding
    function sweep() external payable;

    /// @notice Collects yield from fee receivor and mints ibera shares to Infrared
    /// @dev Only Infrared can call this function
    /// @return sharesMinted The amount of ibera shares minted
    function collect() external returns (uint256 sharesMinted);

    /// @notice Mints ibera shares to receiver for bera paid in by sender
    /// @param receiver Address of the receiver of ibera
    /// @return shares The amount of shares of ibera minted
    function mint(address receiver) external payable returns (uint256 shares);

    /// @notice Burns ibera shares from sender for bera to ultimately be transferred to receiver on subsequent call to claim
    /// @dev Sender must pay withdraw precompile fee upfront
    /// @param receiver Address of the receiver of future bera
    /// @param shares The amount of shares of ibera burned
    /// @return nonce The nonce issued to identify the owed bera funds for claim
    /// @return amount The amount of bera funds that will be available for claim
    function burn(address receiver, uint256 shares)
        external
        payable
        returns (uint256 nonce, uint256 amount);

    /// @notice Registers update to BERA staked in validator with given pubkey at CL
    /// @dev Reverts if not called by depositor or withdrawor
    /// @param pubkey The pubkey of the validator to update BERA stake for at CL
    /// @param delta The change in the amount of BERA staked/unstaked (+/-) at CL
    function register(bytes calldata pubkey, int256 delta) external;

    /// @notice Sets the fee shareholders taken on yield from EL coinbase priority fees + MEV
    /// @param to The new fee shareholders represented as an integer denominator (1/x)%
    function setFeeDivisorShareholders(uint16 to) external;

    /// @notice Sets the deposit signature to be used when depositing to pubkey
    /// @param pubkey The pubkey of the validator receiving the deposit
    /// @param signature The deposit signature to use for pubkey
    function setDepositSignature(
        bytes calldata pubkey,
        bytes calldata signature
    ) external;

    /**
     * @notice Flag to show whether withdrawals are currently enabled
     * @return True if withdrawals are enabled
     */
    function withdrawalsEnabled() external view returns (bool);
}
