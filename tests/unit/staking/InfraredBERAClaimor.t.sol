// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IInfraredBERAClaimor} from "src/interfaces/IInfraredBERAClaimor.sol";
import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {Errors} from "src/utils/Errors.sol";

contract InfraredBERAClaimorTest is InfraredBERABaseTest {
    function testInitialize() public {
        assertEq(
            address(claimor.ibera()),
            address(ibera),
            "IBERA address not set correctly"
        );
        // address(this) deployed contracts using IBERA deployer
        assertTrue(
            claimor.hasRole(claimor.DEFAULT_ADMIN_ROLE(), infraredGovernance),
            "Gov not granted admin role"
        );
        assertTrue(
            claimor.hasRole(claimor.GOVERNANCE_ROLE(), infraredGovernance),
            "Gov not granted governance role"
        );
        assertTrue(
            claimor.hasRole(claimor.KEEPER_ROLE(), keeper),
            "Keeper not granted keeper role"
        );
    }

    function testQueueFailsWhenCalledByUnauthorized() public {
        uint256 amount = 1 ether;

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, alice)
        );
        claimor.queue{value: amount}(alice);
        vm.stopPrank();

        assertEq(claimor.claims(alice), 0, "Claim should not have been created");
        assertEq(address(claimor).balance, 0, "Balance should not have changed");
    }

    function testQueueUpdatesClaims() public {
        address mockWithdrawor = address(0x123);
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.withdrawor.selector),
            abi.encode(mockWithdrawor)
        );

        uint256 claim = claimor.claims(alice);
        uint256 balance = address(claimor).balance;
        uint256 amount = 1 ether;

        // Deal ETH to the mock withdrawor before making the call
        vm.deal(mockWithdrawor, amount);

        vm.startPrank(mockWithdrawor);
        claimor.queue{value: amount}(alice);
        vm.stopPrank();

        assertEq(claimor.claims(alice), claim + amount);
        assertEq(address(claimor).balance, balance + amount);
    }

    function testQueueEmitsQueue() public {
        address mockWithdrawor = address(0x123);
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.withdrawor.selector),
            abi.encode(mockWithdrawor)
        );

        uint256 claim = claimor.claims(alice);
        uint256 amount = 1 ether;

        // Deal ETH to the mock withdrawor before making the call
        vm.deal(mockWithdrawor, amount);

        vm.startPrank(mockWithdrawor);
        vm.expectEmit();
        emit IInfraredBERAClaimor.Queue(alice, amount, claim + amount);
        claimor.queue{value: amount}(alice);
        vm.stopPrank();
    }

    function testSweepUpdatesClaims() public {
        testQueueUpdatesClaims();
        assertTrue(claimor.claims(alice) > 0);
        claimor.sweep(alice);
        assertEq(claimor.claims(alice), 0);
    }

    function testSweepTransfersETH() public {
        testQueueUpdatesClaims();
        uint256 claim = claimor.claims(alice);
        assertTrue(claim > 0);

        uint256 balanceClaimor = address(claimor).balance;
        uint256 balanceAlice = address(alice).balance;

        claimor.sweep(alice);
        assertEq(address(claimor).balance, balanceClaimor - claim);
        assertEq(address(alice).balance, balanceAlice + claim);
    }

    function testSweepEmitsSweep() public {
        testQueueUpdatesClaims();
        uint256 claim = claimor.claims(alice);
        assertTrue(claim > 0);

        vm.expectEmit();
        emit IInfraredBERAClaimor.Sweep(alice, claim);
        claimor.sweep(alice);
    }
}
