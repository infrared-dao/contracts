// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";

/*

    Made with Love by the Bears at Infrared Finance, so that all Bears may
         get the best yields on their BERA. For the Bears, by the Bears. <3


⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡤⢤⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣠⠴⠶⢤⡞⢡⡚⣦⠹⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢰⣃⠀⠀⠈⠁⠀⠉⠁⢺⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⢯⣄⡀⠀⠀⠀⠀⢀⡞⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠉⠓⠦⠤⣤⣤⠞⠀⠀⢀⣴⠒⢦⣴⣖⢲⡀⠀⠀⠀⠀⣠⣴⠾⠿⠷⣶⣄⠀⣀⣠⣤⣴⣶⣶⣶⣦⣤⣤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⠀⠈⠳⠼⣰⠃⠀⠀⠀⣼⡟⠁⠀⣀⣀⠀⠙⢿⠟⠋⠉⠀⠀⠀⠀⠀⠀⠉⠉⠛⠿⣶⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠓⣦⣄⣠⣶⣿⣛⠛⠿⣾⣿⠀⢠⣾⠋⣹⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⣷⣄⡀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣴⡶⠿⠟⠛⠛⠛⠛⠛⠛⠿⢷⣾⣿⣷⡀⠻⠾⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣷⣄⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣾⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⢿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣿⢷⣦⡀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠿⣶⣶⣤⡀⠀⠀⠀⠀⢀⣤⡶⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣆⠙⣿⡄
⠀⠀⠀⠀⠀⠀⠀⣠⣾⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣷⡀⠀⢷⡄⠸⣯⣀⣼⡷⠒⢉⣉⡙⢢⡀⠀⠀⠀⠀⠀⢸⣿⡀⢸⣿
⠀⠀⠀⠀⠀⠀⢠⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⢄⡾⠐⠒⢆⠀⠀⣿⡇⠀⢸⡇⠀⠈⢉⡟⠀⠀⠀⢹⡟⠃⢧⣴⠶⢶⡄⠀⠀⣿⣇⣼⡟
⠀⠀⣠⣴⡶⠶⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⡿⢃⡾⠁⠀⠀⢸⠃⠀⣿⡇⠀⣸⡇⠀⠀⣼⠀⠀⠀⢠⡾⠁⠀⢸⣿⣤⣼⠗⠀⠀⣿⣿⠛⠀
⢀⣾⠟⠁⠀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠀⠀⢿⠇⡼⠁⠀⠀⢀⡜⠀⢀⣿⠃⠀⠉⠀⠀⠀⢧⠀⠠⡶⣿⠁⠀⢠⠇⠀⠉⠁⠀⠀⠀⣿⡏⠀⠀
⢸⣿⠀⢠⡞⠉⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⠾⢿⣠⣷⡄⠀⠁⠳⠤⠖⠋⠀⠀⣸⡟⠀⠀⠀⠀⠀⠀⠘⣄⡀⠀⠛⢀⡴⠋⠀⠀⠀⠀⠀⠀⠀⣿⡇⠀⠀
⢸⣿⡀⠈⠻⣦⣼⠀⠀⠀⠀⠀⠀⠀⢀⣤⣴⡶⠶⠆⠀⢠⣤⡾⠋⠀⣿⠀⠀⠀⠀⠀⠀⠀⢠⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⡅⠀⠀
⠀⠻⣿⣦⣄⣀⣰⡀⠀⠀⠀⠀⠀⠀⣸⠯⢄⡀⠀⠀⠀⢸⣇⠀⠀⠀⣸⡇⠀⠀⠀⠀⠀⢠⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀
⠀⠀⠀⠉⠙⠛⣿⣇⠀⠀⠀⠀⢀⠎⠀⠀⠀⠈⣆⠀⠀⠀⠻⣦⣄⣴⠟⠀⠀⠀⠀⠀⣰⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡄⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⡿⠋⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠸⣿⣆⠀⠀⠀⠘⡄⠀⠀⠀⢀⡞⠀⠀⠀⠀⠀⠉⠀⠀⢀⣀⣤⣴⣾⣿⣧⣄⠀⢀⣠⣴⣶⣶⣶⣤⡶⠋⠉⠀⠀⢀⣀⣀⣠⣤⣶⣾⠿⠋⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠘⢿⣦⡀⠀⠀⠈⠒⠤⠔⠋⠀⠀⠀⠀⠀⠀⣠⣴⡾⠟⠋⠉⠀⠀⠀⠛⣹⣷⣿⠟⠒⠀⠀⠀⠉⢻⣷⣶⣾⠿⠿⠿⠛⠛⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠛⢿⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠾⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⣹⣿⣿⣄⣀⠀⠀⠀⠀⢀⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠿⣷⣶⣶⣤⣤⣶⡦⠀⠁⠀⠀⠀⠀⠀⣀⣀⣀⣤⣴⡾⠟⠁⠙⠿⣷⣶⣤⣴⣾⠿⠛⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⣽⡿⠁⠀⣤⣤⣶⡶⠾⠿⠟⢻⠛⠉⠁⠀⠀⠀⠀⠀⠀⠈⠉⠙⣿⡆⠀⠈⢿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⠟⠁⠀⢸⣟⡁⠀⠀⠀⠀⣰⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⡇⠀⠀⠈⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣶⣿⡏⠀⠀⠀⠸⣿⣤⣶⣀⣤⣾⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣧⣄⣀⣤⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣇⣿⡇⠀⠀⠀⠀⣾⣿⠛⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣍⠛⠛⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⣿⡇⠀⠀⠀⠀⠉⣿⣆⠀⠀⠀⠀⠀⠀⠀⢴⣶⣶⠆⠀⠀⠀⠀⠀⠀⣈⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⡿⠀⠀⠀⠀⠀⠀⣸⣿⡄⠀⠀⠀⠀⠀⠀⢸⣟⢿⣿⣦⠀⠀⢠⣄⣠⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣥⣤⣶⣀⣠⣶⣴⡿⢻⣷⣄⣴⣆⣀⣆⣠⣿⡇⠈⠻⣿⣵⣶⡿⠿⠛⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
*/

