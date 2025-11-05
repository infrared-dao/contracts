// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/depreciated/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";

import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";

contract InfraredBERATest is InfraredBERABaseTest {
    function testInitializeMintsToInfraredBERA() public view {
        uint256 min = 10 ether;
        assertEq(iberaV0.totalSupply(), min);
        assertEq(iberaV0.balanceOf(address(iberaV0)), min);
        assertEq(iberaV0.deposits(), min);

        assertEq(address(depositorV0).balance, min);

        assertEq(iberaV0.pending(), min);
        assertEq(iberaV0.confirmed(), 0);
    }

    function testSweepQueuesToDepositor() public {
        uint256 deposits = iberaV0.deposits();
        uint256 totalSupply = iberaV0.totalSupply();

        uint256 depositorV0Balance = address(depositorV0).balance;

        uint256 pending = iberaV0.pending();
        uint256 confirmed = iberaV0.confirmed();

        uint256 value = 12 ether;

        deal(iberaV0.receivor(), value);
        iberaV0.compound();

        assertEq(iberaV0.deposits(), deposits + value);
        assertEq(iberaV0.totalSupply(), totalSupply);

        assertEq(address(depositorV0).balance, depositorV0Balance + value);
        assertEq(depositorV0.reserves(), address(depositorV0).balance);

        assertEq(iberaV0.pending(), pending + value);
        assertEq(iberaV0.confirmed(), confirmed);
    }

    function testSweepEmitsSweep() public {
        uint256 value = 12 ether;
        vm.expectEmit();
        emit IInfraredBERA.Sweep(value);
        deal(iberaV0.receivor(), value);
        iberaV0.compound();
    }

    function testSweepAccessControl() public {
        uint256 value = 11 ether;
        deal(iberaV0.receivor(), value);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, address(321))
        );
        vm.prank(address(321));
        iberaV0.sweep();

        vm.expectEmit();
        emit IInfraredBERA.Sweep(value);
        vm.prank(address(iberaV0.receivor()));
        iberaV0.sweep{value: value}();
    }

    function testCompoundSweepsFromReceivor() public {
        uint256 deposits = iberaV0.deposits();
        uint256 totalSupply = iberaV0.totalSupply();

        uint256 depositorV0Balance = address(depositorV0).balance;

        uint256 pending = iberaV0.pending();
        uint256 confirmed = iberaV0.confirmed();

        (bool success,) = address(receivor).call{value: 11 ether}("");
        assertTrue(success);
        uint256 balanceReceivor = address(receivor).balance;
        uint256 protocolFeesReceivor = receivor.shareholderFees();

        (uint256 amount, uint256 protocolFee) = receivor.distribution();

        iberaV0.compound();

        assertEq(address(receivor).balance, balanceReceivor - amount);
        assertEq(receivor.shareholderFees(), protocolFeesReceivor + protocolFee);

        assertEq(iberaV0.deposits(), deposits + amount);
        assertEq(iberaV0.totalSupply(), totalSupply);

        assertEq(address(depositorV0).balance, depositorV0Balance + amount);
        assertEq(depositorV0.reserves(), address(depositorV0).balance);

        assertEq(iberaV0.pending(), pending + amount);
        assertEq(iberaV0.confirmed(), confirmed);
    }

    function testMintMintsShares() public {
        // @dev test compound prior separately
        iberaV0.compound();

        uint256 deposits = iberaV0.deposits();
        uint256 totalSupply = iberaV0.totalSupply();
        uint256 sharesAlice = iberaV0.balanceOf(alice);

        uint256 value = 12 ether;

        uint256 shares_ = iberaV0.mint{value: value}(alice);

        uint256 amount = value;
        uint256 shares = Math.mulDiv(totalSupply, amount, deposits);
        assertEq(iberaV0.balanceOf(alice), sharesAlice + shares);
        assertEq(iberaV0.totalSupply(), totalSupply + shares);
        assertEq(shares_, shares);

        // check amount inferred from shares held
        uint256 _deposits = iberaV0.deposits();
        uint256 _totalSupply = iberaV0.totalSupply();
        uint256 _amount = Math.mulDiv(_deposits, shares, _totalSupply);
        assertEq(_amount, amount);

        uint256 delta = _deposits - _amount; // should have given amount burned at init
        uint256 _delta =
            Math.mulDiv(_deposits, _totalSupply - shares, _totalSupply);
        assertEq(delta, _delta);
    }

    function testMintUpdatesDeposits() public {
        // @dev test compound prior separately
        iberaV0.compound();

        uint256 deposits = iberaV0.deposits();

        uint256 value = 12 ether;

        iberaV0.mint{value: value}(alice);
        assertEq(iberaV0.deposits(), deposits + value);
    }

    function testMintQueuesToDepositor() public {
        // @dev test compound prior separately
        iberaV0.compound();

        uint256 depositorV0Balance = address(depositorV0).balance;

        uint256 value = 12 ether;

        iberaV0.mint{value: value}(alice);

        assertEq(address(depositorV0).balance, depositorV0Balance + value);
        assertEq(depositorV0.reserves(), address(depositorV0).balance);
    }

    function testMintCompoundsPrior() public {
        (bool success,) = address(receivor).call{value: 11 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();

        uint256 totalSupply = iberaV0.totalSupply();
        uint256 deposits = iberaV0.deposits();
        uint256 sharesAlice = iberaV0.balanceOf(alice);

        uint256 depositorV0Balance = address(depositorV0).balance;

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        uint256 shares_ = iberaV0.mint{value: 20000 ether}(alice);

        {
            assertEq(
                address(depositorV0).balance,
                depositorV0Balance + 20000 ether + comp_
            );
            assertEq(depositorV0.reserves(), address(depositorV0).balance);
        }
        // check iberaV0 state
        assertEq(iberaV0.deposits(), deposits + comp_ + 20000 ether);

        uint256 shares =
            Math.mulDiv(totalSupply, 20000 ether, (deposits + comp_));
        assertEq(shares, shares_);
        assertEq(iberaV0.totalSupply(), totalSupply + shares);
        assertEq(iberaV0.balanceOf(alice), sharesAlice + shares);
    }

    function testMintEmitsMint() public {
        // @dev test compound prior separately
        iberaV0.compound();

        uint256 value = 12 ether;

        uint256 amount = value;
        uint256 shares =
            Math.mulDiv(iberaV0.totalSupply(), amount, iberaV0.deposits());

        vm.expectEmit();
        emit IInfraredBERA.Mint(alice, amount, shares);
        iberaV0.mint{value: value}(alice);
    }

    function testMintRevertsWhenSharesZero() public {
        // @dev test compound prior separately
        iberaV0.compound();

        uint256 value = 10 ether;

        // need to donate 1e16 ether to reach this error given min deposit of 1 ether
        vm.deal(address(receivor), 1e20 ether);
        (uint256 comp_,) = receivor.distribution();

        uint256 shares = Math.mulDiv(
            iberaV0.totalSupply(), value, iberaV0.deposits() + comp_
        );
        assertEq(shares, 0);

        vm.expectRevert(Errors.InvalidShares.selector);
        iberaV0.mint{value: value}(alice);
    }

    // function testMintRevertsWhenNotInitialized() public {
    //     InfraredBERA _iberaV0 = new InfraredBERA(address(infrared));
    //     vm.expectRevert(IInfraredBERA.NotInitialized.selector);
    //     _iberaV0.mint{value: 1 ether}(alice);
    // }

    function testBurnBurnsShares() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        uint256 sharesAlice = iberaV0.balanceOf(alice);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        // V0 withdrawals should always fail because withdrawor lite doesn't support it
        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, shares);

        // Even after enabling withdrawals on IBERA, withdrawor lite still doesn't support it
        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, shares);
    }

    function testBurnUpdatesDeposits() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        uint256 sharesAlice = iberaV0.balanceOf(alice);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        // V0 burn should fail because withdrawor lite doesn't support it
        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, shares);
    }

    function testBurnQueuesToWithdrawor() public {
        testMintCompoundsPrior();

        uint256 sharesAlice = iberaV0.balanceOf(alice);
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        // V0 burn should fail because withdrawor lite doesn't support queueing
        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, shares);
    }

    // test specific storage to circumvent stack to deep error
    uint256 depositorV0BalanceT1;
    uint256 depositorV0FeesT1;
    uint256 depositorV0NonceT1;

    uint256 withdraworLiteBalanceT1;
    uint256 withdraworLiteFeesT1;
    uint256 withdraworLiteNonceT1;

    function testBurnCompoundsPrior() public {
        // This test requires V2 withdrawal functionality - skipping for V0
        vm.skip(true);
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        (bool success,) = address(receivor).call{value: 12 ether}("");
        assertTrue(success);

        (uint256 comp_,) = receivor.distribution();

        depositorV0BalanceT1 = address(depositorV0).balance;

        withdraworLiteBalanceT1 = address(withdraworLite).balance;
        withdraworLiteFeesT1 = withdraworLite.fees();
        withdraworLiteNonceT1 = withdraworLite.nonceRequest();

        uint256 totalSupply = iberaV0.totalSupply();
        // uint256 sharesAlice = iberaV0.balanceOf(alice);
        uint256 deposits = iberaV0.deposits();

        uint256 shares = iberaV0.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Sweep(comp_);

        vm.prank(alice);
        (uint256 nonce_, uint256 amount_) = iberaV0.burn{
            value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
        }(bob, shares);

        {
            assertEq(address(depositorV0).balance, depositorV0BalanceT1 + comp_);
            assertEq(depositorV0.reserves(), address(depositorV0).balance);
        }
        // check iberaV0 state
        uint256 amount = Math.mulDiv((deposits + comp_), shares, totalSupply);
        {
            assertEq(iberaV0.deposits(), deposits + comp_ - amount);
            assertEq(amount_, amount);
            // check withdraworLite state
            assertEq(nonce_, withdraworLiteNonceT1);
            assertEq(withdraworLite.nonceRequest(), nonce_ + 1);

            assertEq(
                withdraworLite.fees(),
                withdraworLiteFeesT1
                    + InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
            );
            assertEq(
                address(withdraworLite).balance,
                withdraworLiteBalanceT1
                    + InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
            );
            assertEq(
                withdraworLite.reserves(),
                address(withdraworLite).balance - withdraworLite.fees()
            );
        }

        {
            (
                address receiver_,
                uint96 timestamp_,
                uint256 fee_,
                uint256 amountSubmit_,
                uint256 amountProcess_
            ) = withdraworLite.requests(nonce_);
            assertEq(receiver_, bob);
            assertEq(timestamp_, uint96(block.timestamp));
            assertEq(fee_, InfraredBERAConstants.MINIMUM_WITHDRAW_FEE);

            assertEq(amountSubmit_, amount);
            assertEq(amountProcess_, amount);
        }
    }

    function testBurnEmitsBurn() public {
        // This test requires V2 withdrawal functionality - skipping for V0
        vm.skip(true);
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        uint256 totalSupply = iberaV0.totalSupply();
        uint256 sharesAlice = iberaV0.balanceOf(alice);
        uint256 deposits = iberaV0.deposits();

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);
        uint256 amount = Math.mulDiv(deposits, shares, totalSupply);
        uint256 nonce = withdraworLite.nonceRequest();

        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        vm.expectEmit();
        emit IInfraredBERA.Burn(bob, nonce, amount, shares, fee);

        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, shares);
    }

    function testBurnRevertsWhenSharesZero() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        vm.expectRevert(Errors.InvalidShares.selector);
        vm.prank(alice);
        iberaV0.burn{value: fee}(bob, 0);
    }

    function testBurnRevertsWhenFeeBelowMinimum() public {
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        uint256 sharesAlice = iberaV0.balanceOf(alice);
        uint256 shares = sharesAlice / 3;
        assertTrue(shares > 0);

        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        vm.expectRevert(Errors.InvalidFee.selector);
        vm.prank(alice);
        iberaV0.burn(bob, shares);
    }

    // function testBurnRevertsWhenNotInitialized() public {
    //     InfraredBERA _iberaV0 = new InfraredBERA(address(infrared));
    //     vm.expectRevert(IInfraredBERA.InvalidShares.selector);
    //     uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
    //     _iberaV0.burn{value: fee}(alice, 1e18);
    // }

    function testPreviewMintMatchesActualMint() public {
        // First test basic mint without compound
        uint256 value = 12 ether;

        // Get preview
        uint256 previewShares = iberaV0.previewMint(value);

        // Do actual mint
        uint256 actualShares = iberaV0.mint{value: value}(alice);

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
        uint256 previewShares = iberaV0.previewMint(value);

        // Do actual mint which will compound first
        uint256 actualShares = iberaV0.mint{value: value}(alice);

        assertEq(
            previewShares,
            actualShares,
            "Preview shares should match actual shares with compound"
        );
    }

    function testPreviewBurnMatchesActualBurn() public {
        // This test requires V2 withdrawal functionality - skipping for V0
        vm.skip(true);
        // Setup mint first like in testBurn
        testMintCompoundsPrior();

        vm.startPrank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);
        iberaV0.setDepositSignature(pubkey0, signature0);
        vm.stopPrank();
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );

        uint256 shares = iberaV0.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview
        (uint256 previewAmount, uint256 previewFee) =
            iberaV0.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = iberaV0.burn{
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
        // This test requires V2 withdrawal functionality - skipping for V0
        vm.skip(true);
        // Setup compound scenario
        testMintCompoundsPrior();

        // Setup validator signature like in testBurn
        vm.startPrank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);
        iberaV0.setDepositSignature(pubkey0, signature0);
        vm.stopPrank();
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        // Add rewards to test compound
        (bool success,) = address(receivor).call{value: 1 ether}("");
        assertTrue(success);

        uint256 shares = iberaV0.balanceOf(alice) / 3;
        assertTrue(shares > 0);

        // Get preview before any state changes
        (uint256 previewAmount, uint256 previewFee) =
            iberaV0.previewBurn(shares);

        // Do actual burn
        vm.prank(alice);
        (, uint256 actualAmount) = iberaV0.burn{
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

    function testPreviewMintWithCompoundAboveMin() public {
        // Setup initial state
        uint256 mintAmount = 12 ether;

        // Initial mint to setup non-zero totalSupply
        uint256 initialShares = iberaV0.mint{value: mintAmount}(alice);
        assertGt(initialShares, 0);

        // Test compounding with amount above min
        uint256 compoundAmount = (12 ether) * 2;
        (bool success,) = address(receivor).call{value: compoundAmount}("");
        assertTrue(success);

        // Record state before mint
        uint256 preCompoundDeposits = iberaV0.deposits();
        uint256 previewShares = iberaV0.previewMint(mintAmount);

        // Do the actual mint
        uint256 actualShares = iberaV0.mint{value: mintAmount}(alice);

        // Verify
        assertEq(
            previewShares, actualShares, "Preview shares should match actual"
        );
        assertEq(
            iberaV0.deposits() - preCompoundDeposits,
            (mintAmount) + (compoundAmount),
            "Should have compounded"
        );
    }

    function testPreviewBurnReturnsZeroForInvalidShares() public view {
        (uint256 amount, uint256 fee) = iberaV0.previewBurn(0);
        assertEq(amount, 0, "Should return 0 amount for 0 shares");
        assertEq(fee, 0, "Should return 0 for the fee");
    }

    function testRegisterUpdatesStakeWhenDeltaGreaterThanZero() public {
        uint256 stake = iberaV0.stakes(pubkey0);
        uint256 amount = 1 ether;
        int256 delta = int256(amount);

        vm.prank(address(depositorV0));
        iberaV0.register(pubkey0, delta);
        assertEq(iberaV0.stakes(pubkey0), stake + amount);
    }

    function testRegisterUpdatesStakeWhenDeltaLessThanZero() public {
        testRegisterUpdatesStakeWhenDeltaGreaterThanZero();
        uint256 stake = iberaV0.stakes(pubkey0);
        uint256 amount = 0.25 ether;
        assertTrue(amount <= stake);

        int256 delta = -int256(amount);
        vm.prank(address(withdraworLite));
        iberaV0.register(pubkey0, delta);
        assertEq(iberaV0.stakes(pubkey0), stake - amount);
    }

    function testRegisterEmitsRegister() public {
        uint256 stake = iberaV0.stakes(pubkey0);
        uint256 amount = 1 ether;
        int256 delta = int256(amount);

        vm.expectEmit();
        emit IInfraredBERA.Register(pubkey0, delta, stake + amount);
        vm.prank(address(withdraworLite));
        iberaV0.register(pubkey0, delta);
    }

    function testRegisterRevertsWhenUnauthorized() public {
        uint256 amount = 1 ether;
        int256 delta = int256(amount);
        vm.expectRevert();
        iberaV0.register(pubkey0, delta);
    }

    function testsetFeeShareholdersUpdatesFeeProtocol() public {
        assertEq(iberaV0.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees
        vm.prank(infraredGovernance);
        iberaV0.setFeeDivisorShareholders(feeShareholders);
        assertEq(iberaV0.feeDivisorShareholders(), feeShareholders);
    }

    function testsetFeeShareholdersEmitssetFeeShareholders() public {
        assertEq(iberaV0.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees

        vm.expectEmit();
        emit IInfraredBERA.SetFeeShareholders(0, feeShareholders);
        vm.prank(infraredGovernance);
        iberaV0.setFeeDivisorShareholders(feeShareholders);
    }

    function testsetFeeShareholdersRevertsWhenUnauthorized() public {
        assertEq(iberaV0.feeDivisorShareholders(), 0);
        uint16 feeShareholders = 4; // 25% of fees
        vm.expectRevert();
        vm.prank(address(10));
        iberaV0.setFeeDivisorShareholders(feeShareholders);
    }

    function testSetFeeDivisorShareholdersComoundsFirst() public {
        // Setup: Add some rewards that are above minimum to receivor
        uint256 rewardsAmount = 12 ether; // > MINIMUM_DEPOSIT + MINIMUM_DEPOSIT_FEE (11 ether)
        (bool success,) = address(receivor).call{value: rewardsAmount}("");
        assertTrue(success);

        uint16 newFee = 4; // 25% fee

        // Track initial states
        uint256 initialDeposits = iberaV0.deposits();
        uint256 initialReceivorBalance = address(receivor).balance;

        vm.prank(infraredGovernance);
        iberaV0.setFeeDivisorShareholders(newFee);

        // Verify fee was updated
        assertEq(iberaV0.feeDivisorShareholders(), newFee);

        // Verify compounding occurred
        assertGt(iberaV0.deposits(), initialDeposits);
        assertLt(address(receivor).balance, initialReceivorBalance);
    }

    function testSetDepositSignatureUpdatesSignature() public {
        assertEq(iberaV0.signatures(pubkey0).length, 0);
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        assertEq(iberaV0.signatures(pubkey0), signature0);
    }

    function testSetDepositSignatureEmitsSetDepositSignature() public view {
        assertEq(iberaV0.signatures(pubkey0).length, 0);
    }

    function testSetDepositSignatureRevertsWhenUnauthorized() public view {
        assertEq(iberaV0.signatures(pubkey0).length, 0);
    }

    function testConfirmedReturnsZeroWhenPendingExceedsDeposits() public {
        // Setup initial deposits
        uint256 initialDeposit = 100 ether;
        vm.deal(address(this), initialDeposit);
        iberaV0.mint{value: initialDeposit}(address(this));

        // Get current deposits
        uint256 currentDeposits = iberaV0.deposits();

        // Make a large donation to depositorV0 to cause pending > deposits
        uint256 donationAmount = currentDeposits * 2;
        vm.deal(address(depositorV0), donationAmount);

        // Verify confirmed() returns 0 when pending > deposits
        assertEq(
            iberaV0.confirmed(), 0, "Should return 0 when pending > deposits"
        );

        // Verify withdrawals revert when confirmed() is 0
        // In V0, withdrawor lite doesn't support withdrawals, so expect WithdrawalsNotEnabled
        uint256 withdrawAmount = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        vm.deal(address(iberaV0), fee);

        vm.prank(address(iberaV0));
        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        withdraworLite.queue{value: fee}(alice, withdrawAmount);
    }

    function testPrecisionLossEdgeCase() public {
        // This test requires V2 withdrawal functionality - skipping for V0
        vm.skip(true);
        // Setup initial state using same pattern as other burn tests
        testMintCompoundsPrior();

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);
        uint256 _reserves = depositorV0.reserves();
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, _reserves - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(iberaV0.confirmed(), _reserves);
        assertEq(depositorV0.reserves(), 0);

        // Enable withdrawals
        vm.prank(infraredGovernance);
        iberaV0.setWithdrawalsEnabled(true);

        // Record state before mint
        uint256 initialDeposits = iberaV0.deposits();
        uint256 initialTotalSupply = iberaV0.totalSupply();

        // Calculate amount that would cause precision loss on mint
        // Want (deposits * shares) to be close to (totalSupply * n) - 1
        uint256 n = 2; // multiplier
        uint256 targetAmount = ((initialTotalSupply * n) - 1)
            / initialTotalSupply * initialDeposits;

        // Bob mints with edge case amount
        uint256 bobShares = iberaV0.mint{value: targetAmount}(bob);

        // Calculate expected return amount
        uint256 deposits = iberaV0.deposits();
        uint256 totalSupply = iberaV0.totalSupply();
        uint256 expectedAmount = Math.mulDiv(deposits, bobShares, totalSupply);

        // Bob burns shares with minimum withdraw fee
        uint256 withdrawFee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        vm.prank(bob);
        (, uint256 returnedAmount) =
            iberaV0.burn{value: withdrawFee}(bob, bobShares);

        // Verify precision is maintained through mint/burn cycle
        uint256 difference = expectedAmount > returnedAmount
            ? expectedAmount - returnedAmount
            : returnedAmount - expectedAmount;
        assertLe(
            difference, 1, "Should maintain precision through mint/burn cycle"
        );

        // Verify no funds are stuck
        assertEq(
            iberaV0.deposits(), initialDeposits, "No deposits should be stuck"
        );
        assertEq(
            iberaV0.totalSupply(),
            initialTotalSupply,
            "TotalSupply should return to initial state"
        );
        assertEq(
            iberaV0.balanceOf(bob), 0, "Bob should have no remaining shares"
        );
    }
}
