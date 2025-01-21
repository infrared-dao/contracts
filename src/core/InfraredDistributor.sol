// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {InfraredUpgradeable} from "src/core/InfraredUpgradeable.sol";

import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredDistributor} from "src/interfaces/IInfraredDistributor.sol";
import {Errors} from "src/utils/Errors.sol";

/// @title InfraredDistributor
/// @notice A contract for distributing rewards in a single ERC20 token (iBERA) to validators
contract InfraredDistributor is InfraredUpgradeable, IInfraredDistributor {
    using SafeTransferLib for ERC20;

    /// @inheritdoc IInfraredDistributor
    ERC20 public token;

    /// @inheritdoc IInfraredDistributor
    uint256 public amountsCumulative;

    mapping(bytes32 pubkeyHash => Snapshot) internal _snapshots;

    mapping(bytes32 pubkeyHash => address) internal _validators;

    constructor(address _infrared) InfraredUpgradeable(_infrared) {
        if (_infrared == address(0)) revert Errors.ZeroAddress();
    }

    function initialize(address _gov, address _token) external initializer {
        if (_gov == address(0) || _token == address(0)) {
            revert Errors.ZeroAddress();
        }

        token = ERC20(_token);

        // claim amounts calculated via differences so absolute amount not relevant
        amountsCumulative++;

        // grant admin access roles
        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);

        // init upgradeable components
        __InfraredUpgradeable_init();
    }

    /// @inheritdoc IInfraredDistributor
    function add(bytes calldata pubkey, address validator)
        external
        onlyInfrared
    {
        if (_validators[keccak256(pubkey)] != address(0)) {
            revert Errors.ValidatorAlreadyExists();
        }
        _validators[keccak256(pubkey)] = validator;

        Snapshot storage s = _snapshots[keccak256(pubkey)];
        uint256 _amountsCumulative = amountsCumulative;

        s.amountCumulativeLast = _amountsCumulative;
        s.amountCumulativeFinal = 0;

        emit Added(pubkey, validator, _amountsCumulative);
    }

    /// @inheritdoc IInfraredDistributor
    function remove(bytes calldata pubkey) external onlyInfrared {
        address validator = _validators[keccak256(pubkey)];
        if (validator == address(0)) revert Errors.ValidatorDoesNotExist();

        uint256 _amountsCumulative = amountsCumulative;
        if (_amountsCumulative == 0) revert Errors.ZeroAmount();

        Snapshot storage s = _snapshots[keccak256(pubkey)];
        // Add check to prevent re-removal of already removed validators
        if (s.amountCumulativeFinal != 0) {
            revert Errors.ValidatorAlreadyRemoved();
        }

        s.amountCumulativeFinal = _amountsCumulative;

        emit Removed(pubkey, validator, _amountsCumulative);
    }

    /// @inheritdoc IInfraredDistributor
    function purge(bytes calldata pubkey) external onlyGovernor {
        address validator = _validators[keccak256(pubkey)];
        if (validator == address(0)) revert Errors.ValidatorDoesNotExist();

        Snapshot memory s = _snapshots[keccak256(pubkey)];
        if (s.amountCumulativeLast != s.amountCumulativeFinal) {
            revert Errors.ClaimableRewardsExist();
        }

        delete _snapshots[keccak256(pubkey)];
        delete _validators[keccak256(pubkey)];

        emit Purged(pubkey, validator);
    }

    /// @inheritdoc IInfraredDistributor
    function notifyRewardAmount(uint256 amount) external {
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 num = infrared.numInfraredValidators();
        if (num == 0) revert Errors.InvalidValidator();

        unchecked {
            amountsCumulative += amount / num;
        }
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Notified(amount, num);
    }

    /// @inheritdoc IInfraredDistributor
    function claim(bytes calldata pubkey, address recipient) external {
        address validator = _validators[keccak256(pubkey)];
        if (validator != msg.sender) revert Errors.InvalidValidator();

        Snapshot memory s = _snapshots[keccak256(pubkey)];

        uint256 fin = s.amountCumulativeFinal == 0
            ? amountsCumulative
            : s.amountCumulativeFinal;

        // Check if there are any unclaimed rewards
        if (s.amountCumulativeLast == fin) revert Errors.NoRewardsToClaim();

        uint256 amount;
        unchecked {
            amount = fin - s.amountCumulativeLast;
        }

        s.amountCumulativeLast = fin;
        _snapshots[keccak256(pubkey)] = s;

        if (amount > 0) token.safeTransfer(recipient, amount);
        emit Claimed(pubkey, validator, recipient, amount);
    }

    /// @inheritdoc IInfraredDistributor
    function getSnapshot(bytes calldata pubkey)
        external
        view
        returns (uint256 amountCumulativeLast, uint256 amountCumulativeFinal)
    {
        Snapshot memory s = _snapshots[keccak256(pubkey)];
        return (s.amountCumulativeLast, s.amountCumulativeFinal);
    }

    /// @inheritdoc IInfraredDistributor
    function getValidator(bytes calldata pubkey)
        external
        view
        returns (address)
    {
        return _validators[keccak256(pubkey)];
    }
}
