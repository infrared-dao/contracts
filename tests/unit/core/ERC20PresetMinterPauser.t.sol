// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";

contract ERC20PresetMinterPauserTest is Test {
    InfraredGovernanceToken token;

    address admin = address(0xAA);
    address minter = address(0xBB);
    address pauser = address(0xCC);
    address burner = address(0xDD);
    address user = address(0xEE);
    address mockInfrared = address(0xFF);

    function setUp() public {
        // Deploy token
        token = new InfraredGovernanceToken(
            mockInfrared, admin, minter, pauser, burner
        );

        // Minter gives user some tokens
        vm.prank(minter);
        token.mint(user, 1000 ether);
    }

    function testPauseAndUnpause() public {
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());

        vm.prank(pauser);
        token.unpause();
        assertFalse(token.paused());
    }

    function testMintFailsWhenPaused() public {
        vm.prank(pauser);
        token.pause();

        vm.startPrank(minter);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.mint(address(1234), 1 ether);
        vm.stopPrank();
    }

    function testBurnFailsWhenPaused() public {
        // Give burner some tokens first
        vm.prank(minter);
        token.mint(burner, 500 ether);

        vm.prank(pauser);
        token.pause();

        vm.startPrank(burner);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.burn(100 ether);
        vm.stopPrank();
    }

    function testTransferSucceedsWhenPaused() public {
        vm.prank(pauser);
        token.pause();

        vm.prank(user);
        token.transfer(address(0xF0), 200 ether);
        assertTrue(token.balanceOf(address(0xF0)) == 200 ether);

        vm.prank(user);
        token.approve(admin, 100 ether);
        vm.prank(admin);
        token.transferFrom(user, address(0xF0), 100 ether);

        assertTrue(token.balanceOf(address(0xF0)) == 300 ether);
    }
}
