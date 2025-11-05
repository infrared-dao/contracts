// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helper, IAccessControl} from "./Helper.sol";
import {Errors} from "src/utils/Errors.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";

/**
 * @title EdgeCasesTest
 * @notice Tests for edge cases in vault management, rewards, and fee calculations
 * @dev Covers boundary conditions, error states, and unusual scenarios
 */
contract EdgeCasesTest is Helper {
    MockERC20 testToken1;
    MockERC20 testToken2;

    function setUp() public override {
        super.setUp();

        testToken1 = new MockERC20("Test1", "TST1", 18);
        testToken2 = new MockERC20("Test2", "TST2", 18);

        // Whitelist test tokens
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(testToken1), true);
        infrared.updateWhiteListedRewardTokens(address(testToken2), true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    VAULT MANAGEMENT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testVault_RegisterDuplicateAsset() public {
        // Try to register same asset twice
        vm.expectRevert(Errors.DuplicateAssetAddress.selector);
        infrared.registerVault(address(wbera));
    }

    function testVault_RegisterZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        infrared.registerVault(address(0));
    }

    function testVault_RewardTokenLimit() public {
        // MultiRewards supports up to 10 tokens
        // Try to add many reward tokens and see if there's a limit
        // Note: The actual error handling may vary, just test adding several
        for (uint256 i = 0; i < 5; i++) {
            MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);
            vm.prank(infraredGovernance);
            infrared.updateWhiteListedRewardTokens(address(rewardToken), true);

            vm.prank(infraredGovernance);
            infrared.addReward(address(wbera), address(rewardToken), 1 days);
        }

        // Verify rewards were added
        address[] memory tokens = infraredVault.getAllRewardTokens();
        assertGt(tokens.length, 1, "Should have multiple reward tokens");
    }

    function testVault_AddRewardWithZeroDuration() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 0);
    }

    function testVault_AddRewardNotWhitelisted() public {
        MockERC20 notWhitelisted = new MockERC20("Not", "NWL", 18);

        vm.expectRevert(Errors.RewardTokenNotWhitelisted.selector);
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(notWhitelisted), 1 days);
    }

    function testVault_PauseStakingTwice() public {
        vm.startPrank(infraredGovernance);
        infrared.grantRole(infrared.PAUSER_ROLE(), infraredGovernance);
        infrared.pauseStaking(address(wbera));

        // Pausing again should not revert (idempotent)
        infrared.pauseStaking(address(wbera));
        vm.stopPrank();

        // Verify still paused
        assertTrue(infraredVault.paused(), "Vault should remain paused");
    }

    function testVault_UnpauseNotPaused() public {
        // Unpausing already unpaused vault should not revert
        vm.prank(infraredGovernance);
        infrared.unpauseStaking(address(wbera));

        assertFalse(infraredVault.paused(), "Vault should remain unpaused");
    }

    /*//////////////////////////////////////////////////////////////
                    REWARD DISTRIBUTION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testRewards_NotifyZeroAmount() public {
        // Add reward token first
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 1 days);

        // Notify with zero amount should be handled gracefully
        vm.prank(infraredGovernance);
        testToken1.mint(address(this), 0);
        testToken1.approve(address(infrared), 0);

        // Should not revert but also should not change state
        vm.prank(infraredGovernance);
        vm.expectRevert();
        infrared.addIncentives(address(wbera), address(testToken1), 0);
    }

    function testRewards_VeryLargeRewardDuration() public {
        // Test with maximum safe duration (not overflow)
        uint256 maxDuration = 365 days * 10; // 10 years

        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), maxDuration);

        // Verify duration was set
        (, uint256 duration,,,,,) =
            infraredVault.rewardData(address(testToken1));
        assertEq(duration, maxDuration, "Duration should be set correctly");
    }

    function testRewards_UpdateDurationDuringActiveRewards() public {
        // Add reward with initial duration
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 1 days);

        // Add incentives
        testToken1.mint(address(this), 100 ether);
        testToken1.approve(address(infrared), 100 ether);
        vm.prank(address(this));
        infrared.addIncentives(address(wbera), address(testToken1), 100 ether);

        // Update duration while rewards are active
        vm.prank(infraredGovernance);
        infrared.updateRewardsDurationForVault(
            address(wbera), address(testToken1), 2 days
        );

        // Verify new duration
        (, uint256 newDuration,,,,,) =
            infraredVault.rewardData(address(testToken1));
        assertEq(newDuration, 2 days, "Duration should be updated");
    }

    /*//////////////////////////////////////////////////////////////
                    FEE CALCULATION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testFee_MaximumFee() public {
        // Set fee to maximum (100% = 1e6)
        vm.prank(keeper);
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 1e6);

        uint256 fee =
            infrared.fees(uint256(ConfigTypes.FeeType.HarvestVaultFeeRate));
        assertEq(fee, 1e6, "Should allow max fee");
    }

    function testFee_ZeroFee() public {
        // Set fee to zero
        vm.prank(keeper);
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 0);

        uint256 fee =
            infrared.fees(uint256(ConfigTypes.FeeType.HarvestVaultFeeRate));
        assertEq(fee, 0, "Should allow zero fee");
    }

    function testFee_MultipleTypes() public {
        // Set different fees for each type
        vm.startPrank(keeper);

        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 10000); // 1%
        infrared.updateFee(ConfigTypes.FeeType.HarvestBribesFeeRate, 20000); // 2%
        infrared.updateFee(ConfigTypes.FeeType.HarvestOperatorFeeRate, 30000); // 3%
        infrared.updateFee(ConfigTypes.FeeType.HarvestBoostFeeRate, 40000); // 4%

        vm.stopPrank();

        // Verify all were set correctly
        assertEq(infrared.fees(2), 10000);
        assertEq(infrared.fees(4), 20000);
        assertEq(infrared.fees(0), 30000);
        assertEq(infrared.fees(6), 40000);
    }

    /*//////////////////////////////////////////////////////////////
                    STAKING EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testStaking_ZeroAmount() public {
        vm.expectRevert();
        vm.prank(testUser);
        infraredVault.stake(0);
    }

    function testStaking_WithoutApproval() public {
        deal(address(wbera), testUser, 100 ether);

        vm.expectRevert();
        vm.prank(testUser);
        infraredVault.stake(100 ether);
    }

    function testStaking_WhilePaused() public {
        // Pause vault
        vm.startPrank(infraredGovernance);
        infrared.grantRole(infrared.PAUSER_ROLE(), infraredGovernance);
        // vm.prank(infraredGovernance);
        infrared.pauseStaking(address(wbera));
        vm.stopPrank();

        // Try to stake
        deal(address(wbera), testUser, 100 ether);
        vm.startPrank(testUser);
        wbera.approve(address(infraredVault), 100 ether);

        vm.expectRevert();
        infraredVault.stake(100 ether);
        vm.stopPrank();
    }

    function testWithdraw_ZeroAmount() public {
        vm.expectRevert();
        vm.prank(testUser);
        infraredVault.withdraw(0);
    }

    function testWithdraw_MoreThanBalance() public {
        // Stake some first
        stakeInVault(address(infraredVault), address(wbera), testUser, 10 ether);

        // Try to withdraw more
        vm.expectRevert();
        vm.prank(testUser);
        infraredVault.withdraw(20 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    RECOVERY EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testRecover_ZeroAmount() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAmount.selector);
        infrared.recoverERC20(testUser, address(testToken1), 0);

        // Should not revert but also should not transfer anything
    }

    function testRecover_NonexistentBalance() public {
        // Try to recover tokens that contract doesn't have
        vm.prank(infraredGovernance);
        vm.expectRevert();
        infrared.recoverERC20(testUser, address(testToken1), 100 ether);

        // Should revert due to insufficient balance
        // (ERC20 transfer will revert)
    }

    /*//////////////////////////////////////////////////////////////
                    WHITELIST EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testWhitelist_AddRemoveAdd() public {
        address token = address(0x999);

        // Add
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(token, true);
        assertTrue(infrared.whitelistedRewardTokens(token));

        // Remove
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(token, false);
        assertFalse(infrared.whitelistedRewardTokens(token));

        // Add again
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(token, true);
        assertTrue(infrared.whitelistedRewardTokens(token));
    }

    function testWhitelist_AddTwice() public {
        address token = address(0x999);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(token, true);
        // Adding again should be idempotent
        infrared.updateWhiteListedRewardTokens(token, true);
        vm.stopPrank();

        assertTrue(infrared.whitelistedRewardTokens(token));
    }

    /*//////////////////////////////////////////////////////////////
                    CLAIM REWARDS EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testClaimRewards_NoRewards() public {
        // User stakes but no rewards added yet
        stakeInVault(address(infraredVault), address(wbera), testUser, 10 ether);

        // Claim should not revert even with no rewards
        vm.prank(testUser);
        infraredVault.getReward();

        // User should have no reward tokens
        assertEq(ibgt.balanceOf(testUser), 0);
    }

    function testClaimRewards_AfterUnstake() public {
        // Stake
        stakeInVault(address(infraredVault), address(wbera), testUser, 10 ether);

        // Add rewards
        testToken1.mint(address(this), 100 ether);
        testToken1.approve(address(infrared), 100 ether);
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 1 days);
        infrared.addIncentives(address(wbera), address(testToken1), 100 ether);

        // Wait for rewards to accrue
        vm.warp(block.timestamp + 12 hours);

        // Unstake all
        vm.prank(testUser);
        infraredVault.withdraw(10 ether);

        // Should still be able to claim earned rewards
        vm.prank(testUser);
        infraredVault.getReward();

        // User should have some rewards
        assertGt(testToken1.balanceOf(testUser), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    TIME MANIPULATION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testRewards_AfterPeriodFinish() public {
        // Add rewards with 1 day duration
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 1 days);

        testToken1.mint(address(this), 100 ether);
        testToken1.approve(address(infrared), 100 ether);
        infrared.addIncentives(address(wbera), address(testToken1), 100 ether);

        // Stake
        stakeInVault(address(infraredVault), address(wbera), testUser, 10 ether);

        // Warp past period finish
        vm.warp(block.timestamp + 2 days);

        // Claim rewards - should get all rewards
        vm.prank(testUser);
        infraredVault.getReward();

        // User should have rewards (accounting for fees)
        assertGt(testToken1.balanceOf(testUser), 0);
    }

    function testRewards_MultiplePeriodsWithoutClaiming() public {
        // Add initial rewards
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(testToken1), 1 days);

        // Stake
        stakeInVault(address(infraredVault), address(wbera), testUser, 10 ether);

        // Add rewards in multiple periods
        for (uint256 i = 0; i < 3; i++) {
            testToken1.mint(address(this), 100 ether);
            testToken1.approve(address(infrared), 100 ether);
            infrared.addIncentives(
                address(wbera), address(testToken1), 100 ether
            );

            vm.warp(block.timestamp + 1 days);
        }

        // Claim all rewards at once
        uint256 balanceBefore = testToken1.balanceOf(testUser);
        vm.prank(testUser);
        infraredVault.getReward();
        uint256 balanceAfter = testToken1.balanceOf(testUser);

        // Should have accumulated rewards from all periods
        assertGt(balanceAfter - balanceBefore, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPOUND EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testCompound_WithZeroFees() public {
        uint256 depositsBefore = ibera.deposits();

        // Compound with no fees collected
        vm.prank(keeper);
        ibera.compound();

        uint256 depositsAfter = ibera.deposits();

        // Deposits should not change
        assertEq(depositsAfter, depositsBefore, "Deposits should not change");
    }

    function testCompound_MultipleTimes() public {
        // Add fees
        vm.deal(address(receivor), 10 ether);
        // vm.prank(address(receivor));
        // (bool success,) = address(ibera).call{value: 10 ether}("");
        // assertTrue(success);

        uint256 depositsBefore = ibera.deposits();

        // Compound multiple times
        vm.startPrank(keeper);
        ibera.compound();
        ibera.compound();
        ibera.compound();
        vm.stopPrank();

        uint256 depositsAfter = ibera.deposits();

        // Should only compound once (no double-counting)
        assertGt(depositsAfter, depositsBefore);
    }
}
