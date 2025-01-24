// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";

import {InfraredBERAConstants} from "./InfraredBERAConstants.sol";
import {InfraredBERADepositor} from "./InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "./InfraredBERAWithdrawor.sol";
import {InfraredBERAClaimor} from "./InfraredBERAClaimor.sol";
import {InfraredBERAFeeReceivor} from "./InfraredBERAFeeReceivor.sol";

/// @title InfraredBERA
/// @notice Infrared liquid staking token for BERA
/// @dev Assumes BERA balances do *not* change at the CL
contract InfraredBERA is ERC20Upgradeable, Upgradeable, IInfraredBERA {
    /// @inheritdoc IInfraredBERA
    bool public withdrawalsEnabled;
    /// @notice Whether initial mint to address(this) has happened
    bool private _initialized;
    /// @inheritdoc IInfraredBERA
    uint16 public feeDivisorShareholders;
    /// @inheritdoc IInfraredBERA
    address public infrared;
    /// @inheritdoc IInfraredBERA
    address public depositor;
    /// @inheritdoc IInfraredBERA
    address public withdrawor;
    /// @inheritdoc IInfraredBERA
    address public receivor;
    /// @inheritdoc IInfraredBERA
    uint256 public deposits;

    mapping(bytes32 pubkeyHash => uint256 stake) internal _stakes;

    mapping(bytes32 pubkeyHash => bool isStaked) internal _staked;

    mapping(bytes32 pubkeyHash => bool hasExited) internal _exited;

    mapping(bytes32 pubkeyHash => bytes) internal _signatures;

    /// Reserve storage slots for future upgrades
    uint256[50] private _gap; // slither-disable-line unused-state

    /// @inheritdoc IInfraredBERA
    function initialize(
        address _gov,
        address _keeper,
        address _infrared,
        address _depositor,
        address _withdrawor,
        address _receivor
    ) external payable initializer {
        if (
            _gov == address(0) || _infrared == address(0)
                || _depositor == address(0) || _withdrawor == address(0)
                || _receivor == address(0)
        ) revert Errors.ZeroAddress();
        __ERC20_init("Infrared BERA", "iBERA");
        __Upgradeable_init();

        infrared = _infrared;
        depositor = _depositor;
        withdrawor = _withdrawor;
        receivor = _receivor;

        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);

        // mint minimum amount to mitigate inflation attack with shares
        _initialized = true;
        mint(address(this));
    }

    function setWithdrawalsEnabled(bool flag) external onlyGovernor {
        withdrawalsEnabled = flag;
        emit WithdrawalFlagSet(flag);
    }

    function _deposit(uint256 value)
        private
        returns (uint256 nonce, uint256 amount, uint256 fee)
    {
        // @dev check at internal deposit level to prevent donations prior
        if (!_initialized) revert Errors.NotInitialized();

        // calculate amount as value less deposit fee
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        if (value < min + fee) revert Errors.InvalidAmount();

        amount = value - fee;
        // update tracked deposits with validators
        deposits += amount;
        // escrow funds to depositor contract to eventually forward to precompile
        nonce = IInfraredBERADepositor(depositor).queue{value: value}(amount);
    }

    function _withdraw(address receiver, uint256 amount, uint256 fee)
        private
        returns (uint256 nonce)
    {
        if (!_initialized) revert Errors.NotInitialized();

        // request to withdrawor contract to eventually forward to precompile
        nonce = IInfraredBERAWithdrawor(withdrawor).queue{value: fee}(
            receiver, amount
        );
        // update tracked deposits with validators *after* queue given used by withdrawor via confirmed
        deposits -= amount;
    }

    /// @inheritdoc IInfraredBERA
    function pending() public view returns (uint256) {
        return (
            IInfraredBERADepositor(depositor).reserves()
                + IInfraredBERAWithdrawor(withdrawor).rebalancing()
        );
    }

    /// @inheritdoc IInfraredBERA
    function confirmed() external view returns (uint256) {
        uint256 _pending = pending();
        // If pending is greater than deposits, return 0 instead of underflowing
        return _pending > deposits ? 0 : deposits - _pending;
    }

    /// @inheritdoc IInfraredBERA
    function keeper(address account) public view returns (bool) {
        return hasRole(KEEPER_ROLE, account);
    }

    /// @inheritdoc IInfraredBERA
    function governor(address account) public view returns (bool) {
        return hasRole(GOVERNANCE_ROLE, account);
    }

    /// @inheritdoc IInfraredBERA
    function validator(bytes calldata pubkey) external view returns (bool) {
        return IInfrared(infrared).isInfraredValidator(pubkey);
    }

    /// @inheritdoc IInfraredBERA
    function compound() public {
        IInfraredBERAFeeReceivor(receivor).sweep();
    }

    /// @inheritdoc IInfraredBERA
    function sweep() external payable {
        if (msg.sender != receivor) {
            revert Errors.Unauthorized(msg.sender);
        }
        _deposit(msg.value);
        emit Sweep(msg.value);
    }

    /// @inheritdoc IInfraredBERA
    function mint(address receiver)
        public
        payable
        returns (uint256 nonce, uint256 shares)
    {
        // compound yield earned from EL rewards first
        compound();

        // cache prior since updated in _deposit call
        uint256 d = deposits;
        uint256 ts = totalSupply();

        // deposit bera request
        uint256 amount;
        uint256 fee;
        (nonce, amount, fee) = _deposit(msg.value);

        // mint shares to receiver of ibera
        shares = (d != 0 && ts != 0) ? (ts * amount) / d : amount;
        if (shares == 0) revert Errors.InvalidShares();
        _mint(receiver, shares);

        emit Mint(receiver, nonce, amount, shares, fee);
    }

    /// @inheritdoc IInfraredBERA
    function burn(address receiver, uint256 shares)
        external
        payable
        returns (uint256 nonce, uint256 amount)
    {
        if (!withdrawalsEnabled) revert Errors.WithdrawalsNotEnabled();
        // compound yield earned from EL rewards first
        compound();

        uint256 ts = totalSupply();
        if (shares == 0 || ts == 0) revert Errors.InvalidShares();

        amount = (deposits * shares) / ts;
        if (amount == 0) revert Errors.InvalidAmount();

        // burn shares from sender of ibera
        _burn(msg.sender, shares);

        // withdraw bera request
        // @dev pay withdraw precompile fee via funds sent in on payable call
        uint256 fee = msg.value;
        if (fee < InfraredBERAConstants.MINIMUM_WITHDRAW_FEE) {
            revert Errors.InvalidFee();
        }
        nonce = _withdraw(receiver, amount, fee);

        emit Burn(receiver, nonce, amount, shares, fee);
    }

    /// @inheritdoc IInfraredBERA
    function register(bytes calldata pubkey, int256 delta) external {
        if (msg.sender != depositor && msg.sender != withdrawor) {
            revert Errors.Unauthorized(msg.sender);
        }
        if (_exited[keccak256(pubkey)]) {
            revert Errors.ValidatorForceExited();
        }
        // update validator pubkey stake for delta
        uint256 stake = _stakes[keccak256(pubkey)];
        if (delta > 0) stake += uint256(delta);
        else stake -= uint256(-delta);
        _stakes[keccak256(pubkey)] = stake;
        // update whether have staked to validator before
        if (delta > 0 && !_staked[keccak256(pubkey)]) {
            _staked[keccak256(pubkey)] = true;
        }
        // only 0 if validator was force exited
        if (stake == 0) {
            _staked[keccak256(pubkey)] = false;
            _exited[keccak256(pubkey)] = true;
        }

        emit Register(pubkey, delta, stake);
    }

    /// @inheritdoc IInfraredBERA
    function setFeeDivisorShareholders(uint16 to) external onlyGovernor {
        // Get current distributable amount
        (uint256 amount,) = IInfraredBERAFeeReceivor(receivor).distribution();

        // If there are significant accumulated rewards, force processing them first
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        if (amount > 0 && amount < min) {
            revert Errors.CanNotCompoundAccumuldatedBERA();
        }
        compound();
        emit SetFeeShareholders(feeDivisorShareholders, to);
        feeDivisorShareholders = to;
    }

    /// @inheritdoc IInfraredBERA
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

    /// @inheritdoc IInfraredBERA
    function collect() external returns (uint256 sharesMinted) {
        if (msg.sender != address(infrared)) {
            revert Errors.Unauthorized(msg.sender);
        }
        sharesMinted = IInfraredBERAFeeReceivor(receivor).collect();
    }

    /// @inheritdoc IInfraredBERA
    function previewMint(uint256 beraAmount)
        public
        view
        returns (uint256 shares, uint256 fee)
    {
        if (!_initialized) {
            return (0, 0);
        }

        // First simulate compound effects like in actual mint
        (uint256 compoundAmount,) =
            IInfraredBERAFeeReceivor(receivor).distribution();

        // Calculate fee
        fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;

        if (beraAmount < min + fee) {
            return (0, 0);
        }

        // Calculate shares considering both:
        // 1. The compound effect (compoundAmount - fee)
        // 2. The new deposit (beraAmount - fee)
        uint256 ts = totalSupply();
        uint256 depositsAfterCompound = deposits;

        // First simulate compound effect on deposits
        if (compoundAmount > 0) {
            uint256 compoundFee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
            if (
                compoundAmount
                    >= compoundFee + InfraredBERAConstants.MINIMUM_DEPOSIT
            ) {
                depositsAfterCompound += (compoundAmount - compoundFee);
            }
        }

        // Then calculate shares based on user deposit
        uint256 amount = beraAmount - fee;
        if (depositsAfterCompound == 0 || ts == 0) {
            shares = amount;
        } else {
            shares = (ts * amount) / depositsAfterCompound;
        }

        if (shares == 0) {
            return (0, 0);
        }
    }

    /// @inheritdoc IInfraredBERA
    function previewBurn(uint256 shareAmount)
        public
        view
        returns (uint256 beraAmount, uint256 fee)
    {
        if (!_initialized || shareAmount == 0) {
            return (0, 0);
        }

        // First simulate compound effects like in actual burn
        (uint256 compoundAmount,) =
            IInfraredBERAFeeReceivor(receivor).distribution();

        uint256 ts = totalSupply();
        if (ts == 0) {
            return (0, InfraredBERAConstants.MINIMUM_WITHDRAW_FEE);
        }

        // Calculate amount considering compound effect
        uint256 depositsAfterCompound = deposits;

        if (compoundAmount > 0) {
            uint256 compoundFee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
            if (
                compoundAmount
                    >= compoundFee + InfraredBERAConstants.MINIMUM_DEPOSIT
            ) {
                depositsAfterCompound += (compoundAmount - compoundFee);
            }
        }

        beraAmount = (depositsAfterCompound * shareAmount) / ts;
        fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;

        if (beraAmount == 0) {
            return (0, fee);
        }
    }

    /// @inheritdoc IInfraredBERA
    function stakes(bytes calldata pubkey) external view returns (uint256) {
        return _stakes[keccak256(pubkey)];
    }

    /// @inheritdoc IInfraredBERA
    function staked(bytes calldata pubkey) external view returns (bool) {
        return _staked[keccak256(pubkey)];
    }

    /// @inheritdoc IInfraredBERA
    function hasExited(bytes calldata pubkey) external view returns (bool) {
        return _exited[keccak256(pubkey)];
    }

    /// @inheritdoc IInfraredBERA
    function signatures(bytes calldata pubkey)
        external
        view
        returns (bytes memory)
    {
        return _signatures[keccak256(pubkey)];
    }
}
