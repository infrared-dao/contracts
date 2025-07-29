// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlUpgradeable} from
    "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {
    UUPSUpgradeable,
    ERC1967Utils
} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {HarvestBaseCollector} from "src/staking/HarvestBaseCollector.sol";
import "tests/unit/core/Infrared/Helper.sol";
import {Errors} from "src/utils/Errors.sol";

contract HarvestBaseCollectorTest is Helper {
    HarvestBaseCollector public harvestBaseCollector;

    uint256 payoutAmount;

    function setUp() public virtual override {
        super.setUp();

        payoutAmount = 10 ether;

        harvestBaseCollector = HarvestBaseCollector(
            payable(setupProxy(address(new HarvestBaseCollector())))
        );
        // vm.prank(infraredGovernance);
        harvestBaseCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );
    }

    function testInitialize() public view {
        assertEq(harvestBaseCollector.feeReceivor(), address(receivor));
        assertEq(address(harvestBaseCollector.ibgt()), address(ibgt));
        assertEq(harvestBaseCollector.payoutAmount(), 10 ether);
        assertEq(address(harvestBaseCollector.wbera()), address(wbera));
        assertTrue(
            harvestBaseCollector.hasRole(
                harvestBaseCollector.DEFAULT_ADMIN_ROLE(), infraredGovernance
            )
        );
        assertTrue(
            harvestBaseCollector.hasRole(
                harvestBaseCollector.GOVERNANCE_ROLE(), infraredGovernance
            )
        );
        assertTrue(
            harvestBaseCollector.hasRole(
                harvestBaseCollector.KEEPER_ROLE(), keeper
            )
        );
    }

    function testInitializeRevertsZeroAddress() public {
        // Deploy a new uninitialized proxy for testing reverts
        HarvestBaseCollector newCollector = HarvestBaseCollector(
            payable(setupProxy(address(new HarvestBaseCollector())))
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        newCollector.initialize(
            address(0), // _infrared zero
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        newCollector.initialize(
            address(infrared),
            address(0), // _gov zero
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        newCollector.initialize(
            address(infrared),
            infraredGovernance,
            address(0), // _keeper zero
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        newCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(0), // _wbera zero
            address(receivor),
            payoutAmount
        );

        vm.expectRevert(Errors.ZeroAddress.selector);
        newCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(0), // _feeReceivor zero
            payoutAmount
        );
    }

    function testInitializeRevertsZeroAmount() public {
        // Deploy a new uninitialized proxy for testing revert
        HarvestBaseCollector newCollector = HarvestBaseCollector(
            payable(setupProxy(address(new HarvestBaseCollector())))
        );

        vm.expectRevert(Errors.ZeroAmount.selector);
        newCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            0 // _payoutAmount zero
        );
    }

    function testInitializeEmitsEvent() public {
        // Deploy a new uninitialized proxy to capture event
        HarvestBaseCollector newCollector = HarvestBaseCollector(
            payable(setupProxy(address(new HarvestBaseCollector())))
        );

        vm.expectEmit(true, true, false, true);
        emit HarvestBaseCollector.PayoutAmountSet(0, payoutAmount);
        newCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );
    }

    function testReinitializeReverts() public {
        vm.expectRevert();
        harvestBaseCollector.initialize(
            address(infrared),
            infraredGovernance,
            keeper,
            address(ibgt),
            address(wbera),
            address(receivor),
            payoutAmount
        );
    }

    function testSetPayoutAmount() public {
        vm.startPrank(infraredGovernance);
        harvestBaseCollector.setPayoutAmount(1 ether);
        vm.stopPrank();
    }

    function testSetPayoutAmountEmitsEvent() public {
        uint256 newAmount = 1 ether;
        vm.expectEmit(true, true, false, true);
        emit HarvestBaseCollector.PayoutAmountSet(payoutAmount, newAmount);
        vm.prank(infraredGovernance);
        harvestBaseCollector.setPayoutAmount(newAmount);
    }

    function testSetPayoutAmountRevertsZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(infraredGovernance);
        harvestBaseCollector.setPayoutAmount(0);
    }

    function testSetPayoutAmountWhenNotGovernor() public {
        vm.startPrank(keeper);
        vm.expectRevert();
        harvestBaseCollector.setPayoutAmount(1 ether);
        vm.stopPrank();
    }

    function testClaimFeeSuccess() public virtual {
        // Arrange
        address recipient = address(3);

        uint256 feeAmount = 10 ether;
        // simulate bribes collected by the harvestBaseCollector contract
        deal(address(ibgt), address(harvestBaseCollector), 10 ether);

        // uint256 payoutAmount = harvestBaseCollector.payoutAmount();

        // since payoutToken is wbera, deal and deposit
        vm.deal(keeper, payoutAmount);
        vm.prank(keeper);
        wbera.deposit{value: payoutAmount}();

        uint256 initialReceiverBal = address(receivor).balance;
        uint256 initialRecipientBal = ibgt.balanceOf(recipient);
        uint256 initialContractWberaBal =
            wbera.balanceOf(address(harvestBaseCollector));
        uint256 initialContractEthBal = address(harvestBaseCollector).balance;

        // Act
        // vm.deal(address(wbera), 10 ether);
        vm.startPrank(keeper);
        wbera.approve(address(harvestBaseCollector), payoutAmount);
        harvestBaseCollector.claimFee(recipient, feeAmount);
        vm.stopPrank();

        // Assert
        assertEq(address(receivor).balance, initialReceiverBal + payoutAmount);
        assertEq(ibgt.balanceOf(recipient), initialRecipientBal + feeAmount);
        assertEq(
            wbera.balanceOf(address(harvestBaseCollector)),
            initialContractWberaBal
        );
        assertEq(address(harvestBaseCollector).balance, initialContractEthBal);
    }

    function testClaimFeeEmitsEvent() public {
        address recipient = address(3);
        uint256 feeAmount = 10 ether;
        deal(address(ibgt), address(harvestBaseCollector), feeAmount);

        vm.deal(keeper, payoutAmount);
        vm.prank(keeper);
        wbera.deposit{value: payoutAmount}();

        vm.startPrank(keeper);
        wbera.approve(address(harvestBaseCollector), payoutAmount);

        vm.expectEmit(true, true, true, true);
        emit HarvestBaseCollector.FeeClaimed(keeper, recipient, feeAmount);

        harvestBaseCollector.claimFee(recipient, feeAmount);
        vm.stopPrank();
    }

    function testClaimFeeRevertsZeroRecipient() public {
        deal(address(ibgt), address(harvestBaseCollector), 10 ether);

        vm.deal(keeper, payoutAmount);
        vm.startPrank(keeper);
        wbera.deposit{value: payoutAmount}();
        wbera.approve(address(harvestBaseCollector), payoutAmount);

        vm.expectRevert(Errors.ZeroAddress.selector);
        harvestBaseCollector.claimFee(address(0), 10 ether);
        vm.stopPrank();
    }

    function testClaimFeeInsufficientBalanceReverts() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        harvestBaseCollector.claimFee(keeper, 10 ether);
    }

    function testClaimFeeInsufficientAllowanceReverts() public {
        deal(address(ibgt), address(harvestBaseCollector), 10 ether);

        vm.deal(keeper, payoutAmount);
        vm.startPrank(keeper);
        wbera.deposit{value: payoutAmount}();
        // No approve

        vm.expectRevert();
        harvestBaseCollector.claimFee(keeper, 10 ether);
        vm.stopPrank();
    }

    function testClaimFeeInsufficientFeeTokenReverts() public {
        // since payoutToken is wbera, deal and deposit
        vm.deal(keeper, payoutAmount);
        vm.startPrank(keeper);
        wbera.deposit{value: payoutAmount}();
        wbera.approve(address(harvestBaseCollector), payoutAmount);
        vm.expectRevert(Errors.InsufficientFeeTokenBalance.selector);
        harvestBaseCollector.claimFee(keeper, 200 ether); // More than contract has
        vm.stopPrank();
    }

    function testClaimFeeNotKeeperReverts() public {
        vm.expectRevert(); // Role-based revert
        harvestBaseCollector.claimFee(address(3), 10 ether);
    }

    function testSweepSuccessOnlyEth() public {
        // Deal ETH directly to contract
        uint256 sweepAmount = 1 ether;
        vm.deal(address(harvestBaseCollector), sweepAmount);

        uint256 initialReceiverBal = address(receivor).balance;
        uint256 initialContractBal = address(harvestBaseCollector).balance;

        vm.prank(keeper);
        harvestBaseCollector.sweep();

        assertEq(address(harvestBaseCollector).balance, 0);
        assertEq(address(receivor).balance, initialReceiverBal + sweepAmount);
        assertEq(wbera.balanceOf(address(harvestBaseCollector)), 0); // No WBERA involved
    }

    function testSweepSuccessOnlyWbera() public {
        // Deal WBERA directly to contract
        uint256 sweepAmount = 1 ether;
        deal(address(wbera), address(harvestBaseCollector), sweepAmount);
        deal(address(wbera), sweepAmount);

        uint256 initialReceiverBal = address(receivor).balance;
        uint256 initialContractWberaBal =
            wbera.balanceOf(address(harvestBaseCollector));

        vm.prank(keeper);
        harvestBaseCollector.sweep();

        assertEq(wbera.balanceOf(address(harvestBaseCollector)), 0);
        assertEq(address(receivor).balance, initialReceiverBal + sweepAmount);
        assertEq(address(harvestBaseCollector).balance, 0); // ETH should be 0 after withdraw
    }

    function testSweepSuccessBoth() public {
        uint256 ethAmount = 1 ether;
        uint256 wberaAmount = 2 ether;
        vm.deal(address(harvestBaseCollector), ethAmount);
        deal(address(wbera), address(harvestBaseCollector), wberaAmount);
        deal(address(wbera), wberaAmount);

        uint256 initialReceiverBal = address(receivor).balance;

        vm.prank(keeper);
        harvestBaseCollector.sweep();

        assertEq(address(harvestBaseCollector).balance, 0);
        assertEq(wbera.balanceOf(address(harvestBaseCollector)), 0);
        assertEq(
            address(receivor).balance,
            initialReceiverBal + ethAmount + wberaAmount
        );
    }

    function testSweepNoBalanceDoesNothing() public {
        uint256 initialReceiverBal = address(receivor).balance;

        vm.prank(keeper);
        harvestBaseCollector.sweep();

        assertEq(address(harvestBaseCollector).balance, 0);
        assertEq(wbera.balanceOf(address(harvestBaseCollector)), 0);
        assertEq(address(receivor).balance, initialReceiverBal);
    }

    function testSweepNotKeeperReverts() public {
        vm.expectRevert(); // Assume role revert
        harvestBaseCollector.sweep();
    }

    function testReceiveEth() public {
        uint256 sendAmount = 1 ether;
        vm.deal(address(this), sendAmount);

        // Send ETH to contract via fallback
        (bool success,) =
            address(harvestBaseCollector).call{value: sendAmount}("");
        assertTrue(success);

        assertEq(address(harvestBaseCollector).balance, sendAmount);
    }
}
