// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "src/core/MultiRewards.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MissingReturnToken} from
    "@solmate/test/utils/weird-tokens/MissingReturnToken.sol";

contract MultiRewardsConcrete is MultiRewards {
    constructor(address _stakingToken) MultiRewards(_stakingToken) {}

    function updateRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        _setRewardsDuration(_rewardsToken, _rewardsDuration);
    }

    function addReward(
        address _rewardsToken,
        address receiver,
        uint256 _rewardsDuration
    ) external {
        _addReward(_rewardsToken, receiver, _rewardsDuration);
    }

    function notifyRewardAmount(address _rewardToken, uint256 _reward)
        external
    {
        _notifyRewardAmount(_rewardToken, _reward);
    }

    function recoverERC20(address _to, address _token, uint256 _amount)
        external
    {
        _recoverERC20(_to, _token, _amount);
    }

    function onStake(uint256 amount) internal override {
        // Implement custom behavior for staking, if needed
    }

    function onWithdraw(uint256 amount) internal override {
        // Implement custom behavior for withdrawing, if needed
    }

    function onReward() internal override {
        // Implement custom behavior for claiming rewards, if needed
    }
}

contract MultiRewardsTest is Test {
    MultiRewardsConcrete multiRewards;
    MockERC20 rewardToken;
    MockERC20 rewardToken2;
    MockERC20 baseToken;

    MissingReturnToken missingReturnToken;
    BombToken bomb;

    address alice;
    address bob;
    address charlie;

    function setUp() public {
        // Deploy mock tokens
        rewardToken = new MockERC20("RewardToken", "RWD", 18);
        rewardToken2 = new MockERC20("RewardToken2", "RWD2", 18);
        baseToken = new MockERC20("BaseToken", "BASE", 18);

        missingReturnToken = new MissingReturnToken();
        bomb = new BombToken("Bomb token", "BMB", 18);

        // Deploy MultiRewards contract
        multiRewards = new MultiRewardsConcrete(address(baseToken));

        // Assign test addresses
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);

        // Mint tokens for testing
        rewardToken.mint(alice, 1e20);
        rewardToken.mint(bob, 1e20);
        rewardToken2.mint(alice, 1e20);
        rewardToken2.mint(charlie, 1e20);
        baseToken.mint(bob, 1e20);
        baseToken.mint(charlie, 1e20);

        deal(address(missingReturnToken), alice, 1e20);
        deal(address(bomb), alice, 1e20);

        // Set up users
        vm.startPrank(alice);
        rewardToken.approve(address(multiRewards), type(uint256).max);
        rewardToken2.approve(address(multiRewards), type(uint256).max);
        missingReturnToken.approve(address(multiRewards), type(uint256).max);
        bomb.approve(address(multiRewards), type(uint256).max);
        vm.stopPrank();
    }

    function testMultipleRewardEarnings() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), 1e10);
        multiRewards.addReward(address(rewardToken2), charlie, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken2), 1e10);
        vm.stopPrank();

        // Bob stakes base token
        stakeAndApprove(bob, 1e18);

        // Charlie stakes base token
        stakeAndApprove(charlie, 1e18);

        // Check total supply
        assertEq(multiRewards.totalSupply(), 2e18);

        // Simulate time passage
        skip(60);

        // Verify reward per token for rewardToken
        uint256 rewardPerToken =
            multiRewards.rewardPerToken(address(rewardToken));
        assertGt(rewardPerToken, 0);

        // Verify earnings for Bob
        uint256 earningsBob = multiRewards.earned(bob, address(rewardToken));
        assertGt(earningsBob, 0);

        // Verify earnings for Charlie
        uint256 earningsCharlie =
            multiRewards.earned(charlie, address(rewardToken));
        assertGt(earningsCharlie, 0);

        // Check total distributed rewards for rewardToken
        uint256 totalDistributed = earningsBob + earningsCharlie;
        uint256 expectedDistributed = rewardPerToken * 2e18 / 1e18; // Based on total supply and reward rate
        assertApproxEqAbs(totalDistributed, expectedDistributed, 1e5);

        // Validate rewardToken2 (similar checks)
        uint256 earningsBobToken2 =
            multiRewards.earned(bob, address(rewardToken2));
        uint256 earningsCharlieToken2 =
            multiRewards.earned(charlie, address(rewardToken2));
        assertGt(earningsBobToken2, 0);
        assertGt(earningsCharlieToken2, 0);
    }

    function testRewardPerTokenCalculation() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), 1e10);
        vm.stopPrank();

        // Stake tokens
        vm.startPrank(bob);
        baseToken.approve(address(multiRewards), 1e18);
        multiRewards.stake(1e18);
        vm.stopPrank();

        // Simulate time passage
        skip(100);

        // Verify reward per token calculation
        uint256 rewardPerToken =
            multiRewards.rewardPerToken(address(rewardToken));
        assertEq(rewardPerToken, multiRewards.earned(bob, address(rewardToken)));
    }

    function testRewardsStructUpdate() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), 1e10);

        for (uint256 i = 0; i < 5; i++) {
            multiRewards.notifyRewardAmount(address(rewardToken), 1e10);
            skip(60);
            (,, uint256 periodFinish,, uint256 lastUpdateTime,,) =
                multiRewards.rewardData(address(rewardToken));

            assertGt(periodFinish, block.timestamp);
            assertGe(lastUpdateTime, block.timestamp - 60);
        }
        vm.stopPrank();
    }

    function testNoMultiplicationOverflow() public {
        uint256 largeAmount = 1e50;
        baseToken.mint(alice, largeAmount);
        rewardToken.mint(alice, largeAmount);

        vm.startPrank(alice);
        baseToken.approve(address(multiRewards), largeAmount);
        multiRewards.stake(largeAmount);

        rewardToken.approve(address(multiRewards), largeAmount);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), largeAmount);

        skip(60);
        uint256 earnings = multiRewards.earned(alice, address(rewardToken));
        assert(earnings > 0);
        vm.stopPrank();
    }

    function testMultiplicationOverflow() public {
        uint256 largeAmount = 1e70;
        baseToken.mint(alice, largeAmount);
        rewardToken.mint(alice, largeAmount);

        vm.startPrank(alice);
        baseToken.approve(address(multiRewards), largeAmount);
        multiRewards.stake(largeAmount);

        rewardToken.approve(address(multiRewards), largeAmount);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), largeAmount);

        skip(60);
        vm.expectRevert();
        multiRewards.earned(alice, address(rewardToken));
        vm.stopPrank();
    }

    function testNoStakesNoRewards() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(rewardToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(rewardToken), 1e10);
        vm.stopPrank();

        skip(60);
        uint256 rewardPerToken =
            multiRewards.rewardPerToken(address(rewardToken));
        assertEq(rewardPerToken, 0); // No stakes, so reward per token should be 0
    }

    function stakeAndApprove(address user, uint256 amount) internal {
        vm.startPrank(user);
        baseToken.approve(address(multiRewards), amount);
        multiRewards.stake(amount);
        vm.stopPrank();
    }

    function testRevertingTokens() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(missingReturnToken), alice, 3600);
        multiRewards.notifyRewardAmount(address(missingReturnToken), 1e10);
        vm.stopPrank();

        testMultipleRewardEarnings();

        vm.prank(bob);
        multiRewards.getReward();
    }

    function testBombTokens() public {
        vm.startPrank(alice);
        multiRewards.addReward(address(bomb), alice, 3600);
        multiRewards.notifyRewardAmount(address(bomb), 1e10);
        vm.stopPrank();

        testMultipleRewardEarnings();

        vm.prank(bob);
        multiRewards.getReward();
    }

    function testMidPeriodResidualCalculation() public {
        // Setup
        vm.startPrank(alice);
        uint256 rewardDuration = 100; // Small duration to make calculations clearer
        multiRewards.addReward(address(rewardToken), alice, rewardDuration);

        // First notification with amount that will create residual
        uint256 firstAmount = 104; // Will create residual when divided by 100
        multiRewards.notifyRewardAmount(address(rewardToken), firstAmount);

        // Check first residual
        (,,,,,, uint256 firstResidual) =
            multiRewards.rewardData(address(rewardToken));
        assertEq(firstResidual, 4, "First residual should be 4");

        // Move to middle of period
        skip(rewardDuration / 2);

        // Add second amount that will also create residual
        uint256 secondAmount = 53; // Will create residual when combined with leftover (50 + 53 + 4) % D = 7
        multiRewards.notifyRewardAmount(address(rewardToken), secondAmount);
        vm.stopPrank();

        // Get final state
        (,,,,,, uint256 finalResidual) =
            multiRewards.rewardData(address(rewardToken));

        // Verify final residual exists
        assertEq(
            finalResidual, 7, "Should track residual after second notification"
        );
    }
}

contract BombToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(
        address indexed owner, address indexed spender, uint256 amount
    );

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        returns (bool)
    {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        returns (bytes memory)
    {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        assembly {
            return(0, 1000000)
        }
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        returns (bool)
    {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}
