// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20PresetMinterPauser} from "../vendors/ERC20PresetMinterPauser.sol";

/**
 * @title InfraredBGT
 * @notice This contract is the InfraredBGT token.
 */
contract InfraredBGT is ERC20PresetMinterPauser {
    error ZeroAddress();

    address public immutable bgt;

    constructor(address _bgt, address _admin, address _minter, address _pauser)
        ERC20PresetMinterPauser("Infrared BGT", "iBGT", _admin, _minter, _pauser)
    {
        if (_bgt == address(0)) revert ZeroAddress();
        bgt = _bgt;
    }
}
