// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MultiRewardsConcrete} from "tests/unit/core/MultiRewards.t.sol";
import {MultiRewardsHandler} from "./MultiRewardsHandler.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";

contract MultiRewardsInvariants is Test {
    MultiRewardsConcrete internal mr;
    MockERC20 internal baseToken;
    MultiRewardsHandler internal handler;

    function setUp() public {
        baseToken = new MockERC20("BaseToken", "BASE", 18);
        mr = new MultiRewardsConcrete(address(baseToken));
        handler = new MultiRewardsHandler(mr, baseToken);
        targetContract(address(handler));
    }

    // Check totalSupply vs. ghost totalStaked
    function invariant_totalSupplyMatches() external view {
        assertEq(
            mr.totalSupply(), handler.totalStaked(), "totalSupply mismatch"
        );
    }

    // Per-user balanceOf vs. handler's userStaked
    function invariant_userBalances() external view {
        address[] memory arr = handler.actorList();
        for (uint256 i; i < arr.length; i++) {
            assertEq(
                mr.balanceOf(arr[i]),
                handler.userStaked(arr[i]),
                "user balance mismatch"
            );
        }
    }

    // Example: residual < duration and periodFinish >= lastUpdateTime
    function invariant_rewardDataChecks() external view {
        uint256 n = mr.rewardTokensLength();
        for (uint256 i; i < n; i++) {
            address rt = mr.rewardTokens(i);
            (, uint256 dur, uint256 finish,, uint256 lu,, uint256 residual) =
                mr.rewardData(rt);

            if (dur > 0) {
                assertLt(residual, dur, "residual >= duration");
            }
            assertGe(finish, lu, "finish < lastUpdateTime");
        }
    }

    // Basic reward conservation: minted >= (claimed + leftover)
    function invariant_rewardConservation() external view {
        uint256 n = mr.rewardTokensLength();
        address[] memory arr = handler.actorList();
        for (uint256 i; i < n; i++) {
            address rt = mr.rewardTokens(i);
            uint256 minted = handler.totalMinted(rt);
            uint256 leftover = MockERC20(rt).balanceOf(address(mr));
            uint256 sumClaims;
            for (uint256 j; j < arr.length; j++) {
                sumClaims += handler.userClaimed(arr[j], rt);
            }
            // This is approximate if we only increment once per claim
            assertGe(minted, sumClaims + leftover, "minted < claimed+leftover");
        }
    }

    // Formal check of notifyRewardAmount math
    function invariant_notifyRewardMath() external view {
        MultiRewardsHandler.NotifyRecord[] memory logs =
            handler.getNotifyRecords();
        for (uint256 i; i < logs.length; i++) {
            MultiRewardsHandler.NotifyRecord memory r = logs[i];

            (, uint256 dur,,,,,) = mr.rewardData(r.rewardToken);
            if (dur == 0) continue;

            // Simulate the contract's logic:
            uint256 combined = r.addedReward + r.residualBefore;
            uint256 newRate;
            uint256 newResidual;

            if (r.timestampBefore >= r.periodFinishBefore) {
                // fresh distribution
                newResidual = combined % dur;
                newRate = (combined - newResidual) / dur;
            } else {
                // extending
                uint256 leftover = (r.periodFinishBefore - r.timestampBefore)
                    * r.rewardRateBefore;
                uint256 total = combined + leftover;
                newResidual = total % dur;
                newRate = (total - newResidual) / dur;
            }

            // Check final
            assertEq(r.rewardRateAfter, newRate, "rewardRate mismatch");
            assertEq(r.residualAfter, newResidual, "residual mismatch");
            assertEq(
                r.lastUpdateTimeAfter,
                r.timestampBefore,
                "lastUpdateTime mismatch"
            );
            assertEq(
                r.periodFinishAfter,
                r.timestampBefore + dur,
                "periodFinish mismatch"
            );
        }
    }
}
