// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20PresetMinterPauser} from "../vendors/ERC20PresetMinterPauser.sol";

/**
 * @title Infrared Governance Token
 * @notice This contract is the IR token.
 */
contract InfraredGovernanceToken is ERC20PresetMinterPauser {
    error ZeroAddress();

    address public immutable infrared;

    /// @notice Construct the Infrared Governance Token contract
    /// @param _infrared The address of the Infrared contract
    /// @param _admin The address of the admin
    /// @param _minter The address of the minter
    /// @param _pauser The address of the pauser
    /// @param _burner The burner address of the contract
    constructor(
        address _infrared,
        address _admin,
        address _minter,
        address _pauser,
        address _burner
    )
        ERC20PresetMinterPauser(
            "Infrared Governance Token",
            "IR",
            _admin,
            _minter,
            _pauser,
            _burner
        )
    {
        if (_infrared == address(0)) {
            revert ZeroAddress();
        }
        infrared = _infrared;

        _grantRole(MINTER_ROLE, infrared);
    }
}
