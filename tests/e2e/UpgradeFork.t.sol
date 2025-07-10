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
import {InfraredV1_2} from "src/core/upgrades/InfraredV1_2.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from
    "src/staking/upgrades/InfraredBERAWithdrawor.sol";
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
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

contract UpgradeTest is Test {
    string constant RPC_URL = "https://rpc.berachain.com";

    Infrared public infrared;
    InfraredV1_2 newInfrared;

    InfraredVault internal infraredVault;

    uint256 internal fork;

    address infraredGovernance;
    address user = 0x9AF55da5Aac157d36e9034A045Cc5eFc34A7e2F3;
    address rewardToken = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;
    address keeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;

    // create a cartio fork during setup
    function setUp() public virtual {
        // custom params
        infraredGovernance = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
        infrared = Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));

        // create fork
        fork = vm.createFork(RPC_URL);
        vm.selectFork(fork);

        // roll to a block with signifiant stake and rewards in vaults
        vm.rollFork(1018226);

        // upgrade infrared
        newInfrared = new InfraredV1_2();
        address newInfraredImp = address(newInfrared);
        vm.prank(infraredGovernance);
        (bool success,) = address(infrared).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(newInfrared), ""
            )
        );
        require(success, "Upgrade failed");

        // initialize
        // point at proxy
        newInfrared = InfraredV1_2(payable(address(infrared)));
        address[] memory _stakingTokens = new address[](6);
        _stakingTokens[0] = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b; // IBGT
        _stakingTokens[1] = 0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4; // (50WETH-50WBERA-WEIGHTED)
        _stakingTokens[2] = 0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621; // (USDC.e-HONEY-STABLE)
        _stakingTokens[3] = 0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8; // (BYUSD-HONEY-STABLE)
        _stakingTokens[4] = 0x2c4a603A2aA5596287A06886862dc29d56DbC354; // (50WBERA-50HONEY-WEIGHTED)
        _stakingTokens[5] = 0x38fdD999Fe8783037dB1bBFE465759e312f2d809; // (50WBTC-50WBERA-WEIGHTED)
        vm.prank(infraredGovernance);
        newInfrared.initializeV1_2(_stakingTokens);

        // Verify new implementation
        assertEq(newInfrared.implementation(), newInfraredImp);
    }

    function testState() public virtual {
        assertEq(
            address(newInfrared.ibgt()),
            0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
        );

        assertEq(
            address(newInfrared.collector()),
            0x8d44170e120B80a7E898bFba8cb26B01ad21298C
        );
        assertEq(
            address(newInfrared.distributor()),
            0x1fAD980dfafF71E3Fdd9bef643ab2Ff2BdC4Ccd6
        );

        IInfraredVault _ibgtVault = newInfrared.vaultRegistry(
            0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
        );
        assertTrue(address(_ibgtVault) != address(0));
        assertEq(address(_ibgtVault), address(infrared.ibgtVault()));
        assertEq(address(_ibgtVault.infrared()), address(infrared));

        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;

        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address _rewardToken = _rewardTokens[i];
            assertTrue(infrared.whitelistedRewardTokens(_rewardToken));

            (, uint256 rewardDurationIbgt,,,,,) =
                IMultiRewards(address(_ibgtVault)).rewardData(_rewardToken);
            assertTrue(rewardDurationIbgt > 0);
        }

        assertTrue(
            infrared.hasRole(infrared.DEFAULT_ADMIN_ROLE(), infraredGovernance)
        );
        assertTrue(
            infrared.hasRole(
                infrared.KEEPER_ROLE(),
                0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0
            )
        );
        assertTrue(
            infrared.hasRole(infrared.GOVERNANCE_ROLE(), infraredGovernance)
        );
    }

    function testHarvestOldVault() public virtual {
        address stakingToken = 0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4; // (50WETH-50WBERA-WEIGHTED)
        address oldVaultAddress = 0x79fb77363bb12464ca735B0186B4bd7131089A96;
        IInfraredVault oldVault = IInfraredVault(oldVaultAddress);

        IInfraredVault newVault = infrared.vaultRegistry(stakingToken);

        vm.startPrank(0xD2f19a79b026Fb636A7c300bF5947df113940761);
        IBerachainBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba).approve(
            address(oldVault.rewardsVault()), 100 * 100 ether
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        InfraredBGT ibgt = newInfrared.ibgt();

        uint256 oldVaultBalanceBefore = ibgt.balanceOf(oldVaultAddress);
        uint256 newVaultBalanceBefore = ibgt.balanceOf(address(newVault));
        // more bgt shoud have been accumulated
        vm.startPrank(keeper);
        newInfrared.harvestOldVault(oldVaultAddress, stakingToken);
        vm.stopPrank();

        assertEq(ibgt.balanceOf(oldVaultAddress), oldVaultBalanceBefore);
        assertTrue(ibgt.balanceOf(address(newVault)) > newVaultBalanceBefore);
    }

    IInfraredVault vault =
        IInfraredVault(0x5614314Eef828c747602a629B1d974a3f28fF6E2); // old wbtc / wbera

    function testMultipleExitsSameBlock() public {
        vm.warp(block.timestamp + 1);

        address[] memory tokens = vault.getAllRewardTokens();
        assertGt(tokens.length, 0);
        address user1 = 0xE36219AAAB643b34cdF21c528fffDB434fE91Af0;
        address user2 = 0xb707357cD23682120459E0BdB385401185DE5E3B;

        uint256 earnedUser1 = vault.earned(user1, rewardToken);
        uint256 earnedUser2 = vault.earned(user2, rewardToken);

        assertGt(earnedUser1, 0);
        assertGt(earnedUser2, 0);

        uint256 balInitUser1 = ERC20(rewardToken).balanceOf(user1);
        uint256 balInitUser2 = ERC20(rewardToken).balanceOf(user2);

        // snapshot state to roll back
        uint256 snapshotId = vm.snapshotState();

        // firs execute sequentially, different blocks
        vm.prank(user1);
        vault.exit();

        vm.warp(block.timestamp + 2);

        vm.prank(user2);
        vault.exit();

        uint256 balEndUser1 = ERC20(rewardToken).balanceOf(user1);
        uint256 balEndUser2 = ERC20(rewardToken).balanceOf(user2);

        assertGt(balEndUser1, balInitUser1);
        assertGt(balEndUser2, balInitUser2);

        assertLe(earnedUser1, balEndUser1 - balInitUser1);
        assertLe(earnedUser2, balEndUser2 - balInitUser2);

        //  now revert state and check what happens when exit on same block
        vm.revertToState(snapshotId);

        vm.prank(user1);
        vault.exit();

        vm.prank(user2);
        vault.exit();

        assertEq(ERC20(rewardToken).balanceOf(user1), balEndUser1);
        assertEq(ERC20(rewardToken).balanceOf(user2), 0); // assert bug

        assertEq(vault.earned(user2, rewardToken), 0); // can no longer claim

        // use ClaimHelper to get full rewards before exit to avoid losing rewards here
        // For any cases where this does happen, we need to log and recover when all stakers have left
        // Assume all stakers have left
        vm.warp(block.timestamp + 1000000);
        vm.prank(infraredGovernance);
        newInfrared.recoverERC20FromOldVault(
            address(vault), user2, rewardToken, earnedUser2
        );

        assertEq(ERC20(rewardToken).balanceOf(user2), earnedUser2);
    }
}
