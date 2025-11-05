// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "src/core/InfraredBGT.sol";
import "src/core/InfraredVault.sol";
import "src/depreciated/core/Infrared.sol";

import "src/core/MultiRewards.sol";

import "forge-std/Test.sol";

import {MockERC20} from "tests/unit/mocks/MockERC20.sol";

import "@berachain/pol/rewards/RewardVaultFactory.sol";

contract Keeper is Test {
    Infrared public infrared;
    RewardVaultFactory public rewardsFactory;
    address public keeper;

    uint256 public totalBgtRewards;

    IInfraredVault[] public vaults;

    address ibgt;

    constructor(
        Infrared _infrared,
        address _keeper,
        RewardVaultFactory _rewardsFactory
    ) {
        // Initialize mock assets
        infrared = _infrared;
        keeper = _keeper;
        rewardsFactory = _rewardsFactory;
        ibgt = address(infrared.ibgt());
        vm.deal(keeper, type(uint256).max);
        vm.deal(address(this), type(uint256).max);
    }

    function registerVault() public {
        if (vaults.length == 5 || vaults.length > 5) {
            return;
        }

        vm.roll(block.number + 10);

        MockERC20 stakingAsset = new MockERC20("MockPool", "MP", 18);

        rewardsFactory.createRewardVault(address(stakingAsset));

        vm.startPrank(keeper);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = ibgt;
        IInfraredVault v = infrared.registerVault(address(stakingAsset));
        vm.stopPrank();

        // optional - stake 1 ether in the vault
        deal(address(stakingAsset), address(this), 1 ether);
        MockERC20(address(stakingAsset)).approve(address(v), 1 ether);
        InfraredVault(address(v)).stake(1 ether);

        vaults.push(v);
    }

    function harvestVault(uint256 bgtReward, uint256 vaultIndex) public {
        if (vaults.length == 0) {
            return;
        }
        bgtReward = bound(
            bgtReward, 0, ((type(uint256).max / 1e48) - (totalBgtRewards + 1))
        );
        if (bgtReward == 0) {
            return;
        }
        vaultIndex = uint8(bound(vaultIndex, 0, vaults.length - 1)); // bound to vaults.length which should be less than uint8.max

        address vault = address(vaults[uint256(vaultIndex)]);
        address stakingAsset = address(InfraredVault(vault).stakingToken());

        totalBgtRewards += bgtReward;

        // rewardsFactory.increaseRewardsForVault(stakingAsset, bgtReward);

        vm.warp(block.timestamp + 10 days);

        // impersonate keeper and call harvestVault
        vm.prank(keeper);
        infrared.harvestVault(stakingAsset);
        vm.stopPrank();
    }

    function getVaults() public view returns (IInfraredVault[] memory) {
        return vaults;
    }
}
