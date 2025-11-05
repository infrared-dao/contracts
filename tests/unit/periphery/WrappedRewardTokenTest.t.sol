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

    function testConstructor() public view {
        assertEq(address(wrapper.asset()), address(asset), "Incorrect asset");
        assertEq(wrapper.name(), "Wrapped USDC", "Incorrect name");
        assertEq(wrapper.symbol(), "wUSDC", "Incorrect symbol");
        assertEq(wrapper.decimals(), 18, "Incorrect decimals");
        assertEq(wrapper.scaling(), SCALING, "Incorrect scaling");
    }

    function testConstructor18Decimals() public {
        MockERC20 asset18 = new MockERC20("Mock ETH", "mETH", 18);
        WrappedRewardToken wrapper18 =
            new WrappedRewardToken(asset18, "Wrapped ETH", "wETH");
        assertEq(wrapper18.scaling(), 1, "Incorrect scaling for 18 decimals");
    }

    function testConstructor0Decimals() public {
        MockERC20 asset0 = new MockERC20("Mock Token", "mTOK", 0);
        WrappedRewardToken wrapper0 =
            new WrappedRewardToken(asset0, "Wrapped Token", "wTOK");
        assertEq(
            wrapper0.scaling(), 10 ** 18, "Incorrect scaling for 0 decimals"
        );
    }

    function testConstructorRevertHighDecimals() public {
        MockERC20 asset19 = new MockERC20("High Decimals", "HD", 19);
        vm.expectRevert("Asset decimals must be <= 18");
        new WrappedRewardToken(asset19, "Wrapped HD", "wHD");
    }

    function testDepositMinimal() public {
        uint256 assets = 1; // Minimal asset unit
        uint256 expectedShares = SCALING;

        vm.prank(user);
        uint256 shares = wrapper.deposit(assets, receiver);

        assertEq(shares, expectedShares, "Incorrect shares for minimal deposit");
        assertEq(
            wrapper.balanceOf(receiver), expectedShares, "Incorrect balance"
        );
        assertEq(
            asset.balanceOf(address(wrapper)), assets, "Incorrect asset balance"
        );
    }

    function testMintZero() public {
        vm.prank(user);
        uint256 assets = wrapper.mint(0, receiver);
        assertEq(assets, 0, "Non-zero assets for zero mint");
        assertEq(
            wrapper.balanceOf(receiver), 0, "Non-zero balance for zero mint"
        );
    }

    function testWithdrawZero() public {
        vm.prank(user);
        uint256 shares = wrapper.withdraw(0, receiver, user);
        assertEq(shares, 0, "Non-zero shares for zero withdraw");
    }

    function testWithdrawWithAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 withdrawAmount = 5 * 10 ** (ASSET_DECIMALS - 1); // 0.5 tokens
        uint256 expectedShares = 5 * 10 ** 17;

        vm.prank(user);
        wrapper.approve(address(this), expectedShares);

        uint256 shares = wrapper.withdraw(withdrawAmount, receiver, user);

        assertEq(shares, expectedShares, "Incorrect shares burned");
        assertEq(
            wrapper.allowance(user, address(this)), 0, "Allowance not decreased"
        );
    }

    function testWithdrawUnlimitedAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 withdrawAmount = 5 * 10 ** (ASSET_DECIMALS - 1); // 0.5 tokens

        vm.prank(user);
        wrapper.approve(address(this), type(uint256).max);

        wrapper.withdraw(withdrawAmount, receiver, user);

        assertEq(
            wrapper.allowance(user, address(this)),
            type(uint256).max,
            "Unlimited allowance decreased"
        );
    }

    function testWithdrawInsufficientAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 withdrawAmount = 5 * 10 ** (ASSET_DECIMALS - 1); // 0.5 tokens
        uint256 expectedShares = 5 * 10 ** 17;

        vm.prank(user);
        wrapper.approve(address(this), expectedShares - 1);

        vm.expectRevert(); // Underflow
        wrapper.withdraw(withdrawAmount, receiver, user);
    }

    function testWithdrawInsufficientBalance() public {
        uint256 withdrawAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.expectRevert();
        vm.prank(user);
        wrapper.withdraw(withdrawAmount, receiver, user);
    }

    function testRedeemDustRevert() public {
        vm.prank(user);
        wrapper.deposit(1, user); // 1 unit asset, SCALING shares

        uint256 dustShares = SCALING - 1;
        vm.expectRevert("ZERO_ASSETS");
        vm.prank(user);
        wrapper.redeem(dustShares, receiver, user);
    }

    function testRedeemWithAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 redeemShares = 5 * 10 ** 17;

        vm.prank(user);
        wrapper.approve(address(this), redeemShares);

        uint256 assets = wrapper.redeem(redeemShares, receiver, user);

        assertEq(assets, 5 * 10 ** (ASSET_DECIMALS - 1), "Incorrect assets");
        assertEq(
            wrapper.allowance(user, address(this)), 0, "Allowance not decreased"
        );
    }

    function testRedeemUnlimitedAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 redeemShares = 5 * 10 ** 17;

        vm.prank(user);
        wrapper.approve(address(this), type(uint256).max);

        wrapper.redeem(redeemShares, receiver, user);

        assertEq(
            wrapper.allowance(user, address(this)),
            type(uint256).max,
            "Unlimited allowance decreased"
        );
    }

    function testRedeemInsufficientAllowance() public {
        uint256 depositAmount = 1 * (10 ** ASSET_DECIMALS);
        vm.prank(user);
        wrapper.deposit(depositAmount, user);

        uint256 redeemShares = 5 * 10 ** 17;

        vm.prank(user);
        wrapper.approve(address(this), redeemShares - 1);

        vm.expectRevert(); // Underflow
        wrapper.redeem(redeemShares, receiver, user);
    }

    function testRedeemInsufficientBalance() public {
        uint256 redeemShares = 1 * 10 ** 18;
        vm.expectRevert();
        vm.prank(user);
        wrapper.redeem(redeemShares, receiver, user);
    }

    function testConvertToShares() public view {
        assertEq(
            wrapper.convertToShares(1),
            SCALING,
            "Incorrect conversion to shares"
        );
        assertEq(
            wrapper.convertToShares(10 ** ASSET_DECIMALS),
            10 ** 18,
            "Incorrect conversion to shares"
        );
    }

    function testConvertToAssets() public view {
        assertEq(
            wrapper.convertToAssets(SCALING),
            1,
            "Incorrect conversion to assets"
        );
        assertEq(
            wrapper.convertToAssets(SCALING - 1),
            0,
            "Incorrect flooring in conversion"
        );
        assertEq(
            wrapper.convertToAssets(10 ** 18),
            10 ** ASSET_DECIMALS,
            "Incorrect conversion to assets"
        );
    }

    function testPreviewDeposit() public view {
        assertEq(
            wrapper.previewDeposit(1), SCALING, "Incorrect preview deposit"
        );
    }

    function testPreviewMint() public view {
        assertEq(wrapper.previewMint(SCALING), 1, "Incorrect preview mint");
        assertEq(
            wrapper.previewMint(SCALING + 1),
            2,
            "Incorrect ceiling in preview mint"
        );
    }

    function testPreviewWithdraw() public view {
        assertEq(
            wrapper.previewWithdraw(1), SCALING, "Incorrect preview withdraw"
        );
    }

    function testPreviewRedeem() public view {
        assertEq(wrapper.previewRedeem(SCALING), 1, "Incorrect preview redeem");
        assertEq(
            wrapper.previewRedeem(SCALING - 1),
            0,
            "Incorrect flooring in preview redeem"
        );
    }

    function testTotalAssets() public {
        assertEq(wrapper.totalAssets(), 0, "Non-zero initial total assets");

        vm.prank(user);
        wrapper.deposit(10 ** ASSET_DECIMALS, user);

        assertEq(
            wrapper.totalAssets(),
            10 ** ASSET_DECIMALS,
            "Incorrect total assets after deposit"
        );
    }

    function testMaxDeposit() public view {
        assertEq(
            wrapper.maxDeposit(address(0)),
            type(uint256).max,
            "Incorrect max deposit"
        );
    }

    function testMaxMint() public view {
        assertEq(
            wrapper.maxMint(address(0)), type(uint256).max, "Incorrect max mint"
        );
    }

    function testMaxWithdraw() public {
        assertEq(wrapper.maxWithdraw(user), 0, "Non-zero initial max withdraw");

        vm.prank(user);
        wrapper.deposit(10 ** ASSET_DECIMALS, user);

        assertEq(
            wrapper.maxWithdraw(user),
            10 ** ASSET_DECIMALS,
            "Incorrect max withdraw after deposit"
        );
    }

    function testMaxRedeem() public {
        assertEq(wrapper.maxRedeem(user), 0, "Non-zero initial max redeem");

        vm.prank(user);
        wrapper.deposit(10 ** ASSET_DECIMALS, user);

        assertEq(
            wrapper.maxRedeem(user),
            10 ** 18,
            "Incorrect max redeem after deposit"
        );
    }

    function testFuzzDepositRedeem(uint256 assets) public {
        assets = bound(assets, 1, 10 ** 30 / SCALING); // Avoid overflow

        asset.mint(user, assets);

        vm.prank(user);
        uint256 shares = wrapper.deposit(assets, user);

        assertEq(shares, assets * SCALING, "Incorrect shares from fuzz deposit");

        vm.prank(user);
        uint256 redeemedAssets = wrapper.redeem(shares, user, user);

        assertEq(redeemedAssets, assets, "Incorrect assets from fuzz redeem");
    }

    function testFuzzMintWithdraw(uint256 shares) public {
        shares = bound(shares, 1, 10 ** 30);

        uint256 assets = wrapper.previewMint(shares);

        asset.mint(user, assets);

        vm.prank(user);
        uint256 depositedAssets = wrapper.mint(shares, user);

        assertEq(depositedAssets, assets, "Incorrect assets from fuzz mint");

        vm.prank(user);
        uint256 withdrawnShares = wrapper.withdraw(assets - 1, user, user);

        assertEq(
            withdrawnShares,
            (assets - 1) * SCALING,
            "Incorrect shares from fuzz withdraw"
        );
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
