// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {InfraredBERAConstants} from "./InfraredBERAConstants.sol";

/// @title InfraredBERAFeeReceivor
/// @notice Fee receivor receives coinbase priority fees + MEV credited to contract on EL upon block validation
///     also receives collected validator bribe share.
/// @dev CL validators should set fee_recipient to the address of this contract
contract InfraredBERAFeeReceivor is Upgradeable, IInfraredBERAFeeReceivor {
    /// @inheritdoc IInfraredBERAFeeReceivor
    address public InfraredBERA;

    IInfrared public infrared;

    /// @inheritdoc IInfraredBERAFeeReceivor
    uint256 public shareholderFees;

    /// Reserve storage slots for future upgrades
    uint256[50] private _gap; // slither-disable-line unused-state

    /// @notice Initializer function (replaces constructor)
    /// @param _gov Address for admin / gov to upgrade
    /// @param _keeper Address for keeper
    /// @param ibera Address for InfraredBERA
    /// @param _infrared Address for Infrared
    function initialize(
        address _gov,
        address _keeper,
        address ibera,
        address _infrared
    ) external initializer {
        if (
            _gov == address(0) || _keeper == address(0) || ibera == address(0)
                || _infrared == address(0)
        ) revert Errors.ZeroAddress();
        __Upgradeable_init();

        InfraredBERA = ibera;
        infrared = IInfrared(_infrared);

        _grantRole(DEFAULT_ADMIN_ROLE, _gov);
        _grantRole(GOVERNANCE_ROLE, _gov);
        _grantRole(KEEPER_ROLE, _keeper);
    }

    /// @inheritdoc IInfraredBERAFeeReceivor
    function distribution()
        public
        view
        returns (uint256 amount, uint256 fees)
    {
        amount = (address(this).balance - shareholderFees);
        uint16 feeShareholders =
            IInfraredBERA(InfraredBERA).feeDivisorShareholders();

        // take protocol fees
        if (feeShareholders > 0) {
            fees = amount / uint256(feeShareholders);
            amount -= fees;
        }
    }

    /// @inheritdoc IInfraredBERAFeeReceivor
    function sweep() external returns (uint256 amount, uint256 fees) {
        (amount, fees) = distribution();
        // do nothing if InfraredBERA deposit would revert
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        if (amount < min) return (0, 0);

        // add to protocol fees and sweep amount back to ibera to deposit
        if (fees > 0) shareholderFees += fees;
        IInfraredBERA(InfraredBERA).sweep{value: amount}();
        emit Sweep(InfraredBERA, amount, fees);
    }

    /// @inheritdoc IInfraredBERAFeeReceivor
    function collect() external returns (uint256 sharesMinted) {
        if (msg.sender != InfraredBERA) revert Errors.Unauthorized(msg.sender);
        uint256 shf = shareholderFees;
        if (shf == 0) return 0;

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT
            + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        if (shf < min) {
            return 0;
        }

        if (shf > 0) {
            delete shareholderFees;
            (, sharesMinted) =
                IInfraredBERA(InfraredBERA).mint{value: shf}(address(infrared));
        }
        emit Collect(address(infrared), shf, sharesMinted);
    }

    receive() external payable {}
}
