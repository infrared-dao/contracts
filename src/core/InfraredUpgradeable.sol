// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Errors, Upgradeable} from "src/utils/Upgradeable.sol";

import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredUpgradeable} from "src/interfaces/IInfraredUpgradeable.sol";

/**
 * @title InfraredUpgradeable
 * @notice This contract provides base upgradeability functionality for Infrared.
 */
abstract contract InfraredUpgradeable is Upgradeable {
    /// @notice Infrared coordinator contract
    IInfrared public immutable infrared;

    modifier onlyInfrared() {
        if (msg.sender != address(infrared)) revert Errors.NotInfrared();
        _;
    }

    constructor(address _infrared) {
        // _infrared == address(0) means this is infrared
        infrared = IInfrared(_infrared);
        // prevents implementation contracts from being used
        _disableInitializers();
    }

    function __InfraredUpgradeable_init() internal onlyInitializing {
        __Upgradeable_init();
    }
}
