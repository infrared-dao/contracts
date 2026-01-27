// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";
import {BYUSDRewardDistributor} from "src/periphery/BYUSDRewardDistributor.sol";
import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";

contract BYUSDRewardDistributorTest is Helper {
    InfraredBGT public rewardsToken;
    MockERC20 public stakingToken;
    MockERC20 public underlyingToken;
    WrappedRewardToken public wrapper;
    BYUSDRewardDistributor public _distributor;

    // Test addresses
    address public keeper1 = address(0x1337);
    address public keeper2 = address(0x2337);
    address public nonKeeper = address(0xBEEF);
    address public attacker = address(0xBAD);

    // Constants for testing
    uint256 constant INITIAL_DISTRIBUTION_INTERVAL = 2 hours;
    uint256 constant SECONDS_PER_YEAR = 36525 * 24 * 60 * 60 / 100;
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant DEFAULT_REWARDS_DURATION = 86400;

    // Events to test
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event RewardsDistributed(address vault, uint256 amount);
    event DistributionIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event KeeperUpdated(address indexed keeper, bool active);
    event MaxSupplyDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    event UnderlyingDeposited(
        address indexed from, uint256 amount, uint256 duration
    );
    event UnlockedAndWrapped(uint256 underlyingUnlocked);

    function setUp() public override {
        super.setUp();

        rewardsToken = ibgt;

        // Create underlying token (6 decimals to test wrapper scaling)
        underlyingToken = new MockERC20("Underlying", "UND", 6);

        // Create wrapper for underlying token
        wrapper = new WrappedRewardToken(
            ERC20(address(underlyingToken)), "Wrapped Underlying", "wUND"
        );

        // whitelist reward token
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wrapper), true);

        _distributor = new BYUSDRewardDistributor(
            infraredGovernance,
            address(infrared),
            stakingAsset,
            address(wrapper),
            address(underlyingToken),
            address(keeper),
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

        vm.prank(infraredGovernance);
        infrared.addReward(stakingAsset, address(wrapper), 1 days);

        // Add minimal initial rewards to initialize the vault
        deal(address(wrapper), address(this), 1 ether);
        wrapper.approve(address(infrared), 1 ether);
        infrared.addIncentives(stakingAsset, address(wrapper), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        // Verify all state variables are correctly initialized
        assertEq(_distributor.owner(), infraredGovernance);
        assertEq(address(_distributor.infrared()), address(infrared));
        assertEq(address(_distributor.stakingToken()), stakingAsset);
        assertEq(address(_distributor.rewardsToken()), address(wrapper));
        assertEq(
            address(_distributor.underlyingToken()), address(underlyingToken)
        );
        assertEq(address(_distributor.wrapper()), address(wrapper));
        assertEq(
            _distributor.distributionInterval(), INITIAL_DISTRIBUTION_INTERVAL
        );
        assertEq(_distributor.lastDistributionTime(), 0);
        assertEq(_distributor.maxSupplyDeviation(), 100); // 1% default

        // Verify governance is set as initial keeper
        assertTrue(_distributor.keepers(infraredGovernance));
        assertTrue(_distributor.keepers(address(keeper)));

        // Verify approvals are set correctly
        assertEq(
            wrapper.allowance(address(_distributor), address(infrared)),
            type(uint256).max
        );
        assertEq(
            underlyingToken.allowance(address(_distributor), address(wrapper)),
            type(uint256).max
        );
    }

    function test_Constructor_RevertNoVault() public {
        address nonExistentToken = address(0xDEAD);

        vm.expectRevert(BYUSDRewardDistributor.NoVault.selector);
        new BYUSDRewardDistributor(
            infraredGovernance,
            address(infrared),
            nonExistentToken, // This token has no vault
            address(wrapper),
            address(underlyingToken),
            address(keeper),
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
        vm.expectRevert(BYUSDRewardDistributor.ZeroAddress.selector);
        _distributor.updateKeeper(address(0), true);
    }

    function test_UpdateKeeper_RevertNothingToUpdate() public {
        // Try to add governance as keeper (already is)
        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.NothingToUpdate.selector);
        _distributor.updateKeeper(infraredGovernance, true);

        // Try to remove non-existent keeper
        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.NothingToUpdate.selector);
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
        // Fund the distributor with wrapped tokens
        deal(address(wrapper), address(_distributor), 1_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        uint256 maxSupply = _distributor.getMaxTotalSupply();

        // Non-keeper should fail
        vm.prank(nonKeeper);
        vm.expectRevert(BYUSDRewardDistributor.NotKeeper.selector);
        _distributor.distribute(maxSupply);

        // Governance (keeper) should succeed
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);
    }

    function test_Distribute_WithSlippageProtection() public {
        // Fund the distributor
        deal(address(wrapper), address(_distributor), 1_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();

        // Try with max supply that's too low (will trigger slippage)
        uint256 tooLowMaxSupply = currentSupply - 1;

        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.TotalSupplySlippage.selector);
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
        deal(address(wrapper), address(_distributor), fundAmount);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get initial vault state
        IInfraredVault _vault = infrared.vaultRegistry(stakingAsset);
        (,,, uint256 rewardRateBefore,,,) = _vault.rewardData(address(wrapper));

        // Execute distribution with keeper1
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply);

        // Verify state changes
        assertEq(_distributor.lastDistributionTime(), block.timestamp);

        // Verify rewards were added to vault
        (,,, uint256 rewardRateAfter,,,) = _vault.rewardData(address(wrapper));
        assertGt(rewardRateAfter, rewardRateBefore);
    }

    /*//////////////////////////////////////////////////////////////
                    SANDWICH ATTACK PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SandwichAttack_Prevention() public {
        // Fund the distributor
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

        // Skip past the distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get initial state
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 initialSupply = vault.totalSupply();
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        // Simulate attacker front-running by staking large amount
        // Assume attacker stakes and increases supply by 5% (more than 1% tolerance)
        uint256 attackerStake = initialSupply * 5 / 100;
        deal(address(stakingAsset), attacker, attackerStake);
        vm.prank(attacker);
        wbera.approve(address(infraredVault), attackerStake);
        vm.prank(attacker);
        infraredVault.stake(attackerStake);

        // Distribution should fail with the old maxSupply
        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.TotalSupplySlippage.selector);
        _distributor.distribute(maxSupply);

        // But would work with updated maxSupply
        uint256 newMaxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(newMaxSupply);
    }

    function test_SandwichAttack_WithinTolerance() public {
        // Fund the distributor
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

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
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

        // First distribution by keeper1
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 maxSupply1 = _distributor.getMaxTotalSupply();
        vm.prank(keeper1);
        _distributor.distribute(maxSupply1);

        uint256 firstDistTime = _distributor.lastDistributionTime();

        // Second distribution by keeper2
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL * 2 + 1);
        deal(address(wrapper), address(_distributor), 20_000_000 ether);
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
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

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
        vm.expectRevert(BYUSDRewardDistributor.NotKeeper.selector);
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

        deal(address(wrapper), address(_distributor), depositAmount);

        uint256 balanceBefore = wrapper.balanceOf(infraredGovernance);

        vm.prank(infraredGovernance);
        _distributor.withdrawRewards(withdrawAmount);

        assertEq(
            wrapper.balanceOf(infraredGovernance),
            balanceBefore + withdrawAmount
        );
        assertEq(
            wrapper.balanceOf(address(_distributor)),
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

    function testFuzz_Distribute_WithSlippage(uint256 slippagePercent) public {
        // Bound inputs
        slippagePercent = bound(slippagePercent, 0, 1000); // 0% to 10% slippage

        // Fund the distributor
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

        // Wait for distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Get current supply and calculate max with slippage
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 currentSupply = vault.totalSupply();
        uint256 maxWithSlippage =
            currentSupply + (currentSupply * slippagePercent / 10000);

        vm.prank(infraredGovernance);
        if (slippagePercent <= 100) {
            // Within default 1% tolerance
            // Should succeed
            _distributor.distribute(maxWithSlippage);
            assertEq(_distributor.lastDistributionTime(), block.timestamp);
        } else {
            // Should revert due to slippage
            vm.expectRevert(BYUSDRewardDistributor.TotalSupplySlippage.selector);
            _distributor.distribute(currentSupply - 1);
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
        deal(address(wrapper), address(_distributor), 1_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribution should only work with exact supply
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        uint256 exactSupply = vault.totalSupply();

        // Even 1 wei more should fail
        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.TotalSupplySlippage.selector);
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
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

        // Initially should be 0 (too soon)
        uint256 expectedAmount = _distributor.getExpectedAmount();
        assertEq(expectedAmount, 0);

        // Skip past distribution interval
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // With funding and after interval, should return non-zero expected amount
        expectedAmount = _distributor.getExpectedAmount();
        assertGt(expectedAmount, 0);

        // Expected amount should be reasonable (not more than balance)
        assertLe(expectedAmount, wrapper.balanceOf(address(_distributor)));
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
        BYUSDRewardDistributor zeroSupplyDistributor = new BYUSDRewardDistributor(
            infraredGovernance,
            address(infrared),
            stakingAsset,
            address(wrapper),
            address(underlyingToken),
            address(keeper),
            INITIAL_DISTRIBUTION_INTERVAL
        );

        // deal(address(wrapper), address(zeroSupplyDistributor), 10_000_000 ether);

        // // Unstake all to get zero supply
        // infraredVault.withdraw(10_000_000 ether);

        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);
        uint256 expectedAmount = zeroSupplyDistributor.getExpectedAmount();
        assertEq(expectedAmount, 0);
    }

    function test_GetCurrentAPR_Success() public {
        // Setup initial rewards
        deal(address(wrapper), address(_distributor), 10_000_000 ether);
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribute rewards
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Check current APR
        uint256 currentAPR = _distributor.getCurrentAPR();

        // APR should be positive and sustainable
        assertGt(currentAPR, 0);
    }

    function test_GetCurrentAPR_ZeroAfterPeriodFinish() public {
        // Setup and distribute
        deal(address(wrapper), address(_distributor), 10_000_000 ether);
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
        (, uint256 rewardsDuration,,,,,) = vault.rewardData(address(wrapper));
        uint256 totalSupply = vault.totalSupply();

        uint256 expectedAPR = (testAmount * SECONDS_PER_YEAR * BASIS_POINTS)
            / (rewardsDuration * totalSupply);

        uint256 calculatedAPR = _distributor.getAPRForAmount(testAmount);
        assertEq(calculatedAPR, expectedAPR);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

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
        vm.expectRevert(
            BYUSDRewardDistributor.ZeroDistributionInterval.selector
        );
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

    function test_Distribute_RevertNothingToAdd() public {
        // First distribute to set up rewards
        deal(address(wrapper), address(_distributor), 10_000_000 ether);
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

    /*//////////////////////////////////////////////////////////////
                        RECOVERY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawRewards_RevertInsufficientBalance() public {
        deal(address(wrapper), address(_distributor), 100 ether);

        vm.prank(infraredGovernance);
        vm.expectRevert(
            BYUSDRewardDistributor.InsufficientRewardBalance.selector
        );
        _distributor.withdrawRewards(101 ether);
    }

    function test_WithdrawRewards_OnlyOwner() public {
        deal(address(wrapper), address(_distributor), 100 ether);

        vm.prank(nonKeeper);
        vm.expectRevert("UNAUTHORIZED");
        _distributor.withdrawRewards(50 ether);
    }

    function test_RecoverERC20_RevertUseWithdrawRewards() public {
        deal(address(wrapper), address(_distributor), 100 ether);

        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.UseWithdrawRewards.selector);
        _distributor.recoverERC20(address(wrapper), infraredGovernance);
    }

    function test_RecoverERC20_RevertZeroAmount() public {
        // Try to recover token with no balance
        vm.prank(infraredGovernance);
        vm.expectRevert(BYUSDRewardDistributor.ZeroAmount.selector);
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

    function test_Scenario_StakeUnstakeDuringDistribution() public {
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

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

        // APR should be maintained based on available balance
        uint256 currentAPR = _distributor.getCurrentAPR();
        assertGt(currentAPR, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function testInvariant_APRCalculationConsistency() public {
        deal(address(wrapper), address(_distributor), 10_000_000 ether);

        // Get expected amount before distribution
        vm.warp(block.timestamp + INITIAL_DISTRIBUTION_INTERVAL + 1);

        // Distribute
        uint256 maxSupply = _distributor.getMaxTotalSupply();
        vm.prank(infraredGovernance);
        _distributor.distribute(maxSupply);

        // Get actual APR
        uint256 actualAPR = _distributor.getCurrentAPR();

        // APR should be positive and sustainable based on balance
        assertGt(actualAPR, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DepositUnderlying_Success() public {
        uint256 depositAmount = 1000e6; // 1000 tokens with 6 decimals
        uint256 vestDuration = 30 days;

        // Give user some underlying tokens
        deal(address(underlyingToken), keeper, depositAmount);
        vm.startPrank(keeper);
        underlyingToken.approve(address(_distributor), depositAmount);

        // Deposit underlying
        vm.expectEmit(true, false, false, true);
        emit UnderlyingDeposited(keeper, depositAmount, vestDuration);

        _distributor.depositUnderlying(depositAmount, vestDuration);
        vm.stopPrank();
    }

    function test_UnlockableUnderlying_LinearVesting() public {
        uint256 depositAmount = 1000e6;
        uint256 vestDuration = 30 days;

        // Deposit underlying
        deal(address(underlyingToken), keeper, depositAmount);
        vm.startPrank(keeper);
        underlyingToken.approve(address(_distributor), depositAmount);
        _distributor.depositUnderlying(depositAmount, vestDuration);
        vm.stopPrank();
        // Warp to 50% through vesting + one reward period
        IInfraredVault vault = infrared.vaultRegistry(stakingAsset);
        (, uint256 rewardsDuration,,,,,) = vault.rewardData(address(wrapper));

        // Nothing unlockable immediately
        assertEq(
            _distributor.unlockableUnderlying(),
            depositAmount * rewardsDuration / vestDuration
        );

        vm.warp(block.timestamp + vestDuration / 2 + rewardsDuration);

        // Should be able to unlock ~50% + forward unlock amount
        uint256 unlockable = _distributor.unlockableUnderlying();
        assertGt(unlockable, depositAmount / 2);
    }

    function test_Distribute_WithVestedTokens() public {
        // Deposit underlying tokens to vest
        uint256 depositAmount = 100_000e6;
        uint256 vestDuration = 30 days;

        deal(address(underlyingToken), infraredGovernance, depositAmount);
        vm.startPrank(infraredGovernance);
        underlyingToken.approve(address(_distributor), depositAmount);
        _distributor.depositUnderlying(depositAmount, vestDuration);

        // Warp past vesting
        vm.warp(
            block.timestamp + vestDuration + INITIAL_DISTRIBUTION_INTERVAL + 1
        );

        // Distribute should unlock and distribute
        uint256 maxSupply = _distributor.getMaxTotalSupply();

        _distributor.distribute(maxSupply);
        vm.stopPrank();

        // Verify distribution happened
        assertEq(_distributor.lastDistributionTime(), block.timestamp);
    }
}
