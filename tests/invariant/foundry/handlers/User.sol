// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "src/core/InfraredBGT.sol";
import "src/core/InfraredVault.sol";
import "src/depreciated/core/Infrared.sol";

import "./Keeper.sol";

import {MockERC20} from "../../../unit/mocks/MockERC20.sol";

contract User is Test {
    Infrared public infrared;
    Keeper public keeper;

    address[] public users;

    uint256 public totalStaked;
    uint256 public totalWithdrawn;

    mapping(address => InfraredVault[]) public userVaults;
    mapping(address => mapping(InfraredVault => uint256)) public userVaultStaked;
    mapping(address => mapping(InfraredVault => uint256)) public
        userVaultClaimed;

    constructor(Infrared _infrared, Keeper _keeper) {
        infrared = _infrared;
        keeper = _keeper;

        // create a number of users
        users.push(address(0x1));
        users.push(address(0x2));
        users.push(address(0x3));
        users.push(address(0x4));
        users.push(address(0x5));
        users.push(address(0x6));
        users.push(address(0x7));
        users.push(address(0x8));
        users.push(address(0x9));
        users.push(address(0x10));
    }

    function deposit(uint256 amount, uint8 vaultIndex, uint8 userIndex)
        public
    {
        // pick a user either user1, user2, or user3
        amount = bound(amount, 0, type(uint128).max - totalStaked);
        uint256 maxVaultIndex = keeper.getVaults().length;

        vaultIndex = uint8(bound(vaultIndex, 0, maxVaultIndex - 1));
        userIndex = uint8(bound(userIndex, 0, users.length - 1));

        address user = users[userIndex];

        InfraredVault vault =
            InfraredVault(address(keeper.getVaults()[vaultIndex]));
        address stakingToken = address(vault.stakingToken());

        deal(address(stakingToken), user, amount);

        totalStaked += amount;
        userVaultStaked[user][vault] += amount;
        userVaults[user].push(vault);

        vm.startPrank(user);
        MockERC20(address(stakingToken)).approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();

        // jump in time
        vm.warp(block.timestamp + 10 days);
    }

    function deposit2(
        uint256 amount,
        uint8 vaultIndex,
        uint8 userIndex // increase the chances of calling deposit
    ) public {
        // pick a user either user1, user2, or user3
        amount = bound(amount, 0, type(uint128).max - totalStaked);
        uint256 maxVaultIndex = keeper.getVaults().length;

        vaultIndex = uint8(bound(vaultIndex, 0, maxVaultIndex - 1));
        userIndex = uint8(bound(userIndex, 0, users.length - 1));

        address user = users[userIndex];

        InfraredVault vault =
            InfraredVault(address(keeper.getVaults()[vaultIndex]));
        address stakingToken = address(vault.stakingToken());

        deal(address(stakingToken), user, amount);

        totalStaked += amount;
        userVaultStaked[user][vault] += amount;
        userVaults[user].push(vault);

        vm.startPrank(user);
        MockERC20(address(stakingToken)).approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();

        // jump in time
        vm.warp(block.timestamp + 10 days);
    }

    function withdraw(uint256 amount, uint8 userIndex, uint8 vaultIndex)
        public
    {
        userIndex = uint8(bound(userIndex, 0, users.length - 1));

        address user = users[userIndex];

        vaultIndex = uint8(bound(vaultIndex, 0, userVaults[user].length - 1));

        InfraredVault vault = userVaults[user][vaultIndex];

        amount = bound(amount, 0, userVaultStaked[user][vault]);

        if (amount == 0) {
            return;
        }

        userVaultStaked[user][vault] -= amount;

        vm.startPrank(user);
        vault.withdraw(amount);
        vm.stopPrank();
    }

    function claim(uint8 userIndex, uint8 vaultIndex) public {
        userIndex = uint8(bound(userIndex, 0, users.length - 1));

        address user = users[userIndex];

        vaultIndex = uint8(bound(vaultIndex, 0, userVaults[user].length - 1));

        vm.warp(block.timestamp + 1 days);

        InfraredVault vault = userVaults[user][vaultIndex];

        vm.startPrank(user);
        uint256 reward = vault.earned(user, address(infrared.ibgt()));
        userVaultClaimed[user][vault] += reward;
        vault.getReward();
        vm.stopPrank();
    }

    function getUsers() public view returns (address[] memory) {
        return users;
    }
}
