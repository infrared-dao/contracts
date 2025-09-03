// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/periphery/Redeemer.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Mock iBGT token (ERC20 with totalSupply)
contract MockIBGT is ERC20("Mock iBGT", "iBGT", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock BGT with boosts and queuedBoost
contract MockBGT {
    mapping(address => uint256) public boosts;
    mapping(address => uint256) public queuedBoost;

    function setBoosts(address account, uint256 amount) external {
        boosts[account] = amount;
    }

    function setQueuedBoost(address account, uint256 amount) external {
        queuedBoost[account] = amount;
    }
}

// Mock InfraredV1_7
contract MockInfrared {
    address public ibgt;
    uint256 public redeemedAmount;
    address public caller;

    constructor(address _ibgt) {
        ibgt = _ibgt;
    }

    function redeemIbgtForBera(uint256 amount) external {
        redeemedAmount = amount;
        caller = msg.sender;
        // Simulate burning iBGT (assume approved)
        ERC20(ibgt).transferFrom(msg.sender, address(0), amount); // Burn
        // Send ETH (BERA) to caller
        payable(msg.sender).transfer(amount);
    }
}

contract RedeemerTest is Test {
    Redeemer redeemer;
    MockIBGT mockIbgt;
    MockBGT mockBgt;
    MockInfrared mockInfrared;

    address user = address(0x123);

    function setUp() public {
        mockIbgt = new MockIBGT();
        mockBgt = new MockBGT();
        mockInfrared = new MockInfrared(address(mockIbgt));

        redeemer = new Redeemer(address(mockBgt), address(mockInfrared));

        // Mint some iBGT to user
        mockIbgt.mint(user, 1000 ether);
        // Set totalSupply implicitly via mint
        mockIbgt.mint(address(this), 1000 ether); // For totalSupply = 2000 ether
    }

    function test_RedeemSuccess() public {
        // Set unboosted sufficient (totalSupply 2000 - boosts 500 - queued 500 = 1000)
        mockBgt.setBoosts(address(mockInfrared), 500 ether);
        mockBgt.setQueuedBoost(address(mockInfrared), 500 ether);

        // User approves redeemer
        vm.prank(user);
        mockIbgt.approve(address(redeemer), 100 ether);

        // Deal ETH to mockInfrared for simulation
        vm.deal(address(mockInfrared), 100 ether);

        uint256 userBalanceBefore = user.balance;
        // Call as redeemer
        vm.prank(user);
        redeemer.redeemIbgtForBera(100 ether);

        // Assertions
        assertEq(mockInfrared.redeemedAmount(), 100 ether);
        assertEq(user.balance, userBalanceBefore + 100 ether);
        assertEq(mockIbgt.balanceOf(user), 900 ether); // Burned 100
    }

    function test_InsufficientUnboostedReverts() public {
        // Set unboosted insufficient (totalSupply 2000 - 1400 - 600 = 0)
        mockBgt.setBoosts(address(mockInfrared), 1400 ether);
        mockBgt.setQueuedBoost(address(mockInfrared), 600 ether);

        vm.prank(user);
        mockIbgt.approve(address(redeemer), 100 ether);

        vm.prank(user);
        vm.expectRevert(Redeemer.InsufficientUnboostedBGT.selector);
        redeemer.redeemIbgtForBera(100 ether);
    }

    function test_ZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(Redeemer.InvalidAmount.selector);
        redeemer.redeemIbgtForBera(0);
    }

    function test_EventEmitted() public {
        // Setup as in success test
        mockBgt.setBoosts(address(mockInfrared), 500 ether);
        mockBgt.setQueuedBoost(address(mockInfrared), 500 ether);
        vm.prank(user);
        mockIbgt.approve(address(redeemer), 100 ether);
        vm.deal(address(mockInfrared), 100 ether);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Redeemer.IbgtRedeemed(user, 100 ether);
        redeemer.redeemIbgtForBera(100 ether);
    }
}
