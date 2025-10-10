// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IInfraredV1_7} from "./IInfraredV1_7.sol";

/**
 * @title IInfraredV1_9 Interface
 * @notice Interface for Infrared V1.9 upgrade.
 */
interface IInfraredV1_9 is IInfraredV1_7 {
    function wiBGT() external returns (address);
}
