// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title Infrared Governance Token
 * @notice This contract is the IR token.
 */
contract InfraredGovernanceTokenV1_2 is ERC20 {
    /// @notice Infrared multisig governance address for holding initial shares
    address public immutable holding;

    /// @notice Construct the Infrared Governance Token contract
    /// @param _admin The address of the admin to mint initial shares to
    constructor(address _admin) ERC20("Infrared Governance Token", "IR", 18) {
        if (_admin == address(0)) revert();
        holding = _admin;
        // total supply = 1 B
        _mint(_admin, 1_000_000_000 ether);
    }
}
