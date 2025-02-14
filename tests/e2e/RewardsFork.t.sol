// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import {BeraChef} from "@berachain/pol/rewards/BeraChef.sol";
import {IBeaconDeposit as IBerachainBeaconDeposit} from
    "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {Distributor as BerachainDistributor} from
    "@berachain/pol/rewards/Distributor.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";

import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IBerachainBGTStaker} from "src/interfaces/IBerachainBGTStaker.sol";
import {IFeeCollector as IBerachainFeeCollector} from
    "@berachain/pol/interfaces/IFeeCollector.sol";

import {Infrared} from "src/core/Infrared.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";
import {IWBERA} from "src/interfaces/IWBERA.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {InfraredDeployer} from "script/InfraredDeployer.s.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";

contract ForkTest is Test {
    string constant RPC_URL = "https://rpc.berachain.com";

    Infrared public infrared;

    InfraredVault internal infraredVault;

    uint256 internal fork;

    address infraredGovernance;
    address user = 0x9AF55da5Aac157d36e9034A045Cc5eFc34A7e2F3;
    address rewardToken = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;

    // create a cartio fork during setup
    function setUp() public virtual {
        // custom params
        infraredGovernance = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
        infrared = Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));

        // create fork
        fork = vm.createFork(RPC_URL);
        vm.selectFork(fork);

        // retreive addersses
        infraredVault =
            InfraredVault(0x79fb77363bb12464ca735B0186B4bd7131089A96);
    }

    function test_recreateStake_with_fix() public {
        vm.selectFork(fork);

        vm.rollFork(1018226);

        vm.prank(address(infrared));
        bytes memory code = address(
            new InfraredVault(0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4, 600)
        ).code;
        address targetAddr = 0x79fb77363bb12464ca735B0186B4bd7131089A96;
        vm.etch(targetAddr, code);

        // vm.prank(user);
        // infraredVault.stake(1);

        // vm.roll(block.number + 1 );
        // vm.warp(block.timestamp + 2);

        // vm.prank(infraredGovernance);
        // infrared.updateRewardsDurationForVault(0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4, 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b, 3600);

        infrared.harvestVault(0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4);

        vm.prank(user);
        infraredVault.stake(133693314717444387122);

        (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        ) = infraredVault.rewardData(rewardToken);

        uint256 rewardPerToken = infraredVault.rewardPerToken(rewardToken);

        console.log("rewardPerToken", rewardPerToken);

        console.log("rewardsAccount", infraredVault.rewards(user, rewardToken));
        console.log("rewardRate: ", rewardRate);
        console.log("periodFinish", periodFinish);
        console.log(block.timestamp, periodFinish);
        console.log(infraredVault.earned(user, rewardToken));

        uint256 userRewardPerTokenPaid =
            infraredVault.userRewardPerTokenPaid(user, rewardToken);
        uint256 balance = infraredVault.balanceOf(user);
        uint256 rewards = infraredVault.rewards(user, rewardToken);

        console.log("!!!balance!!!", balance);
        console.log("!!!rewardPerToken!!!", rewardPerToken);
        console.log("!!!userRewardPerTokenPaid!!!", userRewardPerTokenPaid);
        console.log("!!!rewards!!!", rewards);

        uint256 earned = (balance * (rewardPerToken - userRewardPerTokenPaid))
            / 1e18 + rewards;

        console.log("!!!earned!!!", earned);
    }

    function test_recreateStake() public {
        vm.selectFork(fork);

        vm.rollFork(1018226);

        // vm.prank(user);
        // infraredVault.stake(1);

        // vm.roll(block.number + 1 );
        // vm.warp(block.timestamp + 2);

        // vm.prank(infraredGovernance);
        // infrared.updateRewardsDurationForVault(0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4, 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b, 3600);

        infrared.harvestVault(0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4);

        vm.prank(user);
        infraredVault.stake(133693314717444387122);

        (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        ) = infraredVault.rewardData(rewardToken);

        uint256 rewardPerToken = infraredVault.rewardPerToken(rewardToken);

        console.log("rewardPerToken", rewardPerToken);

        console.log("rewardsAccount", infraredVault.rewards(user, rewardToken));
        console.log("rewardRate: ", rewardRate);
        console.log("periodFinish", periodFinish);
        console.log(block.timestamp, periodFinish);
        console.log("earned", infraredVault.earned(user, rewardToken));

        uint256 userRewardPerTokenPaid =
            infraredVault.userRewardPerTokenPaid(user, rewardToken);
        uint256 balance = infraredVault.balanceOf(user);
        uint256 rewards = infraredVault.rewards(user, rewardToken);

        console.log("!!!balance!!!", balance);
        console.log("!!!rewardPerToken!!!", rewardPerToken);
        console.log("!!!userRewardPerTokenPaid!!!", userRewardPerTokenPaid);
        console.log("!!!rewards!!!", rewards);

        uint256 earned = (balance * (rewardPerToken - userRewardPerTokenPaid))
            / 1e18 + rewards;

        console.log("!!!earned!!!", earned);
    }
}
