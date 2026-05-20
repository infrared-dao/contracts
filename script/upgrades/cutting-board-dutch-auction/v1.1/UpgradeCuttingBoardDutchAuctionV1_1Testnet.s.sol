// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

/// @notice Upgrades the CuttingBoardDutchAuction proxy to V1_1 on testnet.
/// @dev    Caller must hold GOVERNANCE_ROLE (or DEFAULT_ADMIN_ROLE) on the proxy.
///         Suitable for Bepolia where governance is an EOA.
///         No re-initialisation is required — V1_1 only overrides two functions.
contract UpgradeCuttingBoardDutchAuctionV1_1Testnet is Script {
    function run(address _proxy, address _implementation) external {
        if (_proxy == address(0) || _implementation == address(0)) revert();

        bytes memory data = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", _implementation, ""
        );

        vm.startBroadcast();
        (bool success,) = _proxy.call(data);
        if (!success) revert();
        vm.stopBroadcast();
    }
}
