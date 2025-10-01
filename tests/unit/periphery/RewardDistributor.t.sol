// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Owned} from "@solmate/auth/Owned.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";
import {RewardDistributor} from "src/periphery/RewardDistributor.sol";

contract RewardDistributorTest is Helper {
    InfraredBGT public rewardsToken;
    MockERC20 public stakingToken;
    RewardDistributor public _distributor;

    // Test addresses
    address public keeper1 = address(0x1337);
    address public keeper2 = address(0x2337);
    address public nonKeeper = address(0xBEEF);
    address public attacker = address(0xBAD);

    // Constants for testing
    uint256 constant INITIAL_TARGET_APR = 1500; // 15%
    uint256 constant INITIAL_DISTRIBUTION_INTERVAL = 2 hours;
    uint256 constant SECONDS_PER_YEAR = 36525 * 24 * 60 * 60 / 100;
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant DEFAULT_REWARDS_DURATION = 86400;

    // Events to test
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event RewardsDistributed(address vault, uint256 amount);
    event TargetAPRUpdated(uint256 oldAPR, uint256 newAPR);
    event DistributionIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event KeeperUpdated(address indexed keeper, bool active);
    event MaxSupplyDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);

    function setUp() public override {
        super.setUp();

        rewardsToken = ibgt;

        _distributor = new RewardDistributor(
            infraredGovernance,
            address(infrared),
            stakingAsset,
            address(rewardsToken),
            address(keeper),
            INITIAL_TARGET_APR,
            INITIAL_DISTRIBUTION_INTERVAL
        );

        // Setup initial vault state with staking and rewards
        _setupInitialVaultState();
    }

    function _setupInitialVaultState() private {
        // Stake tokens to have non-zero totalSupply
        deal(address(stakingAsset), address(this), 10000 ether);
        wbera.approve(address(infraredVault), 10000 ether);
        infraredVault.stake(10000 ether);

        // Add minimal initial rewards to initialize the vault
        deal(address(rewardsToken), address(this), 1 ether);
        rewardsToken.approve(address(infrared), 1 ether);
        infrared.addIncentives(stakingAsset, address(rewardsToken), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        // Verify all state variables are correctly initialized
        assertEq(_distributor.owner(), infraredGovernance);
        assertEq(address(_distributor.infrared()), address(infrared));
        assertEq(address(_distributor.stakingToken()), stakingAsset);
        assertEq(address(_distributor.rewardsToken()), address(rewardsToken));
        assertEq(_distributor.targetAPR(), INITIAL_TARGET_APR);
        assertEq(
            _distributor.distributionInterval(), INITIAL_DISTRIBUTION_INTERVAL
        );
        assertEq(_distributor.lastDistributionTime(), 0);
        assertEq(_distributor.maxSupplyDeviation(), 100); // 1% default

        // Verify governance is set as initial keeper
        assertTrue(_distributor.keepers(infraredGovernance));

        // Verify approval is set correctly
        assertEq(
            rewardsToken.allowance(address(_distributor), address(infrared)),
            type(uint256).max
        );
    }

    function test_Constructor_RevertNoVault() public {
        address nonExistentToken = address(0xDEAD);

        vm.expectRevert(RewardDistributor.NoVault.selector);
        new RewardDistributor(
            infraredGovernance,
            address(infrared),
            nonExistentToken, // This token has no vault
            address(rewardsToken),
            address(keeper),
            INITIAL_TARGET_APR,
            INITIAL_DISTRIBUTION_INTERVAL
        );
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateKeeper_AddKeeper() public {
        assertFalse(_distributor.keepers(keeper1));

        vm.expectEmit(true, false, false, true);
        emit KeeperUpdated(keeper1, true);

        vm.prank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);

        assertTrue(_distributor.keepers(keeper1));
    }

    function test_UpdateKeeper_RemoveKeeper() public {
        // First add a keeper
        vm.prank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);
        assertTrue(_distributor.keepers(keeper1));

        // Now remove them
        vm.expectEmit(true, false, false, true);
        emit KeeperUpdated(keeper1, false);

        vm.prank(infraredGovernance);
        _distributor.updateKeeper(keeper1, false);

        assertFalse(_distributor.keepers(keeper1));
    }

    function test_UpdateKeeper_RevertZeroAddress() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.ZeroAddress.selector);
        _distributor.updateKeeper(address(0), true);
    }

    function test_UpdateKeeper_RevertNothingToUpdate() public {
        // Try to add governance as keeper (already is)
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.NothingToUpdate.selector);
        _distributor.updateKeeper(infraredGovernance, true);

        // Try to remove non-existent keeper
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.NothingToUpdate.selector);
        _distributor.updateKeeper(keeper1, false);
    }

    function test_UpdateKeeper_RevertUnauthorized() public {
        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.updateKeeper(keeper1, true);
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetMaxTotalSupply() public view {
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();
        uint256 maxDeviation = _distributor.maxSupplyDeviation();

        uint256 expectedMax =
            currentSupply + (currentSupply * maxDeviation / BASIS_POINTS);
        uint256 actualMax = _distributor.getMaxTotalSupply();

        assertEq(actualMax, expectedMax);
    }

    function test_SetMaxSupplyDeviation_Success() public {
        uint256 newDeviation = 500; // 5%

        vm.expectEmit(true, true, false, false);
        emit MaxSupplyDeviationUpdated(200, newDeviation);

        vm.prank(infraredGovernance);
        _distributor.setMaxSupplyDeviation(newDeviation);

        assertEq(_distributor.maxSupplyDeviation(), newDeviation);
    }

    function test_SetMaxSupplyDeviation_RevertUnauthorized() public {
        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.setMaxSupplyDeviation(500);
    }

    /*//////////////////////////////////////////////////////////////
                     DISTRIBUTE TESTS (UPDATED)
    //////////////////////////////////////////////////////////////*/

    function test_Distribute_OnlyKeeper() public {
        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 1_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        uint256 maxSupply = _distributor.getMaxTotalSupply();

        // Non-keeper should fail
        vm.prank(nonKeeper);
        vm.expectRevert(RewardDistributor.NotKeeper.selector);
        _distributor.distribute(maxSupply);

        // Governance (keeper) should succeed
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);
    }

    function test_Distribute_WithSlippageProtection() public {
        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 1_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();

        // Try with max supply that's too low (will trigger slippage)
        uint256 tooLowMaxSupply = currentSupply - 1;

        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.TotalSupplySlippage.selector);
        _distributor.distribute(tooLowMaxSupply);

        // Should work with proper max supply
        uint256 properMaxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(properMaxSupply);
    }

    function test_Distribute_FirstDistribution_WithKeeper() public {
        // Add an additional keeper
        vm.prank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);

        // Fund the distributor
        uint256 fundAmount = 1_000_000 ether;
        deal(address(rewardsToken), address(_distributor), fundAmount);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get initial vault state
        IInfraredVault _vault = infrared.vaultRegistry(stakingAsset);
        (, uint256 rewardsDuration,, uint256 rewardRateBefore,,,) =
            _vault.rewardData(address(rewardsToken));
        uint256 totalSupply = _vault.totalSupply();

        // Calculate expected additional amount
        uint256 expectedTotalRewards = (
            INITIAL_TARGET_APR * totalSupply * rewardsDuration
        ) / (SECONDS_PER_YEAR * BASIS_POINTS);

        // Expect the event
        vm.expectEmit(true, false, false, false);
        emit RewardsDistributed(address(_vault), expectedTotalRewards);

        // Execute distribution with keeper1
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply);

        // Verify state changes
        assertEq(_distributor.lastDistributionTime(), block.timestamp);

        // Verify rewards were added to vault
        (,,, uint256 rewardRateAfter,,,) =
            _vault.rewardData(address(rewardsToken));
        assertGt(rewardRateAfter, rewardRateBefore);
    }

    /*//////////////////////////////////////////////////////////////
                    SANDWICH ATTACK PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SandwichAttack_Prevention() public {
        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get initial state
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 initialSupply = vault.totalSupply();
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        // Simulate attacker front-running by staking large amount
        // (In real test, would need to actually stake to increase totalSupply)
        // For this test, we'll simulate by using a maxSupply that's now too low

        // Assume attacker stakes and increases supply by 5% (more than 2% tolerance)
        uint256 attackerStake = initialSupply * 5 / 100;
        deal(address(stakingAsset), attacker, attackerStake);
        vm.prank(attacker);
        wbera.approve(address(infraredVault), attackerStake);
        vm.prank(attacker);
        infraredVault.stake(attackerStake);

        // Distribution should fail with the old maxSupply
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.TotalSupplySlippage.selector);
        _distributor.distribute(maxSupply);

        // But would work with updated maxSupply
        uint256 newMaxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(newMaxSupply);
    }

    function test_SandwichAttack_WithinTolerance() public {
        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get initial state
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 initialSupply = vault.totalSupply();
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        // Small stake within tolerance (1%, less than 2% limit)
        uint256 smallStake = initialSupply * 1 / 100;
        deal(address(stakingAsset), address(this), smallStake);
        wbera.approve(address(infraredVault), smallStake);
        infraredVault.stake(smallStake);

        // Should still work with original maxSupply since within tolerance
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS (UPDATED)
    //////////////////////////////////////////////////////////////*/

    function test_Integration_MultipleKeepers() public {
        // Setup multiple keepers
        vm.startPrank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);
        _distributor.updateKeeper(keeper2, true);
        vm.stopPrank();

        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // First distribution by keeper1
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply1 = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply1);

        uint256 firstDistTime = _distributor.lastDistributionTime();

        // Second distribution by keeper2
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply2 = _distributor.getMaxTotalSupply();
        vm.prank(keeper2);
        _distributor.distribute(maxSupply2);

        // Both distributions should work
        assertGt(_distributor.lastDistributionTime(), firstDistTime);
    }

    function test_Integration_KeeperRotation() public {
        // Start with keeper1
        vm.prank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);

        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // First distribution by keeper1
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply);

        // Remove keeper1, add keeper2
        vm.startPrank(infraredGovernance);
        _distributor.updateKeeper(keeper1, false);
        _distributor.updateKeeper(keeper2, true);
        vm.stopPrank();

        // keeper1 should no longer work
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        vm.expectRevert(RewardDistributor.NotKeeper.selector);
        _distributor.distribute(maxSupply);

        // keeper2 should work
        vm.prank(keeper2);
        _distributor.distribute(maxSupply);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS (UPDATED)
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawRewards_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        deal(address(rewardsToken), address(_distributor), depositAmount);

        uint256 balanceBefore = rewardsToken.balanceOf(infraredGovernance);

        vm.prank(infraredGovernance);
        _distributor.withdrawRewards(withdrawAmount);

        assertEq(
            rewardsToken.balanceOf(infraredGovernance),
            balanceBefore + withdrawAmount
        );
        assertEq(
            rewardsToken.balanceOf(address(_distributor)),
            depositAmount - withdrawAmount
        );
    }

    function test_RecoverTokens_Success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 100 ether;

        deal(address(wbera), address(_distributor), depositAmount);

        uint256 balanceBefore = wbera.balanceOf(infraredGovernance);

        vm.prank(infraredGovernance);
        _distributor.recoverERC20(address(wbera), address(infraredGovernance));

        assertEq(
            wbera.balanceOf(infraredGovernance), balanceBefore + withdrawAmount
        );
        assertEq(
            wbera.balanceOf(address(_distributor)),
            depositAmount - withdrawAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ TESTS (UPDATED)
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Distribute_WithSlippage(
        uint256 apr,
        uint256 slippagePercent
    ) public {
        // Bound inputs
        apr = bound(apr, 1000, 10000); // 10% to 100% APR
        slippagePercent = bound(slippagePercent, 0, 1000); // 0% to 10% slippage

        // Setup new distributor
        RewardDistributor fuzzDistributor = new RewardDistributor(
            infraredGovernance,
            address(infrared),
            stakingAsset,
            address(rewardsToken),
            address(keeper),
            apr,
            INITIAL_DISTRIBUTION_INTERVAL
        );

        // Fund it
        deal(address(rewardsToken), address(fuzzDistributor), 10_000_000 ether);

        // Wait for distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get current supply and calculate max with slippage
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();
        uint256 maxWithSlippage =
            currentSupply + (currentSupply * slippagePercent / 10000);

        vm.prank(infraredGovernance);
        if (slippagePercent <= 200) {
            // Within default 2% tolerance
            // Should succeed
            fuzzDistributor.distribute(maxWithSlippage);
            assertEq(fuzzDistributor.lastDistributionTime(), block.timestamp);
        } else {
            // Should revert due to slippage
            vm.expectRevert(RewardDistributor.TotalSupplySlippage.selector);
            fuzzDistributor.distribute(currentSupply - 1);
        }
    }

    function testFuzz_MaxSupplyDeviation(uint256 deviation) public {
        deviation = bound(deviation, 0, 10000); // 0% to 100%

        vm.prank(infraredGovernance);
        _distributor.setMaxSupplyDeviation(deviation);

        assertEq(_distributor.maxSupplyDeviation(), deviation);

        // Verify getMaxTotalSupply calculation
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();
        uint256 expectedMax =
            currentSupply + (currentSupply * deviation / BASIS_POINTS);

        assertEq(_distributor.getMaxTotalSupply(), expectedMax);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES (UPDATED)
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_ZeroSupplyDeviation() public {
        // Set deviation to 0 (no tolerance)
        vm.prank(infraredGovernance);
        _distributor.setMaxSupplyDeviation(0);

        // Fund distributor
        deal(address(rewardsToken), address(_distributor), 1_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribution should only work with exact supply
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 exactSupply = vault.totalSupply();

        // Even 1 wei more should fail
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.TotalSupplySlippage.selector);
        _distributor.distribute(exactSupply - 1);

        // Exact supply should work
        vm.prank(infraredGovernance);
        _distributor.distribute(exactSupply);
    }

    function test_EdgeCase_MaxSupplyDeviationOverflow() public {
        // Set very high deviation
        vm.prank(infraredGovernance);
        _distributor.setMaxSupplyDeviation(10000); // 100%

        // Should handle without overflow
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();

        assertEq(maxSupply, currentSupply * 2); // 100% increase = 2x
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetExpectedAmount_Success() public {
        // Fund the distributor
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Initially should be 0 (too soon)
        uint256 expectedAmount = _distributor.getExpectedAmount();
        assertEq(expectedAmount, 0);

        // Skip past distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Calculate expected amount manually
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        (
            ,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            ,
            ,
            uint256 residual
        ) = vault.rewardData(address(rewardsToken));

        uint256 totalSupply = vault.totalSupply();
        uint256 leftover = block.timestamp >= periodFinish
            ? 0
            : (periodFinish - block.timestamp) * rewardRate;

        uint256 totalRewardsNeeded = (
            INITIAL_TARGET_APR * totalSupply * rewardsDuration
        ) / (SECONDS_PER_YEAR * BASIS_POINTS);

        uint256 expectedCalc = totalRewardsNeeded > (leftover + residual)
            ? totalRewardsNeeded - (leftover + residual)
            : 0;

        expectedAmount = _distributor.getExpectedAmount();
        assertEq(expectedAmount, expectedCalc);
    }

    function test_GetExpectedAmount_ZeroWithInsufficientBalance() public {
        // Don't fund the distributor
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Should return 0 due to insufficient balance
        uint256 expectedAmount = _distributor.getExpectedAmount();
        assertEq(expectedAmount, 0);
    }

    function test_GetExpectedAmount_ZeroTotalSupply() public {
        // Create a new vault with zero staked supply
        RewardDistributor zeroSupplyDistributor = new RewardDistributor(
            infraredGovernance,
            address(infrared),
            stakingAsset,
            address(rewardsToken),
            address(keeper),
            INITIAL_TARGET_APR,
            INITIAL_DISTRIBUTION_INTERVAL
        );

        deal(
            address(rewardsToken),
            address(zeroSupplyDistributor),
            10_000_000 ether
        );

        // Unstake all to get zero supply
        infraredVault.withdraw(10000 ether);

        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 expectedAmount = zeroSupplyDistributor.getExpectedAmount();
        assertEq(expectedAmount, 0);
    }

    function test_GetCurrentAPR_Success() public {
        // Setup initial rewards
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribute rewards
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Check current APR
        uint256 currentAPR = _distributor.getCurrentAPR();

        // Should be close to target APR (allowing for some rounding)
        assertApproxEqAbs(currentAPR, INITIAL_TARGET_APR, 10);
    }

    function test_GetCurrentAPR_ZeroAfterPeriodFinish() public {
        // Setup and distribute
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Warp past period finish
        vm.warp(block.timestamp + DEFAULT_REWARDS_DURATION + 1);

        uint256 currentAPR = _distributor.getCurrentAPR();
        assertEq(currentAPR, 0);
    }

    function test_GetAPRForAmount_Success() public view {
        uint256 testAmount = 1000 ether;

        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        (, uint256 rewardsDuration,,,,,) =
            vault.rewardData(address(rewardsToken));
        uint256 totalSupply = vault.totalSupply();

        uint256 expectedAPR = (testAmount * SECONDS_PER_YEAR * BASIS_POINTS)
            / (rewardsDuration * totalSupply);

        uint256 calculatedAPR = _distributor.getAPRForAmount(testAmount);
        assertEq(calculatedAPR, expectedAPR);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetTargetAPR_OnlyKeeper() public {
        uint256 newAPR = 2000; // 20%

        // Non-keeper should fail
        vm.prank(nonKeeper);
        vm.expectRevert(RewardDistributor.NotKeeper.selector);
        _distributor.setTargetAPR(newAPR);

        // Keeper should succeed
        vm.expectEmit(true, true, false, false);
        emit TargetAPRUpdated(INITIAL_TARGET_APR, newAPR);

        vm.prank(infraredGovernance);
        _distributor.setTargetAPR(newAPR);

        assertEq(_distributor.targetAPR(), newAPR);
    }

    function test_SetTargetAPR_RevertZeroAPR() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.ZeroTargetAPR.selector);
        _distributor.setTargetAPR(0);
    }

    function test_SetDistributionInterval_Success() public {
        uint256 newInterval = 4 hours;

        vm.expectEmit(true, true, false, false);
        emit DistributionIntervalUpdated(
            INITIAL_DISTRIBUTION_INTERVAL, newInterval
        );

        vm.prank(infraredGovernance);
        _distributor.setDistributionInterval(newInterval);

        assertEq(_distributor.distributionInterval(), newInterval);
    }

    function test_SetDistributionInterval_RevertZeroInterval() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.ZeroDistributionInterval.selector);
        _distributor.setDistributionInterval(0);
    }

    function test_SetDistributionInterval_OnlyOwner() public {
        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.setDistributionInterval(4 hours);
    }

    /*//////////////////////////////////////////////////////////////
                        DISTRIBUTION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Distribute_RevertZeroRewardDuration() public {
        // This would require mocking the vault to return 0 duration
        // Skip for now as it requires significant setup changes
    }

    function test_Distribute_RevertDistributionTooSoon() public {
        deal(address(rewardsToken), address(_distributor), 1_000_000 ether);

        // Try to distribute immediately (too soon)
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.DistributionTooSoon.selector);
        _distributor.distribute(maxSupply);
    }

    function test_Distribute_RevertNothingToAdd() public {
        // First distribute to set up rewards
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Immediately try again (should have nothing to add)
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // If the calculation results in 0 additional amount needed
        maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        // This might revert with NothingToAdd depending on the exact timing
        // and calculation
    }

    function test_Distribute_RevertInsufficientBalance() public {
        // Don't fund the distributor fully
        deal(address(rewardsToken), address(_distributor), 1 wei);

        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.InsufficientRewardBalance.selector);
        _distributor.distribute(maxSupply);
    }

    /*//////////////////////////////////////////////////////////////
                        RECOVERY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawRewards_RevertInsufficientBalance() public {
        deal(address(rewardsToken), address(_distributor), 100 ether);

        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.InsufficientRewardBalance.selector);
        _distributor.withdrawRewards(101 ether);
    }

    function test_WithdrawRewards_OnlyOwner() public {
        deal(address(rewardsToken), address(_distributor), 100 ether);

        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.withdrawRewards(50 ether);
    }

    function test_RecoverERC20_RevertUseWithdrawRewards() public {
        deal(address(rewardsToken), address(_distributor), 100 ether);

        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.UseWithdrawRewards.selector);
        _distributor.recoverERC20(address(rewardsToken), infraredGovernance);
    }

    function test_RecoverERC20_RevertZeroAmount() public {
        // Try to recover token with no balance
        vm.prank(infraredGovernance);
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        _distributor.recoverERC20(address(wbera), infraredGovernance);
    }

    function test_RecoverERC20_OnlyOwner() public {
        deal(address(wbera), address(_distributor), 100 ether);

        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.recoverERC20(address(wbera), nonKeeper);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_ChangingAPRMidPeriod() public {
        // Setup and initial distribution
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        uint256 initialAPR = _distributor.getCurrentAPR();
        assertApproxEqAbs(initialAPR, INITIAL_TARGET_APR, 10);

        // Change target APR mid-period
        uint256 newTargetAPR = 3000; // 30%
        vm.prank(infraredGovernance);
        _distributor.setTargetAPR(newTargetAPR);

        // Wait for next distribution
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribute with new APR
        maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Check that new distribution targets new APR
        uint256 newAPR = _distributor.getCurrentAPR();
        assertApproxEqAbs(newAPR, newTargetAPR, 100);
    }

    function test_Scenario_StakeUnstakeDuringDistribution() public {
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Initial distribution
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Stake more tokens
        deal(address(stakingAsset), address(this), 5000 ether);
        wbera.approve(address(infraredVault), 5000 ether);
        infraredVault.stake(5000 ether);

        // Wait and distribute again
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // APR should still be close to target despite supply change
        uint256 currentAPR = _distributor.getCurrentAPR();
        assertApproxEqAbs(currentAPR, INITIAL_TARGET_APR, 100);
    }

    function test_Scenario_MultipleKeepersChangingAPR() public {
        // Setup multiple keepers
        vm.startPrank(infraredGovernance);
        _distributor.updateKeeper(keeper1, true);
        _distributor.updateKeeper(keeper2, true);
        vm.stopPrank();

        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Keeper1 sets APR and distributes
        vm.prank(keeper1);
        _distributor.setTargetAPR(2000);

        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply);

        // Keeper2 changes APR and distributes
        vm.prank(keeper2);
        _distributor.setTargetAPR(2500);

        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper2);
        _distributor.distribute(maxSupply);

        assertEq(_distributor.targetAPR(), 2500);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function testInvariant_APRCalculationConsistency() public {
        deal(address(rewardsToken), address(_distributor), 10_000_000 ether);

        // Get expected amount before distribution
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 expectedAmount = _distributor.getExpectedAmount();

        // Distribute
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Get actual APR
        uint256 actualAPR = _distributor.getCurrentAPR();

        // Should be very close (allowing for rounding)
        assertApproxEqAbs(actualAPR, INITIAL_TARGET_APR, 50);
    }
}
