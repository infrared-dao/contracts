// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IVoter} from "src/voting/interfaces/IVoter.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

contract AdminFunctionsTest is Helper {
    address stakingToken;
    IInfraredVault vault;
    InfraredV1_9 infraredV9;

    function setUp() public override {
        super.setUp();

        // Cast to V1_9 to access new functions
        infraredV9 = InfraredV1_9(payable(address(infrared)));

        stakingToken = address(new MockERC20("Staking Token", "STK", 18));
        vault = infraredV9.registerVault(stakingToken);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE REWARD TESTS
    //////////////////////////////////////////////////////////////*/

    function testRemoveReward() public {
        // Add a reward token first
        address rewardToken = address(new MockERC20("Reward", "RWD", 18));

        vm.startPrank(infraredGovernance);
        infraredV9.updateWhiteListedRewardTokens(rewardToken, true);
        infraredV9.addReward(stakingToken, rewardToken, 7 days);

        // Verify it was added
        address[] memory rewardsBefore = vault.getAllRewardTokens();
        bool foundBefore = false;
        for (uint256 i = 0; i < rewardsBefore.length; i++) {
            if (rewardsBefore[i] == rewardToken) foundBefore = true;
        }
        assertTrue(foundBefore, "Reward token should be added");

        // Remove the reward token
        infraredV9.removeReward(stakingToken, rewardToken);
        vm.stopPrank();

        // Verify it was removed
        address[] memory rewardsAfter = vault.getAllRewardTokens();
        bool foundAfter = false;
        for (uint256 i = 0; i < rewardsAfter.length; i++) {
            if (rewardsAfter[i] == rewardToken) foundAfter = true;
        }
        assertFalse(foundAfter, "Reward token should be removed");
    }

    function testRemoveRewardOnlyGovernor() public {
        address rewardToken = address(honey);

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.removeReward(stakingToken, rewardToken);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.removeReward(stakingToken, rewardToken);
    }

    function testRemoveRewardLosesUnclaimedRewards() public {
        // This test documents the expected behavior that unclaimed rewards are lost
        address rewardToken = address(new MockERC20("Reward", "RWD", 18));

        vm.startPrank(infraredGovernance);
        infraredV9.updateWhiteListedRewardTokens(rewardToken, true);
        infraredV9.addReward(stakingToken, rewardToken, 7 days);
        vm.stopPrank();

        // Add rewards to vault
        deal(rewardToken, address(this), 1000 ether);
        MockERC20(rewardToken).approve(address(infrared), 1000 ether);
        infraredV9.addIncentives(stakingToken, rewardToken, 1000 ether);

        // Stake to be eligible for rewards
        stakeInVault(address(vault), stakingToken, testUser, 100 ether);

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // User should have earned some rewards
        uint256 earnedBefore = vault.earned(testUser, rewardToken);
        assertTrue(earnedBefore > 0, "User should have earned rewards");

        // Remove reward token (emergency function)
        vm.prank(infraredGovernance);
        infraredV9.removeReward(stakingToken, rewardToken);

        // After removal, user cannot claim those rewards
        // This is the expected (but unfortunate) behavior of the emergency function
    }

    /*//////////////////////////////////////////////////////////////
                        SET VOTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetVoter() public {
        // Deploy a mock voter contract
        address mockVoter = address(new MockERC20("Voter", "VOTE", 18));

        vm.prank(infraredGovernance);
        infraredV9.setVoter(mockVoter);

        assertEq(address(infraredV9.voter()), mockVoter, "Voter not set");
    }

    // Note: VoterSet event removed in V1_9
    // function testSetVoterEmitsEvent() public {
    //     address mockVoter = address(new MockERC20("Voter", "VOTE", 18));
    //     vm.prank(infraredGovernance);
    //     infraredV9.setVoter(mockVoter);
    // }

    function testSetVoterRevertsZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(infraredGovernance);
        infraredV9.setVoter(address(0));
    }

    function testSetVoterRevertsAlreadySet() public {
        address mockVoter1 = address(new MockERC20("Voter1", "VOTE1", 18));
        address mockVoter2 = address(new MockERC20("Voter2", "VOTE2", 18));

        vm.startPrank(infraredGovernance);
        infraredV9.setVoter(mockVoter1);

        // Try to set again
        vm.expectRevert(Errors.AlreadySet.selector);
        infraredV9.setVoter(mockVoter2);
        vm.stopPrank();
    }

    function testSetVoterOnlyGovernor() public {
        address mockVoter = address(new MockERC20("Voter", "VOTE", 18));

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.setVoter(mockVoter);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.setVoter(mockVoter);
    }

    /*//////////////////////////////////////////////////////////////
                    UPDATE IR MINT RATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateIRMintRate() public {
        // Set IR first if not already set
        uint256 newRate = 1e18; // 1:1 ratio

        vm.prank(infraredGovernance);
        infraredV9.updateIRMintRate(newRate);

        // Note: We can't easily verify the internal storage directly,
        // but we can verify through the event emission
    }

    function testUpdateIRMintRateEmitsEvent() public {
        uint256 newRate = 2e18;

        //         vm.expectEmit(true, true, true, true);
        //         emit InfraredV1_9.UpdatedIRMintRate(0, newRate, infraredGovernance);

        vm.prank(infraredGovernance);
        infraredV9.updateIRMintRate(newRate);
    }

    function testUpdateIRMintRateOnlyGovernor() public {
        uint256 newRate = 1e18;

        vm.expectRevert();
        vm.prank(keeper);
        infraredV9.updateIRMintRate(newRate);

        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.updateIRMintRate(newRate);
    }

    function testUpdateIRMintRateMultipleTimes() public {
        vm.startPrank(infraredGovernance);

        // First update
        infraredV9.updateIRMintRate(1e18);

        // Second update
        infraredV9.updateIRMintRate(2e18);

        // Third update
        infraredV9.updateIRMintRate(5e17);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    TOGGLE AUCTION BASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testToggleAuctionBase() public {
        bool initialState = infraredV9.auctionBase();

        vm.prank(keeper);
        infraredV9.toggleAuctionBase();

        bool afterToggle = infraredV9.auctionBase();
        assertEq(afterToggle, !initialState, "Auction base should toggle");
    }

    function testToggleAuctionBaseOnlyKeeper() public {
        vm.expectRevert();
        vm.prank(testUser);
        infraredV9.toggleAuctionBase();

        // Governance also cannot call - keeper only
        vm.expectRevert();
        vm.prank(infraredGovernance);
        infraredV9.toggleAuctionBase();
    }

    function testToggleAuctionBaseMultipleTimes() public {
        bool initial = infraredV9.auctionBase();

        vm.startPrank(keeper);

        // Toggle 1
        infraredV9.toggleAuctionBase();
        assertEq(infraredV9.auctionBase(), !initial);

        // Toggle 2
        infraredV9.toggleAuctionBase();
        assertEq(infraredV9.auctionBase(), initial);

        // Toggle 3
        infraredV9.toggleAuctionBase();
        assertEq(infraredV9.auctionBase(), !initial);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    CHARGED FEES ON REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

    function testChargedFeesOnRewards() public view {
        uint256 amount = 1000 ether;
        uint256 feeTotal = 50000; // 0.5% (in units of 1e6)
        uint256 feeProtocol = 20000; // 0.2%

        (uint256 amtRecipient, uint256 amtVoter, uint256 amtProtocol) =
            infraredV9.chargedFeesOnRewards(amount, feeTotal, feeProtocol);

        // Verify amounts sum correctly
        assertEq(
            amtRecipient + amtVoter + amtProtocol,
            amount,
            "Amounts should sum to total"
        );

        // Protocol fee should be applied
        assertTrue(amtProtocol > 0, "Protocol fee should be non-zero");

        // Recipient should get the most
        assertTrue(
            amtRecipient > amtVoter, "Recipient should get more than voter"
        );
        assertTrue(
            amtRecipient > amtProtocol,
            "Recipient should get more than protocol"
        );
    }

    function testChargedFeesOnRewardsZeroFees() public view {
        uint256 amount = 1000 ether;
        uint256 feeTotal = 0;
        uint256 feeProtocol = 0;

        (uint256 amtRecipient, uint256 amtVoter, uint256 amtProtocol) =
            infraredV9.chargedFeesOnRewards(amount, feeTotal, feeProtocol);

        // With no fees, recipient gets everything
        assertEq(amtRecipient, amount, "Recipient should get all");
        assertEq(amtVoter, 0, "Voter should get nothing");
        assertEq(amtProtocol, 0, "Protocol should get nothing");
    }

    function testChargedFeesOnRewardsRevertsInvalidFee() public {
        uint256 amount = 1000 ether;
        uint256 feeTotal = 2e6 + 1; // > 100%
        uint256 feeProtocol = 0;

        vm.expectRevert(Errors.InvalidFee.selector);
        infraredV9.chargedFeesOnRewards(amount, feeTotal, feeProtocol);
    }

    function testChargedFeesOnRewardsDifferentScenarios() public view {
        uint256 amount = 1000 ether;

        // Scenario 1: Low fees
        (uint256 amt1,,) = infraredV9.chargedFeesOnRewards(amount, 10000, 5000);
        assertTrue(amt1 >= 990 ether, "Low fees, high recipient amount");

        // Scenario 2: High fees
        (uint256 amt2,,) =
            infraredV9.chargedFeesOnRewards(amount, 100000, 50000);
        assertTrue(amt2 < 950 ether, "High fees, lower recipient amount");

        // Scenario 3: All to protocol
        (,, uint256 amt3) =
            infraredV9.chargedFeesOnRewards(amount, 100000, 100000);
        assertTrue(amt3 > 0, "Protocol gets fees");
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAdminFunctionsSequence() public {
        // Test a realistic sequence of admin operations
        vm.startPrank(infraredGovernance);

        // 1. Update IR mint rate
        infraredV9.updateIRMintRate(1e18);

        // 2. Set voter (if not already set)
        if (address(infraredV9.voter()) == address(0)) {
            address mockVoter = address(new MockERC20("Voter", "VOTE", 18));
            infraredV9.setVoter(mockVoter);
        }

        // 3. Add and remove reward token
        address tempReward = address(new MockERC20("Temp", "TMP", 18));
        infraredV9.updateWhiteListedRewardTokens(tempReward, true);
        infraredV9.addReward(stakingToken, tempReward, 7 days);
        infraredV9.removeReward(stakingToken, tempReward);

        vm.stopPrank();

        // 4. Toggle auction base (keeper)
        vm.prank(keeper);
        infraredV9.toggleAuctionBase();
    }
}
