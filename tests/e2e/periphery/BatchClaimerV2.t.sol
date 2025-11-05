// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {BatchClaimerV2_2} from "src/periphery/BatchClaimerV2_2.sol";
import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";

import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "lib/contracts/src/pol/interfaces/IRewardVault.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";

contract BatchClaimerV2Test is Test {
    BatchClaimerV2_2 public multi;
    BatchClaimerV2_2 public multiImpl; // For direct testing without proxy if needed
    uint256 blockNumber = 8253019;
    string constant MAINNET_RPC_URL = "https://rpc.berachain.com";
    uint256 mainnetFork;
    InfraredV1_9 internal constant infrared =
        InfraredV1_9(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    address gov = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
    ERC4626 public constant wBYUSD =
        ERC4626(0x334404782aB67b4F6B2A619873E579E971f9AAB7);
    address rewardsFactoryAddr;
    address wiBGTAddr;

    function setUp() public {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, blockNumber);
        wiBGTAddr = address(
            new WrappedRewardToken(
                ERC20(address(infrared.ibgt())), "Wrapped Infrared BGT", "wiBGT"
            )
        );
        multi = BatchClaimerV2_2(
            setupProxy(
                address(new BatchClaimerV2_2()),
                abi.encodeWithSelector(
                    BatchClaimerV2_2.initialize.selector, gov, wiBGTAddr
                )
            )
        );
        vm.prank(gov);
        infrared.grantRole(keccak256("KEEPER_ROLE"), address(multi));
        rewardsFactoryAddr = address(infrared.rewardsFactory());
    }

    function test_Initialization() public {
        // Test that initialization sets correct values
        assertEq(multi.owner(), gov);
        assertEq(address(multi.rewardsFactory()), rewardsFactoryAddr);
        assertEq(address(multi.wiBGT()), wiBGTAddr);

        // Test re-initialization reverts
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        multi.initialize(gov, wiBGTAddr);
    }

    function test_ConstructorDisablesInitializers() public {
        multiImpl = new BatchClaimerV2_2();
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        multiImpl.initialize(gov, wiBGTAddr);
    }

    function test_Version() public view {
        assertEq(multi.version(), "2.2.0");
    }

    function test_UpdateRewardsFactory() public {
        address newFactory = makeAddr("newFactory");
        // Non-owner cannot update
        vm.expectRevert();
        multi.updateRewardsFactory(newFactory);

        // Owner can update
        vm.prank(gov);
        multi.updateRewardsFactory(newFactory);
        assertEq(address(multi.rewardsFactory()), newFactory);

        // Revert on zero address
        vm.prank(gov);
        vm.expectRevert(BatchClaimerV2_2.ZeroAddress.selector);
        multi.updateRewardsFactory(address(0));
    }

    function test_AuthorizeUpgrade() public {
        address newImpl = address(new BatchClaimerV2_2());

        // Non-owner cannot upgrade
        vm.expectRevert();
        multi.upgradeToAndCall(newImpl, "");

        // Owner can upgrade
        vm.prank(gov);
        multi.upgradeToAndCall(newImpl, "");
        // Verify implementation updated (using storage slot for UUPS proxy)
        bytes32 implSlot =
            bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        assertEq(
            address(uint160(uint256(vm.load(address(multi), implSlot)))),
            newImpl
        );
    }

    function test_Send_wiBGT_Unwrap() public {
        address user = makeAddr("userWiBGT");
        ERC4626 wiBGT = ERC4626(wiBGTAddr);
        address underlying = address(infrared.ibgt()); // Assuming iBGT is the underlying

        // Deal some wiBGT to user
        deal(wiBGTAddr, user, 1e18);
        deal(address(wiBGT.asset()), wiBGTAddr, 1e18);
        uint256 balBefore = ERC20(underlying).balanceOf(user);

        // No approval, should not unwrap
        address[] memory assets = new address[](1);
        assets[0] = address(1); // Dummy to trigger loop
        multi.batchClaim(user, assets);
        assertEq(ERC20(underlying).balanceOf(user), balBefore);

        // With approval, should unwrap if preview >0
        vm.prank(user);
        wiBGT.approve(address(multi), type(uint256).max);
        // Mock previewRedeem to return >0 (since it's a wrapper, assume it does)

        multi.batchClaim(user, assets);
    }

    function test_ZeroUserRevert() public {
        address[] memory assets = new address[](1);
        assets[0] = address(1); // Dummy asset
        vm.expectRevert(BatchClaimerV2_2.ZeroAddress.selector);
        multi.batchClaim(address(0), assets);
    }

    function test_EmptyAssetsRevert() public {
        address user = makeAddr("user");
        address[] memory assets = new address[](0);
        vm.expectRevert(BatchClaimerV2_2.InvalidInputs.selector);
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

    function test_InfraVaultClaim() public {
        address user = makeAddr("userInfra");
        address stakingAsset = address(new MockERC20("tmp", "tmp", 18));

        // Mock infrared.vaultRegistry to return a vault
        address mockVault = address(infrared.registerVault(stakingAsset));
        vm.mockCall(
            address(infrared),
            abi.encodeWithSelector(
                InfraredV1_9.vaultRegistry.selector, stakingAsset
            ),
            abi.encode(IInfraredVault(mockVault))
        );

        // Expect call to getRewardForUser
        vm.expectCall(
            mockVault,
            abi.encodeWithSelector(
                IMultiRewards.getRewardForUser.selector, user
            )
        );

        address[] memory assets = new address[](1);
        assets[0] = stakingAsset;
        multi.batchClaim(user, assets);
    }

    // function test_ExternalVaultClaim() public {
    //     address user = makeAddr("userExternal");
    //     address stakingAsset = makeAddr("stakingAssetWithExternal");

    //     // Mock no infra vault
    //     vm.mockCall(
    //         address(infrared),
    //         abi.encodeWithSelector(InfraredV1_9.vaultRegistry.selector, stakingAsset),
    //         abi.encode(IInfraredVault(address(0)))
    //     );

    //     // Mock rewardsFactory.getVault
    //     address mockVault = makeAddr("mockRewardsVault");
    //     vm.mockCall(
    //         rewardsFactoryAddr,
    //         abi.encodeWithSelector(IBerachainRewardsVaultFactory.getVault.selector, stakingAsset),
    //         abi.encode(IBerachainRewardsVault(mockVault))
    //     );

    //     // Mock vault.operator(user) == address(infrared)
    //     vm.mockCall(
    //         mockVault,
    //         abi.encodeWithSelector(IBerachainRewardsVault.operator.selector, user),
    //         abi.encode(address(infrared))
    //     );

    //     // Mock infrared.externalVaultRewards >0
    //     vm.mockCall(
    //         address(infrared),
    //         abi.encodeWithSelector(InfraredV1_9.externalVaultRewards.selector, stakingAsset, user),
    //         abi.encode(1)
    //     );

    //     // Expect call to claimExternalVaultRewards
    //     vm.expectCall(
    //         address(infrared),
    //         abi.encodeWithSelector(InfraredV1_9.claimExternalVaultRewards.selector, stakingAsset, user)
    //     );

    //     address[] memory assets = new address[](1);
    //     assets[0] = stakingAsset;
    //     multi.batchClaim(user, assets);
    // }

    function test_ExternalVaultNoClaimIfNoRewards() public {
        address user = makeAddr("userExternalNoRewards");
        address stakingAsset = makeAddr("stakingAssetWithExternalNoRewards");

        // Mock no infra vault
        vm.mockCall(
            address(infrared),
            abi.encodeWithSelector(
                InfraredV1_9.vaultRegistry.selector, stakingAsset
            ),
            abi.encode(IInfraredVault(address(0)))
        );

        // Mock rewardsFactory.getVault
        address mockVault = makeAddr("mockRewardsVault");
        vm.mockCall(
            rewardsFactoryAddr,
            abi.encodeWithSelector(
                IBerachainRewardsVaultFactory.getVault.selector, stakingAsset
            ),
            abi.encode(IBerachainRewardsVault(mockVault))
        );

        // Mock vault.operator(user) == address(infrared)
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(
                IBerachainRewardsVault.operator.selector, user
            ),
            abi.encode(address(infrared))
        );

        // Mock infrared.externalVaultRewards ==0
        vm.mockCall(
            address(infrared),
            abi.encodeWithSelector(
                InfraredV1_9.externalVaultRewards.selector, stakingAsset, user
            ),
            abi.encode(0)
        );

        // No expectCall to claimExternalVaultRewards
        vm.expectCall(
            address(infrared),
            abi.encodeWithSelector(
                InfraredV1_9.claimExternalVaultRewards.selector,
                stakingAsset,
                user
            ),
            0
        );

        address[] memory assets = new address[](1);
        assets[0] = stakingAsset;
        multi.batchClaim(user, assets);
    }

    function test_UnwrapSkippedIfNoAllowance() public {
        address user = makeAddr("userNoAllowance");
        // ERC4626 wiBGT = ERC4626(wiBGTAddr);

        // Deal some wiBGT
        deal(wiBGTAddr, user, 1e18);

        // Mock previewRedeem >0
        vm.mockCall(
            wiBGTAddr,
            abi.encodeWithSelector(ERC4626.previewRedeem.selector, 1e18),
            abi.encode(1e18)
        );

        // No approval, expect no redeem call
        vm.expectCall(
            wiBGTAddr,
            abi.encodeWithSelector(ERC4626.redeem.selector, 1e18, user, user),
            0
        );

        address[] memory assets = new address[](1);
        assets[0] = address(1); // Dummy
        multi.batchClaim(user, assets);
    }

    function test_UnwrapSkippedIfPreviewZero() public {
        address user = makeAddr("userPreviewZero");
        ERC4626 wiBGT = ERC4626(wiBGTAddr);

        // Deal some wiBGT
        deal(wiBGTAddr, user, 1e18);

        // Approve
        vm.prank(user);
        wiBGT.approve(address(multi), type(uint256).max);

        // Mock previewRedeem ==0
        vm.mockCall(
            wiBGTAddr,
            abi.encodeWithSelector(ERC4626.previewRedeem.selector, 1e18),
            abi.encode(0)
        );

        // Expect no redeem call
        vm.expectCall(
            wiBGTAddr,
            abi.encodeWithSelector(ERC4626.redeem.selector, 1e18, user, user),
            0
        );

        address[] memory assets = new address[](1);
        assets[0] = address(1); // Dummy
        multi.batchClaim(user, assets);
    }

    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }
}
