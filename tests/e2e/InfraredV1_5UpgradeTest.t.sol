// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {
    UUPSUpgradeable,
    ERC1967Utils
} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";
import {BribeCollectorV1_3} from "src/core/upgrades/BribeCollectorV1_3.sol";
import {IBribeCollector} from "src/interfaces/IBribeCollector.sol";
import {HelperForkTest} from "./HelperForkTest.t.sol";

contract InfraredV1_5UpgradeTest is HelperForkTest {
    InfraredV1_5 public implementation;
    BribeCollectorV1_3 public bribeCollectorImplementation;
    address public user;

    // Test tokens for bribe claiming
    address public feeToken;
    address public payoutToken;

    function setUp() public override {
        // Set custom parameters
        admin = address(this);
        infraredGovernance = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
        keeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;
        user = address(0x1234);

        // Load validator data from fixtures
        _loadValidatorData();

        // Create and select mainnet fork with specified block number
        // mainnetFork = vm.createFork(MAINNET_RPC_URL, 4143138);
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();

        // Deploy new implementations
        implementation = new InfraredV1_5();
        bribeCollectorImplementation = new BribeCollectorV1_3();

        // Store test tokens
        IBribeCollector collectorInterface = IBribeCollector(address(collector));
        payoutToken = collectorInterface.payoutToken();
        feeToken = address(honey);
    }

    function testUpgradeBribeCollectorToV1_3() public {
        // Setup: Prepare tokens for testing claim permissions
        uint256 initialFeeAmount = 1 ether;
        deal(feeToken, address(collector), initialFeeAmount);

        uint256 payoutAmount =
            IBribeCollector(address(collector)).payoutAmount();

        // Fund user and keeper with WBERA payout token
        deal(payoutToken, user, payoutAmount);
        deal(payoutToken, keeper, payoutAmount);

        // Upgrade BribeCollector to v1.3
        vm.startPrank(infraredGovernance);
        (bool success,) = address(collector).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(bribeCollectorImplementation),
                ""
            )
        );
        require(success, "Upgrade BribeCollector failed");

        // Grant KEEPER_ROLE to the keeper address
        (success,) = address(collector).call(
            abi.encodeWithSignature(
                "grantRole(bytes32,address)", keccak256("KEEPER_ROLE"), keeper
            )
        );
        require(success, "Grant KEEPER_ROLE failed");
        vm.stopPrank();

        // Test claimFees permissions

        // 1. User without KEEPER_ROLE should not be able to claim fees
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = feeToken;
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = initialFeeAmount / 2;

        vm.startPrank(user);
        ERC20(payoutToken).approve(address(collector), payoutAmount);
        vm.expectRevert(); // Should revert due to missing KEEPER_ROLE
        IBribeCollector(address(collector)).claimFees(
            user, feeTokens, feeAmounts
        );
        vm.stopPrank();

        // 2. Keeper should be able to claim fees
        uint256 userFeeTokenBalanceBefore = ERC20(feeToken).balanceOf(user);

        vm.startPrank(keeper);
        ERC20(payoutToken).approve(address(collector), payoutAmount);
        IBribeCollector(address(collector)).claimFees(
            user, feeTokens, feeAmounts
        );
        vm.stopPrank();

        // Verify user received fee tokens
        uint256 userFeeTokenBalanceAfter = ERC20(feeToken).balanceOf(user);
        assertEq(
            userFeeTokenBalanceAfter - userFeeTokenBalanceBefore, feeAmounts[0]
        );
    }

    function testUpgradeInfraredToV1_5() public {
        // Perform the upgrade to Infrared v1.5
        vm.startPrank(infraredGovernance);
        (bool success,) = address(infrared).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(implementation), ""
            )
        );
        require(success, "Upgrade Infrared failed");
        vm.stopPrank();

        // Verify upgrade through successful interaction with upgraded functions
        // Specific tests would depend on the changes in InfraredV1_5
        // This test simply verifies the upgrade transaction succeeded
    }

    function testFullUpgrade() public {
        // Upgrade BribeCollector
        testUpgradeBribeCollectorToV1_3();

        // Upgrade Infrared
        testUpgradeInfraredToV1_5();
    }
}
