// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/upgrades/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";

import {InfraredBERABaseE2ETest} from "./InfraredBERABase.t.sol";

contract InfraredBERAE2ETest is InfraredBERABaseE2ETest {
    function testSweepQueuesToDepositor() public {
        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();

        uint256 depositorBalance = address(depositor).balance;

        uint256 pending = ibera.pending();
        uint256 confirmed = ibera.confirmed();

        uint256 value = 12 ether;

        deal(
            ibera.receivor(),
            value + IInfraredBERAFeeReceivor(ibera.receivor()).shareholderFees()
        );
        ibera.compound();

        assertEq(ibera.deposits(), deposits + value);
        assertEq(ibera.totalSupply(), totalSupply);

        assertEq(address(depositor).balance, depositorBalance + value);
        assertEq(depositorV2.reserves(), address(depositor).balance);

        assertEq(ibera.pending(), pending + value);
        assertEq(ibera.confirmed(), confirmed);
    }

    function testSweepEmitsSweep() public {
        uint256 value = 12 ether;
        vm.expectEmit();
        emit IInfraredBERA.Sweep(value);
        deal(
            ibera.receivor(),
            value + IInfraredBERAFeeReceivor(ibera.receivor()).shareholderFees()
        );
        ibera.compound();
    }

    function testSweepAccessControl() public {
        uint256 value = 11 ether;
        deal(
            ibera.receivor(),
            value + IInfraredBERAFeeReceivor(ibera.receivor()).shareholderFees()
        );
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

        ibera.compound();

        assertEq(address(receivor).balance, balanceReceivor - amount);
        assertEq(receivor.shareholderFees(), protocolFeesReceivor + protocolFee);

        assertEq(ibera.deposits(), deposits + amount);
        assertEq(ibera.totalSupply(), totalSupply);

        assertEq(address(depositor).balance, depositorBalance + amount);
        assertEq(depositorV2.reserves(), address(depositor).balance);

        assertEq(ibera.pending(), pending + amount);
        assertEq(ibera.confirmed(), confirmed);
    }

    function testMintMintsShares() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 value = 12 ether;

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
        assertEq(_amount, amount - 1);

        uint256 delta = _deposits - _amount; // should have given amount burned at init
        uint256 _delta =
            Math.mulDiv(_deposits, _totalSupply - shares, _totalSupply);
        assertEq(delta, _delta + 1);
    }

    function testMintUpdatesDeposits() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 deposits = ibera.deposits();

        uint256 value = 12 ether;

        ibera.mint{value: value}(alice);
        assertEq(ibera.deposits(), deposits + value);
    }

    function testMintQueuesToDepositor() public {
        // @dev test compound prior separately
        ibera.compound();

        uint256 depositorBalance = address(depositor).balance;

        uint256 value = 12 ether;

        ibera.mint{value: value}(alice);

        assertEq(address(depositor).balance, depositorBalance + value);
        assertEq(depositorV2.reserves(), address(depositor).balance);
    }

    function testMintCompoundsPrior() public {
        (bool success,) = address(receivor).call{value: 11 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();

        uint256 totalSupply = ibera.totalSupply();
        uint256 deposits = ibera.deposits();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 depositorBalance = address(depositor).balance;

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        uint256 shares_ = ibera.mint{value: 20000 ether}(alice);

        {
            assertEq(
                address(depositor).balance,
                depositorBalance + 20000 ether + comp_
            );
            assertEq(depositorV2.reserves(), address(depositor).balance);
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

        uint256 value = 12 ether;

        uint256 amount = value;
        uint256 shares =
            Math.mulDiv(ibera.totalSupply(), amount, ibera.deposits());

        vm.expectEmit();
        emit IInfraredBERA.Mint(alice, amount, shares);
        ibera.mint{value: value}(alice);
    }

    function testBurnBurnsShares() public {
        testMintCompoundsPrior();

        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        ibera.burn(bob, shares);

        assertEq(ibera.totalSupply(), totalSupply - shares + fee);
        assertEq(ibera.balanceOf(alice), sharesAlice - shares);
    }

    function testBurnUpdatesDeposits() public {
        testMintCompoundsPrior();
        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);
        uint256 amount = Math.mulDiv(deposits, shares - fee, totalSupply);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        (, uint256 amount_) = ibera.burn(bob, shares);

        assertEq(amount_, amount);
        assertEq(ibera.deposits(), deposits - amount);
    }

    function testBurnQueuesToWithdrawor() public {
        testMintCompoundsPrior();

        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        uint256 amount = Math.mulDiv(deposits, shares - fee, totalSupply);
        uint256 nonce = withdrawor.requestsFinalisedUntil();

        uint256 withdraworBalance = address(withdrawor).balance;

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.prank(alice);
        (uint256 nonce_,) = ibera.burn(bob, shares);

        assertEq(nonce_, nonce + 1);
        assertEq(address(withdrawor).balance, withdraworBalance);

        (
            ,
            uint88 timestamp_,
            address receiver_,
            uint256 amountSubmit_,
            uint256 amountProcess_
        ) = withdrawor.requests(nonce + 1);
        assertEq(receiver_, bob);
        assertEq(timestamp_, uint88(block.timestamp));

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
        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        (bool success,) = address(receivor).call{value: 12 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();

        depositorBalanceT1 = address(depositor).balance;

        withdraworBalanceT1 = address(withdrawor).balance;

        withdraworNonceT1 = withdrawor.requestsFinalisedUntil();

        uint256 totalSupply = ibera.totalSupply();

        uint256 deposits = ibera.deposits();

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        vm.prank(alice);
        (uint256 nonce_, uint256 amount_) = ibera.burn(bob, shares);

        {
            assertEq(address(depositor).balance, depositorBalanceT1 + comp_);
            assertEq(depositorV2.reserves(), address(depositor).balance);
        }
        // check ibera state
        uint256 amount = Math.mulDiv(
            (deposits + comp_),
            shares - InfraredBERAConstants.MINIMUM_WITHDRAW_FEE,
            totalSupply
        );
        {
            assertEq(ibera.deposits(), deposits + comp_ - amount);
            assertEq(amount_, amount);
            // check withdrawor state
            assertEq(nonce_, withdraworNonceT1 + 1);
            assertEq(address(withdrawor).balance, withdraworBalanceT1);
        }

        {
            (
                ,
                uint88 timestamp_,
                address receiver_,
                uint256 amountSubmit_,
                uint256 amountProcess_
            ) = withdrawor.requests(nonce_);
            assertEq(receiver_, bob);
            assertEq(timestamp_, uint88(block.timestamp));

            assertEq(amountSubmit_, amount);
            assertEq(amountProcess_, amount);
        }
    }

    function testBurnEmitsBurn() public {
        testMintCompoundsPrior();

        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        uint256 totalSupply = ibera.totalSupply();
        uint256 sharesAlice = ibera.balanceOf(alice);
        uint256 deposits = ibera.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);
        uint256 amount = Math.mulDiv(deposits, shares - fee, totalSupply);
        uint256 nonce = withdrawor.requestsFinalisedUntil();

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Burn(bob, nonce + 1, amount, shares, fee);

        vm.prank(alice);
        ibera.burn(bob, shares);
    }

    function testBurnRevertsWhenSharesZero() public {
        testMintCompoundsPrior();
        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.expectRevert(Errors.MinExitFeeNotMet.selector);
        vm.prank(alice);
        ibera.burn(bob, 0);
    }

    function testPreviewMintMatchesActualMint() public {
        // First test basic mint without compound
        uint256 value = 12 ether;

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
        (bool success,) = address(receivor).call{value: 12 ether}("");
        assertTrue(success);

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

    function testPreviewBurnMatchesActualBurn() public {
        // Setup mint first like in testBurn
        testMintCompoundsPrior();

        vm.startPrank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        vm.stopPrank();

        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview
        (uint256 previewAmount,) = iberaV2.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = ibera.burn(bob, shares);

        assertEq(
            previewAmount,
            actualAmount,
            "Preview amount should match actual amount"
        );
    }

    function testPreviewBurnWithCompoundMatchesActualBurn() public {
        // Setup compound scenario
        testMintCompoundsPrior();

        // Setup validator signature like in testBurn
        vm.startPrank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);
        ibera.setDepositSignature(pubkey0, signature0);

        uint256 prevConfirmed = ibera.confirmed();
        vm.stopPrank();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );
        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        // Add rewards to test compound
        (bool success,) = address(receivor).call{value: 1 ether}("");
        assertTrue(success);

        uint256 shares = ibera.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview before any state changes
        (uint256 previewAmount,) = iberaV2.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = ibera.burn(bob, shares);

        assertEq(
            previewAmount,
            actualAmount,
            "Preview amount should match actual amount with compound"
        );
    }

    function testPreviewMintWithCompoundAboveMin() public {
        // Setup initial state
        uint256 mintAmount = 12 ether;

        // Initial mint to setup non-zero totalSupply
        uint256 initialShares = ibera.mint{value: mintAmount}(alice);
        assertGt(initialShares, 0);

        // Test compounding with amount above min
        uint256 compoundAmount = (12 ether) * 2;
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
        (uint256 amount,) = iberaV2.previewBurn(0);
        assertEq(amount, 0, "Should return 0 amount for 0 shares");
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

    function testSetDepositSignatureUpdatesSignature() public {
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        assertEq(ibera.signatures(pubkey0), signature0);
    }

    function testPrecisionLossEdgeCase() public {
        // Setup initial state using same pattern as other burn tests
        testMintCompoundsPrior();

        uint256 prevConfirmed = ibera.confirmed();
        uint256 _reserves = depositorV2.reserves();
        uint256 remainder = _reserves % 1 gwei;
        _reserves -= remainder;
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            _reserves,
            nextBlockTimestamp
        );
        assertEq(ibera.confirmed(), prevConfirmed + _reserves);
        assertEq(depositorV2.reserves(), remainder);

        // Enable withdrawals
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        // Record state before mint
        uint256 initialDeposits = ibera.deposits();
        uint256 initialTotalSupply = ibera.totalSupply();

        // Calculate amount that would cause precision loss on mint
        // Want (deposits * shares) to be close to (totalSupply * n) - 1
        uint256 n = 2; // multiplier
        uint256 targetAmount = ((initialTotalSupply * n) - 1)
            / initialTotalSupply * initialDeposits;

        // Bob mints with edge case amount
        uint256 bobShares = ibera.mint{value: targetAmount}(bob);

        // Calculate expected return amount
        uint256 deposits = ibera.deposits();
        uint256 totalSupply = ibera.totalSupply();
        // Bob burns shares with minimum withdraw fee
        uint256 withdrawFee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 expectedAmount =
            Math.mulDiv(deposits, bobShares - withdrawFee, totalSupply);

        vm.prank(bob);
        (, uint256 returnedAmount) = ibera.burn(bob, bobShares);

        // Verify precision is maintained through mint/burn cycle
        uint256 difference = expectedAmount > returnedAmount
            ? expectedAmount - returnedAmount
            : returnedAmount - expectedAmount;
        assertLe(
            difference, 1, "Should maintain precision through mint/burn cycle"
        );

        // Verify no funds are stuck
        assertEq(
            ibera.deposits(),
            initialDeposits + (deposits * withdrawFee / totalSupply) + 1,
            "No deposits should be stuck"
        );
        assertEq(
            ibera.totalSupply(),
            initialTotalSupply + withdrawFee,
            "TotalSupply should return to initial state"
        );
        assertEq(ibera.balanceOf(bob), 0, "Bob should have no remaining shares");
    }
}
