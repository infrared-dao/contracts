// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IRateProvider} from "src/beraswap/IRateProvider.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";

/**
 * @title iBERA Rate Provider
 * @notice Returns the value of iBERA in terms of BERA
 */
contract InfraredBERARateProvider is IRateProvider {
    /// @notice The address of the ibera contract
    IInfraredBERA public immutable ibera;

    /// @notice Constructs the MevETHRateProvider contract, setting the mevETH address
    constructor(IInfraredBERA _ibera) {
        ibera = _ibera;
    }

    /// @notice Returns the value of iBERA in terms of BERA
    /// @return amount the value of iBERA in terms of BERA
    function getRate() external view override returns (uint256) {
        (uint256 amount,) = ibera.previewBurn(1 ether);
        return amount;
    }
}
