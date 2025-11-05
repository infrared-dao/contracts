// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Helper.sol";
import "@forge-std/console2.sol";
import "src/depreciated/core/Infrared.sol";
import "src/core/libraries/ConfigTypes.sol";
import "src/depreciated/interfaces/IInfrared.sol";
import "src/depreciated/interfaces/IInfraredV1_5.sol";
import "src/interfaces/IMultiRewards.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "@berachain/pol/interfaces/IRewardVault.sol";
import {InfraredV1_7} from "src/depreciated/core/InfraredV1_7.sol";

contract InfraredRewardsTest is Helper {
    /*//////////////////////////////////////////////////////////////
                Vault Rewards test
    //////////////////////////////////////////////////////////////*/

    function testharvestVaultSuccess() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(ibgt);
        rewardTokens[1] = address(ir);

        // InfraredVault vault = InfraredVault(
        //     address(infrared.registerVault(address(wbera), rewardTokens))
        // );
        InfraredVault vault = infraredVault;

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        vm.stopPrank();

        address user = address(10);
        vm.deal(address(user), 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();

        address vaultWbera = factory.getVault(address(wbera));

        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        uint256 vaultBalanceBefore = ibgt.balanceOf(address(vault));

        vm.startPrank(address(vault));
        vault.rewardsVault().setOperator(address(infrared));
        vm.startPrank(keeper);
        vm.expectEmit();
        emit IInfrared.VaultHarvested(
            keeper, address(wbera), address(vault), 99999999999999999000
        );
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        uint256 vaultBalanceAfter = ibgt.balanceOf(address(vault));
        assertTrue(
            vaultBalanceAfter > vaultBalanceBefore,
            "Vault should have more InfraredBGT after harvest"
        );
    }

    function testClaimExternalVaultRewardsSuccess() public {
        address vaultWbera = factory.getVault(address(wbera));
        IBerachainRewardsVault vault = IBerachainRewardsVault(vaultWbera);
        address user = address(10);
        address user2 = address(12);
        vm.deal(address(user), 1000 ether);
        vm.deal(address(user2), 1000 ether);
        uint256 stakeAmount = 1000 ether;

        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 200 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 200 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 200 ether
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        uint256 uservaultBalanceBefore = ibgt.balanceOf(address(user));

        vm.startPrank(user);
        vault.setOperator(address(infrared));
        vm.stopPrank();

        vm.startPrank(user2);
        vault.setOperator(address(infrared));
        vm.stopPrank();

        uint256 expectedAmount = IInfraredV1_5(address(infrared))
            .externalVaultRewards(address(wbera), user);

        // test unauthorized
        vm.startPrank(address(0));
        vm.expectRevert();
        IInfraredV1_5(address(infrared)).claimExternalVaultRewards(
            address(wbera), user
        );
        vm.stopPrank();

        // test keeper can call
        vm.startPrank(keeper);
        vm.expectEmit();
        emit IInfraredV1_5.ExternalVaultClaimed(
            user, address(wbera), address(vault), 99999999999999999000
        );
        IInfraredV1_5(address(infrared)).claimExternalVaultRewards(
            address(wbera), user
        );
        vm.stopPrank();

        // test user can call
        vm.startPrank(user2);
        vm.expectEmit();
        emit IInfraredV1_5.ExternalVaultClaimed(
            user2, address(wbera), address(vault), 99999999999999999000
        );
        IInfraredV1_5(address(infrared)).claimExternalVaultRewards(
            address(wbera), user2
        );
        vm.stopPrank();

        uint256 userBalanceAfter = ibgt.balanceOf(address(user));
        assertTrue(
            userBalanceAfter > uservaultBalanceBefore,
            "Vault should have more InfraredBGT after harvest"
        );
        assertEq(userBalanceAfter - uservaultBalanceBefore, expectedAmount);
    }

    function testharvestVaultNotWhitelistedToken() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        vm.expectRevert(abi.encodeWithSignature("VaultNotSupported()"));
        infrared.harvestVault(address(mockAsset));
    }

    function testrecoverERC20Success() public {
        uint256 recoverAmount = 10 ether;
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        mockAsset.mint(address(infrared), recoverAmount);

        address user = address(10);
        uint256 userBalanceBefore = mockAsset.balanceOf(user);

        vm.startPrank(address(infraredGovernance));
        vm.expectEmit();
        emit IInfrared.Recovered(
            infraredGovernance, address(mockAsset), recoverAmount
        );
        infrared.recoverERC20(user, address(mockAsset), recoverAmount);
        vm.stopPrank();

        uint256 userBalanceAfter = mockAsset.balanceOf(user);
        assertTrue(
            userBalanceAfter == userBalanceBefore + recoverAmount,
            "User should have more mockAsset after recovery"
        );
    }

    function testrecoverERC20ZeroAddressRecipient() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);

        vm.startPrank(address(infraredGovernance));
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        infrared.recoverERC20(address(0), address(mockAsset), 10 ether);
        vm.stopPrank();
    }

    function testrecoverERC20ZeroAddressToken() public {
        address user = address(10);

        vm.startPrank(address(infraredGovernance));
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        infrared.recoverERC20(user, address(0), 10 ether);
        vm.stopPrank();
    }

    function testrecoverERC20ZeroAmount() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        address user = address(10);

        vm.startPrank(address(infraredGovernance));
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        infrared.recoverERC20(user, address(mockAsset), 0);
        vm.stopPrank();
    }

    function testrecoverERC20NotGovernor() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        address user = address(10);

        vm.startPrank(address(user));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                user,
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.recoverERC20(user, address(mockAsset), 10 ether);
        vm.stopPrank();
    }

    function testHarvestVaultRedRevert() public {
        deployIR();
        uint256 rewardsDuration = 7 days;
        vm.startPrank(address(infrared));
        for (uint160 i = 0; i < 9; i++) {
            infraredVault.addReward(
                address(new MockERC20("MockAsset", "MCK", 18)), rewardsDuration
            );
        }

        // Setup: Configure RED token and mint rate
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);

        infrared.updateIRMintRate(1_500_000); // 1.5x RED per InfraredBGT
        vm.stopPrank();

        // Setup vault and user stake
        address user = address(10);
        vm.deal(user, 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(wbera));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10 days);

        // Perform harvest
        vm.startPrank(address(infraredVault));
        infraredVault.rewardsVault().setOperator(address(infrared));
        vm.startPrank(keeper);

        /// Should not Revert, IR Should always be allowed as a reward
        ///vm.expectRevert(abi.encodeWithSignature("MaxNumberOfRewards()"));

        infrared.harvestVault(address(wbera));
        vm.stopPrank();
    }

    function testRecoverERC20WithProtocolFees() public {
        // First run harvestVault to accumulate protocol fees
        testHarvestVaultWithProtocolFees();

        // Mint extra "unaccounted" tokens to the contract
        // Make sure we mint enough to have some available after protocol fees
        uint256 extraTokens = 100 ether; // Increased amount
        vm.startPrank(address(infrared));
        ibgt.mint(address(infrared), extraTokens);
        vm.stopPrank();

        // Calculate available balance (total - protocol fees)
        uint256 totalBalance = ibgt.balanceOf(address(infrared));
        uint256 protocolFees = infrared.protocolFeeAmounts(address(ibgt));
        uint256 availableBalance = totalBalance - protocolFees;

        // Verify we have unaccounted tokens
        assertTrue(
            availableBalance > 0, "Should have unaccounted tokens available"
        );

        // Test 1: Attempt to recover more than available balance (should fail)
        vm.startPrank(infraredGovernance);
        vm.expectRevert(
            abi.encodeWithSignature("TokensReservedForProtocolFees()")
        );
        infrared.recoverERC20(address(123), address(ibgt), availableBalance + 1);
        vm.stopPrank();

        // Test 2: Attempt to recover exactly available balance (should succeed)
        vm.startPrank(infraredGovernance);
        infrared.recoverERC20(address(456), address(ibgt), availableBalance);
        vm.stopPrank();

        // Verify balances after successful recovery
        assertEq(
            ibgt.balanceOf(address(456)),
            availableBalance,
            "Recipient should have received available balance"
        );
        assertEq(
            ibgt.balanceOf(address(infrared)),
            protocolFees,
            "Infrared should retain only protocol fees"
        );

        // Test 3: Attempt to recover remaining amount (should fail)
        vm.startPrank(infraredGovernance);
        vm.expectRevert(
            abi.encodeWithSignature("TokensReservedForProtocolFees()")
        );
        infrared.recoverERC20(address(789), address(ibgt), 1);
        vm.stopPrank();
    }

    function testRecoverERC20WithZeroProtocolFees() public {
        // Mint tokens directly to the contract without harvesting
        uint256 amount = 100 ether;
        vm.startPrank(address(infrared));
        ibgt.mint(address(infrared), amount);
        vm.stopPrank();

        // Verify initial state
        uint256 totalBalance = ibgt.balanceOf(address(infrared));
        uint256 protocolFees = infrared.protocolFeeAmounts(address(ibgt));

        // Log values for debugging
        console.log("Total Balance:", totalBalance);
        console.log("Protocol Fees:", protocolFees);
        console.log("Available Balance:", totalBalance - protocolFees);

        // Should be able to recover full amount since no protocol fees
        assertTrue(protocolFees == 0, "Should have no protocol fees");

        // Test 1: Recover full amount (should succeed)
        vm.startPrank(infraredGovernance);
        infrared.recoverERC20(address(456), address(ibgt), amount);
        vm.stopPrank();

        // Verify balances after recovery
        assertEq(
            ibgt.balanceOf(address(456)),
            amount,
            "Recipient should have received full amount"
        );
        assertEq(
            ibgt.balanceOf(address(infrared)),
            0,
            "Infrared should have zero balance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                Incentives test
    //////////////////////////////////////////////////////////////*/

    event RewardStored(address indexed rewardsToken, uint256 rewardsDuration);
    event RewardAdded(address indexed rewardsToken, uint256 reward);

    function testAddRewardSuccess() public {
        // Setup new reward token
        MockERC20 newRewardToken = new MockERC20("NewReward", "NRT", 18);
        uint256 rewardsDuration = 7 days;

        vm.startPrank(infraredGovernance);
        // Whitelist the new reward token first
        infrared.updateWhiteListedRewardTokens(address(newRewardToken), true);

        // The event is emitted from the vault contract
        vm.expectEmit();
        emit IMultiRewards.RewardStored(
            address(newRewardToken), rewardsDuration
        );
        infrared.addReward(
            address(wbera), address(newRewardToken), rewardsDuration
        );
        vm.stopPrank();

        // Verify reward was added by checking reward duration
        (, uint256 duration,,,,,) =
            infraredVault.rewardData(address(newRewardToken));
        assertEq(duration, rewardsDuration, "Reward duration should match");
    }

    function testAddRewardFailsWithNonWhitelistedReward() public {
        vm.expectRevert(abi.encodeWithSignature("RewardTokenNotWhitelisted()"));
        vm.prank(infraredGovernance);
        infrared.addReward(address(wbera), address(ir), 7 days);
    }

    function testAddRewardFailsWithZeroDuration() public {
        deployIR();
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(ir), true);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        infrared.addReward(address(wbera), address(ir), 0);
        vm.stopPrank();
    }

    function testAddRewardFailsWithNoVault() public {
        deployIR();
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(ir), true);
        vm.expectRevert(abi.encodeWithSignature("NoRewardsVault()"));
        infrared.addReward(address(1), address(ir), 7 days);
        vm.stopPrank();
    }

    function deployIR() internal {
        ir = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        // gov only (i.e. this needs to be run by gov)
        vm.startPrank(infraredGovernance);
        infrared.setIR(address(ir));

        vm.stopPrank();
    }

    function testAddRewardFailsWithNotAuthorized() public {
        vm.startPrank(address(1));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(1),
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.addReward(address(wbera), address(ir), 7 days);
    }

    function testAddIncentivesSuccess() public {
        uint256 rewardAmount = 100 ether;
        uint256 rewardsDuration = 7 days;
        MockERC20 newRewardToken = new MockERC20("NewReward", "NRT", 18);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(newRewardToken), true);
        infrared.addReward(
            address(wbera), address(newRewardToken), rewardsDuration
        );
        vm.stopPrank();

        // Deal tokens to admin (test contract)
        deal(address(newRewardToken), address(this), rewardAmount);

        // Approve the Infrared contract to spend tokens
        newRewardToken.approve(address(infrared), rewardAmount);

        uint256 residual = rewardAmount % rewardsDuration;

        // Expect the event from the vault
        vm.expectEmit(true, true, true, true, address(infraredVault));
        emit RewardAdded(address(newRewardToken), rewardAmount - residual);

        // Call addIncentives
        infrared.addIncentives(
            address(wbera), address(newRewardToken), rewardAmount
        );

        // Verify rewards were added
        (,,, uint256 rewardRate,,,) =
            infraredVault.rewardData(address(newRewardToken));
        assertTrue(rewardRate > 0, "Reward rate should be set");
    }

    function testAddIncentivesFailsWithZeroAmount() public {
        MockERC20 newRewardToken = new MockERC20("NewReward", "NRT", 18);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(newRewardToken), true);
        infrared.addReward(address(wbera), address(newRewardToken), 7 days);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        infrared.addIncentives(address(wbera), address(newRewardToken), 0);
    }

    function testAddIncentivesFailsWithInvalidVault() public {
        vm.expectRevert(abi.encodeWithSignature("NoRewardsVault()"));
        infrared.addIncentives(address(1), address(ibgt), 100 ether);
    }

    function testAddIncentivesFailsWithNonWhitelistedReward() public {
        MockERC20 newRewardToken = new MockERC20("NewReward", "NRT", 18);

        vm.expectRevert(abi.encodeWithSignature("RewardTokenNotWhitelisted()"));
        infrared.addIncentives(
            address(wbera), address(newRewardToken), 100 ether
        );
    }

    function testHarvestVault() public {
        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(stakingAsset));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Setup: Register vault and stake
        address user = address(123);
        stakeInVault(address(infraredVault), stakingAsset, user, 100 ether);

        // Advance time to accrue rewards
        vm.warp(20 days);

        // Store initial balance
        uint256 vaultBalanceBefore = ibgt.balanceOf(address(infraredVault));

        // Expect the VaultHarvested event
        vm.expectEmit();
        emit IInfrared.VaultHarvested(
            address(this),
            stakingAsset,
            address(infraredVault),
            99999999999999999900 // small rounding error
        );

        // Perform harvest
        infrared.harvestVault(stakingAsset);

        // Verify balance after harvest
        uint256 vaultBalanceAfter = ibgt.balanceOf(address(infraredVault));
        assertApproxEqAbs(
            vaultBalanceAfter,
            vaultBalanceBefore + 100 ether,
            100,
            "Incorrect InfraredBGT amount after harvest"
        );

        // Assert that BGT balance and InfraredBGT balance are equal
        assertEq(
            ibgt.totalSupply(),
            bgt.balanceOf(address(infrared)),
            "BGT and InfraredBGT total supply mismatch"
        );
    }

    function testHarvestVaultWithProtocolFees() public {
        // Setup: Register vault, stake, and configure fees
        address user = address(123);
        stakeInVault(address(infraredVault), stakingAsset, user, 100 ether);

        vm.startPrank(keeper);
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultFeeRate, 3e5); // 30% total fee
        infrared.updateFee(ConfigTypes.FeeType.HarvestVaultProtocolRate, 1e6); // 100% of fee to protocol
        vm.stopPrank();

        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(stakingAsset));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10 days);

        // Store initial balances
        uint256 vaultBalanceBefore = ibgt.balanceOf(address(infraredVault));
        uint256 protocolFeeAmountBefore =
            infrared.protocolFeeAmounts(address(ibgt));

        // Calculate expected amounts
        uint256 totalReward = 100 ether; // This should match the actual reward amount
        uint256 protocolFees = (totalReward * 3e5) / 1e6;
        uint256 netBgtAmt = totalReward - protocolFees; // Net BGT amount after fees

        // Expect events with calculated values
        vm.expectEmit();
        emit IInfrared.VaultHarvested(
            keeper, stakingAsset, address(infraredVault), 99999999999999999900
        );

        // Perform harvest
        vm.startPrank(keeper);
        infrared.harvestVault(stakingAsset);
        vm.stopPrank();

        // Verify balances after harvest with a tolerance for rounding errors
        uint256 vaultBalanceAfter = ibgt.balanceOf(address(infraredVault));
        assertApproxEqRel(
            vaultBalanceAfter,
            vaultBalanceBefore + netBgtAmt,
            100,
            "Incorrect InfraredBGT amount to vault"
        ); // allow small rounding error

        // Verify protocol fee amounts with a slightly larger tolerance
        uint256 protocolFeeAmountAfter =
            infrared.protocolFeeAmounts(address(ibgt));
        assertApproxEqAbs(
            protocolFeeAmountAfter,
            protocolFeeAmountBefore + protocolFees,
            100, // Allow a slightly larger absolute difference
            "Incorrect protocol fee amount for InfraredBGT"
        );

        // Additional verification: Check that the total supply of InfraredBGT matches the expected total
        assertEq(
            ibgt.totalSupply(),
            bgt.balanceOf(address(infrared)),
            "BGT and InfraredBGT total supply mismatch"
        );
    }

    function testRevertHarvestVaultInvalidPool() public {
        // factory.increaseRewardsForVault(stakingAsset, 100 ether);
        address user = address(123);
        stakeInVault(address(infraredVault), stakingAsset, user, 100 ether);

        vm.warp(10 days);
        vm.expectRevert(Errors.VaultNotSupported.selector);
        infrared.harvestVault(address(123));
    }

    function testHarvestVaultWithRedMinting() public {
        deployIR();
        // Setup: Configure RED token and mint rate
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);

        infrared.updateIRMintRate(1_500_000); // 1.5x RED per InfraredBGT
        vm.stopPrank();

        // Setup vault and user stake
        address user = address(10);
        vm.deal(user, 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(wbera));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10 days);

        // Store balances before harvest
        uint256 vaultIbgtBefore = ibgt.balanceOf(address(infraredVault));
        uint256 vaultRedBefore = ir.balanceOf(address(infraredVault));

        // Perform harvest
        vm.startPrank(address(infraredVault));
        infraredVault.rewardsVault().setOperator(address(infrared));
        vm.startPrank(keeper);
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        // Calculate expected amounts
        uint256 harvestedAmount = 99999999999999999000; // From the emitted event
        uint256 netIbgtAmount = harvestedAmount; // No fees applied
        uint256 expectedRedAmount = (netIbgtAmount * 1_500_000) / 1e6; // 1.5x IR per net InfraredBGT

        // Verify balances after harvest
        uint256 vaultIbgtAfter = ibgt.balanceOf(address(infraredVault));
        uint256 vaultRedAfter = ir.balanceOf(address(infraredVault));

        // Assert InfraredBGT increase matches expected amount
        assertEq(
            vaultIbgtAfter - vaultIbgtBefore,
            netIbgtAmount,
            "Incorrect InfraredBGT amount"
        );

        // Assert RED minting matches expected ratio
        assertEq(
            vaultRedAfter - vaultRedBefore,
            expectedRedAmount,
            "Incorrect RED minting amount"
        );

        // Verify RED:InfraredBGT ratio is maintained
        assertApproxEqRel(
            (vaultRedAfter - vaultRedBefore) * 1e6,
            (vaultIbgtAfter - vaultIbgtBefore) * 1_500_000,
            1e16, // 1% tolerance
            "RED:InfraredBGT ratio mismatch"
        );
    }

    function testHarvestVaultWithDoesNotFailWithPausedRedMinting() public {
        deployIR();
        // Setup: Configure RED token and mint rate
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);

        infrared.updateIRMintRate(1_500_000); // 1.5x RED per InfraredBGT
        ir.pause();
        vm.stopPrank();

        // Setup vault and user stake
        address user = address(10);
        vm.deal(user, 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(wbera));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10 days);

        // Store balances before harvest
        uint256 vaultIbgtBefore = ibgt.balanceOf(address(infraredVault));
        uint256 vaultRedBefore = ir.balanceOf(address(infraredVault));

        // Perform harvest
        vm.startPrank(address(infraredVault));
        infraredVault.rewardsVault().setOperator(address(infrared));
        vm.startPrank(keeper);
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        // Calculate expected amounts
        uint256 harvestedAmount = 99999999999999999000; // From the emitted event
        uint256 netIbgtAmount = harvestedAmount; // No fees applied
        uint256 expectedRedAmount = 0; // paused

        // Verify balances after harvest
        uint256 vaultIbgtAfter = ibgt.balanceOf(address(infraredVault));
        uint256 vaultRedAfter = ir.balanceOf(address(infraredVault));

        // Assert InfraredBGT increase matches expected amount
        assertEq(
            vaultIbgtAfter - vaultIbgtBefore,
            netIbgtAmount,
            "Incorrect InfraredBGT amount"
        );

        // Assert RED minting matches expected ratio
        assertEq(
            vaultRedAfter - vaultRedBefore,
            expectedRedAmount,
            "Incorrect RED minting amount"
        );
    }

    function testClaimLostRewardsOnVault() public {
        // Setup: Register vault and distribute rewards
        address stakingToken = address(wbera);
        address user = address(123);
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 50 ether;

        // Stake some tokens to simulate initial user participation
        stakeInVault(address(infraredVault), stakingToken, user, stakeAmount);

        // Distribute rewards to the vault
        address vaultWbera = factory.getVault(stakingToken);
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), rewardAmount);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), rewardAmount);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), rewardAmount
        );
        vm.stopPrank();

        // Advance time to ensure rewards are claimable
        vm.warp(block.timestamp + 10 days);

        infrared.harvestVault(stakingToken);

        // Unstake all tokens to simulate no users staked
        vm.startPrank(user);
        infraredVault.withdraw(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 20 days);

        // check if user has any rewards
        uint256 rewards = infraredVault.earned(user, address(ibgt));
        assertEq(rewards, 0, "User should have no rewards");

        // verify that infrared has a balance of 1 wei in the vault
        assertEq(
            infraredVault.balanceOf(address(infrared)),
            1,
            "Infrared should have a balance of 1 wei in the vault"
        );
        // verify that the total supply is 1 wei more than the balance of infrared
        assertEq(
            infraredVault.totalSupply(),
            1,
            "Total supply should be 1 wei more than the balance of infrared"
        );

        // Store initial balance of Infrared contract
        uint256 initialInfraredBalance = ibgt.balanceOf(address(infrared));

        // check how much infrared has earned
        uint256 earned = infraredVault.earned(address(infrared), address(ibgt));
        assertEq(earned > 0, true, "Infrared should have earned rewards");

        // Claim lost rewards
        vm.startPrank(infraredGovernance);
        infrared.claimLostRewardsOnVault(stakingToken);
        vm.stopPrank();

        // Verify that the Infrared contract's balance increased by the reward amount
        uint256 finalInfraredBalance = ibgt.balanceOf(address(infrared));
        assertApproxEqRel(
            finalInfraredBalance,
            initialInfraredBalance + rewardAmount,
            1e6,
            "Infrared should have claimed the lost rewards"
        );
    }

    function testHarvestVaultWithPausedIRToken() public {
        deployIR();

        // Setup: Configure IR token and mint rate
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        infrared.updateIRMintRate(1_500_000); // 1.5x IR per InfraredBGT

        // Pause IR token
        ir.pause();
        vm.stopPrank();

        // Setup vault and user stake
        address user = address(10);
        vm.deal(user, 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(wbera));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 10 days);

        uint256 vaultIRBefore = ir.balanceOf(address(infraredVault));

        // Perform harvest
        vm.startPrank(keeper);
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        uint256 vaultIRAfter = ir.balanceOf(address(infraredVault));

        // Verify no IR tokens were minted while paused
        assertEq(
            vaultIRAfter,
            vaultIRBefore,
            "No IR tokens should be minted while paused"
        );
    }

    function testPauseAndUnpauseHarvestFunctions() public {
        // Setup initial state
        vm.startPrank(infraredGovernance);
        infrared.grantRole(infrared.PAUSER_ROLE(), address(123)); // Grant PAUSER_ROLE to a third party
        vm.stopPrank();

        // Test 1: Any harvest function should work before pausing
        infrared.harvestBase();
        infrared.harvestVault(address(wbera));
        infrared.harvestBoostRewards();
        infrared.harvestOperatorRewards();

        // Test 2: PAUSER_ROLE can pause
        vm.startPrank(address(123));
        infrared.pause();
        vm.stopPrank();

        // Test 3: All harvest functions should revert when paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        infrared.harvestBase();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        infrared.harvestVault(address(wbera));

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        infrared.harvestBoostRewards();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        infrared.harvestOperatorRewards();

        // Test 4: Only governor can unpause
        vm.startPrank(address(123));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(123),
                infrared.GOVERNANCE_ROLE()
            )
        );
        infrared.unpause();
        vm.stopPrank();

        // Test 5: Governor can unpause
        vm.startPrank(infraredGovernance);
        infrared.unpause();
        vm.stopPrank();

        // Test 6: Functions work again after unpause
        infrared.harvestBase();
        infrared.harvestVault(address(wbera));
        infrared.harvestBoostRewards();
        infrared.harvestOperatorRewards();
    }

    function testOnlyGovernorAndPauserCanPause() public {
        // Test 1: Random address cannot pause
        vm.startPrank(address(456));
        vm.expectRevert(abi.encodeWithSignature("NotPauser()"));
        infrared.pause();
        vm.stopPrank();

        // Test 2: Governor can pause without PAUSER_ROLE
        vm.startPrank(infraredGovernance);
        infrared.pause();
        infrared.unpause();
        vm.stopPrank();

        // Test 3: Address with PAUSER_ROLE can pause
        vm.startPrank(infraredGovernance);
        infrared.grantRole(infrared.PAUSER_ROLE(), address(789));
        vm.stopPrank();

        vm.startPrank(address(789));
        infrared.pause();
        vm.stopPrank();

        // Cleanup: unpause for other tests
        vm.startPrank(infraredGovernance);
        infrared.unpause();
        vm.stopPrank();
    }

    function testPauserRoleManagement() public {
        // Test 1: Only governor can grant PAUSER_ROLE
        bytes32 pauserRole = infrared.PAUSER_ROLE();

        vm.startPrank(address(123));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(123),
                infrared.DEFAULT_ADMIN_ROLE()
            )
        );
        infrared.grantRole(pauserRole, address(456));
        vm.stopPrank();

        // Test 2: Governor can grant and revoke PAUSER_ROLE
        vm.startPrank(infraredGovernance);
        infrared.grantRole(pauserRole, address(456));
        assertTrue(infrared.hasRole(pauserRole, address(456)));

        infrared.revokeRole(pauserRole, address(456));
        assertFalse(infrared.hasRole(pauserRole, address(456)));
        vm.stopPrank();

        // Test 3: Revoked pauser cannot pause
        vm.startPrank(address(456));
        vm.expectRevert(abi.encodeWithSignature("NotPauser()"));
        infrared.pause();
        vm.stopPrank();
    }

    function testRewardsContinueAfterPause() public {
        // Setup rewards in BerachainRewardsVault
        address vaultWbera = factory.getVault(address(stakingAsset));
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        address user = address(123);
        stakeInVault(address(infraredVault), stakingAsset, user, 100 ether);

        // Advance time to accrue rewards
        vm.warp(2 days);

        // Perform harvest
        infrared.harvestVault(stakingAsset);

        // Record initial earned amount
        uint256 initialEarned = infraredVault.earned(user, address(ibgt));

        // Pause the contract
        address hypernative = address(101);
        bytes32 pauser = infrared.PAUSER_ROLE();

        vm.prank(infraredGovernance);
        infrared.grantRole(pauser, hypernative);

        vm.prank(hypernative);
        infrared.pause();

        // Skip forward time within reward period
        vm.warp(block.timestamp + 2 days);

        // Check rewards still accrued during pause
        uint256 earnedDuringPause = infraredVault.earned(user, address(ibgt));
        assertTrue(
            earnedDuringPause > initialEarned,
            "Rewards should accrue during pause"
        );

        // Unpause and harvest
        vm.prank(infraredGovernance);
        infrared.unpause();

        infrared.harvestVault(stakingAsset);

        // Skip more time and verify rewards continue to accrue
        vm.warp(block.timestamp + 2 days);
        uint256 earnedAfterUnpause = infraredVault.earned(user, address(ibgt));
        assertTrue(
            earnedAfterUnpause > earnedDuringPause,
            "Rewards should continue accruing after unpause"
        );
    }

    function testRedeemIbgtForBera() public {
        assertTrue(ibgt.hasRole(ibgt.BURNER_ROLE(), address(infrared)));
        uint256 amount = 10000 ether;
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(infrared), amount);
        vm.stopPrank();
        vm.startPrank(address(infrared));
        ibgt.mint(keeper, amount);
        vm.stopPrank();
        uint256 prevIbgtSupply = ibgt.totalSupply();
        uint256 prevbgtSupply = bgt.balanceOf(address(infrared));
        uint256 prevBeraBal = keeper.balance;

        // expect revert if not keeper
        vm.expectRevert();
        InfraredV1_7(payable(address(infrared))).redeemIbgtForBera(amount);

        vm.startPrank(keeper);
        // expect revert if ibgt not approved
        vm.expectRevert();
        InfraredV1_7(payable(address(infrared))).redeemIbgtForBera(amount);

        // approve
        ibgt.approve(address(infrared), amount);

        // expect revert if zero amount
        vm.expectRevert();
        InfraredV1_7(payable(address(infrared))).redeemIbgtForBera(0);

        // expect success
        InfraredV1_7(payable(address(infrared))).redeemIbgtForBera(amount);
        vm.stopPrank();

        assertEq(ibgt.totalSupply(), prevIbgtSupply - amount);
        assertEq(bgt.balanceOf(address(infrared)), prevbgtSupply - amount);
        assertEq(keeper.balance, prevBeraBal + amount);
    }

    receive() external payable {}
}
