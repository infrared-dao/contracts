// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20PresetMinterPauser} from "../vendors/ERC20PresetMinterPauser.sol";

/**
 * @title Infrared Governance Token
 * @notice This contract is the IR token.
 */
contract InfraredGovernanceToken is ERC20PresetMinterPauser {
    error ZeroAddress();

    address public immutable ibgt;
    address public immutable infrared;

    /// @notice Construct the Infrared Governance Token contract
    /// @param _ibgt The address of the IBGT contract
    /// @param _infrared The address of the Infrared contract
    /// @param _admin The address of the admin
    /// @param _minter The address of the minter
    /// @param _pauser The address of the pauser
    constructor(
        address _ibgt,
        address _infrared,
        address _admin,
        address _minter,
        address _pauser
    )
        ERC20PresetMinterPauser(
            "Infrared Governance Token",
            "IR",
            _admin,
            _minter,
            _pauser
        )
    {
        if (_ibgt == address(0) || _infrared == address(0)) {
            revert ZeroAddress();
        }
        ibgt = _ibgt;
        infrared = _infrared;

        _grantRole(MINTER_ROLE, infrared);
    }
}
