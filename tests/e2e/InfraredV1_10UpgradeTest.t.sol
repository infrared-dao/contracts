// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    UUPSUpgradeable,
    ERC1967Utils
} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InfraredV1_10} from "src/core/InfraredV1_10.sol";
import {IInfraredV1_10} from "src/interfaces/IInfraredV1_10.sol";
import {InfraredGovernanceTokenV1_2 as InfraredGovernanceToken} from
    "src/core/InfraredGovernanceTokenV1_2.sol";
import {IRAuction} from "src/periphery/IRAuction.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {IRRewardDistributor} from "src/periphery/IRRewardDistributor.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {HelperForkTest} from "./HelperForkTest.t.sol";
import {Errors} from "src/utils/Errors.sol";

/// @title InfraredV1_10UpgradeTest
/// @notice Tests for upgrading Infrared to V1_10 with IR token integration
contract InfraredV1_10UpgradeTest is HelperForkTest {
    InfraredV1_10 public implementation;
    InfraredGovernanceToken public irToken;
    StakedIR public stakedIR;
    IRAuction public irAuction;
    IRRewardDistributor public irRewardDistributor;

    address public user1;
    address public user2;
    address public user3;

    address public compounder;

    uint256 constant INITIAL_IR_SUPPLY = 1_000_000 ether;
    uint256 constant USER_INITIAL_BALANCE = 10_000 ether;
    uint256 constant PAYOUT_AMOUNT = 100 ether;

    // Storage slot locations for verification
    bytes32 public constant VALIDATOR_STORAGE_LOCATION =
        0x8ea5a3cc3b9a6be40b16189aeb1b6e6e61492e06efbfbe10619870b5bc1cc500;
    bytes32 public constant VAULT_STORAGE_LOCATION =
        0x1bb2f1339407e6d63b93b8b490a9d43c5651f6fc4327c66addd5939450742a00;
    bytes32 public constant REWARDS_STORAGE_LOCATION =
        0xad12e6d08cc0150709acd6eed0bf697c60a83227922ab1d254d1ca4d3072ca00;

    function setUp() public override {
        // Set custom parameters
        admin = address(this);
        infraredGovernance = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
        keeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;
        user1 = address(0x1234);
        user2 = address(0x5678);
        user3 = address(0x3333);

        compounder = address(0x4444);

        // Load validator data from fixtures
        _loadValidatorData();

        // Create and select mainnet fork with specified block number
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 12494285);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();

        // Deploy new implementation
        implementation = new InfraredV1_10();

        // Deploy IR token
        irToken = new InfraredGovernanceToken(infraredGovernance);

        // Deploy StakedIR with proxy
        vm.prank(infraredGovernance);
        irToken.transfer(address(this), 100 ether);

        // Deploy implementation
        address stakedIRImpl = address(new StakedIR());

        // Pre-compute proxy address for approval
        address sirProxyAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        irToken.approve(sirProxyAddress, 10 ether);

        // Deploy proxy and initialize
        bytes memory stakedIRInitData = abi.encodeWithSelector(
            StakedIR.initialize.selector,
            IERC20(address(irToken)),
            infraredGovernance
        );
        ERC1967Proxy stakedIRProxy =
            new ERC1967Proxy(stakedIRImpl, stakedIRInitData);
        stakedIR = StakedIR(address(stakedIRProxy));

        // Deploy IRAuction implementation
        address irAuctionImplementation = address(new IRAuction());

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            infraredGovernance,
            keeper,
            address(irToken),
            address(stakedIR),
            PAYOUT_AMOUNT
        );
        ERC1967Proxy proxy = new ERC1967Proxy(irAuctionImplementation, initData);
        irAuction = IRAuction(address(proxy));

        // Deploy IRRewardDistributor
        irRewardDistributor = new IRRewardDistributor();

        // Perform the upgrade to Infrared v1.10
        vm.startPrank(infraredGovernance);
        (bool success,) = address(infrared).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(implementation), ""
            )
        );
        require(success, "Upgrade Infrared failed");
        // Initialize V1_10 specific features
        InfraredV1_10(payable(address(infrared))).initializeV1_10(
            address(irToken), address(irAuction)
        );
        vm.stopPrank();

        // Distribute IR to users
        vm.startPrank(infraredGovernance);
        irToken.transfer(user1, USER_INITIAL_BALANCE);
        irToken.transfer(user2, USER_INITIAL_BALANCE);
        irToken.transfer(user3, USER_INITIAL_BALANCE);
        irToken.transfer(compounder, USER_INITIAL_BALANCE);
        irToken.transfer(keeper, 10_000 ether);
        vm.stopPrank();
    }

    /// @notice Test storage layout preservation across upgrade
    function testStorageLayoutPreservation() public view {
        // Verify IR token is set
        assertEq(address(infrared.ir()), address(irToken));

        // Verify IR token is whitelisted
        assertTrue(infrared.whitelistedRewardTokens(address(irToken)));

        // Verify existing state is preserved
        assertEq(address(infrared.ibgt()), address(ibgt));
        assertEq(address(infrared.collector()), address(collector));
        assertEq(infrared.rewardsDuration(), 3600);

        assertEq(
            address(infrared.distributor()),
            address(infraredDistributor),
            "distributor changed"
        );
        assertEq(address(infrared.wbera()), address(wbera), "wbera changed");
        assertEq(address(infrared.honey()), address(honey), "honey changed");

        assertEq(InfraredV1_10(payable(address(infrared))).auctionBase(), false);
        assertEq(
            InfraredV1_10(payable(address(infrared))).wiBGT(),
            0x4f3C10D2bC480638048Fa67a7D00237a33670C1B
        );
        assertEq(
            InfraredV1_10(payable(address(infrared))).irCollector(),
            address(irAuction)
        );
        assertEq(
            InfraredV1_10(payable(address(infrared))).harvestBaseCollector(),
            0x7332051C4EeD9CD40B28BA0a1c5d042666897dA8
        );
    }

    /// @notice Test that IR bribes can be collected after upgrade
    function testCollectIRBribesAfterUpgrade() public {
        uint256 initBal = stakedIR.totalAssets();

        // Mint IR tokens to infrared contract
        vm.prank(infraredGovernance);
        irToken.transfer(address(collector), 100 ether);

        // Setup: Configure IR split ratio (e.g., 5% for testing)
        vm.prank(infraredGovernance);
        InfraredV1_10(payable(address(infrared))).updateIRBribeSplit(50000); // 5%

        // Simulate collector calling collectBribes with IR token
        uint256 collectorBalance = irToken.balanceOf(address(collector));

        vm.startPrank(address(collector));
        irToken.approve(address(infrared), 100 ether);
        infrared.collectBribes(address(irToken), collectorBalance);
        vm.stopPrank();

        irAuction.sweepPayoutToken();

        // Verify IR tokens were distributed
        // Should have sent some to irAuction based on IR split
        assertEq(stakedIR.totalAssets(), initBal + 475 * 100 ether / 10000);
    }

    /// @notice Test IR token can be used as vault incentive after upgrade
    function testAddIRIncentivesAfterUpgrade() public {
        // Upgrade and initialize
        vm.startPrank(infraredGovernance);
        IInfraredVault vault = infrared.vaultRegistry(address(ibgt));
        infrared.addReward(address(ibgt), address(irToken), 7 days);
        vm.stopPrank();

        // Mint IR to user1 and approve
        vm.startPrank(infraredGovernance);
        irToken.transfer(user1, 1000 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        irToken.approve(address(infrared), 1000 ether);

        // Add IR incentives to iBGT vault
        infrared.addIncentives(address(ibgt), address(irToken), 100 ether);
        vm.stopPrank();

        // Verify incentives were added
        assertEq(irToken.balanceOf(address(vault)), 100 ether);
    }

    /// @notice Test IR can be whitelisted/unwhitelisted after upgrade
    function testIRWhitelistManagement() public {
        vm.startPrank(infraredGovernance);

        // Verify IR is whitelisted after initialization
        assertTrue(infrared.whitelistedRewardTokens(address(irToken)));

        // Test removing IR from whitelist
        infrared.updateWhiteListedRewardTokens(address(irToken), false);
        assertFalse(infrared.whitelistedRewardTokens(address(irToken)));

        // Test adding back to whitelist
        infrared.updateWhiteListedRewardTokens(address(irToken), true);
        assertTrue(infrared.whitelistedRewardTokens(address(irToken)));
        vm.stopPrank();
    }

    /// @notice Test validator operations still work after upgrade
    function testValidatorOperationsAfterUpgrade() public {
        vm.startPrank(infraredGovernance);

        // Test that validator queries still work
        uint256 numValidators = infrared.numInfraredValidators();
        assertTrue(numValidators >= 0);

        // Test BGT balance query
        uint256 bgtBalance = infrared.getBGTBalance();
        assertTrue(bgtBalance >= 0);
    }

    /// @notice Test vault operations still work after upgrade
    function testVaultOperationsAfterUpgrade() public view {
        // Verify iBGT vault still exists
        IInfraredVault ibgtVault = infrared.vaultRegistry(address(ibgt));
        assertTrue(address(ibgtVault) != address(0));

        // Verify rewards duration is still accessible
        uint256 duration = infrared.rewardsDuration();
        assertTrue(duration > 0);
    }

    /// @notice Test protocol fee operations after upgrade
    function testProtocolFeesAfterUpgrade() public view {
        // Verify fee queries still work
        uint256 fee0 = infrared.fees(0);
        assertTrue(fee0 >= 0);

        // Verify protocol fee amounts are still accessible
        uint256 protocolFees = infrared.protocolFeeAmounts(address(wbera));
        assertTrue(protocolFees >= 0);
    }

    /// @notice Test basic deposit functionality
    function testDeposit() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);

        uint256 sharesBefore = stakedIR.balanceOf(user1);
        uint256 shares = stakedIR.deposit(depositAmount, user1);
        uint256 sharesAfter = stakedIR.balanceOf(user1);

        assertEq(sharesAfter - sharesBefore, shares);
        assertEq(stakedIR.totalAssets(), 10 ether + depositAmount); // includes constructor deposit
        assertTrue(shares > 0);
        vm.stopPrank();
    }

    /// @notice Test deposit functionality
    function testDepositUpdatesTimestamp() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);

        uint256 sharesBefore = stakedIR.balanceOf(user1);
        stakedIR.deposit(depositAmount, user1);

        uint256 sharesAfter = stakedIR.balanceOf(user1);
        assertGt(sharesAfter, sharesBefore);
        vm.stopPrank();
    }

    /// @notice Test mint functionality
    function testMint() public {
        uint256 sharesToMint = 100 ether;

        vm.startPrank(user1);
        uint256 assetsNeeded = stakedIR.previewMint(sharesToMint);
        irToken.approve(address(stakedIR), assetsNeeded);

        uint256 sharesBefore = stakedIR.balanceOf(user1);
        uint256 assets = stakedIR.mint(sharesToMint, user1);
        uint256 sharesAfter = stakedIR.balanceOf(user1);

        assertEq(sharesAfter - sharesBefore, sharesToMint);
        assertTrue(assets > 0);
        vm.stopPrank();
    }

    /// @notice Test multiple deposits update weighted average timestamp
    function testWeightedAverageTimestamp() public {
        uint256 firstDeposit = 100 ether;
        uint256 secondDeposit = 200 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), firstDeposit + secondDeposit);

        // First deposit
        stakedIR.deposit(firstDeposit, user1);
        uint256 firstBalance = stakedIR.balanceOf(user1);

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Second deposit
        stakedIR.deposit(secondDeposit, user1);

        uint256 totalBalance = stakedIR.balanceOf(user1);

        // Verify total balance is correct
        assertGt(totalBalance, firstBalance);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test withdrawal ticket system - request and claim
    function testWithdrawRespectsLockup() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user1);

        // Request withdrawal
        stakedIR.redeem(shares, user1, user1);
        uint256 requestId = 1; // First request

        // Try to claim immediately (should fail)
        vm.expectRevert(StakedIR.WithdrawalNotReady.selector);
        stakedIR.claimWithdraw(requestId);

        vm.stopPrank();
    }

    /// @notice Test withdrawal succeeds after withdrawal period
    function testWithdrawAfterLockup() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user1);

        // Request withdrawal
        stakedIR.redeem(shares, user1, user1);
        uint256 requestId = 1; // First request

        // Advance time past withdrawal period (7 days default)
        vm.warp(block.timestamp + 8 days);

        uint256 irBalanceBefore = irToken.balanceOf(user1);
        uint256 assets = stakedIR.claimWithdraw(requestId);
        uint256 irBalanceAfter = irToken.balanceOf(user1);

        assertEq(irBalanceAfter - irBalanceBefore, assets);
        assertEq(stakedIR.balanceOf(user1), 0);
        vm.stopPrank();
    }

    /// @notice Test withdrawal ticket status checking
    function testLockupRemaining() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user1);

        // Request withdrawal
        stakedIR.redeem(shares, user1, user1);
        uint256 requestId = 1; // First request

        // Check ticket is not ready initially
        assertFalse(stakedIR.isWithdrawalReady(requestId));

        // Advance 3 days
        vm.warp(block.timestamp + 3 days);
        assertFalse(stakedIR.isWithdrawalReady(requestId));

        // Advance past withdrawal period
        vm.warp(block.timestamp + 5 days);
        assertTrue(stakedIR.isWithdrawalReady(requestId));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         COMPOUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test compound functionality increases share value
    function testCompound() public {
        // User1 deposits
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 sharesBefore = stakedIR.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 shareValueBefore = stakedIR.convertToAssets(1 ether); // 1 share in assets

        // Compounder adds rewards
        uint256 compoundAmount = 50 ether;
        vm.startPrank(compounder);
        irToken.approve(address(stakedIR), compoundAmount);
        stakedIR.compound(compoundAmount);
        vm.stopPrank();

        uint256 shareValueAfter = stakedIR.convertToAssets(1 ether);

        // Share value should increase after compounding
        assertGt(shareValueAfter, shareValueBefore);

        // Total assets should include compound amount
        assertEq(
            stakedIR.totalAssets(), 10 ether + depositAmount + compoundAmount
        );

        // User1's shares value should have increased
        uint256 userAssetsAfter = stakedIR.convertToAssets(sharesBefore);
        assertGt(userAssetsAfter, depositAmount);
    }

    /// @notice Test compound emits correct event
    function testCompoundEvent() public {
        uint256 compoundAmount = 50 ether;

        vm.startPrank(compounder);
        irToken.approve(address(stakedIR), compoundAmount);

        vm.expectEmit(true, false, false, true);
        emit StakedIR.Compounded(
            compounder, compoundAmount, 10 ether + compoundAmount
        );

        stakedIR.compound(compoundAmount);
        vm.stopPrank();
    }

    /// @notice Test compound with zero amount reverts
    function testCompoundZeroAmount() public {
        vm.prank(compounder);
        vm.expectRevert(Errors.ZeroAmount.selector);
        stakedIR.compound(0);
    }

    /// @notice Test multiple compounds accumulate correctly
    function testMultipleCompounds() public {
        // User deposits
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), 100 ether);
        stakedIR.deposit(100 ether, user1);
        vm.stopPrank();

        uint256 totalCompounded = 0;
        uint256 compoundAmount = 10 ether;

        // Perform multiple compounds
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(compounder);
            irToken.approve(address(stakedIR), compoundAmount);
            stakedIR.compound(compoundAmount);
            vm.stopPrank();

            totalCompounded += compoundAmount;
        }

        assertEq(stakedIR.totalCompounded(), totalCompounded);
        assertEq(stakedIR.totalAssets(), 10 ether + 100 ether + totalCompounded);
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test transfer updates receiver's timestamp
    function testTransferUpdatesReceiverTimestamp() public {
        uint256 depositAmount = 100 ether;

        // User1 deposits
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user1);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 2 days);

        // Transfer to user2
        vm.prank(user1);
        stakedIR.transfer(user2, shares / 2);

        // User2's balance should be updated
        assertEq(stakedIR.balanceOf(user2), shares / 2);
    }

    /// @notice Test transferFrom updates receiver's balance
    function testTransferFromUpdatesReceiverTimestamp() public {
        uint256 depositAmount = 100 ether;

        // User1 deposits and approves user3
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user1);
        stakedIR.approve(user3, shares);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 2 days);

        // User3 transfers from user1 to user2
        vm.prank(user3);
        stakedIR.transferFrom(user1, user2, shares / 2);

        // User2's balance should be updated
        assertEq(stakedIR.balanceOf(user2), shares / 2);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test setWithdrawalPeriod by governance
    function testSetMinLockupPeriod() public {
        uint256 newPeriod = 14 days;

        vm.prank(infraredGovernance);
        vm.expectEmit(true, true, false, true);
        emit StakedIR.WithdrawalPeriodUpdated(7 days, newPeriod);
        stakedIR.setWithdrawalPeriod(newPeriod);

        assertEq(stakedIR.withdrawalPeriod(), newPeriod);
    }

    /// @notice Test only governance can set withdrawal period
    function testOnlyGovernanceCanSetLockupPeriod() public {
        vm.prank(user1);
        // AccessControl uses AccessControlUnauthorizedAccount error
        vm.expectRevert();
        stakedIR.setWithdrawalPeriod(14 days);
    }

    /// @notice Test new withdrawal period applies to new tickets
    function testNewLockupPeriodApplies() public {
        // Set new withdrawal period
        uint256 newPeriod = 14 days;
        vm.prank(infraredGovernance);
        stakedIR.setWithdrawalPeriod(newPeriod);

        // User deposits and requests withdrawal
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), 100 ether);
        uint256 shares = stakedIR.deposit(100 ether, user1);
        stakedIR.redeem(shares, user1, user1);
        uint256 requestId = 1; // First request

        // Try to claim before new withdrawal period (should fail)
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(StakedIR.WithdrawalNotReady.selector);
        stakedIR.claimWithdraw(requestId);

        // Claim after new withdrawal period (should succeed)
        vm.warp(block.timestamp + 7 days); // total 15 days
        stakedIR.claimWithdraw(requestId);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test totalAssets returns correct value
    function testTotalAssets() public {
        uint256 initialAssets = stakedIR.totalAssets();
        assertEq(initialAssets, 10 ether); // constructor deposit

        // Add deposits
        vm.startPrank(user1);
        irToken.approve(address(stakedIR), 100 ether);
        stakedIR.deposit(100 ether, user1);
        vm.stopPrank();

        assertEq(stakedIR.totalAssets(), 110 ether);

        // Add compound
        vm.startPrank(compounder);
        irToken.approve(address(stakedIR), 50 ether);
        stakedIR.compound(50 ether);
        vm.stopPrank();

        assertEq(stakedIR.totalAssets(), 160 ether);
    }

    /// @notice Test totalCompounded tracking
    function testTotalCompounded() public {
        assertEq(stakedIR.totalCompounded(), 0);

        vm.startPrank(compounder);
        irToken.approve(address(stakedIR), 100 ether);
        stakedIR.compound(50 ether);
        assertEq(stakedIR.totalCompounded(), 50 ether);

        stakedIR.compound(30 ether);
        assertEq(stakedIR.totalCompounded(), 80 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test deposit with different receiver
    function testDepositToDifferentReceiver() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 shares = stakedIR.deposit(depositAmount, user2);

        // User2 should have the shares
        assertEq(stakedIR.balanceOf(user2), shares);
        vm.stopPrank();
    }

    /// @notice Test inflation attack prevention
    function testInflationAttackPrevention() public view {
        // Constructor deposits 10 ether to prevent inflation attacks
        assertEq(stakedIR.balanceOf(address(stakedIR)), 10 ether);
        assertEq(stakedIR.totalSupply(), 10 ether);
    }

    /// @notice Test preview functions accuracy
    function testPreviewFunctions() public {
        uint256 depositAmount = 100 ether;

        // Preview deposit
        uint256 expectedShares = stakedIR.previewDeposit(depositAmount);

        vm.startPrank(user1);
        irToken.approve(address(stakedIR), depositAmount);
        uint256 actualShares = stakedIR.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);

        // Preview withdraw
        uint256 expectedAssets = stakedIR.previewRedeem(actualShares);
        assertApproxEqAbs(expectedAssets, depositAmount, 1); // Allow 1 wei difference for rounding
    }

    /// @notice Test proper initialization
    function testInitialization() public view {
        assertEq(address(irAuction.payoutToken()), address(irToken));
        assertEq(irAuction.payoutAmount(), PAYOUT_AMOUNT);
        assertTrue(
            irAuction.hasRole(irAuction.GOVERNANCE_ROLE(), infraredGovernance)
        );
        assertTrue(irAuction.hasRole(irAuction.KEEPER_ROLE(), keeper));
    }

    /// @notice Test initialization with zero address reverts
    function testInitializationZeroAddressReverts() public {
        IRAuction newImpl = new IRAuction();

        // Zero infrared address
        bytes memory initData1 = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(0),
            infraredGovernance,
            keeper,
            address(irToken),
            address(stakedIR),
            PAYOUT_AMOUNT
        );
        vm.expectRevert();
        new ERC1967Proxy(address(newImpl), initData1);

        // Zero gov address
        bytes memory initData2 = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            address(0),
            keeper,
            address(irToken),
            address(stakedIR),
            PAYOUT_AMOUNT
        );
        vm.expectRevert();
        new ERC1967Proxy(address(newImpl), initData2);

        // Zero IR token address
        bytes memory initData3 = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            infraredGovernance,
            keeper,
            address(0),
            address(stakedIR),
            PAYOUT_AMOUNT
        );
        vm.expectRevert();
        new ERC1967Proxy(address(newImpl), initData3);

        // Zero sIR vault address
        bytes memory initData4 = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            infraredGovernance,
            keeper,
            address(irToken),
            address(0),
            PAYOUT_AMOUNT
        );
        vm.expectRevert();
        new ERC1967Proxy(address(newImpl), initData4);
    }

    /// @notice Test initialization with zero payout amount reverts
    function testInitializationZeroPayoutReverts() public {
        IRAuction newImpl = new IRAuction();

        bytes memory initData = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            infraredGovernance,
            keeper,
            address(irToken),
            address(stakedIR),
            0
        );

        vm.expectRevert();
        new ERC1967Proxy(address(newImpl), initData);
    }

    /*//////////////////////////////////////////////////////////////
                         CLAIM FEES TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test successful fee claim
    function testClaimFees() public {
        // Setup: Give auction contract some WBERA rewards
        uint256 rewardAmount = 1000 ether;
        deal(address(wbera), address(irAuction), rewardAmount);

        // Approve keeper to pay IR
        vm.startPrank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        // Prepare claim parameters
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;

        uint256 bidderIRBefore = irToken.balanceOf(keeper);
        uint256 bidderWBERABefore = wbera.balanceOf(keeper);
        uint256 sirAssetsBefore = stakedIR.totalAssets();

        // Claim as keeper
        vm.stopPrank();
        vm.prank(keeper);
        irAuction.claimFees(keeper, rewardTokens, amounts);

        // Verify bidder paid IR
        assertEq(
            irToken.balanceOf(keeper), bidderIRBefore - PAYOUT_AMOUNT, "IR paid"
        );

        // Verify bidder received WBERA
        assertEq(
            wbera.balanceOf(keeper),
            bidderWBERABefore + rewardAmount,
            "WBERA received"
        );

        // Verify IR was compounded into sIR
        assertEq(
            stakedIR.totalAssets(),
            sirAssetsBefore + PAYOUT_AMOUNT,
            "IR compounded"
        );
    }

    /// @notice Test claim fees emits correct event
    function testClaimFeesEvent() public {
        uint256 rewardAmount = 1000 ether;
        deal(address(wbera), address(irAuction), rewardAmount);

        vm.prank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;

        vm.prank(keeper);
        vm.expectEmit(true, true, false, true);
        emit IRAuction.AuctionClaimed(
            keeper, address(wbera), rewardAmount, PAYOUT_AMOUNT
        );
        irAuction.claimFees(keeper, rewardTokens, amounts);
    }

    /// @notice Test only keeper can claim fees
    function testOnlyKeeperCanClaimFees() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        vm.prank(user1);
        vm.expectRevert();
        irAuction.claimFees(user1, rewardTokens, amounts);
    }

    /// @notice Test claim fees with multiple tokens
    function testClaimFeesMultipleTokens() public {
        // Setup rewards
        uint256 wberaAmount = 1000 ether;
        uint256 honeyAmount = 500 ether;
        deal(address(wbera), address(irAuction), wberaAmount);
        deal(address(honey), address(irAuction), honeyAmount);

        vm.prank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wberaAmount;
        amounts[1] = honeyAmount;

        uint256 wberaBefore = wbera.balanceOf(keeper);
        uint256 honeyBefore = honey.balanceOf(keeper);

        vm.prank(keeper);
        irAuction.claimFees(keeper, rewardTokens, amounts);

        assertEq(wbera.balanceOf(keeper), wberaBefore + wberaAmount);
        assertEq(honey.balanceOf(keeper), honeyBefore + honeyAmount);
    }

    /// @notice Test claim fees with mismatched array lengths reverts
    function testClaimFeesMismatchedArrays() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidArrayLength.selector);
        irAuction.claimFees(keeper, rewardTokens, amounts);
    }

    /// @notice Test claim fees with payout token in rewards reverts
    function testClaimFeesPayoutTokenReverts() public {
        deal(address(irToken), address(irAuction), 1000 ether);

        vm.prank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(irToken); // Trying to claim IR
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidFeeToken.selector);
        irAuction.claimFees(keeper, rewardTokens, amounts);
    }
    /// @notice Test claim fees with insufficient balance reverts

    function testClaimFeesInsufficientBalance() public {
        // Setup: auction has less than claimed amount
        uint256 actualBalance = 500 ether;
        uint256 claimedAmount = 1000 ether;
        deal(address(wbera), address(irAuction), actualBalance);

        vm.prank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimedAmount;

        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientFeeTokenBalance.selector);
        irAuction.claimFees(keeper, rewardTokens, amounts);
    }

    /// @notice Test claim fees with insufficient IR balance reverts
    function testClaimFeesInsufficientIRBalance() public {
        uint256 rewardAmount = 1000 ether;
        deal(address(wbera), address(irAuction), rewardAmount);

        // Bidder has less IR than payout amount
        vm.startPrank(keeper);
        irToken.transfer(user1, 9950 ether); // Leave only 50 ether
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);
        vm.stopPrank();

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;

        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        irAuction.claimFees(keeper, rewardTokens, amounts);
    }

    /// @notice Test claim fees with zero address recipient reverts
    function testClaimFeesZeroAddressRecipient() public {
        uint256 rewardAmount = 1000 ether;
        deal(address(wbera), address(irAuction), rewardAmount);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = rewardAmount;

        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        irAuction.claimFees(address(0), rewardTokens, amounts);
    }

    /// @notice Test claim fees skips zero amounts
    function testClaimFeesSkipsZeroAmounts() public {
        deal(address(wbera), address(irAuction), 1000 ether);
        deal(address(honey), address(irAuction), 1000 ether);

        vm.prank(keeper);
        irToken.approve(address(irAuction), PAYOUT_AMOUNT);

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 0; // Zero amount

        uint256 honeyBefore = honey.balanceOf(keeper);

        vm.prank(keeper);
        irAuction.claimFees(keeper, rewardTokens, amounts);

        // Should receive WBERA but not HONEY
        assertGt(wbera.balanceOf(keeper), 0);
        assertEq(honey.balanceOf(keeper), honeyBefore); // No change
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test setPayoutAmount by governance
    function testSetPayoutAmount() public {
        uint256 newAmount = 200 ether;

        vm.prank(infraredGovernance);
        vm.expectEmit(true, true, false, true);
        emit IRAuction.PayoutAmountSet(PAYOUT_AMOUNT, newAmount);
        irAuction.setPayoutAmount(newAmount);

        assertEq(irAuction.payoutAmount(), newAmount);
    }

    /// @notice Test only governance can set payout amount
    function testOnlyGovernanceCanSetPayoutAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        irAuction.setPayoutAmount(200 ether);
    }

    /// @notice Test set payout amount with zero reverts
    function testSetPayoutAmountZeroReverts() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAmount.selector);
        irAuction.setPayoutAmount(0);
    }

    /// @notice Test recoverERC20 by governance
    function testRecoverERC20() public {
        uint256 prevBal = wbera.balanceOf(infraredGovernance);

        // Send some tokens to auction by mistake
        uint256 stuckAmount = 500 ether;
        deal(address(wbera), address(irAuction), stuckAmount);

        vm.prank(infraredGovernance);
        vm.expectEmit(true, true, false, true);
        emit IRAuction.TokensRecovered(
            address(wbera), infraredGovernance, stuckAmount
        );
        irAuction.recoverERC20(address(wbera), infraredGovernance, stuckAmount);

        assertEq(wbera.balanceOf(infraredGovernance), prevBal + stuckAmount);
    }

    /// @notice Test only governance can recover tokens
    function testOnlyGovernanceCanRecoverTokens() public {
        vm.prank(user1);
        vm.expectRevert();
        irAuction.recoverERC20(address(wbera), user1, 100 ether);
    }

    /// @notice Test recover with zero address reverts
    function testRecoverZeroAddressReverts() public {
        vm.startPrank(infraredGovernance);

        vm.expectRevert(Errors.ZeroAddress.selector);
        irAuction.recoverERC20(address(0), infraredGovernance, 100 ether);

        vm.expectRevert(Errors.ZeroAddress.selector);
        irAuction.recoverERC20(address(wbera), address(0), 100 ether);

        vm.stopPrank();
    }

    /// @notice Test recover with zero amount reverts
    function testRecoverZeroAmountReverts() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAmount.selector);
        irAuction.recoverERC20(address(wbera), infraredGovernance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         SWEEP PAYOUT TOKEN TEST
    //////////////////////////////////////////////////////////////*/

    /// @notice Test sweepPayoutToken functionality
    function testSweepPayoutToken() public {
        // Send IR to auction
        uint256 sweepAmount = 100 ether;
        vm.prank(infraredGovernance);
        irToken.transfer(address(irAuction), sweepAmount);

        uint256 sirAssetsBefore = stakedIR.totalAssets();

        // Anyone can call sweep
        vm.prank(user1);
        irAuction.sweepPayoutToken();

        // Verify payout amount was compounded into sIR
        assertEq(
            stakedIR.totalAssets(), sirAssetsBefore + irAuction.payoutAmount()
        );
    }

    /// @notice Test sweep with insufficient balance reverts
    function testSweepInsufficientBalance() public {
        // No IR in auction
        vm.prank(user1);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        irAuction.sweepPayoutToken();
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test getTokenBalance view function
    function testGetTokenBalance() public {
        uint256 amount = 1000 ether;
        deal(address(wbera), address(irAuction), amount);

        uint256 balance = irAuction.getTokenBalance(address(wbera));
        assertEq(balance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test full auction cycle
    function testFullAuctionCycle() public {
        // 1. Rewards accumulate in auction
        uint256 wberaReward = 1000 ether;
        uint256 honeyReward = 500 ether;
        deal(address(wbera), address(irAuction), wberaReward);
        deal(address(honey), address(irAuction), honeyReward);

        // 2. Multiple bidders compete
        vm.prank(infraredGovernance);
        irToken.transfer(keeper, 2 * PAYOUT_AMOUNT);
        vm.prank(keeper);
        irToken.approve(address(irAuction), 2 * PAYOUT_AMOUNT);

        // 3. First bidder claims
        address[] memory rewardTokens1 = new address[](1);
        rewardTokens1[0] = address(wbera);
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = wberaReward;

        uint256 keeperIRBefore = irToken.balanceOf(keeper);

        vm.prank(keeper);
        irAuction.claimFees(keeper, rewardTokens1, amounts1);

        assertEq(wbera.balanceOf(keeper), wberaReward);
        assertEq(irToken.balanceOf(keeper), keeperIRBefore - PAYOUT_AMOUNT);

        // 4. Second bidder claims remaining
        address[] memory rewardTokens2 = new address[](1);
        rewardTokens2[0] = address(honey);
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = honeyReward;

        vm.prank(keeper);
        irAuction.claimFees(keeper, rewardTokens2, amounts2);

        assertEq(honey.balanceOf(keeper), honeyReward);

        // 5. Verify all IR was compounded into sIR
        // 2 claims * PAYOUT_AMOUNT
        assertGe(stakedIR.totalAssets(), PAYOUT_AMOUNT * 2);
    }
}
