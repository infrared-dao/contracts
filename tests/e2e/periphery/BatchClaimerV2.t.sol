// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";

import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";
import {BatchClaimerV2_1} from "src/periphery/BatchClaimerV2_1.sol";

contract BatchClaimerV2Test is Test {
    BatchClaimerV2_1 public multi;
    uint256 blockNumber = 8253019;
    string constant MAINNET_RPC_URL = "https://rpc.berachain.com";
    uint256 mainnetFork;
    InfraredV1_5 internal constant infrared =
        InfraredV1_5(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    address gov = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
    ERC4626 public constant wBYUSD =
        ERC4626(0x334404782aB67b4F6B2A619873E579E971f9AAB7);
    address rewardsFactoryAddr;

    function setUp() public {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, blockNumber);
        multi = new BatchClaimerV2_1();
        vm.prank(gov);
        infrared.grantRole(keccak256("KEEPER_ROLE"), address(multi));
        rewardsFactoryAddr = address(infrared.rewardsFactory());
    }

    function test_ZeroUserRevert() public {
        address[] memory assets = new address[](1);
        assets[0] = address(1); // Dummy asset
        vm.expectRevert(BatchClaimerV2_1.ZeroAddress.selector);
        multi.batchClaim(address(0), assets);
    }

    function test_EmptyAssetsRevert() public {
        address user = makeAddr("user");
        address[] memory assets = new address[](0);
        vm.expectRevert(BatchClaimerV2_1.InvalidInputs.selector);
        multi.batchClaim(user, assets);
    }

    function test_Send() public {
        address user = 0xc84ABde550ae615257067D898a6Cdd235E1857D0;
        address asset = 0x334404782aB67b4F6B2A619873E579E971f9AAB7;
        address underlying = 0x688e72142674041f8f6Af4c808a4045cA1D6aC82;
        address[] memory assets = new address[](1);
        assets[0] = asset;

        uint256 balBefore = ERC20(underlying).balanceOf(user);
        vm.prank(user);
        ERC20(asset).approve(address(multi), type(uint256).max);
        multi.batchClaim(user, assets);
        assertGt(ERC20(underlying).balanceOf(user), balBefore);

        // test dust is skipped
        deal(asset, user, 999999999999);
        balBefore = ERC20(underlying).balanceOf(user);
        multi.batchClaim(user, assets);
        assertEq(ERC20(underlying).balanceOf(user), balBefore);
    }

    function test_BatchMultipleAssets() public {
        address user = makeAddr("userWithMultipleAssets");
        // Use real assets from the fork; assuming some known staking assets
        // For coverage, we can use assets that may or may not have vaults
        address asset1 = 0x334404782aB67b4F6B2A619873E579E971f9AAB7; // wBYUSD
        address asset2 = address(0); // Invalid asset to test no-op branches
        address[] memory assets = new address[](2);
        assets[0] = asset1;
        assets[1] = asset2;

        // Mock some balances or approvals if needed, but since fork, proceed
        // This test focuses on not reverting and looping correctly
        vm.prank(user);
        multi.batchClaim(user, assets);

        // No specific assertions, but coverage for loop and branches where vaults == 0
    }

    function test_NoInfraVaultNoExternal() public {
        address user = makeAddr("userNoVaults");
        address dummyAsset = makeAddr("dummyAsset"); // No vaults registered
        address[] memory assets = new address[](1);
        assets[0] = dummyAsset;

        // Should not revert, just no-op
        vm.prank(user);
        multi.batchClaim(user, assets);
    }
}
