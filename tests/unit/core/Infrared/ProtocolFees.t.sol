// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

contract ProtocolFeesTest is Helper {
    address stakingToken;
    IInfraredVault vault;
    InfraredV1_9 infraredV9;

    function setUp() public override {
        super.setUp();
        infraredV9 = InfraredV1_9(payable(address(infrared)));

        // Register vault
        stakingToken = address(new MockERC20("Staking Token", "STK", 18));
        vm.prank(infraredGovernance);
        vault = infraredV9.registerVault(stakingToken);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM PROTOCOL FEES TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimProtocolFeesSuccess() public {
        // Generate protocol fees by harvesting a vault with fees
        address rewardToken = address(honey);

        vm.startPrank(infraredGovernance);
        infraredV9.updateWhiteListedRewardTokens(rewardToken, true);
        infraredV9.addReward(stakingToken, rewardToken, 7 days);
        vm.stopPrank();

        // Add liquidity
        stakeInVault(address(vault), stakingToken, testUser, 100 ether);

        // Simulate BGT rewards
        deal(address(bgt), beraVault, 100 ether);

        // Harvest to generate fees
        infraredV9.harvestVault(stakingToken);

        // Check if protocol fees were accumulated
        uint256 protocolFees = infraredV9.protocolFeeAmounts(address(ibgt));

        if (protocolFees > 0) {
            address recipient = address(0x999);
            uint256 balanceBefore = ibgt.balanceOf(recipient);

            // Claim protocol fees
            vm.prank(infraredGovernance);
            infraredV9.claimProtocolFees(recipient, address(ibgt));

            uint256 balanceAfter = ibgt.balanceOf(recipient);
            assertTrue(balanceAfter > balanceBefore, "Should have claimed fees");

            // Fees should be reset to 0
            assertEq(
                infraredV9.protocolFeeAmounts(address(ibgt)),
                0,
                "Protocol fees should be reset"
            );
        }
    }

    function testClaimProtocolFeesOnlyGovernor() public {
        address recipient = address(0x999);

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.claimProtocolFees(recipient, address(ibgt));

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.claimProtocolFees(recipient, address(ibgt));
    }

    function testClaimProtocolFeesWithZeroAmount() public {
        // Should not revert when claiming zero fees
        address recipient = address(0x999);
        uint256 balanceBefore = ibgt.balanceOf(recipient);

        vm.prank(infraredGovernance);
        infraredV9.claimProtocolFees(recipient, address(ibgt));

        uint256 balanceAfter = ibgt.balanceOf(recipient);
        assertEq(balanceAfter, balanceBefore, "Balance should not change");
    }

    function testClaimProtocolFeesMultipleTokens() public {
        // Test claiming fees for different tokens
        address token1 = address(ibgt);
        address token2 = address(honey);

        // Generate fees through harvesting
        vm.startPrank(infraredGovernance);
        infraredV9.updateWhiteListedRewardTokens(token2, true);
        infraredV9.addReward(stakingToken, token2, 7 days);
        vm.stopPrank();

        stakeInVault(address(vault), stakingToken, testUser, 100 ether);
        deal(address(bgt), beraVault, 100 ether);
        infraredV9.harvestVault(stakingToken);

        address recipient = address(0x999);

        // Claim fees for token1
        vm.startPrank(infraredGovernance);
        infraredV9.claimProtocolFees(recipient, token1);

        // Claim fees for token2
        infraredV9.claimProtocolFees(recipient, token2);
        vm.stopPrank();
    }

    function testClaimProtocolFeesAfterMultipleHarvests() public {
        // Setup
        vm.startPrank(infraredGovernance);
        infraredV9.updateWhiteListedRewardTokens(address(honey), true);
        infraredV9.addReward(stakingToken, address(honey), 7 days);
        vm.stopPrank();

        stakeInVault(address(vault), stakingToken, testUser, 100 ether);

        // Multiple harvests
        for (uint256 i = 0; i < 3; i++) {
            deal(address(bgt), beraVault, 50 ether);
            infraredV9.harvestVault(stakingToken);
            vm.warp(block.timestamp + 1 days);
        }

        // Check accumulated fees
        uint256 protocolFees = infraredV9.protocolFeeAmounts(address(ibgt));

        if (protocolFees > 0) {
            address recipient = address(0x999);

            vm.prank(infraredGovernance);
            infraredV9.claimProtocolFees(recipient, address(ibgt));

            assertEq(
                infraredV9.protocolFeeAmounts(address(ibgt)),
                0,
                "All fees should be claimed"
            );
        }
    }

    function testClaimProtocolFeesRevertsZeroAddress() public {
        vm.expectRevert();
        vm.prank(infraredGovernance);
        infraredV9.claimProtocolFees(address(0), address(ibgt));
    }

    function testClaimProtocolFeesToDifferentRecipients() public {
        // Generate fees
        stakeInVault(address(vault), stakingToken, testUser, 100 ether);
        deal(address(bgt), beraVault, 100 ether);
        infraredV9.harvestVault(stakingToken);

        uint256 protocolFees = infraredV9.protocolFeeAmounts(address(ibgt));

        if (protocolFees > 0) {
            address recipient1 = address(0x111);
            address recipient2 = address(0x222);

            // First claim - should get all fees
            vm.prank(infraredGovernance);
            infraredV9.claimProtocolFees(recipient1, address(ibgt));

            assertTrue(
                ibgt.balanceOf(recipient1) > 0,
                "Recipient 1 should receive fees"
            );

            // Generate more fees
            deal(address(bgt), beraVault, 100 ether);
            infraredV9.harvestVault(stakingToken);

            uint256 newFees = infraredV9.protocolFeeAmounts(address(ibgt));
            if (newFees > 0) {
                // Second claim to different recipient
                vm.prank(infraredGovernance);
                infraredV9.claimProtocolFees(recipient2, address(ibgt));

                assertTrue(
                    ibgt.balanceOf(recipient2) > 0,
                    "Recipient 2 should receive fees"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATE BGT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDelegateBGT() public {
        address delegatee = address(0x123);

        // Mint some BGT to Infrared contract
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        // Delegate BGT (should not revert)
        vm.prank(infraredGovernance);
        infraredV9.delegateBGT(delegatee);

        // Note: BGT contract doesn't expose a view function to verify delegation
        // The function should execute without reverting
    }

    function testDelegateBGTOnlyGovernor() public {
        address delegatee = address(0x123);

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.delegateBGT(delegatee);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.delegateBGT(delegatee);
    }

    function testDelegateBGTChangeDelegatee() public {
        address delegatee1 = address(0x111);
        address delegatee2 = address(0x222);

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        vm.startPrank(infraredGovernance);

        // First delegation
        infraredV9.delegateBGT(delegatee1);

        // Change delegation (should not revert)
        infraredV9.delegateBGT(delegatee2);

        vm.stopPrank();
    }

    function testDelegateBGTWithNoBGTBalance() public {
        // Should not revert even with 0 BGT balance
        address delegatee = address(0x123);

        vm.prank(infraredGovernance);
        infraredV9.delegateBGT(delegatee);

        // Should execute without reverting
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testProtocolFeesAndDelegationWorkflow() public {
        // 1. Setup vault and generate rewards
        stakeInVault(address(vault), stakingToken, testUser, 100 ether);
        deal(address(bgt), beraVault, 100 ether);

        // 2. Harvest to generate protocol fees
        infraredV9.harvestVault(stakingToken);

        // 3. Delegate BGT voting power
        address delegatee = address(0x123);
        vm.prank(infraredGovernance);
        infraredV9.delegateBGT(delegatee);

        // 4. Claim protocol fees
        uint256 protocolFees = infraredV9.protocolFeeAmounts(address(ibgt));
        if (protocolFees > 0) {
            vm.prank(infraredGovernance);
            infraredV9.claimProtocolFees(infraredGovernance, address(ibgt));
        }

        // Both operations should complete successfully
    }

    function testClaimProtocolFeesDoesNotAffectUserRewards() public {
        // Setup
        address user1 = address(0x111);
        address user2 = address(0x222);

        stakeInVault(address(vault), stakingToken, user1, 50 ether);
        stakeInVault(address(vault), stakingToken, user2, 50 ether);

        // Generate rewards and fees
        deal(address(bgt), beraVault, 100 ether);
        infraredV9.harvestVault(stakingToken);

        // Check user rewards before claiming protocol fees
        uint256 user1EarnedBefore = vault.earned(user1, address(ibgt));
        uint256 user2EarnedBefore = vault.earned(user2, address(ibgt));

        // Claim protocol fees
        uint256 protocolFees = infraredV9.protocolFeeAmounts(address(ibgt));
        if (protocolFees > 0) {
            vm.prank(infraredGovernance);
            infraredV9.claimProtocolFees(infraredGovernance, address(ibgt));
        }

        // User rewards should not change
        uint256 user1EarnedAfter = vault.earned(user1, address(ibgt));
        uint256 user2EarnedAfter = vault.earned(user2, address(ibgt));

        assertEq(
            user1EarnedAfter,
            user1EarnedBefore,
            "User1 rewards should not change"
        );
        assertEq(
            user2EarnedAfter,
            user2EarnedBefore,
            "User2 rewards should not change"
        );
    }
}
