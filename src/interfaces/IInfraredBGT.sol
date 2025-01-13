// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Mintable} from "./IERC20Mintable.sol";

interface IInfraredBGT is IERC20Mintable, IAccessControl {
    /// @notice The address of the BGT non-transferrable ERC20 token
    function bgt() external view returns (address);
}
