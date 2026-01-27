// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Errors} from "src/utils/Errors.sol";

contract StakedIRTest is Test {
    StakedIR public sir;
    MockERC20 public ir;

    address public infrared = makeAddr("infrared");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public compounder = makeAddr("compounder");

    uint256 constant INITIAL_DEPOSIT = 10 ether;
    uint256 constant WITHDRAWAL_PERIOD = 7 days;

    event Compounded(
        address indexed compounder, uint256 amount, uint256 newTotalAssets
    );
    event WithdrawalPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event WithdrawalRequested(
        address indexed user,
        uint256 indexed requestId,
        uint256 shares,
        uint256 unlockTime
    );
    event WithdrawalClaimed(
        address indexed user,
        uint256 indexed requestId,
        uint256 shares,
        uint256 assets
    );

    function setUp() public {
        // Deploy IR token
        ir = new MockERC20("Infrared", "IR", 18);

        // Mint initial IR for initialization
        ir.mint(address(this), INITIAL_DEPOSIT);

        // Deploy StakedIR implementation
        address sirImpl = address(new StakedIR());

        // Pre-compute proxy address for approval (inflation protection)
        address sirProxyAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        ir.approve(sirProxyAddress, INITIAL_DEPOSIT);

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), infrared
        );
        sir = StakedIR(address(new ERC1967Proxy(sirImpl, initData)));

        // Setup test users with IR tokens
        ir.mint(alice, 1000 ether);
        ir.mint(bob, 1000 ether);
        ir.mint(compounder, 1000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_InitialState() public view {
        assertEq(address(sir.asset()), address(ir));
        assertEq(sir.name(), "Staked IR");
        assertEq(sir.symbol(), "sIR");
        // Governance role should be set via AccessControl
        assertTrue(sir.hasRole(sir.GOVERNANCE_ROLE(), infrared));
        assertEq(sir.withdrawalPeriod(), WITHDRAWAL_PERIOD);
        assertEq(sir.totalCompounded(), 0);
        assertEq(sir.totalReserved(), 0);
        assertEq(sir.requestLength(), 0);

        // Check inflation protection worked
        assertEq(sir.balanceOf(address(sir)), INITIAL_DEPOSIT);
    }

    function test_RevertInitialize_ZeroAddress() public {
        address sirImpl = address(new StakedIR());
        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(0)), infrared
        );
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(sirImpl, initData);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      DEPOSIT TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Deposit() public {
        uint256 depositAmount = 100 ether;

        vm.prank(alice);
        ir.approve(address(sir), depositAmount);

        // test pause / un-pause
        vm.prank(infrared);
        sir.pause();

        vm.expectRevert();
        sir.deposit(depositAmount, alice);

        vm.prank(infrared);
        sir.unpause();

        vm.prank(alice);
        uint256 shares = sir.deposit(depositAmount, alice);

        assertEq(sir.balanceOf(alice), shares);
        assertEq(sir.totalAssets(), INITIAL_DEPOSIT + depositAmount);
        assertEq(sir.totalReserved(), 0);
    }

    function test_Mint() public {
        uint256 shares = 100 ether;

        vm.prank(alice);
        ir.approve(address(sir), type(uint256).max);

        // test pause / un-pause
        vm.prank(infrared);
        sir.pause();

        vm.expectRevert();
        sir.mint(shares, alice);

        vm.prank(infrared);
        sir.unpause();

        vm.prank(alice);
        uint256 assets = sir.mint(shares, alice);

        assertEq(sir.balanceOf(alice), shares);
        assertGt(assets, 0);
    }

    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        ir.approve(address(sir), amount);

        uint256 sharesBefore = sir.balanceOf(alice);
        uint256 shares = sir.deposit(amount, alice);

        assertEq(sir.balanceOf(alice), sharesBefore + shares);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  WITHDRAWAL REQUEST TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_RedeemCreatesWithdrawalRequest() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawShares = 50 ether;

        // Alice deposits
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);

        // Redeem creates a withdrawal request
        uint256 expectedUnlockTime = block.timestamp + WITHDRAWAL_PERIOD;

        vm.expectEmit(true, true, false, true);
        emit WithdrawalRequested(alice, 1, withdrawShares, expectedUnlockTime);

        uint256 sharesBefore = sir.balanceOf(alice);
        uint256 assets = sir.redeem(withdrawShares, alice, alice);
        vm.stopPrank();

        // Shares burned immediately
        assertEq(sir.balanceOf(alice), sharesBefore - withdrawShares);
        assertGt(assets, 0);
        assertEq(sir.requestLength(), 1);
        assertEq(sir.totalReserved(), assets);

        // Check request details
        (
            bool claimed,
            uint256 reqShares,
            uint256 reqAssets,
            uint256 unlockTime,
            address receiver
        ) = sir.getWithdrawalRequest(1);
        assertFalse(claimed);
        assertEq(reqShares, withdrawShares);
        assertEq(reqAssets, assets);
        assertEq(unlockTime, expectedUnlockTime);
        assertEq(receiver, alice);
        assertFalse(sir.isWithdrawalReady(1));

        // Check user requests
        uint256[] memory userRequests = sir.getUserRequests(alice);
        assertEq(userRequests.length, 1);
        assertEq(userRequests[0], 1);
    }

    function test_WithdrawCreatesWithdrawalRequest() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAssets = 50 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);
        vm.stopPrank();

        // test pause / un-pause
        vm.prank(infrared);
        sir.pause();

        vm.expectRevert();
        sir.withdraw(withdrawAssets, alice, alice);

        vm.prank(infrared);
        sir.unpause();

        vm.prank(alice);
        // Withdraw creates a withdrawal request
        uint256 shares = sir.withdraw(withdrawAssets, alice, alice);

        assertGt(shares, 0);
        assertEq(sir.requestLength(), 1);
    }

    function test_RevertRedeem_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        sir.redeem(0, alice, alice);
    }

    function test_MultipleWithdrawalRequests() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        uint256 shares = sir.deposit(depositAmount, alice);

        // Create multiple requests
        sir.redeem(30 ether, alice, alice);
        assertEq(sir.balanceOf(alice), shares - 30 ether);
        assertEq(sir.requestLength(), 1);

        sir.redeem(20 ether, alice, alice);
        assertEq(sir.balanceOf(alice), shares - 50 ether);
        assertEq(sir.requestLength(), 2);

        sir.redeem(25 ether, alice, alice);
        assertEq(sir.balanceOf(alice), shares - 75 ether);
        assertEq(sir.requestLength(), 3);

        vm.stopPrank();

        assertGt(sir.totalReserved(), 0);

        // Check user has 3 requests
        uint256[] memory userRequests = sir.getUserRequests(alice);
        assertEq(userRequests.length, 3);
    }

    function test_ClaimWithdraw() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawShares = 60 ether;

        // Alice deposits
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        uint256 shares = sir.deposit(depositAmount, alice);

        // Request withdrawal
        uint256 expectedAssets = sir.redeem(withdrawShares, alice, alice);

        // Fast forward past withdrawal period
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);

        assertTrue(sir.isWithdrawalReady(1));

        // Claim withdrawal
        uint256 irBalanceBefore = ir.balanceOf(alice);
        uint256 reservedBefore = sir.totalReserved();

        vm.expectEmit(true, true, false, true);
        emit WithdrawalClaimed(alice, 1, withdrawShares, expectedAssets);

        uint256 assets = sir.claimWithdraw(1);
        vm.stopPrank();

        assertEq(assets, expectedAssets);
        assertEq(ir.balanceOf(alice), irBalanceBefore + assets);
        assertEq(sir.balanceOf(alice), shares - withdrawShares);
        assertEq(sir.totalReserved(), reservedBefore - assets);

        // Check request is marked as claimed
        (bool claimed,,,,) = sir.getWithdrawalRequest(1);
        assertTrue(claimed);
        assertFalse(sir.isWithdrawalReady(1));
    }

    function test_RevertClaimWithdraw_NotReady() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);

        sir.redeem(50 ether, alice, alice);

        // Try to claim immediately
        vm.expectRevert(StakedIR.WithdrawalNotReady.selector);
        sir.claimWithdraw(1);
        vm.stopPrank();
    }

    function test_RevertClaimWithdraw_InvalidRequestId() public {
        vm.prank(alice);
        vm.expectRevert(StakedIR.InvalidRequestId.selector);
        sir.claimWithdraw(999);
    }

    function test_RevertClaimWithdraw_AlreadyClaimed() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);

        sir.redeem(50 ether, alice, alice);

        // Fast forward and claim
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);
        sir.claimWithdraw(1);

        // Try to claim again
        vm.expectRevert(StakedIR.InvalidState.selector);
        sir.claimWithdraw(1);
        vm.stopPrank();
    }

    function test_ClaimBatch() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        uint256 shares = sir.deposit(depositAmount, alice);

        // Create multiple requests
        sir.redeem(20 ether, alice, alice);
        sir.redeem(30 ether, alice, alice);
        sir.redeem(25 ether, alice, alice);

        uint256 sharesAfterRequests = sir.balanceOf(alice);
        assertEq(sharesAfterRequests, shares - 75 ether);

        // Fast forward
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);

        // Claim all in batch
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = 1;
        requestIds[1] = 2;
        requestIds[2] = 3;

        uint256 balanceBefore = ir.balanceOf(alice);
        uint256 totalAssets = sir.claimBatch(requestIds);
        vm.stopPrank();

        assertGt(totalAssets, 0);
        assertEq(ir.balanceOf(alice), balanceBefore + totalAssets);

        // Shares remain the same (already burned)
        assertEq(sir.balanceOf(alice), sharesAfterRequests);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      COMPOUNDING TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Compound() public {
        // Alice deposits
        vm.startPrank(alice);
        ir.approve(address(sir), 100 ether);
        sir.deposit(100 ether, alice);
        vm.stopPrank();

        uint256 sharesBefore = sir.balanceOf(alice);
        uint256 totalAssetsBefore = sir.totalAssets();

        // Compound (anyone can call - it's a donation)
        uint256 compoundAmount = 50 ether;
        vm.startPrank(bob);
        ir.approve(address(sir), compoundAmount);

        vm.expectEmit(true, false, false, true);
        emit Compounded(bob, compoundAmount, totalAssetsBefore + compoundAmount);

        sir.compound(compoundAmount);
        vm.stopPrank();

        // Alice's shares stay the same but are worth more
        assertEq(sir.balanceOf(alice), sharesBefore);
        assertEq(sir.totalAssets(), totalAssetsBefore + compoundAmount);
        assertEq(sir.totalCompounded(), compoundAmount);

        // Alice's share value increased
        assertGt(sir.convertToAssets(sharesBefore), 100 ether);
    }

    function test_RevertCompound_ZeroAmount() public {
        vm.prank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        sir.compound(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      TRANSFER TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Transfer() public {
        uint256 depositAmount = 100 ether;
        uint256 transferAmount = 30 ether;

        // Alice deposits
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);

        // Transfer to Bob
        sir.transfer(bob, transferAmount);
        vm.stopPrank();

        assertEq(sir.balanceOf(bob), transferAmount);
        assertEq(sir.balanceOf(alice), depositAmount - transferAmount);
    }

    function test_TransferFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 transferAmount = 40 ether;

        // Alice deposits and approves Bob
        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);
        sir.approve(bob, transferAmount);
        vm.stopPrank();

        // Bob transfers from Alice to himself
        vm.prank(bob);
        sir.transferFrom(alice, bob, transferAmount);

        assertEq(sir.balanceOf(bob), transferAmount);
        assertEq(sir.balanceOf(alice), depositAmount - transferAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetWithdrawalPeriod() public {
        uint256 newPeriod = 14 days;

        vm.expectEmit(false, false, false, true);
        emit WithdrawalPeriodUpdated(WITHDRAWAL_PERIOD, newPeriod);

        vm.prank(infrared);
        sir.setWithdrawalPeriod(newPeriod);

        assertEq(sir.withdrawalPeriod(), newPeriod);
    }

    function test_RevertSetWithdrawalPeriod_Unauthorized() public {
        vm.prank(alice);
        // AccessControl will revert with AccessControlUnauthorizedAccount
        vm.expectRevert();
        sir.setWithdrawalPeriod(14 days);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTION TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GetQueuedAmount() public {
        vm.startPrank(alice);
        ir.approve(address(sir), 200 ether);
        sir.deposit(200 ether, alice);

        // Create some requests
        sir.redeem(50 ether, alice, alice);
        uint256 queuedAfterFirst = sir.getQueuedAmount();
        assertGt(queuedAfterFirst, 0);

        sir.redeem(30 ether, alice, alice);
        uint256 queuedAfterSecond = sir.getQueuedAmount();
        assertGt(queuedAfterSecond, queuedAfterFirst);

        // After time passes, queued should decrease
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);
        uint256 queuedAfterDelay = sir.getQueuedAmount();
        assertEq(queuedAfterDelay, 0);

        vm.stopPrank();
    }

    function test_GetClaimableAmount() public {
        vm.startPrank(alice);
        ir.approve(address(sir), 200 ether);
        sir.deposit(200 ether, alice);

        sir.redeem(50 ether, alice, alice);

        // Initially nothing is claimable
        uint256 claimableBefore = sir.getClaimableAmount();
        assertEq(claimableBefore, 0);

        // After time passes, should be claimable
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);
        uint256 claimableAfter = sir.getClaimableAmount();
        assertGt(claimableAfter, 0);

        vm.stopPrank();
    }

    function test_PreviewUnlockTime() public view {
        uint256 unlockTime = sir.previewUnlockTime();
        assertEq(unlockTime, block.timestamp + WITHDRAWAL_PERIOD);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTEGRATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_MultipleUsersWithdrawWithRequests() public {
        // Alice and Bob deposit
        vm.startPrank(alice);
        ir.approve(address(sir), 100 ether);
        uint256 aliceShares = sir.deposit(100 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        ir.approve(address(sir), 200 ether);
        uint256 bobShares = sir.deposit(200 ether, bob);
        vm.stopPrank();

        // Compound increases value for both
        vm.startPrank(compounder);
        ir.approve(address(sir), 90 ether);
        sir.compound(90 ether);
        vm.stopPrank();

        // Both request withdrawals
        vm.prank(alice);
        sir.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        sir.redeem(bobShares, bob, bob);

        // Fast forward
        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);

        // Both claim - should get more than they put in due to compounding
        vm.prank(alice);
        uint256 aliceAssets = sir.claimWithdraw(1);
        assertGt(aliceAssets, 100 ether);

        vm.prank(bob);
        uint256 bobAssets = sir.claimWithdraw(2);
        assertGt(bobAssets, 200 ether);
    }

    function test_SharesBurnedImmediately() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        uint256 shares = sir.deposit(depositAmount, alice);

        // Redeem burns shares immediately
        uint256 sharesBefore = sir.balanceOf(alice);
        sir.redeem(shares, alice, alice);

        // Shares should be burned immediately
        assertEq(sir.balanceOf(alice), sharesBefore - shares);
        assertEq(sir.balanceOf(alice), 0);

        vm.stopPrank();
    }

    function test_TotalAssetsExcludesReserved() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        ir.approve(address(sir), depositAmount);
        sir.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalAssetsBefore = sir.totalAssets();

        // Bob deposits and requests withdrawal
        vm.startPrank(bob);
        ir.approve(address(sir), 200 ether);
        uint256 shares = sir.deposit(200 ether, bob);
        sir.redeem(shares, bob, bob);
        vm.stopPrank();

        // totalAssets should exclude the reserved amount
        uint256 totalAssetsAfter = sir.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore);
        assertGt(sir.totalReserved(), 0);
    }

    function testFuzz_RedeemAndClaim(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);

        vm.startPrank(alice);
        ir.approve(address(sir), amount);
        uint256 shares = sir.deposit(amount, alice);

        sir.redeem(shares, alice, alice);

        vm.warp(block.timestamp + WITHDRAWAL_PERIOD + 1);

        uint256 balanceBefore = ir.balanceOf(alice);
        uint256 assets = sir.claimWithdraw(1);

        assertEq(sir.balanceOf(alice), 0);
        assertEq(ir.balanceOf(alice), balanceBefore + assets);
        assertApproxEqAbs(assets, amount, 1);

        vm.stopPrank();
    }
}