/// @title InfraredBERA
/// @notice Infrared BERA is a liquid staking token for Berachain
/// @dev This is the main "Front-End" contract for the whole BERA staking system.
contract InfraredBERAV2 is ERC20Upgradeable, Upgradeable, IInfraredBERAV2 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Withdrawals are not enabled by default, not supported by https://github.com/berachain/beacon-kit yet.
    bool public withdrawalsEnabled;

    /// @notice Whether the contract has been initialized
    bool private _initialized;

    /// @notice The fee divisor for protocol + operator + voter fees. 1/N, where N is the divisor. example 100 = 1/100 = 1%
    uint16 public feeDivisorShareholders;

    /// @notice The `Infrared.sol` smart contract.
    address public infrared;

    /// @notice The `InfraredBERADepositor.sol` smart contract.
    address public depositor;

    /// @notice The `InfraredBERAWithdrawor.sol` smart contract.
    address public withdrawor;

    /// @notice The `InfraredBERAFeeReceivor.sol` smart contract.
    address public receivor;

    /// @notice The total amount of `BERA` deposited by the system.
    uint256 public deposits;

    /// @notice Mapping of validator pubkeyHash to their stake in `BERA`.
    mapping(bytes32 pubkeyHash => uint256 stake) internal _stakes;

    /// @notice Mapping of validator pubkeyHash to whether they have recieved stake from this contract.
    mapping(bytes32 pubkeyHash => bool isStaked) internal _staked;

    /// @notice Mapping of validator pubkeyHash to whether they have exited from this contract. (voluntarily or force).
    mapping(bytes32 pubkeyHash => bool hasExited) internal _exited;

    /// @notice Mapping of validator pubkeyHash to their deposit signature. All validators MUST have their signiture amounts set to `INITIAL_DEPOSIT` to be valid.
    mapping(bytes32 pubkeyHash => bytes) internal _signatures;

    /// @notice internal buffer of accumulated exit fees in iBERA to claim
    uint256 internal exitFeesToCollect;

    /// @notice burn fee in iBERA covers operational costs for withdrawal precompile (small amounts should be directed to swaps)
    uint256 public burnFee;

    /// @notice time, in seconds, to allow staleness of proof data relative to current head
    uint256 public proofTimestampBuffer;

    /// @notice BEX pool rate provider for backwards compatibility with previewBurn
    address public rateProvider;

    /// @dev Reserve storage slots for future upgrades for safety
    uint256[36] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initiializer for `InfraredBERAV2`.
    function initializeV2() external onlyGovernor {
        withdrawalsEnabled = true;
        burnFee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        proofTimestampBuffer = 10 minutes;
        rateProvider = 0x776fD57Bbeb752BDeEB200310faFAe9A155C50a0;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       AUTH                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Checks if account has the governance role.
    /// @param account The address to check.
    /// @return True if the account has the governance role.
    function governor(address account) public view returns (bool) {
        return hasRole(GOVERNANCE_ROLE, account);
    }

    /// @notice Checks if account has the keeper role.
    /// @param account The address to check.
    /// @return True if the account has the keeper role.
    function keeper(address account) public view returns (bool) {
        return hasRole(KEEPER_ROLE, account);
    }

    /// @notice Checks if a given pubkey is a validator in the `Infrared` contract.
    /// @param pubkey The pubkey to check.
    /// @return True if the pubkey is a validator.
    function validator(bytes calldata pubkey) external view returns (bool) {
        return IInfrared(infrared).isInfraredValidator(pubkey);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN                                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Allows withdrawals to be enabled or disabled.
    /// @param flag The flag to set for withdrawals.
    /// @dev Only callable by the governor.
    function setWithdrawalsEnabled(bool flag) external onlyGovernor {
        withdrawalsEnabled = flag;
        emit WithdrawalFlagSet(flag);
    }

    /// @notice Updates burn fee (in iBERA)
    /// @param _fee Amount in iBERA to charge for burns
    /// @dev Only callable by the governor.
    function updateBurnFee(uint256 _fee) external onlyGovernor {
        burnFee = _fee;
        emit BurnFeeUpdated(_fee);
    }

    /// @notice Updates iBERA BEX pool rate provider address
    /// @param _rateProvider Address of rate provider
    /// @dev Only callable by the governor.
    function updateRateProvider(address _rateProvider) external onlyGovernor {
        if (_rateProvider == address(0)) revert Errors.ZeroAddress();
        rateProvider = _rateProvider;
        emit RateProviderUpdated(_rateProvider);
    }

    /// @notice Sets the fee shareholders taken on yield from EL coinbase priority fees + MEV
    /// @param to The new fee shareholders represented as an integer denominator (1/x)%
    function setFeeDivisorShareholders(uint16 to) external onlyGovernor {
        compound();
        emit SetFeeShareholders(feeDivisorShareholders, to);
        feeDivisorShareholders = to;
    }

    /// @notice Updates proof timestamp buffer
    /// @param _newBuffer new timespan in seconds to allow staleness of proof data relative to current head
    function updateProofTimestampBuffer(uint256 _newBuffer)
        external
        onlyGovernor
    {
        if (_newBuffer == 0) revert Errors.ZeroAmount();
        proofTimestampBuffer = _newBuffer;
        emit ProofTimestampBufferUpdated(_newBuffer);
    }

    /// @notice Sets the deposit signature for a given pubkey. Ensure that the pubkey has signed the correct deposit amount of `INITIAL_DEPOSIT`.
    /// @param pubkey The pubkey to set the deposit signature for.
    /// @param signature The signature to set for the pubkey.
    /// @dev Only callable by the governor.
    function setDepositSignature(
        bytes calldata pubkey,
        bytes calldata signature
    ) external onlyGovernor {
        if (signature.length != 96) revert Errors.InvalidSignature();
        emit SetDepositSignature(
            pubkey, _signatures[keccak256(pubkey)], signature
        );
        _signatures[keccak256(pubkey)] = signature;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MINT/BURN                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mints `ibera` to the `receiver` in exchange for `bera`.
    /// @dev takes in msg.value as amount to mint `ibera` with.
    /// @param receiver The address to mint `ibera` to.
    /// @return shares The amount of `ibera` minted.
    function mint(address receiver) public payable returns (uint256 shares) {
        // @dev make sure to compound yield earned from EL rewards first to avoid accounting errors.
        compound();

        // cache prior since updated in _deposit call
        uint256 d = deposits;
        uint256 ts = totalSupply();

        // deposit bera request
        uint256 amount = msg.value;
        _deposit(amount);

        // mint shares to receiver of ibera, if there are no deposits or total supply, mint full amount
        // else mint amount based on total supply and deposits: (totalSupply * amount) / deposits
        shares = (d != 0 && ts != 0) ? (ts * amount) / d : amount;
        if (shares == 0) revert Errors.InvalidShares();
        _mint(receiver, shares);

        emit Mint(receiver, amount, shares);
    }

    /// @notice Burns `ibera` from the `msg.sender` and sets a receiver to get the `BERA` in exchange for `iBERA`.
    /// @param receiver The address to send the `BERA` to.
    /// @param shares The amount of `ibera` to burn.
    /// @return nonce The nonce of the withdrawal. Queue based system for withdrawals.
    /// @return amount The amount of `BERA` withdrawn for the exchange of `iBERA`.
    /// @dev return amount is net of fees
    function burn(address receiver, uint256 shares)
        external
        returns (uint256 nonce, uint256 amount)
    {
        if (!withdrawalsEnabled) revert Errors.WithdrawalsNotEnabled();
        if (receiver == address(0)) revert Errors.ZeroAddress();

        // check min exit fee is met in ibera
        uint256 fee = burnFee;
        if (shares < fee) revert Errors.MinExitFeeNotMet();
        uint256 netShares = shares - fee;

        // @dev make sure to compound yield earned from EL rewards first to avoid accounting errors.
        compound();

        uint256 ts = totalSupply();
        if (netShares == 0 || ts == 0) revert Errors.InvalidShares();

        amount = (deposits * netShares) / ts;

        // burn shares from sender of ibera
        _burn(msg.sender, netShares);

        nonce = _withdraw(receiver, amount);

        // collect exit fees to claim from goverance for funding withdrawal precompile fees
        exitFeesToCollect += fee;
        _transfer(msg.sender, address(this), fee);

        emit Burn(receiver, nonce, amount, shares, fee);
    }

    /// @notice Internal function to update top level accounting and minimum deposit.
    /// @param amount The amount of `BERA` to deposit.
    function _deposit(uint256 amount) internal {
        // @dev check at internal deposit level to prevent donations prior
        if (!_initialized) revert Errors.NotInitialized();

        // update tracked deposits with validators
        deposits += amount;
        // escrow funds to depositor contract to eventually forward to precompile
        InfraredBERADepositorV2(depositor).queue{value: amount}();
    }

    /// @notice Internal function to update top level accounting.
    /// @param receiver The address to withdraw `BERA` to.
    /// @param amount The amount of `BERA` to withdraw.
    function _withdraw(address receiver, uint256 amount)
        private
        returns (uint256 nonce)
    {
        if (!_initialized) revert Errors.NotInitialized();

        // request to withdrawor contract to eventually forward to precompile
        nonce = IInfraredBERAWithdrawor(withdrawor).queue(receiver, amount);
        // update tracked deposits with validators *after* queue given used by withdrawor via confirmed
        deposits -= amount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ACCOUNTING                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Previews the amount of InfraredBERA shares that would be minted for a given BERA amount
    /// @param beraAmount The amount of BERA to simulate depositing
    /// @return shares The amount of InfraredBERA shares that would be minted, returns 0 if the operation would fail
    function previewMint(uint256 beraAmount)
        public
        view
        returns (uint256 shares)
    {
        if (!_initialized) {
            return 0;
        }

        // First simulate compound effects like in actual mint
        (uint256 compoundAmount,) =
            IInfraredBERAFeeReceivor(receivor).distribution();

        // Calculate shares considering both:
        // 1. The compound effect (compoundAmount - fee)
        // 2. The new deposit (beraAmount - fee)
        uint256 ts = totalSupply();
        uint256 depositsAfterCompound = deposits;

        // First simulate compound effect on deposits
        if (compoundAmount > 0) {
            depositsAfterCompound += (compoundAmount);
        }

        // Then calculate shares based on user deposit
        uint256 amount = beraAmount;
        if (depositsAfterCompound == 0 || ts == 0) {
            shares = amount;
        } else {
            shares = (ts * amount) / depositsAfterCompound;
        }
    }

    /// @notice Previews the amount of BERA that would be received for burning InfraredBERA shares
    /// @param shareAmount The amount of InfraredBERA shares to simulate burning
    /// @return beraAmount The amount of BERA that would be received, returns 0 if the operation would fail
    /// @return fee The fee that would be charged for the burn operation in iBERA
    function previewBurn(uint256 shareAmount)
        public
        view
        returns (uint256 beraAmount, uint256 fee)
    {
        if (!_initialized || shareAmount == 0) {
            return (0, 0);
        }

        // flat fee in storage
        fee = burnFee;

        // Special case: Backwards compatibility for BEX pool rate provider
        if (msg.sender == rateProvider) {
            fee = 0;
        }

        // First simulate compound effects like in actual burn
        (uint256 compoundAmount,) =
            IInfraredBERAFeeReceivor(receivor).distribution();

        uint256 ts = totalSupply();

        // Calculate amount considering compound effect
        uint256 depositsAfterCompound = deposits;

        if (compoundAmount > 0) {
            depositsAfterCompound += (compoundAmount);
        }

        if (ts == 0 || shareAmount <= fee) {
            beraAmount = 0;
        } else {
            beraAmount = (depositsAfterCompound * (shareAmount - fee)) / ts;
        }
    }

    /// @notice Returns the amount of BERA staked in validator with given pubkey
    /// @return The amount of BERA staked in validator
    function stakes(bytes calldata pubkey) external view returns (uint256) {
        return _stakes[keccak256(pubkey)];
    }

    /// @notice Returns whether initial deposit has been staked to validator with given pubkey
    /// @return Whethere initial deposit has been staked to validator
    function staked(bytes calldata pubkey) external view returns (bool) {
        return _staked[keccak256(pubkey)];
    }

    /// @notice Pending deposits yet to be forwarded to CL
    /// @return The amount of BERA yet to be deposited to CL
    function pending() public view returns (uint256) {
        return (InfraredBERADepositorV2(depositor).reserves());
    }

    /// @notice Confirmed deposits sent to CL, total - future deposits
    /// @return The amount of BERA confirmed to be deposited to CL
    function confirmed() external view returns (uint256) {
        uint256 _pending = pending();
        // If pending is greater than deposits, return 0 instead of underflowing
        return _pending > deposits ? 0 : deposits - _pending;
    }

    /// @inheritdoc IInfraredBERAV2
    function compound() public {
        (uint256 compoundAmount,) =
            IInfraredBERAFeeReceivor(receivor).distribution();
        if (compoundAmount > 0) {
            IInfraredBERAFeeReceivor(receivor).sweep();
        }
    }

    /// @notice Compounds accumulated EL yield in fee receivor into deposits
    /// @dev Called internally at bof whenever InfraredBERA minted or burned
    /// @dev Only sweeps if amount transferred from fee receivor would exceed min deposit thresholds
    function sweep() external payable {
        if (msg.sender != receivor) {
            revert Errors.Unauthorized(msg.sender);
        }
        uint256 balance = msg.value;
        _deposit(balance);
        emit Sweep(balance);
    }

    /// @notice Collects yield from fee receivor and mints ibera shares to Infrared
    /// @dev Called in `RewardsLib::harvestOperatorRewards()` in `Infrared.sol`
    /// @dev Only Infrared can call this function
    /// @return sharesMinted The amount of ibera shares
    function collect() external returns (uint256 sharesMinted) {
        if (msg.sender != address(infrared)) {
            revert Errors.Unauthorized(msg.sender);
        }
        sharesMinted = IInfraredBERAFeeReceivor(receivor).collect();
    }

    /// @notice Claims ibera exit fees for funding withdrawal precompile fees
    /// @dev Only Governance can call this function
    /// @param to address to send exit fees to (eg keeper or governance multisig)
    function claimExitFees(address to) external onlyGovernor {
        if (to == address(0)) revert Errors.ZeroAddress();
        uint256 amount = exitFeesToCollect;
        delete exitFeesToCollect;
        _transfer(address(this), address(to), amount);
        emit ExitFeesCollected(amount, to);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VALIDATORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the accounted for stake of a validator pubkey.
    /// @notice This does NOT mean its the balance on the CL, edge case is if another user has staked to the pubkey.
    /// @param pubkey The pubkey of the validator.
    /// @param delta The change in stake.
    function register(bytes calldata pubkey, int256 delta) external {
        if (msg.sender != depositor && msg.sender != withdrawor) {
            revert Errors.Unauthorized(msg.sender);
        }
        bytes32 pubkeyHash = keccak256(pubkey);
        if (_exited[pubkeyHash]) {
            revert Errors.ValidatorForceExited();
        }
        // update validator pubkey stake for delta
        uint256 stake = _stakes[pubkeyHash];
        if (delta > 0) stake += uint256(delta);
        else stake -= uint256(-delta);
        _stakes[pubkeyHash] = stake;
        // update whether have staked to validator before
        if (delta > 0 && !_staked[pubkeyHash]) {
            _staked[pubkeyHash] = true;
        }
        // only 0 if validator was force exited
        if (stake == 0) {
            _staked[pubkeyHash] = false;
            _exited[pubkeyHash] = true;
        }

        emit Register(pubkey, delta, stake);
    }

    /// @notice Updates the internal accounting for stake of a validator pubkey.
    /// @dev used after edge case events, such as bypass beacon deposits
    /// @param header The Beacon block header data
    /// @param _validator Validator struct data
    /// @param validatorMerkleWitness merkle proof of the validator against state root in header
    /// @param balanceMerkleWitness Merkle witness for balance container
    /// @param validatorIndex index of validator
    /// @param balanceLeaf 32 bytes chunk including packed balance
    /// @param nextBlockTimestamp timestamp of following block to header to verify parent root in beaconroots call
    function registerViaProofs(
        BeaconRootsVerify.BeaconBlockHeader calldata header,
        BeaconRootsVerify.Validator calldata _validator,
        bytes32[] calldata validatorMerkleWitness,
        bytes32[] calldata balanceMerkleWitness,
        uint256 validatorIndex,
        bytes32 balanceLeaf,
        uint256 nextBlockTimestamp
    ) external onlyKeeper {
        // cache pubkey ref
        bytes32 _pubkeyHash = keccak256(_validator.pubkey);
        // internal accounting balance for validator
        uint256 stake = _stakes[_pubkeyHash];

        // require stake non zero (valid staked Infrared validator)
        if (stake == 0) revert Errors.ZeroBalance();

        // check for pending withdrawals
        uint256 _pending = IInfraredBERAWithdrawor(withdrawor)
            .getTotalPendingWithdrawals(_pubkeyHash);
        // CL balance for validator (given in gwei)
        // CL balances are packed, 4 per bytes32 chunk. Offsets are index % 4.
        uint256 _balance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // check internal balance versus cl balance
        if (stake + _pending == _balance) return;

        // require balance non zero. Use sweepForceExit to register forced exit
        if (_balance == 0) revert Errors.ZeroBalance();

        // check proof data is not stale
        if (block.timestamp > nextBlockTimestamp + proofTimestampBuffer) {
            revert Errors.StaleProof();
        }

        // verify stake amount againt CL via beacon roots proof
        if (
            !BeaconRootsVerify.verifyValidatorBalance(
                header,
                balanceMerkleWitness,
                validatorIndex,
                _balance,
                balanceLeaf,
                nextBlockTimestamp
            )
        ) {
            revert Errors.BalanceMissmatch();
        }

        // verify validator againt CL via beacon roots proof
        if (
            // note: beaconroots call above, so we can now internally verify against state root
            !BeaconRootsVerify.verifyValidator(
                header.stateRoot,
                _validator,
                validatorMerkleWitness,
                validatorIndex
            )
        ) {
            revert Errors.InvalidValidator();
        }

        // increase deposits if stake amount has increased
        if (_balance > stake + _pending) {
            deposits += _balance - stake - _pending;
        }

        // set internal accounting balance to correct CL balance, adjusted for pending withdrawals
        _stakes[_pubkeyHash] = _balance - _pending;

        // update whether have staked to validator before
        if (!_staked[_pubkeyHash]) {
            _staked[_pubkeyHash] = true;
        }

        emit RegisterViaProof(_validator.pubkey, _balance - _pending, stake);
    }

    /// @notice Returns whether a validator pubkey has exited.
    function hasExited(bytes calldata pubkey) external view returns (bool) {
        return _exited[keccak256(pubkey)];
    }

    /// @notice Returns the deposit signature to use for given pubkey
    /// @return The deposit signature for pubkey
    function signatures(bytes calldata pubkey)
        external
        view
        returns (bytes memory)
    {
        return _signatures[keccak256(pubkey)];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               ERC4626 partial compliance                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function asset() external pure returns (address) {
        return address(0); // Native BERA
    }

    function totalAssets() public view returns (uint256) {
        return deposits;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        if (!withdrawalsEnabled) return 0;
        (uint256 amount,) = previewBurn(balanceOf(owner));
        return amount;
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return withdrawalsEnabled ? balanceOf(owner) : 0;
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets * supply / totalAssets();
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares * totalAssets() / supply;
    }
}
