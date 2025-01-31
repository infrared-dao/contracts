// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MultiRewardsConcrete} from "tests/unit/core/MultiRewards.t.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";

contract MultiRewardsHandler is Test {
    MultiRewardsConcrete public mr;
    MockERC20 public stakeToken;

    address[] public actors;
    address public distributor;

    // Track user staked amounts for each actor
    mapping(address => uint256) public userStaked;
    uint256 public totalStaked;

    // Track total minted rewards per token
    mapping(address => uint256) public totalMinted;
    // Approx user claims (optional approach)
    mapping(address => mapping(address => uint256)) public userClaimed;

    // For a formal check on notifyRewardAmount math
    struct NotifyRecord {
        address rewardToken;
        // Pre-state
        uint256 rewardRateBefore;
        uint256 periodFinishBefore;
        uint256 lastUpdateTimeBefore;
        uint256 residualBefore;
        uint256 timestampBefore;
        // Input
        uint256 addedReward;
        // Post-state
        uint256 rewardRateAfter;
        uint256 periodFinishAfter;
        uint256 lastUpdateTimeAfter;
        uint256 residualAfter;
    }

    NotifyRecord[] public notifyRecords;

    constructor(MultiRewardsConcrete _mr, MockERC20 _stakeToken) {
        mr = _mr;
        stakeToken = _stakeToken;

        // Example actors
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));

        // Give them stake tokens
        for (uint256 i; i < actors.length; i++) {
            stakeToken.mint(actors[i], 1_000_000 ether);
        }

        // Designate a distributor
        distributor = address(0xD159B);
    }

    function stake(uint256 actorIdx, uint256 amount) public {
        address user = _pickActor(actorIdx);
        amount = bound(amount, 0, stakeToken.balanceOf(user));
        vm.startPrank(user);
        stakeToken.approve(address(mr), amount);
        try mr.stake(amount) {
            userStaked[user] += amount;
            totalStaked += amount;
        } catch {}
        vm.stopPrank();
    }

    function withdraw(uint256 actorIdx, uint256 amount) public {
        address user = _pickActor(actorIdx);
        uint256 bal = userStaked[user];
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.startPrank(user);
        try mr.withdraw(amount) {
            userStaked[user] -= amount;
            totalStaked -= amount;
        } catch {}
        vm.stopPrank();
    }

    function getReward(uint256 actorIdx) public {
        address user = _pickActor(actorIdx);
        vm.startPrank(user);
        try mr.getReward() {
            // Increment a simple "claim" counter
            // For real totals, track user balances pre/post
            // or rely on an onReward hook
            // E.g. assume a single reward token for demo
            // or loop if multiple tokens
            userClaimed[user][address(stakeToken)]++;
        } catch {}
        vm.stopPrank();
    }

    function notifyRewardAmount(address rToken, uint256 reward) public {
        vm.startPrank(distributor);

        // Pre-state
        (
            ,
            ,
            uint256 pfBefore,
            uint256 rrBefore,
            uint256 luBefore,
            ,
            uint256 resBefore
        ) = mr.rewardData(rToken);

        uint256 timeBefore = block.timestamp;

        // Mint + approve
        MockERC20(rToken).mint(distributor, reward);
        MockERC20(rToken).approve(address(mr), reward);

        try mr.notifyRewardAmount(rToken, reward) {
            // Post-state
            (
                ,
                ,
                uint256 pfAfter,
                uint256 rrAfter,
                uint256 luAfter,
                ,
                uint256 resAfter
            ) = mr.rewardData(rToken);

            totalMinted[rToken] += reward;

            notifyRecords.push(
                NotifyRecord({
                    rewardToken: rToken,
                    rewardRateBefore: rrBefore,
                    periodFinishBefore: pfBefore,
                    lastUpdateTimeBefore: luBefore,
                    residualBefore: resBefore,
                    timestampBefore: timeBefore,
                    addedReward: reward,
                    rewardRateAfter: rrAfter,
                    periodFinishAfter: pfAfter,
                    lastUpdateTimeAfter: luAfter,
                    residualAfter: resAfter
                })
            );
        } catch {}
        vm.stopPrank();
    }

    function getNotifyRecords() external view returns (NotifyRecord[] memory) {
        return notifyRecords;
    }

    function actorList() external view returns (address[] memory) {
        return actors;
    }

    function _pickActor(uint256 idx) internal view returns (address) {
        return actors[bound(idx, 0, actors.length - 1)];
    }
}
