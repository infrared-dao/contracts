// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Upgradeable} from "src/utils/Upgradeable.sol";
import {IInfraredBERAClaimor} from "src/interfaces/IInfraredBERAClaimor.sol";

/// @title InfraredBERAClaimor
/// @author bungabear69420
/// @notice Claimor to claim BERA withdrawn from CL for Infrared liquid staking token
/// @dev Separate contract so withdrawor process has trusted contract to forward funds to so no issue with naked bera transfer and receive function
contract InfraredBERAClaimor is Upgradeable, IInfraredBERAClaimor {
    /// @inheritdoc IInfraredBERAClaimor
    mapping(address => uint256) public claims;

    /// @notice Initializer function (replaces constructor)
    /// @param admin Address of the initial admin
    function initialize(address admin) external initializer {
        __Upgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IInfraredBERAClaimor
    function queue(address receiver) external payable {
        uint256 claim = claims[receiver];
        claim += msg.value;
        claims[receiver] = claim;
        emit Queue(receiver, msg.value, claim);
    }

    /// @inheritdoc IInfraredBERAClaimor
    function sweep(address receiver) external {
        uint256 amount = claims[receiver];
        delete claims[receiver];
        if (amount > 0) SafeTransferLib.safeTransferETH(receiver, amount);
        emit Sweep(receiver, amount);
    }
}
