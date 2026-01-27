// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IRAuction} from "src/periphery/IRAuction.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "src/utils/Errors.sol";

contract IRAuctionTest is Test {
    IRAuction public auction;
    StakedIR public sir;
    MockERC20 public ir;
    MockERC20 public wbera;
    MockERC20 public honey;
    MockInfrared public infrared;

    address public governor = makeAddr("governor");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public keeper = makeAddr("keeper");

    uint256 constant PAYOUT_AMOUNT = 100 ether;
    uint256 constant INITIAL_SIR_DEPOSIT = 10 ether;

    event AuctionClaimed(
        address indexed claimer,
        address indexed rewardToken,
        uint256 rewardAmount,
        uint256 irPaid
    );
    event PayoutAmountSet(uint256 oldAmount, uint256 newAmount);
    event TokensRecovered(
        address indexed token, address indexed to, uint256 amount
    );

    function setUp() public {
        // Deploy tokens
        ir = new MockERC20("Infrared", "IR", 18);
        wbera = new MockERC20("Wrapped BERA", "WBERA", 18);
        honey = new MockERC20("Honey", "HONEY", 18);

        // Deploy StakedIR with proxy
        ir.mint(address(this), INITIAL_SIR_DEPOSIT);

        address sirImpl = address(new StakedIR());

        // Pre-compute proxy address for approval
        address sirProxyAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        ir.approve(sirProxyAddress, INITIAL_SIR_DEPOSIT);

        // Deploy proxy and initialize
        bytes memory sirInitData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), address(this)
        );
        sir = StakedIR(address(new ERC1967Proxy(sirImpl, sirInitData)));

        // Deploy mock Infrared
        address red = makeAddr("red");
        address rewardsFactory = makeAddr("rewardsFactory");
        infrared = new MockInfrared(address(wbera), red, rewardsFactory);

        // Whitelist tokens
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        infrared.updateWhiteListedRewardTokens(address(honey), true);

        // Deploy IRAuction via proxy
        IRAuction implementation = new IRAuction();
        bytes memory initData = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            governor,
            keeper,
            address(ir),
            address(sir),
            PAYOUT_AMOUNT
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        auction = IRAuction(address(proxy));

        // Setup test users
        ir.mint(alice, 10000 ether);
        ir.mint(bob, 10000 ether);
        ir.mint(keeper, 10000 ether);
        wbera.mint(address(auction), 1000 ether);
        honey.mint(address(auction), 1000 ether);
    }

    function setupProxy(address implementation, bytes memory initData)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, initData));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public view {
        assertEq(auction.payoutToken(), address(ir));
        assertEq(auction.payoutAmount(), PAYOUT_AMOUNT);
        assertTrue(auction.hasRole(auction.GOVERNANCE_ROLE(), governor));
    }

    function test_RevertInitialize_ZeroAddress() public {
        IRAuction implementation = new IRAuction();

        // Zero infrared
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRAuction.initialize.selector,
                address(0),
                governor,
                keeper,
                address(ir),
                address(sir),
                PAYOUT_AMOUNT
            )
        );

        // Zero governor
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRAuction.initialize.selector,
                address(infrared),
                address(0),
                keeper,
                address(ir),
                address(sir),
                PAYOUT_AMOUNT
            )
        );

        // Zero IR token
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRAuction.initialize.selector,
                address(infrared),
                governor,
                keeper,
                address(0),
                address(sir),
                PAYOUT_AMOUNT
            )
        );

        // Zero sIR vault
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRAuction.initialize.selector,
                address(infrared),
                governor,
                keeper,
                address(ir),
                address(0),
                PAYOUT_AMOUNT
            )
        );
    }

    function test_RevertInitialize_ZeroPayoutAmount() public {
        IRAuction implementation = new IRAuction();

        vm.expectRevert(Errors.ZeroAmount.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRAuction.initialize.selector,
                address(infrared),
                governor,
                keeper,
                address(ir),
                address(sir),
                0
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      AUCTION TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ClaimFees_SingleToken() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        uint256 sirTotalAssetsBefore = sir.totalAssets();
        uint256 aliceWBERABefore = wbera.balanceOf(alice);

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit AuctionClaimed(alice, address(wbera), amounts[0], PAYOUT_AMOUNT);

        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();

        // Alice received WBERA
        assertEq(wbera.balanceOf(alice), aliceWBERABefore + amounts[0]);

        // sIR total assets increased (IR was compounded)
        assertEq(sir.totalAssets(), sirTotalAssetsBefore + PAYOUT_AMOUNT);
    }

    function test_ClaimFees_MultipleTokens() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();

        assertEq(wbera.balanceOf(alice), amounts[0]);
        assertEq(honey.balanceOf(alice), amounts[1]);
    }

    function test_ClaimFees_SkipsZeroAmounts() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 0; // Zero amount should be skipped

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();

        assertEq(wbera.balanceOf(alice), amounts[0]);
        assertEq(honey.balanceOf(alice), 0); // Not transferred
    }

    function test_RevertClaimFees_ArrayLengthMismatch() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectRevert(Errors.InvalidArrayLength.selector);
        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();
    }

    function test_RevertClaimFees_ZeroPayoutAmount() public {
        // Set payout to 0
        vm.prank(governor);
        auction.setPayoutAmount(1);

        vm.prank(governor);
        vm.expectRevert(Errors.ZeroAmount.selector);
        auction.setPayoutAmount(0);
    }

    function test_RevertClaimFees_ZeroRecipient() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        auction.claimFees(address(0), rewardTokens, amounts);
    }

    function test_RevertClaimFees_InsufficientBalance() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        address poorUser = makeAddr("poorUser");
        ir.mint(poorUser, PAYOUT_AMOUNT - 1); // Not enough

        bytes32 _role = auction.KEEPER_ROLE();
        vm.prank(governor);
        auction.grantRole(_role, poorUser);

        vm.startPrank(poorUser);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectRevert(Errors.InsufficientBalance.selector);
        auction.claimFees(poorUser, rewardTokens, amounts);
        vm.stopPrank();
    }

    function test_RevertClaimFees_PayoutTokenAsReward() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(ir); // Try to claim payout token

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectRevert(Errors.InvalidFeeToken.selector);
        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();
    }

    function test_RevertClaimFees_NotWhitelisted() public {
        MockERC20 maliciousToken = new MockERC20("Malicious", "MAL", 18);
        maliciousToken.mint(address(auction), 100 ether);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(maliciousToken);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectRevert(Errors.FeeTokenNotWhitelisted.selector);
        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();
    }

    function test_RevertClaimFees_InsufficientContractBalance() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10000 ether; // More than contract has

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        vm.expectRevert(Errors.InsufficientFeeTokenBalance.selector);
        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  SWEEP PAYOUT TOKEN TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SweepPayoutToken() public {
        uint256 sirBalanceBefore = ir.balanceOf(address(sir));

        // Send some IR to auction
        ir.mint(address(auction), 500 ether);

        // Anyone can call sweep
        vm.prank(alice);
        auction.sweepPayoutToken();

        assertGt(ir.balanceOf(address(sir)), sirBalanceBefore);
    }

    function test_RevertSweepPayoutToken_ZeroBalance() public {
        // Auction has no IR
        vm.expectRevert(Errors.InsufficientBalance.selector);
        auction.sweepPayoutToken();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetPayoutAmount() public {
        uint256 newAmount = 200 ether;

        vm.expectEmit(false, false, false, true);
        emit PayoutAmountSet(PAYOUT_AMOUNT, newAmount);

        vm.prank(governor);
        auction.setPayoutAmount(newAmount);

        assertEq(auction.payoutAmount(), newAmount);
    }

    function test_RevertSetPayoutAmount_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        auction.setPayoutAmount(200 ether);
    }

    function test_RevertSetPayoutAmount_ZeroAmount() public {
        vm.prank(governor);
        vm.expectRevert(Errors.ZeroAmount.selector);
        auction.setPayoutAmount(0);
    }

    function test_RecoverERC20() public {
        MockERC20 stuckToken = new MockERC20("Stuck", "STUCK", 18);
        stuckToken.mint(address(auction), 100 ether);

        vm.expectEmit(true, true, false, true);
        emit TokensRecovered(address(stuckToken), alice, 100 ether);

        vm.prank(governor);
        auction.recoverERC20(address(stuckToken), alice, 100 ether);

        assertEq(stuckToken.balanceOf(alice), 100 ether);
        assertEq(stuckToken.balanceOf(address(auction)), 0);
    }

    function test_RevertRecoverERC20_Unauthorized() public {
        MockERC20 stuckToken = new MockERC20("Stuck", "STUCK", 18);
        stuckToken.mint(address(auction), 100 ether);

        vm.prank(alice);
        vm.expectRevert();
        auction.recoverERC20(address(stuckToken), alice, 100 ether);
    }

    function test_RevertRecoverERC20_ZeroAddress() public {
        vm.prank(governor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        auction.recoverERC20(address(0), alice, 100 ether);

        vm.prank(governor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        auction.recoverERC20(address(wbera), address(0), 100 ether);
    }

    function test_RevertRecoverERC20_ZeroAmount() public {
        vm.prank(governor);
        vm.expectRevert(Errors.ZeroAmount.selector);
        auction.recoverERC20(address(wbera), alice, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GetTokenBalance() public view {
        uint256 wberaBalance = auction.getTokenBalance(address(wbera));
        assertEq(wberaBalance, 1000 ether);

        uint256 honeyBalance = auction.getTokenBalance(address(honey));
        assertEq(honeyBalance, 1000 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTEGRATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FullAuctionFlow() public {
        // 1. Bob deposits into sIR
        vm.startPrank(bob);
        ir.approve(address(sir), 1000 ether);
        uint256 bobShares = sir.deposit(1000 ether, bob);
        vm.stopPrank();

        uint256 bobShareValueBefore = sir.convertToAssets(bobShares);

        // 2. Rewards accumulate in auction contract (already set up)

        // 3. Alice auctions IR for rewards
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(wbera);
        rewardTokens[1] = address(honey);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);

        auction.claimFees(alice, rewardTokens, amounts);
        vm.stopPrank();

        // 4. Verify outcomes
        // Alice got rewards
        assertEq(wbera.balanceOf(alice), 100 ether);
        assertEq(honey.balanceOf(alice), 50 ether);

        // Bob's sIR shares increased in value
        uint256 bobShareValueAfter = sir.convertToAssets(bobShares);
        assertGt(bobShareValueAfter, bobShareValueBefore);

        // The increase should be roughly PAYOUT_AMOUNT
        assertApproxEqRel(
            bobShareValueAfter - bobShareValueBefore,
            PAYOUT_AMOUNT,
            0.01e18 // 1% tolerance for rounding
        );
    }

    function test_MultipleAuctions() public {
        // Multiple users auction over time
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            ir.mint(user, PAYOUT_AMOUNT);

            address[] memory rewardTokens = new address[](1);
            rewardTokens[0] = address(wbera);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 10 ether;

            vm.startPrank(keeper);
            ir.approve(address(auction), PAYOUT_AMOUNT);
            auction.claimFees(user, rewardTokens, amounts);
            vm.stopPrank();

            assertEq(wbera.balanceOf(user), 10 ether);
        }

        // sIR total assets should have increased by 5 * PAYOUT_AMOUNT
        assertGe(sir.totalAssets(), INITIAL_SIR_DEPOSIT + (5 * PAYOUT_AMOUNT));
    }
}
