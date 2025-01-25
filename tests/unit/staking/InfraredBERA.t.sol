// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";

import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";

contract InfraredBERATest is InfraredBERABaseTest {
    function testInitializeMintsToInfraredBERA() public view {
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        assertEq(ibera.totalSupply(), min);
        assertEq(ibera.balanceOf(address(ibera)), min);
        assertEq(ibera.deposits(), min);

        assertEq(address(depositor).balance, min);

        assertEq(ibera.pending(), min);
        assertEq(ibera.confirmed(), 0);
    }

    function testSweepQueuesToDepositor() public {
        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();

        uint256 depositorBalance = address(depositor).balance;

        uint256 pending = ibera.pending();
        uint256 confirmed = ibera.confirmed();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        deal(ibera.receivor(), value);
        ibera.compound();

        assertEq(ibera.deposits(), deposits + value);
        assertEq(ibera.totalSupply(), totalSupply);

        assertEq(address(depositor).balance, depositorBalance + value);
        assertEq(depositor.reserves(), address(depositor).balance);

        assertEq(ibera.pending(), pending + value);
        assertEq(ibera.confirmed(), confirmed);
    }

    function testSweepEmitsSweep() public {
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);
        vm.expectEmit();
        emit IInfraredBERA.Sweep(value);
        deal(ibera.receivor(), value);
        ibera.compound();
    }

    function testSweepAccessControl() public {
        uint256 value = 11 ether;
        deal(ibera.receivor(), value);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, address(321))
        );
        vm.prank(address(321));
        ibera.sweep();

        vm.expectEmit();
        emit IInfraredBERA.Sweep(value);
        vm.prank(address(ibera.receivor()));
        ibera.sweep{value: value}();
    }

    function testCompoundSweepsFromReceivor() public {
        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();

        uint256 depositorBalance = address(depositor).balance;

        uint256 pending = ibera.pending();
        uint256 confirmed = ibera.confirmed();

        (bool success,) = address(receivor).call{value: 11 ether}("");
        assertTrue(success);
        uint256 balanceReceivor = address(receivor).balance;
        uint256 protocolFeesReceivor = receivor.shareholderFees();

        (uint256 amount, uint256 protocolFee) = receivor.distribution();
        assertTrue(amount >= InfraredBERAConstants.MINIMUM_DEPOSIT);

        ibera.compound();

        assertEq(address(receivor).balance, balanceReceivor - amount);
        assertEq(receivor.shareholderFees(), protocolFeesReceivor + protocolFee);

        assertEq(ibera.deposits(), deposits + amount);
        assertEq(ibera.totalSupply(), totalSupply);

        assertEq(address(depositor).balance, depositorBalance + amount);
        assertEq(depositor.reserves(), address(depositor).balance);

        assertEq(ibera.pending(), pending + amount);
        assertEq(ibera.confirmed(), confirmed);
    }

    function testCompoundPassesWhenDistributionBelowMin() public {
        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();

        uint256 depositorBalance = address(depositor).balance;

        uint256 pending = ibera.pending();
        uint256 confirmed = ibera.confirmed();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 0.01 ether;

        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);

        uint256 protocolFeesReceivor = receivor.shareholderFees();

        (uint256 amount,) = receivor.distribution();
        assertTrue(amount < min);

        ibera.compound();

        assertEq(address(receivor).balance, value);
        assertEq(receivor.shareholderFees(), protocolFeesReceivor);

        assertEq(ibera.deposits(), deposits);
        assertEq(ibera.totalSupply(), totalSupply);

        assertEq(address(depositor).balance, depositorBalance);
        assertEq(depositor.reserves(), address(depositor).balance);

        assertEq(ibera.pending(), pending);
        assertEq(ibera.confirmed(), confirmed);
    }

    function testMintMintsShares() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        uint256 shares_ = ibera.mint{value: value}(alice);

        uint256 amount = value;
        uint256 shares = Math.mulDiv(totalSupply, amount, deposits);
        assertEq(ibera.balanceOf(alice), sharesAlice + shares);
        assertEq(ibera.totalSupply(), totalSupply + shares);
        assertEq(shares_, shares);

        // check amount inferred from shares held
        uint256 _deposits = ibera.deposits();
        uint256 _totalSupply = ibera.totalSupply();
        uint256 _amount = Math.mulDiv(_deposits, shares, _totalSupply);
        assertEq(_amount, amount);

        uint256 delta = _deposits - _amount; // should have given amount burned at init
        assertEq(delta, min);
        uint256 _delta =
            Math.mulDiv(_deposits, _totalSupply - shares, _totalSupply);
        assertEq(delta, _delta);
    }

    function testMintUpdatesDeposits() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 deposits = ibera.deposits();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        ibera.mint{value: value}(alice);
        assertEq(ibera.deposits(), deposits + value);
    }

    function testMintQueuesToDepositor() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 depositorBalance = address(depositor).balance;

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        ibera.mint{value: value}(alice);

        assertEq(address(depositor).balance, depositorBalance + value);
        assertEq(depositor.reserves(), address(depositor).balance);
    }

    function testMintCompoundsPrior() public {
        (bool success,) = address(receivor).call{value: 11 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();

        uint256 totalSupply = ibera.totalSupply();
        uint256 deposits = ibera.deposits();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 depositorBalance = address(depositor).balance;

        assertTrue(comp_ >= InfraredBERAConstants.MINIMUM_DEPOSIT);

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        uint256 shares_ = ibera.mint{value: 20000 ether}(alice);

        {
            assertEq(
                address(depositor).balance,
                depositorBalance + 20000 ether + comp_
            );
            assertEq(depositor.reserves(), address(depositor).balance);
        }
        // check ibera state
        assertEq(ibera.deposits(), deposits + comp_ + 20000 ether);

        uint256 shares =
            Math.mulDiv(totalSupply, 20000 ether, (deposits + comp_));
        assertEq(shares, shares_);
        assertEq(ibera.totalSupply(), totalSupply + shares);
        assertEq(ibera.balanceOf(alice), sharesAlice + shares);
    }

    function testMintEmitsMint() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        uint256 amount = value;
        uint256 shares =
            Math.mulDiv(ibera.totalSupply(), amount, ibera.deposits());

        vm.expectEmit();
        emit IInfraredBERA.Mint(alice, amount, shares);
        ibera.mint{value: value}(alice);
    }

    function testMintRevertsWhenAmountLessThanDepositFee() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 0.001 ether;
        assertTrue(value < min);

        vm.expectRevert(Errors.InvalidAmount.selector);
        ibera.mint{value: value}(alice);
    }

    function testMintRevertsWhenSharesZero() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = min;

        // need to donate 1e16 ether to reach this error given min deposit of 1 ether
        vm.deal(address(receivor), 1e20 ether);
        (uint256 comp_,) = receivor.distribution();

        uint256 shares =
            Math.mulDiv(ibera.totalSupply(), min, ibera.deposits() + comp_);
        assertEq(shares, 0);

        vm.expectRevert(Errors.InvalidShares.selector);
        ibera.mint{value: value}(alice);
    }

    // function testMintRevertsWhenNotInitialized() public {
    //     InfraredBERA _ibera = new InfraredBERA(address(infrared));
    //     vm.expectRevert(IInfraredBERA.NotInitialized.selector);
    //     _ibera.mint{value: 1 ether}(alice);
    // }

    function testBurnBurnsShares() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        vm.prank(alice);
        ibera.burn{value: fee}(bob, shares);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        ibera.burn{value: fee}(bob, shares);

        assertEq(ibera.totalSupply(), totalSupply - shares);
        assertEq(ibera.balanceOf(alice), sharesAlice - shares);
    }

    function testBurnUpdatesDeposits() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);
        uint256 amount = Math.mulDiv(deposits, shares, totalSupply);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        (, uint256 amount_) = ibera.burn{value: fee}(bob, shares);

        assertEq(amount_, amount);
        assertEq(ibera.deposits(), deposits - amount);
    }

    function testBurnQueuesToWithdrawor() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        uint256 amount = Math.mulDiv(deposits, shares, totalSupply);
        uint256 nonce = withdrawor.nonceRequest();

        uint256 withdraworBalance = address(withdrawor).balance;
        uint256 withdraworFees = withdrawor.fees();

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        (uint256 nonce_,) = ibera.burn{value: fee}(bob, shares);

        assertEq(nonce_, nonce);
        assertEq(withdrawor.nonceRequest(), nonce + 1);

        assertEq(withdrawor.fees(), withdraworFees + fee);
        assertEq(address(withdrawor).balance, withdraworBalance + fee);
        assertEq(
            withdrawor.reserves(),
            address(withdrawor).balance - withdrawor.fees()
        );

        (
            address receiver_,
            uint96 timestamp_,
            uint256 fee_,
            uint256 amountSubmit_,
            uint256 amountProcess_
        ) = withdrawor.requests(nonce);
        assertEq(receiver_, bob);
        assertEq(timestamp_, uint96(block.timestamp));
        assertEq(fee_, fee);

        assertEq(amountSubmit_, amount);
        assertEq(amountProcess_, amount);
    }

    // test specific storage to circumvent stack to deep error
    uint256 depositorBalanceT1;
    uint256 depositorFeesT1;
    uint256 depositorNonceT1;

    uint256 withdraworBalanceT1;
    uint256 withdraworFeesT1;
    uint256 withdraworNonceT1;

    function testBurnCompoundsPrior() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        (bool success,) = address(receivor).call{value: 12 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();
        assertTrue(comp_ >= InfraredBERAConstants.MINIMUM_DEPOSIT);

        depositorBalanceT1 = address(depositor).balance;

        withdraworBalanceT1 = address(withdrawor).balance;
        withdraworFeesT1 = withdrawor.fees();
        withdraworNonceT1 = withdrawor.nonceRequest();

        uint256 totalSupply = ibera.totalSupply();
        // uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        vm.prank(alice);
        (uint256 nonce_, uint256 amount_) = ibera.burn{
            value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
        }(bob, shares);

        {
            assertEq(address(depositor).balance, depositorBalanceT1 + comp_);
            assertEq(depositor.reserves(), address(depositor).balance);
        }
        // check ibera state
        uint256 amount = Math.mulDiv((deposits + comp_), shares, totalSupply);
        {
            assertEq(ibera.deposits(), deposits + comp_ - amount);
            assertEq(amount_, amount);
            // check withdrawor state
            assertEq(nonce_, withdraworNonceT1);
            assertEq(withdrawor.nonceRequest(), nonce_ + 1);

            assertEq(
                withdrawor.fees(),
                withdraworFeesT1 + InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
            );
            assertEq(
                address(withdrawor).balance,
                withdraworBalanceT1 + InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
            );
            assertEq(
                withdrawor.reserves(),
                address(withdrawor).balance - withdrawor.fees()
            );
        }

        {
            (
                address receiver_,
                uint96 timestamp_,
                uint256 fee_,
                uint256 amountSubmit_,
                uint256 amountProcess_
            ) = withdrawor.requests(nonce_);
            assertEq(receiver_, bob);
            assertEq(timestamp_, uint96(block.timestamp));
            assertEq(fee_, InfraredBERAConstants.MINIMUM_WITHDRAW_FEE);

            assertEq(amountSubmit_, amount);
            assertEq(amountProcess_, amount);
        }
    }

    function testBurnEmitsBurn() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);
        uint256 amount = Math.mulDiv(deposits, shares, totalSupply);
        uint256 nonce = withdrawor.nonceRequest();

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Burn(bob, nonce, amount, shares, fee);

        vm.prank(alice);
        ibera.burn{value: fee}(bob, shares);
    }

    function testBurnRevertsWhenSharesZero() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        vm.expectRevert(Errors.InvalidShares.selector);
        vm.prank(alice);
        ibera.burn{value: fee}(bob, 0);
    }

    function testBurnRevertsWhenFeeBelowMinimum() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectRevert(Errors.InvalidFee.selector);
        vm.prank(alice);
        ibera.burn(bob, shares);
    }

    // function testBurnRevertsWhenNotInitialized() public {
    //     InfraredBERA _ibera = new InfraredBERA(address(infrared));
    //     vm.expectRevert(IInfraredBERA.InvalidShares.selector);
    //     uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
    //     _ibera.burn{value: fee}(alice, 1e18);
    // }

    function testPreviewMintMatchesActualMint() public {
        // First test basic mint without compound
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 12 ether;
        assertTrue(value > min);

        // Get preview
        uint256 previewShares = ibera.previewMint(value);

        // Do actual mint
        uint256 actualShares = ibera.mint{value: value}(alice);

        // Compare results
        assertEq(
            previewShares,
            actualShares,
            "Preview shares should match actual shares"
        );
    }

    function testPreviewMintWithCompoundMatchesActualMint() public {
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        (bool success,) = address(receivor).call{value: 12 ether}("");
        assertTrue(success);

        (uint256 compAmount,) = receivor.distribution();
        assertTrue(compAmount >= min);

        uint256 value = 20000 ether;

        // Get compound preview before any state changes
        uint256 previewShares = ibera.previewMint(value);

        // Do actual mint which will compound first
        uint256 actualShares = ibera.mint{value: value}(alice);

        assertEq(
            previewShares,
            actualShares,
            "Preview shares should match actual shares with compound"
        );
    }

    function testPreviewMintReturnsZeroForInvalidAmount() public view {
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 value = 0.001 ether;
        assertTrue(value < min);

        uint256 shares = ibera.previewMint(value);
        assertEq(shares, 0, "Should return 0 shares for invalid amount");
    }

    function testPreviewBurnMatchesActualBurn() public {
        // Setup mint first like in testBurn
        testMintCompoundsPrior();

        vm.startPrank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);
        ibera.setDepositSignature(pubkey0, signature0);
        vm.stopPrank();
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview
        (uint256 previewAmount, uint256 previewFee) = ibera.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = ibera.burn{
            value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
        }(bob, shares);

        assertEq(
            previewAmount,
            actualAmount,
            "Preview amount should match actual amount"
        );
        assertEq(
            previewFee,
            InfraredBERAConstants.MINIMUM_WITHDRAW_FEE,
            "Preview fee should match withdraw fee"
        );
    }

    function testPreviewBurnWithCompoundMatchesActualBurn() public {
        // Setup compound scenario
        testMintCompoundsPrior();

        // Setup validator signature like in testBurn
        vm.startPrank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);
        ibera.setDepositSignature(pubkey0, signature0);
        vm.stopPrank();
        uint256 _reserves = depositor.reserves();
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.confirmed(), _reserves);
        assertEq(depositor.reserves(), 0);

        // Add rewards to test compound
        (bool success,) = address(receivor).call{value: 1 ether}("");
        assertTrue(success);

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview before any state changes
        (uint256 previewAmount, uint256 previewFee) = ibera.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = ibera.burn{
            value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
        }(bob, shares);

        assertEq(
            previewAmount,
            actualAmount,
            "Preview amount should match actual amount with compound"
        );
        assertEq(
            previewFee,
            InfraredBERAConstants.MINIMUM_WITHDRAW_FEE,
            "Preview fee should match withdraw fee with compound"
        );
    }

    function testPreviewMintNoCompoundBetweenFeeAndMin() public {
        // Setup initial state
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 mintAmount = 12 ether;

        // Initial mint to setup non-zero totalSupply
        uint256 initialShares = ibera.mint{value: mintAmount}(alice);
        assertGt(initialShares, 0);

        // Test compounding with amount between fee and min+fee
        uint256 compoundAmount = min - 1; // Amount > fee but < min+fee
        (bool success,) = address(receivor).call{value: compoundAmount}("");
        assertTrue(success);

        // Record state before mint
        uint256 preCompoundDeposits = ibera.deposits();
        uint256 previewShares = ibera.previewMint(mintAmount);

        // Do the actual mint
        uint256 actualShares = ibera.mint{value: mintAmount}(alice);

        // Verify
        assertEq(
            previewShares, actualShares, "Preview shares should match actual"
        );
        assertEq(
            ibera.deposits() - preCompoundDeposits,
            mintAmount,
            "Should not have compounded"
        );
    }

    function testPreviewMintWithCompoundAboveMin() public {
        // Setup initial state
        uint256 min = InfraredBERAConstants.MINIMUM_DEPOSIT;
        uint256 mintAmount = 12 ether;

        // Initial mint to setup non-zero totalSupply
        uint256 initialShares = ibera.mint{value: mintAmount}(alice);
        assertGt(initialShares, 0);

        // Test compounding with amount above min
        uint256 compoundAmount = (min) * 2;
        (bool success,) = address(receivor).call{value: compoundAmount}("");
        assertTrue(success);

        // Record state before mint
        uint256 preCompoundDeposits = ibera.deposits();
        uint256 previewShares = ibera.previewMint(mintAmount);

        // Do the actual mint
        uint256 actualShares = ibera.mint{value: mintAmount}(alice);

        // Verify
        assertEq(
            previewShares, actualShares, "Preview shares should match actual"
        );
        assertEq(
            ibera.deposits() - preCompoundDeposits,
            (mintAmount) + (compoundAmount),
            "Should have compounded"
        );
    }

    function testPreviewBurnReturnsZeroForInvalidShares() public view {
        (uint256 amount, uint256 fee) = ibera.previewBurn(0);
        assertEq(amount, 0, "Should return 0 amount for 0 shares");
        assertEq(fee, 0, "Should return 0 for the fee");
    }

    function testRegisterUpdatesStakeWhenDeltaGreaterThanZero() public {
        uint256 stake = ibera.stakes(pubkey0);
        uint256 amount = 1 ether;
        int256 delta = int256(amount);

        vm.prank(address(depositor));
        ibera.register(pubkey0, delta);
        assertEq(ibera.stakes(pubkey0), stake + amount);
    }

    function testRegisterUpdatesStakeWhenDeltaLessThanZero() public {
        testRegisterUpdatesStakeWhenDeltaGreaterThanZero();
        uint256 stake = ibera.stakes(pubkey0);
        uint256 amount = 0.25 ether;
        assertTrue(amount <= stake);

        int256 delta = -int256(amount);
        vm.prank(address(withdrawor));
        ibera.register(pubkey0, delta);
        assertEq(ibera.stakes(pubkey0), stake - amount);
    }

    function testRegisterEmitsRegister() public {
        uint256 stake = ibera.stakes(pubkey0);
        uint256 amount = 1 ether;
        int256 delta = int256(amount);

        vm.expectEmit();
        emit IInfraredBERA.Register(pubkey0, delta, stake + amount);
        vm.prank(address(withdrawor));
        ibera.register(pubkey0, delta);
    }

    function testRegisterRevertsWhenUnauthorized() public {
        uint256 amount = 1 ether;
        int256 delta = int256(amount);
        vm.expectRevert();
        ibera.register(pubkey0, delta);
    }

    function testsetFeeShareholdersUpdatesFeeProtocol() public {
        assertEq(ibera.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees
        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(feeShareholders);
        assertEq(ibera.feeDivisorShareholders(), feeShareholders);
    }

    function testsetFeeShareholdersEmitssetFeeShareholders() public {
        assertEq(ibera.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees

        vm.expectEmit();
        emit IInfraredBERA.SetFeeShareholders(0, feeShareholders);
        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(feeShareholders);
    }

    function testsetFeeShareholdersRevertsWhenUnauthorized() public {
        assertEq(ibera.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees
        vm.expectRevert();
        vm.prank(address(10));
        ibera.setFeeDivisorShareholders(feeShareholders);
    }

    function testSetFeeDivisorShareholdersComoundsFirst() public {
        // Setup: Add some rewards that are above minimum to receivor
        uint256 rewardsAmount = 12 ether; // > MINIMUM_DEPOSIT + MINIMUM_DEPOSIT_FEE (11 ether)
        (bool success,) = address(receivor).call{value: rewardsAmount}("");
        assertTrue(success);

        // Verify we have enough to compound
        (uint256 amount,) = receivor.distribution();
        assertTrue(amount >= InfraredBERAConstants.MINIMUM_DEPOSIT);

        uint16 newFee = 4; // 25% fee

        // Track initial states
        uint256 initialDeposits = ibera.deposits();
        uint256 initialReceivorBalance = address(receivor).balance;

        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(newFee);

        // Verify fee was updated
        assertEq(ibera.feeDivisorShareholders(), newFee);

        // Verify compounding occurred
        assertGt(ibera.deposits(), initialDeposits);
        assertLt(address(receivor).balance, initialReceivorBalance);
    }

    function testSetFeeDivisorShareholdersRevertsWithUncompoundableAmount()
        public
    {
        // Setup: Add some rewards but less than minimum to receivor
        uint256 rewardsAmount = 5 ether; // < MINIMUM_DEPOSIT + MINIMUM_DEPOSIT_FEE (11 ether)
        (bool success,) = address(receivor).call{value: rewardsAmount}("");
        assertTrue(success);

        // Verify amount is non-zero but below minimum
        (uint256 amount,) = receivor.distribution();
        assertTrue(amount > 0);
        assertTrue(amount < InfraredBERAConstants.MINIMUM_DEPOSIT);

        uint16 newFee = 4; // 25% fee

        // Should revert when trying to set new fee with uncompoundable amount
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.CanNotCompoundAccumuldatedBERA.selector);
        ibera.setFeeDivisorShareholders(newFee);

        // Verify fee wasn't changed
        assertEq(ibera.feeDivisorShareholders(), 0);
    }

    function testSetDepositSignatureUpdatesSignature() public {
        assertEq(ibera.signatures(pubkey0).length, 0);
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        assertEq(ibera.signatures(pubkey0), signature0);
    }

    function testSetDepositSignatureEmitsSetDepositSignature() public view {
        assertEq(ibera.signatures(pubkey0).length, 0);
    }

    function testSetDepositSignatureRevertsWhenUnauthorized() public view {
        assertEq(ibera.signatures(pubkey0).length, 0);
    }

    function testConfirmedReturnsZeroWhenPendingExceedsDeposits() public {
        // Setup initial deposits
        uint256 initialDeposit = 100 ether;
        vm.deal(address(this), initialDeposit);
        ibera.mint{value: initialDeposit}(address(this));

        // Get current deposits
        uint256 currentDeposits = ibera.deposits();

        // Make a large donation to depositor to cause pending > deposits
        uint256 donationAmount = currentDeposits * 2;
        vm.deal(address(depositor), donationAmount);

        // Verify confirmed() returns 0 when pending > deposits
        assertEq(
            ibera.confirmed(), 0, "Should return 0 when pending > deposits"
        );

        // Verify withdrawals revert when confirmed() is 0
        uint256 withdrawAmount = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        vm.deal(address(ibera), fee);

        vm.prank(address(ibera));
        vm.expectRevert(Errors.InvalidAmount.selector);
        withdrawor.queue{value: fee}(alice, withdrawAmount);
    }

    function testFail_QueueDonationUnderflow() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);

        vm.deal(address(ibera), 2 * fee);
        withdrawor.nonceRequest();

        vm.deal(address(depositor), 201 ether); // DONATION

        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }
}
