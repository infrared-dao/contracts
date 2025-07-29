// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals)
        ERC20(name, symbol, decimals)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WrappedRewardTokenTest is Test {
    WrappedRewardToken public wrapper;
    MockERC20 public asset;

    address public user = address(0x1234);
    address public receiver = address(0x5678);

    uint8 constant ASSET_DECIMALS = 6;
    uint256 constant SCALING = 10 ** (18 - ASSET_DECIMALS); // 10^12 for 6 decimals

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", ASSET_DECIMALS);
        wrapper = new WrappedRewardToken(asset, "Wrapped USDC", "wUSDC");

        // Mint initial assets to user
        asset.mint(user, 1_000_000 * (10 ** ASSET_DECIMALS)); // 1M whole tokens
        vm.prank(user);
        asset.approve(address(wrapper), type(uint256).max);
    }

    function testDeposit() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS); // 1 whole token (10^6 units)
        uint256 expectedShares = 1 * 10 ** 18; // 1 * 10^18 shares

        vm.prank(user);
        uint256 shares = wrapper.deposit(depositAmount, receiver);

        assertEq(shares, expectedShares, "Incorrect shares minted");
        assertEq(
            wrapper.balanceOf(receiver),
            expectedShares,
            "Incorrect receiver balance"
        );
        assertEq(
            asset.balanceOf(address(wrapper)),
            depositAmount,
            "Incorrect vault asset balance"
        );
        assertEq(
            asset.balanceOf(user),
            1_000_000 * (10 ** ASSET_DECIMALS) - depositAmount,
            "Incorrect user asset balance"
        );
    }

    function testMint() public {
        uint256 mintShares = 1 * 10 ** 18; // 1 whole share
        uint256 expectedAssets = 1 * (10 ** ASSET_DECIMALS); // 1 whole token (10^6 units)

        vm.prank(user);
        uint256 assets = wrapper.mint(mintShares, receiver);

        assertEq(assets, expectedAssets, "Incorrect assets deposited");
        assertEq(
            wrapper.balanceOf(receiver),
            mintShares,
            "Incorrect receiver balance"
        );
        assertEq(
            asset.balanceOf(address(wrapper)),
            expectedAssets,
            "Incorrect vault asset balance"
        );
        assertEq(
            asset.balanceOf(user),
            1_000_000 * (10 ** ASSET_DECIMALS) - expectedAssets,
            "Incorrect user asset balance"
        );
    }

    function testMintWithCeiling() public {
        uint256 mintShares = 10 ** 18 + 1; // Slightly more than 1 whole share
        uint256 expectedAssets = 1 * (10 ** ASSET_DECIMALS) + 1; // Ceils to 1 whole token + 1 unit

        vm.prank(user);
        uint256 assets = wrapper.mint(mintShares, receiver);

        assertEq(assets, expectedAssets, "Incorrect assets for ceiled mint");
        assertEq(
            wrapper.balanceOf(receiver),
            mintShares,
            "Incorrect receiver balance"
        );
    }

    function testWithdraw() public {
        // First deposit
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS); // 1 whole token
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 withdrawAmount = 1 * (10 ** ASSET_DECIMALS); // 1 whole token
        uint256 expectedShares = 1 * 10 ** 18;

        vm.prank(user);
        uint256 shares = wrapper.withdraw(withdrawAmount, receiver, user);

        assertEq(shares, expectedShares, "Incorrect shares burned");
        assertEq(
            wrapper.balanceOf(user), 0, "Incorrect owner balance after withdraw"
        );
        assertEq(
            asset.balanceOf(receiver),
            withdrawAmount,
            "Incorrect receiver asset balance"
        );
        assertEq(
            asset.balanceOf(address(wrapper)),
            0,
            "Incorrect vault asset balance after withdraw"
        );
    }

    function testRedeem() public {
        // First deposit
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS); // 1 whole token
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 redeemShares = 1 * 10 ** 18; // 1 whole share
        uint256 expectedAssets = 1 * (10 ** ASSET_DECIMALS);

        vm.prank(user);
        uint256 assets = wrapper.redeem(redeemShares, receiver, user);

        assertEq(assets, expectedAssets, "Incorrect assets redeemed");
        assertEq(
            wrapper.balanceOf(user), 0, "Incorrect owner balance after redeem"
        );
        assertEq(
            asset.balanceOf(receiver),
            expectedAssets,
            "Incorrect receiver asset balance"
        );
        assertEq(
            asset.balanceOf(address(wrapper)),
            0,
            "Incorrect vault asset balance after redeem"
        );
    }

    function testRedeemWithDust() public {
        // Deposit 1 whole token
        vm.prank(user);
        wrapper.deposit(1 * (10 ** ASSET_DECIMALS), user);

        // Redeem a fractional amount
        uint256 redeemShares = 5 * 10 ** 17; // 0.5 * 10^18 shares
        uint256 expectedAssets = 5 * 10 ** (ASSET_DECIMALS - 1); // 0.5 whole tokens (5 * 10^5 units)

        vm.prank(user);
        uint256 assets = wrapper.redeem(redeemShares, receiver, user);

        assertEq(
            assets, expectedAssets, "Incorrect assets for fractional redeem"
        );
        assertEq(
            wrapper.balanceOf(user),
            10 ** 18 - 5 * 10 ** 17,
            "Incorrect remaining balance (dust)"
        );
        assertEq(
            asset.balanceOf(address(wrapper)),
            10 ** ASSET_DECIMALS - expectedAssets,
            "Incorrect remaining vault assets"
        );
    }

    function testDonationNoInflation() public {
        // Deposit 1 whole token
        vm.prank(user);
        wrapper.deposit(1 * (10 ** ASSET_DECIMALS), user);

        // Simulate donation
        uint256 donation = 1 * (10 ** ASSET_DECIMALS);
        asset.mint(address(wrapper), donation); // Direct mint to vault (simulates donation)

        // Check conversion rates unchanged
        assertEq(
            wrapper.convertToShares(1 * (10 ** ASSET_DECIMALS)),
            10 ** 18,
            "Inflation in convertToShares"
        );
        assertEq(
            wrapper.convertToAssets(10 ** 18),
            1 * (10 ** ASSET_DECIMALS),
            "Inflation in convertToAssets"
        );

        // New deposit should be unaffected
        vm.prank(user);
        wrapper.deposit(1 * (10 ** ASSET_DECIMALS), receiver);

        assertEq(
            wrapper.balanceOf(receiver),
            10 ** 18,
            "Diluted shares for new depositor"
        );

        // Original user redeems - should get only their amount, not donation
        vm.prank(user);
        wrapper.redeem(10 ** 18, user, user);

        assertEq(
            asset.balanceOf(user),
            (1_000_000 * (10 ** ASSET_DECIMALS) - 2 * (10 ** ASSET_DECIMALS))
                + 1 * (10 ** ASSET_DECIMALS),
            "Unexpected redemption amount"
        );
        // Donation remains in vault
        assertEq(
            asset.balanceOf(address(wrapper)),
            1 * (10 ** ASSET_DECIMALS) + donation,
            "Donation affected"
        );
    }

    function testZeroDeposit() public {
        vm.expectRevert("ZERO_SHARES");
        vm.prank(user);
        wrapper.deposit(0, receiver);
    }

    function testZeroRedeem() public {
        vm.expectRevert("ZERO_ASSETS");
        vm.prank(user);
        wrapper.redeem(0, receiver, user);
    }
}
