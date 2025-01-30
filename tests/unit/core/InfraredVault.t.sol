// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/Test.sol";

import {
    IInfraredVault,
    InfraredVault,
    Errors,
    MultiRewards
} from "src/core/InfraredVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";

import {IInfrared} from "src/interfaces/IInfrared.sol";

import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {RewardVaultFactory} from "@berachain/pol/rewards/RewardVaultFactory.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "@berachain/pol/interfaces/IRewardVault.sol";
import {MockRewardVault} from "@berachain/../test/mock/pol/MockRewardVault.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {Helper} from "./Infrared/Helper.sol";

contract InfraredVaultTest is Helper {
    InfraredBGT public rewardsToken;

    MockERC20 public stakingToken;

    // address constant admin = address(1);
    address constant pool = address(3);
    address constant user = address(4);
    address constant user2 = address(5);

    IBerachainRewardsVault public rewardsVault;

    function setUp() public override {
        super.setUp();

        rewardsVault = infraredVault.rewardsVault();

        rewardsToken = ibgt;
        admin = address(1);
        // stakingToken = wbera;
        // rewardsToken = address(ibgt);
    }

    function testRevertWithZeroAddressesInConstructor() public {
        // Test each parameter with zero address
        address[] memory testAddresses = new address[](8);
        testAddresses[0] = address(0); // Zero admin address
        testAddresses[1] = address(wbera);
        testAddresses[2] = address(2); // Infrared address
        testAddresses[3] = address(3); // Pool address
        testAddresses[4] = address(factory);
        testAddresses[5] = address(factory);
        testAddresses[6] = address(4); // Zero admin address
        testAddresses[7] = address(5); // Zero admin address

        for (uint256 i = 0; i < testAddresses.length; i++) {
            address[] memory constructorParams = new address[](8);
            for (uint256 j = 0; j < constructorParams.length; j++) {
                constructorParams[j] = (i == j) ? address(0) : testAddresses[j];
            }
            // Act & Assert
            vm.expectRevert(Errors.ZeroAddress.selector);
            new InfraredVault(
                constructorParams[0], // Staking Token
                1 days
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        harvest
    //////////////////////////////////////////////////////////////*/

    event Harvest(address _sender, address _pool, uint256 _bgtAmount);

    /*//////////////////////////////////////////////////////////////
                        addReward
    //////////////////////////////////////////////////////////////*/

    event RewardStored(address rewardsToken, uint256 rewardsDuration);

    function testRevertWithZeroAddressForTokenAddReward() public {
        uint256 rewardsDuration = 30 days;

        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.addReward(address(0), rewardsDuration);
        vm.stopPrank();
    }

    function testRevertWithZeroDurationAddReward() public {
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAmount.selector);
        infraredVault.addReward(address(0x3), 0);
        vm.stopPrank();
    }

    function testAccessControlAddReward() public {
        uint256 rewardsDuration = 30 days;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, address(this))
        );
        infraredVault.addReward(address(0x3), rewardsDuration);
    }

    function testMaxRewardTokenAddReward() public {
        uint256 rewardsDuration = 30 days;

        vm.startPrank(address(infrared));
        for (uint160 i = 0; i < 9; i++) {
            infraredVault.addReward(address(i + 900), rewardsDuration);
        }
        // Now reached max reward tokens
        vm.expectRevert(abi.encodeWithSignature("MaxNumberOfRewards()"));
        infraredVault.addReward(address(1000), rewardsDuration);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        notifyRewardAmount
    //////////////////////////////////////////////////////////////*/

    event RewardAdded(address rewardsToken, uint256 amount);

    function testSuccessfulNotification() public {
        uint256 rewardAmount = 1000 ether;
        vm.startPrank(address(infrared));
        infraredVault.updateRewardsDuration(address(rewardsToken), 30 days);
        deal(address(rewardsToken), address(infrared), rewardAmount);
        rewardsToken.approve(address(infraredVault), rewardAmount);

        uint256 residual = rewardAmount % 30 days;
        vm.expectEmit(true, true, true, true, address(infraredVault));
        emit IMultiRewards.RewardAdded(
            address(rewardsToken), rewardAmount - residual
        );

        infraredVault.notifyRewardAmount(address(rewardsToken), rewardAmount);

        (
            ,
            ,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
        ) = getRewardData(address(infraredVault), address(rewardsToken));
        assertTrue(periodFinish > block.timestamp, "Reward notification failed");
        // check reward data updated on notify
        assertEq(rewardRate, rewardAmount / (30 days));
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(periodFinish, block.timestamp + 30 days);
        assertEq(rewardPerTokenStored, 0);
        // check balance transfer
        assertEq(rewardsToken.balanceOf(address(infraredVault)), rewardAmount);
        assertEq(rewardsToken.balanceOf(address(infrared)), 0);
    }

    function test_malicious_calls_addIncentives() public {
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

        // Call addIncentives
        infrared.addIncentives(
            address(wbera), address(newRewardToken), rewardAmount
        );

        console.log("----- Output the state before the attack -----");
        (,, uint256 periodFinish, uint256 rewardRate,,,) =
            infraredVault.rewardData(address(newRewardToken));
        assertTrue(rewardRate > 0, "Reward rate should be set");
        console.log("rewardRate before the attack:", rewardRate);
        console.log("periodFinish before the attack:", periodFinish);

        //////////////////////////////////////////////
        //  Malicious user calls `addIncentives()`  //
        //////////////////////////////////////////////
        vm.warp(block.timestamp + rewardsDuration / 2);
        // init maliciousUser
        address maliciousUser = makeAddr("maliciousUser");
        deal(address(newRewardToken), maliciousUser, rewardAmount);
        vm.startPrank(maliciousUser);
        newRewardToken.approve(address(infrared), 1000);

        vm.expectRevert(Errors.RewardRateDecreased.selector);
        infrared.addIncentives(address(wbera), address(newRewardToken), 1);
    }

    function testRevertWithZeroAddressForToken() public {
        uint256 rewardAmount = 1000 ether;

        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.notifyRewardAmount(address(0), rewardAmount);
        vm.stopPrank();
    }

    function testRevertWithZeroAmount() public {
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), 30 days);

        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAmount.selector);
        infraredVault.notifyRewardAmount(address(rewardsToken), 0);
        vm.stopPrank();
    }

    function testAccessControlNotifyRewardAmount() public {
        uint256 rewardAmount = 1000 ether;

        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), 30 days);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSignature("Unauthorized(address)", address(this))
        );
        infraredVault.notifyRewardAmount(address(0x3), rewardAmount);
    }

    function testRewardTokenAlreadyAdded() public {
        vm.startPrank(address(infrared));
        vm.expectRevert(bytes(""));
        infraredVault.addReward(address(rewardsToken), 30 days);
    }

    /*//////////////////////////////////////////////////////////////
                        recoverERC20
    //////////////////////////////////////////////////////////////*/

    function testSuccessfulRecoverERC20() public {
        // deploy a random token
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amountTotal = 200 ether;
        deal(address(randomToken), address(infraredVault), amountTotal);

        // recover random token with admin
        vm.startPrank(address(infrared));
        uint256 amount = 100 ether;
        infraredVault.recoverERC20(user2, address(randomToken), amount);
        vm.stopPrank();

        // check amount sent to user
        assertEq(randomToken.balanceOf(user2), amount);
    }

    function testRevertWithAmountGreaterThanBalanceRecoverERC20() public {
        // deploy a random token
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amountTotal = 200 ether;
        deal(address(randomToken), address(infraredVault), amountTotal);

        // check cannot recover random token with amount greater than balance
        vm.startPrank(address(infrared));
        vm.expectRevert();
        infraredVault.recoverERC20(user2, address(randomToken), amountTotal + 1);
        vm.stopPrank();
    }

    function testRevertWithZeroAddressToRecoverERC20() public {
        // deploy a random token
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amount = 200 ether;
        deal(address(randomToken), address(infraredVault), amount);

        // check cannot recover random token to zero address
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.recoverERC20(address(0), address(randomToken), amount);
        vm.stopPrank();
    }

    function testRevertWithZeroAddressTokenRecoverERC20() public {
        // deploy a random token
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amount = 200 ether;
        deal(address(randomToken), address(infraredVault), amount);

        // check cannot recover random token zero
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.recoverERC20(user2, address(0), amount);
        vm.stopPrank();
    }

    function testRevertWithZeroAmountRecoverERC20() public {
        // deploy a random token
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amount = 200 ether;
        deal(address(randomToken), address(infraredVault), amount);

        // check cannot recover random token with zero amount
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAmount.selector);
        infraredVault.recoverERC20(user2, address(randomToken), 0);
        vm.stopPrank();
    }

    function testWithTokenStakingTokenRecoverERC20() public {
        uint256 stakeAmount = 100 ether;
        deal(address(wbera), address(infraredVault), stakeAmount);

        // check cannot recover staking token
        vm.startPrank(address(infrared));
        infraredVault.recoverERC20(user2, address(wbera), stakeAmount);
        vm.stopPrank();
    }

    function testRevertWithTokenRewardTokenRecoverERC20() public {
        // Setup reward token in the infraredVault and mint rewards
        vm.startPrank(address(infrared));
        uint256 rewardsAmount = 100 ether;
        infraredVault.addReward(address(0x3), 86400);
        rewardsToken.mint(address(infrared), rewardsAmount);
        rewardsToken.approve(address(infraredVault), rewardsAmount);
        infraredVault.notifyRewardAmount(address(rewardsToken), rewardsAmount);
        vm.stopPrank();

        // check cannot recover reward token
        (,,,, uint256 lastUpdateTime,,) =
            infraredVault.rewardData(address(rewardsToken));
        assertTrue(lastUpdateTime != 0);

        vm.startPrank(address(infrared));
        vm.expectRevert("Cannot withdraw reward token");
        infraredVault.recoverERC20(user2, address(rewardsToken), rewardsAmount);
        vm.stopPrank();
    }

    function testAccessControlRecoverERC20() public {
        // deploy a random token
        address unauthorizedUser = address(3);
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // deal and send in random token to infraredVault
        uint256 amount = 200 ether;
        deal(address(randomToken), address(infraredVault), amount);

        // check unauthorized user cannot recover
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        infraredVault.recoverERC20(user, address(randomToken), amount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        updateRewardsDuration
    //////////////////////////////////////////////////////////////*/

    function testSuccessfulDurationUpdate() public {
        uint256 newDuration = 7 days;

        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), newDuration); // Setup reward token
        vm.stopPrank();
        vm.startPrank(address(infrared));
        vm.expectEmit();
        emit IMultiRewards.RewardsDurationUpdated(
            address(rewardsToken), newDuration
        );
        infraredVault.updateRewardsDuration(address(rewardsToken), newDuration);
        vm.stopPrank();

        // Verify that the rewards duration was updated correctly
        (, uint256 actualDuration,,,,,) =
            getRewardData(address(infraredVault), address(rewardsToken));
        assertEq(
            actualDuration,
            newDuration,
            "Rewards duration not updated correctly"
        );
    }

    function testRevertWithZeroAddressForTokenUpdateRewardsDuration() public {
        uint256 newDuration = 7 days;

        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.updateRewardsDuration(address(0), newDuration);
        vm.stopPrank();
    }

    function testRevertWithZeroDurationUpdateRewardsDuration() public {
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), 1 days); // Setup reward token
        vm.stopPrank();
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAmount.selector);
        infraredVault.updateRewardsDuration(address(rewardsToken), 0);
        vm.stopPrank();
    }

    function testAccessControlUpdateRewardsDuration() public {
        uint256 newDuration = 7 days;

        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), newDuration); // Setup reward token
        vm.stopPrank();

        vm.startPrank(address(5)); // Non-admin address
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, address(5))
        );
        infraredVault.updateRewardsDuration(address(rewardsToken), newDuration);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        togglePause
    //////////////////////////////////////////////////////////////*/

    event Paused(address account);

    function testSuccessfulPause() public {
        // check not paused
        assertTrue(!infraredVault.paused());

        // check paused event emitted
        vm.expectEmit();
        emit Paused(address(infrared));

        // pause infraredVault
        vm.startPrank(address(infrared));
        infraredVault.togglePause();
        vm.stopPrank();

        // check now paused
        assertTrue(infraredVault.paused());
    }

    event Unpaused(address account);

    function testSuccessfulUnpause() public {
        // set up so paused
        vm.startPrank(address(infrared));
        infraredVault.togglePause();
        vm.stopPrank();
        assertTrue(infraredVault.paused());

        // check unpaused event emitted
        vm.expectEmit();
        emit Unpaused(address(infrared));

        // unpause infraredVault
        vm.startPrank(address(infrared));
        infraredVault.togglePause();
        vm.stopPrank();

        // check now unpaused
        assertTrue(!infraredVault.paused());
    }

    function testAccessControlPause() public {
        address unauthorizedUser = address(4);
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        infraredVault.togglePause();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        stake
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);

    function testSuccessfulStake() public {
        uint256 stakeAmount = 100 ether;
        deal(user, stakeAmount);
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();

        // User approves the infraredVault to spend their tokens
        wbera.approve(address(infraredVault), stakeAmount);

        // check stake event emitted
        emit Staked(user, stakeAmount);

        // User stakes tokens into the infraredVault
        infraredVault.stake(stakeAmount);

        // Check user's balance in the infraredVault
        uint256 userBalance = infraredVault.balanceOf(user);
        assertEq(userBalance, stakeAmount, "User balance should be updated");

        // Check total supply in the infraredVault
        uint256 totalSupply = infraredVault.totalSupply() - 1; // infared holds a balance of 1 wei in every vault
        assertEq(totalSupply, stakeAmount, "Total supply should be updated");

        // Check staking token transferred to berachain rewards infraredVault
        assertEq(
            wbera.balanceOf(address(infraredVault.rewardsVault())), stakeAmount
        );
        assertEq(wbera.balanceOf(address(infraredVault)), 0);
        assertEq(wbera.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testStakeWithZeroAmount() public {
        deal(address(wbera), user, 0);
        vm.startPrank(user);
        wbera.approve(address(infraredVault), 0);

        vm.expectRevert("Cannot stake 0");
        infraredVault.stake(0);
        vm.stopPrank();
    }

    function testStakeMoreThanUsersBalance() public {
        uint256 stakeAmount = 2000 ether; // More than user's balance

        deal(address(wbera), user, stakeAmount - 1000 ether);
        vm.startPrank(user);
        wbera.approve(address(infraredVault), stakeAmount);

        vm.expectRevert(); // Expect revert due to insufficient balance
        infraredVault.stake(stakeAmount);
        vm.stopPrank();
    }

    // Assuming there's no access control for staking, otherwise:
    function testAccessControlOnStake() public {
        address unauthorizedUser = address(3);
        uint256 stakeAmount = 100 ether;
        deal(address(wbera), user, stakeAmount);

        // User approves the infraredVault to spend their tokens
        vm.startPrank(unauthorizedUser);
        wbera.approve(address(infraredVault), stakeAmount);

        vm.expectRevert();
        infraredVault.stake(stakeAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        withdraw
    //////////////////////////////////////////////////////////////*/

    event Withdrawn(address indexed user, uint256 amount);

    function testSuccessfulWithdraw() public {
        deal(user2, 500 ether);
        vm.startPrank(user2);
        wbera.deposit{value: 500 ether}();
        // User stakes tokens
        wbera.approve(address(infraredVault), 500 ether);
        infraredVault.stake(500 ether);
        vm.stopPrank();

        uint256 withdrawAmount = 500 ether;

        // check withdrawn event emitted
        vm.expectEmit();
        emit Withdrawn(user2, withdrawAmount);

        vm.startPrank(user2);
        infraredVault.withdraw(withdrawAmount);
        vm.stopPrank();

        // Check user's balance in the infraredVault after withdrawal
        uint256 userBalance = infraredVault.balanceOf(user2);
        assertEq(
            userBalance, 0, "User balance should decrease after withdrawal"
        );

        // Check total supply in the infraredVault after withdrawal
        uint256 totalSupply = infraredVault.totalSupply() - 1; // infared holds a balance of 1 wei in every vault
        assertEq(
            totalSupply, 0, "Total supply should decrease after withdrawal"
        );

        // Check user's token balance
        uint256 userTokenBalance = wbera.balanceOf(user2);
        assertEq(
            userTokenBalance,
            500 ether,
            "User should receive the withdrawn tokens"
        );
    }

    function testWithdrawMoreThanStaked() public {
        // User stakes tokens
        deal(user2, 500 ether);
        vm.startPrank(user2);
        wbera.deposit{value: 500 ether}();
        wbera.approve(address(infraredVault), 500 ether);
        infraredVault.stake(500 ether);
        vm.stopPrank();

        uint256 withdrawAmount = 600 ether; // More than staked amount

        vm.startPrank(user2);
        vm.expectRevert(); // Expect revert due to insufficient balance
        infraredVault.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    function testWithdrawZeroAmount() public {
        // User stakes tokens
        deal(user2, 500 ether);
        vm.startPrank(user2);
        wbera.deposit{value: 500 ether}();
        wbera.approve(address(infraredVault), 500 ether);
        infraredVault.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Cannot withdraw 0");
        infraredVault.withdraw(0);
        vm.stopPrank();
    }

    function testWithdrawAsDifferentUser() public {
        // User stakes tokens
        deal(user2, 500 ether);
        vm.startPrank(user2);
        wbera.deposit{value: 500 ether}();
        wbera.approve(address(infraredVault), 500 ether);
        infraredVault.stake(500 ether);
        vm.stopPrank();

        address otherUser = address(6);
        uint256 withdrawAmount = 100 ether;

        vm.startPrank(otherUser);
        // Assuming otherUser hasn't staked anything
        vm.expectRevert(); // Expect revert due to insufficient balance
        infraredVault.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        getReward
    //////////////////////////////////////////////////////////////*/

    function testSuccessfulGetReward() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount, rewardsDuration);

        vm.startPrank(user);
        // Manipulate time to simulate the passage of the reward duration
        skip(rewardsDuration + 100 minutes);
        infraredVault.getReward();

        vm.stopPrank();

        // Check user's rewards token balance
        uint256 userRewardsBalance = rewardsToken.balanceOf(user);
        assertAlmostEqual(
            userRewardsBalance,
            rewardsAmount,
            tolerance,
            "User should receive the rewards within tolerance"
        );
    }

    function testGetRewardWhenNoRewards() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount, rewardsDuration);

        address otherUser = address(3);

        // Simulate another user who hasn't earned any rewards
        vm.startPrank(otherUser);
        infraredVault.getReward();
        vm.stopPrank();

        // Check other user's rewards token balance
        uint256 otherUserRewardsBalance = rewardsToken.balanceOf(otherUser);
        assertEq(
            otherUserRewardsBalance, 0, "User should not receive any rewards"
        );
    }

    function testMultipleRewardsClaim() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount, rewardsDuration);
        // Claim rewards twice
        vm.startPrank(user);
        // First claim
        skip(rewardsDuration + 1 minutes / 2); // Simulate half the reward duration
        infraredVault.getReward();

        // Second claim
        skip(rewardsDuration + 1 minutes / 2); // Complete the reward duration
        infraredVault.getReward();

        vm.stopPrank();

        // Check user's rewards token balance after second claim

        uint256 userRewardsBalanceAfterSecondClaim =
            rewardsToken.balanceOf(user);
        assertAlmostEqual(
            userRewardsBalanceAfterSecondClaim,
            rewardsAmount,
            tolerance,
            "User should receive the full rewards within tolerance after second claim"
        );
    }

    function testMultipleRewardTokensClaim() public {
        uint256 firstRewardAmount = 50 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(firstRewardAmount, rewardsDuration);
        // Initialize second mock reward token
        MockERC20 secondRewardsToken =
            new MockERC20("Second Reward Token", "SRWD", 18);

        // Add the second reward token to the infraredVault
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(secondRewardsToken), rewardsDuration);

        vm.stopPrank();

        uint256 amountToStake = 100 ether;

        // Users stake some tokens
        vm.deal(address(user), amountToStake);
        vm.startPrank(user);
        wbera.deposit{value: amountToStake}();
        wbera.approve(address(infraredVault), amountToStake);
        infraredVault.stake(amountToStake);
        vm.stopPrank();

        // Notify rewards for both tokens
        uint256 secondRewardAmount = 75 ether;

        vm.startPrank(address(infrared));
        secondRewardsToken.mint(address(infrared), secondRewardAmount);
        secondRewardsToken.approve(address(infraredVault), secondRewardAmount);
        infraredVault.notifyRewardAmount(
            address(secondRewardsToken), secondRewardAmount
        );
        vm.stopPrank();

        // Skip time to ensure rewards are distributed
        skip(rewardsDuration + 100 minutes);

        // User claims rewards
        vm.startPrank(user);
        infraredVault.getReward();
        vm.stopPrank();

        // Check user received rewards for both tokens
        uint256 userFirstRewardBalance = rewardsToken.balanceOf(user);
        uint256 userSecondRewardBalance = secondRewardsToken.balanceOf(user);

        assertAlmostEqual(
            userFirstRewardBalance,
            firstRewardAmount,
            tolerance,
            "Incorrect first reward amount"
        );
        assertAlmostEqual(
            userSecondRewardBalance,
            secondRewardAmount,
            tolerance,
            "Incorrect second reward amount"
        );
    }

    function testSameStakingTokenAndRewardToken() public {
        uint256 rewardsAmount = 1 ether;
        uint256 rewardsDuration = 30 days;

        // Setup reward token in the infraredVault and mint rewards
        vm.deal(address(infrared), rewardsAmount);
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(wbera), rewardsDuration);
        wbera.deposit{value: rewardsAmount}();
        wbera.approve(address(infraredVault), rewardsAmount);
        infraredVault.notifyRewardAmount(address(wbera), rewardsAmount);
        vm.stopPrank();

        // User stakes tokens
        uint256 stakeAmount = 100 ether;

        vm.deal(address(user), stakeAmount);
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        vm.deal(address(user2), stakeAmount);
        vm.startPrank(user2);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Manipulate time to simulate the passage of the reward duration
        skip(rewardsDuration + 100 minutes);

        vm.prank(user);
        infraredVault.getReward();

        vm.prank(user2);
        infraredVault.getReward();

        // Check user's rewards token balance
        uint256 userRewardsBalance = wbera.balanceOf(user);
        assertAlmostEqual(
            userRewardsBalance,
            rewardsAmount / 2,
            tolerance,
            "User should receive the rewards within tolerance"
        );

        userRewardsBalance = wbera.balanceOf(user2);
        assertAlmostEqual(
            userRewardsBalance,
            rewardsAmount / 2,
            tolerance,
            "User should receive the rewards within tolerance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        getRewardForUser
    //////////////////////////////////////////////////////////////*/

    function testSuccessfulGetRewardForUser() public {
        uint256 rewardsAmount = 100 ether;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount, rewardsDuration);

        // Manipulate time to simulate the passage of the reward duration
        skip(rewardsDuration + 100 minutes);
        infraredVault.getRewardForUser(user);

        // Check user's rewards token balance
        uint256 userRewardsBalance = rewardsToken.balanceOf(user);
        assertAlmostEqual(
            userRewardsBalance,
            rewardsAmount,
            tolerance,
            "User should receive the rewards within tolerance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER
    //////////////////////////////////////////////////////////////*/

    function getRewardData(address _infraredVault, address _rewardsToken)
        internal
        returns (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        )
    {
        (bool success, bytes memory data) = _infraredVault.call(
            abi.encodeWithSignature("rewardData(address)", _rewardsToken)
        );
        require(success, "Failed to get reward data");

        // Decode the returned data based on the structure of the Reward struct
        (
            rewardsDistributor,
            rewardsDuration,
            periodFinish,
            rewardRate,
            lastUpdateTime,
            rewardPerTokenStored,
            rewardResidual
        ) = abi.decode(
            data,
            (address, uint256, uint256, uint256, uint256, uint256, uint256)
        );
        return (
            rewardsDistributor,
            rewardsDuration,
            periodFinish,
            rewardRate,
            lastUpdateTime,
            rewardPerTokenStored,
            rewardResidual
        );
    }

    function setUpGetReward(uint256 rewardsAmount, uint256 rewardsDuratoin)
        internal
    {
        // Setup reward token in the infraredVault and mint rewards
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(0x3), rewardsDuratoin);
        rewardsToken.mint(address(infrared), rewardsAmount);
        rewardsToken.approve(address(infraredVault), rewardsAmount);
        infraredVault.notifyRewardAmount(address(rewardsToken), rewardsAmount);
        vm.stopPrank();

        // User stakes tokens
        vm.deal(address(user), 500 ether);
        vm.startPrank(user);
        wbera.deposit{value: 500 ether}();
        wbera.approve(address(infraredVault), 500 ether);
        infraredVault.stake(500 ether);
        vm.stopPrank();
    }

    uint256 constant tolerance = 1 ether / 1e10; // Example tolerance: 0.000001 ether

    // Helper function to assert equality within a tolerance range
    function assertAlmostEqual(
        uint256 left,
        uint256 right,
        uint256 _tolerance,
        string memory message
    ) internal pure {
        if (left > right) {
            assertTrue(left - right <= _tolerance, message);
        } else {
            assertTrue(right - left <= _tolerance, message);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Getters
    //////////////////////////////////////////////////////////////*/
    function testGetAllRewardTokens() public {
        // Setup: Add multiple reward tokens
        MockERC20 rewardToken1 = new MockERC20("Reward1", "RWD1", 18);
        MockERC20 rewardToken2 = new MockERC20("Reward2", "RWD2", 18);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(rewardToken1), true);
        infrared.updateWhiteListedRewardTokens(address(rewardToken2), true);

        infrared.addReward(address(wbera), address(rewardToken1), 7 days);
        infrared.addReward(address(wbera), address(rewardToken2), 7 days);
        vm.stopPrank();

        // Get all reward tokens
        address[] memory allRewards = infraredVault.getAllRewardTokens();

        // Verify results - note that InfraredBGT is already added in setup
        assertEq(
            allRewards.length,
            3,
            "Should have 3 reward tokens (including InfraredBGT)"
        );
        assertTrue(
            allRewards[0] == address(ibgt) || allRewards[1] == address(ibgt)
                || allRewards[2] == address(ibgt),
            "InfraredBGT should be in rewards"
        );
        assertTrue(
            allRewards[0] == address(rewardToken1)
                || allRewards[1] == address(rewardToken1)
                || allRewards[2] == address(rewardToken1),
            "rewardToken1 should be in rewards"
        );
        assertTrue(
            allRewards[0] == address(rewardToken2)
                || allRewards[1] == address(rewardToken2)
                || allRewards[2] == address(rewardToken2),
            "rewardToken2 should be in rewards"
        );
    }

    function testGetAllRewardsForUser() public {
        // address user = address(0x123);
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 1000 ether;

        // Setup: Add reward token and distribute rewards
        MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(rewardToken), true);
        infrared.addReward(address(wbera), address(rewardToken), 7 days);
        vm.stopPrank();

        // Setup: Give user some WBERA to stake
        deal(address(wbera), user, stakeAmount);

        // Setup: Add rewards
        deal(address(ibgt), address(infrared), 100 ether);
        // add ibgt rewards to vault
        vm.startPrank(address(infrared));
        ibgt.approve(address(infraredVault), 100 ether);
        infraredVault.notifyRewardAmount(address(ibgt), 100 ether);
        vm.stopPrank();

        // add reward token rewards to vault
        deal(address(rewardToken), address(infrared), rewardAmount);
        vm.startPrank(address(infrared));
        rewardToken.approve(address(infraredVault), rewardAmount);
        infraredVault.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        // User stakes tokens
        vm.startPrank(user);
        wbera.approve(address(infraredVault), stakeAmount);
        infraredVault.stake(stakeAmount);
        vm.stopPrank();

        // Simulate passage of time to accrue rewards
        skip(7 days);

        // Get all rewards for user
        IInfraredVault.UserReward[] memory rewards =
            infraredVault.getAllRewardsForUser(user);

        // Verify results
        assertEq(rewards.length, 2, "Should have 2 reward tokens");
        assertTrue(
            rewards[0].amount > 0, "User should have rewards for InfraredBGT"
        );
        assertTrue(
            rewards[0].token == address(ibgt),
            "User should have rewards for rewardToken"
        );
        assertTrue(
            rewards[1].amount > 0, "User should have rewards for rewardToken"
        );
        assertTrue(
            rewards[1].token == address(rewardToken),
            "User should have rewards for rewardToken"
        );
    }

    function testGetAllRewardsForUserOnlyOneRewardToken() public {
        testGetAllRewardsForUser();

        // stake for user2
        deal(address(wbera), user2, 100 ether);
        vm.startPrank(user2);
        wbera.approve(address(infraredVault), 100 ether);
        infraredVault.stake(100 ether);
        vm.stopPrank();

        // add more ibgt rewards to vault
        deal(address(ibgt), address(infrared), 100 ether);
        vm.startPrank(address(infrared));
        ibgt.approve(address(infraredVault), 100 ether);
        infraredVault.notifyRewardAmount(address(ibgt), 100 ether);
        vm.stopPrank();

        // Simulate passage of time to accrue rewards
        skip(7 days);

        // get rewards for user2
        IInfraredVault.UserReward[] memory user2Rewards =
            infraredVault.getAllRewardsForUser(user2);
        assertEq(user2Rewards.length, 1, "Should have 1 reward token");
        assertTrue(
            user2Rewards[0].amount > 0,
            "User should have rewards for InfraredBGT"
        );
        assertTrue(
            user2Rewards[0].token == address(ibgt),
            "User should have rewards for InfraredBGT"
        );

        // get rewards for user and verify amount is greater
        IInfraredVault.UserReward[] memory userRewards =
            infraredVault.getAllRewardsForUser(user);
        assertEq(userRewards.length, 2, "Should have 1 reward token");
        assertTrue(
            userRewards[0].amount > user2Rewards[0].amount,
            "User should have rewards for InfraredBGT"
        );
        assertTrue(
            userRewards[0].token == address(ibgt),
            "User should have rewards for InfraredBGT"
        );
    }

    function testGetAllRewardsForUserWithNoStake() public {
        // Setup: Add reward token without any stakes or rewards
        MockERC20 rewardToken = new MockERC20("Reward", "RWD", 18);

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(rewardToken), true);
        infrared.addReward(address(wbera), address(rewardToken), 7 days);
        vm.stopPrank();

        // add ibgt rewards to vault
        deal(address(ibgt), address(infrared), 100 ether);
        vm.startPrank(address(infrared));
        ibgt.approve(address(infraredVault), 100 ether);
        infraredVault.notifyRewardAmount(address(ibgt), 100 ether);
        vm.stopPrank();

        // Get all rewards for user with no stake
        IInfraredVault.UserReward[] memory rewards =
            infraredVault.getAllRewardsForUser(user);

        // Verify results
        assertEq(
            rewards.length, 0, "Should have 2 reward tokens but zero amounts"
        );
    }

    function testRewardPerTokenPrecisionHandling() public {
        // Setup
        uint256 rewardDuration = 7 days;
        MockERC20 _stakingToken = MockERC20(address(wbera));

        vm.startPrank(address(infrared));
        infraredVault.updateRewardsDuration(
            address(rewardsToken), rewardDuration
        );
        vm.stopPrank();

        // User stakes
        uint256 stakingAmount = 1 ether;
        deal(address(_stakingToken), user, stakingAmount);
        vm.startPrank(user);
        _stakingToken.approve(address(infraredVault), stakingAmount);
        infraredVault.stake(stakingAmount);
        vm.stopPrank();

        // Notify reward with a residual
        uint256 rewardAmount = rewardDuration - 1; // This will create a residual
        deal(address(rewardsToken), address(infrared), rewardAmount);
        vm.startPrank(address(infrared));
        rewardsToken.approve(address(infraredVault), rewardAmount);
        infraredVault.notifyRewardAmount(address(rewardsToken), rewardAmount);
        vm.stopPrank();

        // Check that the rewardPerToken is zero due to precision loss
        assertEq(infraredVault.rewardPerToken(address(rewardsToken)), 0);

        // Skip time to simulate the reward period
        skip(rewardDuration);

        // Check that no rewards are claimable due to precision loss
        uint256 balanceBefore = rewardsToken.balanceOf(user);
        vm.startPrank(user);
        infraredVault.getReward();
        uint256 balanceAfter = rewardsToken.balanceOf(user);
        vm.stopPrank();
        assertEq(balanceAfter - balanceBefore, 0);

        // Notify reward again to check if residual is handled
        uint256 additionalRewardAmount = rewardDuration + 1; // Add more to cover residual
        deal(address(rewardsToken), address(infrared), additionalRewardAmount);
        vm.startPrank(address(infrared));
        rewardsToken.approve(address(infraredVault), additionalRewardAmount);
        infraredVault.notifyRewardAmount(
            address(rewardsToken), additionalRewardAmount
        );
        vm.stopPrank();

        // Skip time again
        skip(rewardDuration);

        // Check that rewards are now claimable
        balanceBefore = rewardsToken.balanceOf(user);
        vm.startPrank(user);
        infraredVault.getReward();
        balanceAfter = rewardsToken.balanceOf(user);
        vm.stopPrank();
        assertTrue(
            balanceAfter - balanceBefore > 0, "Rewards should be claimable"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        removing rewards
    //////////////////////////////////////////////////////////////*/

    // Test removing rewards from InfraredVault
    function testSuccessfulRemoveReward() public {
        // Setup: Add a new reward token
        MockERC20 rewardToken = new MockERC20("Reward Token", "RWD", 18);
        uint256 rewardsDuration = 7 days;

        vm.startPrank(address(infrared));
        infraredVault.addReward(address(rewardToken), rewardsDuration);

        // Verify reward token was added
        address[] memory rewardTokensBefore = infraredVault.getAllRewardTokens();
        assertTrue(
            contains(rewardTokensBefore, address(rewardToken)),
            "Reward token should be in the list before removal"
        );

        // Remove the reward token
        infraredVault.removeReward(address(rewardToken));
        vm.stopPrank();

        // Verify reward token was removed
        address[] memory rewardTokensAfter = infraredVault.getAllRewardTokens();
        assertFalse(
            contains(rewardTokensAfter, address(rewardToken)),
            "Reward token should not be in the list after removal"
        );
    }

    function testRevertRemoveRewardWithZeroAddress() public {
        vm.startPrank(address(infrared));
        vm.expectRevert(Errors.ZeroAddress.selector);
        infraredVault.removeReward(address(0));
        vm.stopPrank();
    }

    function testRevertRemoveRewardUnauthorized() public {
        // Try to remove reward token from unauthorized address
        address unauthorizedCaller = address(0x123);
        MockERC20 rewardToken = new MockERC20("Reward Token", "RWD", 18);

        vm.startPrank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Unauthorized.selector, unauthorizedCaller
            )
        );
        infraredVault.removeReward(address(rewardToken));
        vm.stopPrank();
    }

    function testRemoveRewardAndAddBack() public {
        // Setup: Add a new reward token
        MockERC20 rewardToken = new MockERC20("Reward Token", "RWD", 18);
        uint256 rewardsDuration = 7 days;

        vm.startPrank(address(infrared));
        infraredVault.addReward(address(rewardToken), rewardsDuration);

        // Remove the reward token
        infraredVault.removeReward(address(rewardToken));

        // Add it back
        infraredVault.addReward(address(rewardToken), rewardsDuration);
        vm.stopPrank();

        // Verify reward token was added back successfully
        address[] memory rewardTokens = infraredVault.getAllRewardTokens();
        assertTrue(
            contains(rewardTokens, address(rewardToken)),
            "Reward token should be in the list after adding back"
        );
    }

    function testRemoveRewardWithActiveRewards() public {
        // Setup: Add a new reward token and distribute some rewards
        MockERC20 rewardToken = new MockERC20("Reward Token", "RWD", 18);
        uint256 rewardsDuration = 7 days;
        uint256 rewardAmount = 1000 ether;

        // Add reward token
        vm.startPrank(address(infrared));
        infraredVault.addReward(address(rewardToken), rewardsDuration);

        // Setup rewards
        deal(address(rewardToken), address(infrared), rewardAmount);
        rewardToken.approve(address(infraredVault), rewardAmount);
        infraredVault.notifyRewardAmount(address(rewardToken), rewardAmount);

        // Remove reward token while rewards are active
        vm.expectRevert();
        infraredVault.removeReward(address(rewardToken));
        vm.stopPrank();
    }

    // Helper function to check if an address exists in an array
    function contains(address[] memory addresses, address target)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) {
                return true;
            }
        }
        return false;
    }
}
