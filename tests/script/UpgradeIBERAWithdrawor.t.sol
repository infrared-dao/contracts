// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";

contract UpgradeInfraredBERAWithdraworTest is Helper {
    function testUpgradeability() public {
        // deploy new implementation
        withdrawor = new InfraredBERAWithdrawor();
        address newWithdrawor = address(withdrawor);
        // perform upgrade
        vm.prank(infraredGovernance);
        (bool success,) = address(withdraworLite).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(withdrawor), ""
            )
        );
        require(success, "Upgrade failed");

        // initialize
        // point at proxy
        withdrawor = InfraredBERAWithdrawor(payable(address(withdraworLite)));
        vm.prank(infraredGovernance);
        withdrawor.initializeV2(address(10));

        // Verify new implementation
        assertEq(withdraworLite.implementation(), newWithdrawor);
    }

    function isProxy(address proxy) internal view returns (bool) {
        (bool success, bytes memory data) =
            proxy.staticcall(abi.encodeWithSignature("implementation()"));
        return success && data.length > 0;
    }
}
