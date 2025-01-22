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
