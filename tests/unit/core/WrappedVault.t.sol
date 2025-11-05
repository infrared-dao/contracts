// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@solmate/tokens/ERC20.sol";
import "src/core/WrappedVault.sol";
import "src/depreciated/core/Infrared.sol";
import "src/core/InfraredVault.sol";
import {Helper} from "./Infrared/Helper.sol";

contract WrappedVaultTest is Helper {
    WrappedVault public wrappedVault;

    ERC20 public stakingToken;
    address public rewardDistributor = address(0x123);

    address public user = address(0x456);
    address public owner = address(0x789);

    function setUp() public override {
        super.setUp();

        // Deploy the staking token (ERC20 mock)
        stakingToken = ERC20(address(ibgt));

        // Deploy the WrappedVault contract
        wrappedVault = new WrappedVault(
            rewardDistributor,
            address(infrared),
            address(stakingToken),
            string.concat("Wrapped Infrared Vault ", stakingToken.name()),
            string.concat("w", stakingToken.symbol())
        );

        // Set up initial conditions
        vm.label(user, "User");
        vm.label(owner, "Owner");
        vm.label(rewardDistributor, "RewardDistributor");

        // Mint some tokens to the user for testing
        deal(address(stakingToken), user, 1000 ether);
    }

    function testDeposit() public {
        vm.startPrank(user);

        // Approve the WrappedVault to spend user's staking tokens
        stakingToken.approve(address(wrappedVault), 500 ether);

        // Deposit tokens into the WrappedVault
        wrappedVault.deposit(500 ether, user);

        // Verify balances
        assertEq(
            wrappedVault.balanceOf(user),
            500 ether,
            "User's vault shares should match the deposit amount"
        );
        assertEq(
            stakingToken.balanceOf(user),
            500 ether,
            "User's staking token balance should decrease"
        );

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);

        // Approve and deposit tokens
        stakingToken.approve(address(wrappedVault), 500 ether);
        wrappedVault.deposit(500 ether, user);

        // Withdraw tokens
        wrappedVault.withdraw(500 ether, user, user);

        // Verify balances
        assertEq(
            wrappedVault.balanceOf(user),
            0,
            "User's vault shares should be zero after withdrawal"
        );
        assertEq(
            stakingToken.balanceOf(user),
            1000 ether,
            "User's staking token balance should be restored"
        );

        vm.stopPrank();
    }

    function testClaimRewards() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount);

        vm.startPrank(user);

        // Approve and deposit tokens
        stakingToken.approve(address(wrappedVault), 500 ether);
        wrappedVault.deposit(500 ether, user);

        skip(rewardsDuration + 100 minutes);

        // Claim rewards
        wrappedVault.claimRewards();

        // Verify reward distributor received the rewards
        assertGt(
            wbera.balanceOf(rewardDistributor),
            99.99 ether,
            "Reward distributor should receive all rewards"
        );

        vm.stopPrank();
    }

    function testClaimRewardsSameAsStaking() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        deal(address(ibgt), address(this), rewardsAmount);
        ibgt.approve(address(infrared), rewardsAmount);
        infrared.addIncentives(address(ibgt), address(ibgt), rewardsAmount);

        vm.startPrank(user);

        // Approve and deposit tokens
        stakingToken.approve(address(wrappedVault), 500 ether);
        wrappedVault.deposit(500 ether, user);

        skip(rewardsDuration + 100 minutes);

        // Claim rewards
        wrappedVault.claimRewards();

        // Verify reward distributor received the rewards
        assertGt(
            ibgt.balanceOf(rewardDistributor),
            99.99 ether,
            "Reward distributor should receive all rewards"
        );

        vm.stopPrank();
    }

    function setUpGetReward(uint256 rewardsAmount) internal {
        // Setup reward token in the infraredVault and mint rewards
        vm.startPrank(address(infrared));
        deal(address(wbera), address(infrared), rewardsAmount);
        wbera.approve(address(wrappedVault.iVault()), rewardsAmount);
        wrappedVault.iVault().notifyRewardAmount(address(wbera), rewardsAmount);
        vm.stopPrank();
    }
}
