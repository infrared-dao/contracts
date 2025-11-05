// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BribeCollectorTest} from "./BribeCollector.t.sol";
import {BribeCollectorV1_3} from "src/depreciated/core/BribeCollectorV1_3.sol";
import {Errors} from "src/utils/Errors.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract BribeCollectorV1_3Test is BribeCollectorTest {
    function setUp() public override {
        super.setUp();

        // Verify the KEEPER_ROLE is correctly set up
        assertTrue(
            collector.hasRole(collector.KEEPER_ROLE(), SEARCHER),
            "SEARCHER should have KEEPER_ROLE"
        );
        assertTrue(
            collector.hasRole(collector.KEEPER_ROLE(), keeper),
            "keeper should have KEEPER_ROLE"
        );
        assertTrue(
            collector.hasRole(collector.KEEPER_ROLE(), address(this)),
            "Test contract should have KEEPER_ROLE"
        );
    }

    function testClaimFeesSuccess() public override {
        super.testClaimFeesSuccess();
    }

    function testClaimFeesRejectsPayoutTokenAndSweepPayoutToken()
        public
        override
    {
        super.testClaimFeesRejectsPayoutTokenAndSweepPayoutToken();
    }

    function testClaimFeesNonKeeperFails() public {
        address nonKeeper = address(999);
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(honey);
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 1 ether;

        // Simulate bribes collected
        deal(address(honey), address(collector), 1 ether);

        // Give nonKeeper enough WBERA
        vm.deal(nonKeeper, collector.payoutAmount());
        vm.prank(nonKeeper);
        wbera.deposit{value: collector.payoutAmount()}();

        // Approve spending
        vm.prank(nonKeeper);
        ERC20(collector.payoutToken()).approve(
            address(collector), collector.payoutAmount()
        );

        // Attempt to claim fees as non-keeper should fail
        vm.prank(nonKeeper);
        vm.expectRevert(); // Should revert due to missing KEEPER_ROLE
        collector.claimFees(recipient, feeTokens, feeAmounts);
    }
}
