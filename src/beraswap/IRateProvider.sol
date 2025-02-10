// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title IRateProvider
interface IRateProvider {
    /**
     * getRate()
     *
     * @dev Returns the current rate of a given asset.
     * @return uint256 The current rate of the asset.
     */
    function getRate() external view returns (uint256);
}
