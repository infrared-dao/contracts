// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";

contract InfraredBERADepositorTest is InfraredBERABaseTest {
    function testQueueUpdatesFees() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 fees = depositor.fees();
        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);

        assertEq(depositor.fees(), fees + fee);
    }

    function testQueueUpdatesNonce() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 nonceSlip = depositor.nonceSlip();
        uint256 nonceSubmit = depositor.nonceSubmit();

        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);

        assertEq(depositor.nonceSlip(), nonceSlip + 1);
        assertEq(depositor.nonceSubmit(), nonceSubmit);
    }

    function testQueueStoresSlip() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 nonceSlip = depositor.nonceSlip();
        (uint96 _timestamp, uint256 _fee, uint256 _amount) =
            depositor.slips(nonceSlip);
        assertEq(_timestamp, 0);
        assertEq(_fee, 0);
        assertEq(_amount, 0);

        vm.prank(address(ibera));
        uint256 nonce_ = depositor.queue{value: value}(amount);

        assertEq(nonce_, nonceSlip);
        (uint96 timestamp_, uint256 fee_, uint256 amount_) =
            depositor.slips(nonce_);
        assertEq(timestamp_, uint96(block.timestamp));
        assertEq(fee_, fee);
        assertEq(amount_, amount);
    }

    function testQueueUpdatesReserves() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 reserves = depositor.reserves();
        uint256 fees = depositor.fees();
        assertEq(reserves, balanceDepositor - fees);

        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);

        assertEq(depositor.reserves(), reserves + amount);
    }

    function testQueueWhenSenderWithdrawor() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(withdrawor), value);
        assertTrue(address(withdrawor).balance >= value);

        vm.prank(address(withdrawor));
        uint256 nonce_ = depositor.queue{value: value}(amount);

        (uint96 timestamp_, uint256 fee_, uint256 amount_) =
            depositor.slips(nonce_);
        assertEq(timestamp_, uint96(block.timestamp));
        assertEq(fee_, fee);
        assertEq(amount_, amount);
    }

    function testQueueEmitsQueue() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);
        uint256 nonce = depositor.nonceSlip();

        vm.expectEmit();
        emit IInfraredBERADepositor.Queue(nonce, amount);
        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);
    }

    function testQueueMultiple() public {
        uint256 value = 288 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;

        uint256 reserves = depositor.reserves();
        uint256 fees = depositor.fees();

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);
        uint256 nonce = depositor.nonceSlip();

        vm.prank(address(ibera));
        depositor.queue{value: 80 ether}(80 ether - fee);
        vm.prank(address(ibera));
        depositor.queue{value: 96 ether}(96 ether - fee);
        vm.prank(address(ibera));
        depositor.queue{value: 112 ether}(112 ether - fee);

        assertEq(depositor.reserves(), reserves + 288 ether - 3 * fee);
        assertEq(depositor.fees(), fees + 3 * fee);
        assertEq(address(depositor).balance, reserves + fees + 288 ether);
        assertEq(depositor.nonceSlip(), nonce + 3);

        (,, uint256 amountFirst_) = depositor.slips(nonce);
        (,, uint256 amountSecond_) = depositor.slips(nonce + 1);
        (,, uint256 amountThird_) = depositor.slips(nonce + 2);
        assertEq(amountFirst_, 80 ether - fee);
        assertEq(amountSecond_, 96 ether - fee);
        assertEq(amountThird_, 112 ether - fee);
    }

    function testQueueRevertsWhenSenderUnauthorized() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 amount = value - fee;

        vm.expectRevert();
        depositor.queue{value: value}(amount);
    }

    function testQueueRevertsWhenAmountZero() public {
        uint256 value = 1 ether;
        uint256 amount = 0;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);
    }

    function testQueueRevertsWhenValueLessThanAmount() public {
        uint256 value = 1 ether;
        uint256 amount = 2 ether;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);
    }

    function testQueueRevertsWhenFeeLessThanMin() public {
        uint256 value = 1 ether;
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE - 1;
        uint256 amount = value - fee;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.expectRevert(Errors.InvalidFee.selector);
        vm.prank(address(ibera));
        depositor.queue{value: value}(amount);
    }

    function testExecuteUpdatesSlipsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(depositor.nonceSlip(), 5); // 1 on init, 3 on test multiple
        assertEq(depositor.nonceSubmit(), 1); // none submitted yet

        uint256 fees = depositor.fees();
        (, uint256 feeFirst, uint256 amountFirst) = depositor.slips(1);
        (, uint256 feeSecond, uint256 amountSecond) = depositor.slips(2);

        uint256 amount = amountFirst + amountSecond;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, amount - InfraredBERAConstants.INITIAL_DEPOSIT
        );

        // nonce submit should have been bumped up by 2 given processed 2 slips
        assertEq(depositor.nonceSubmit(), 3);
        assertEq(depositor.fees(), fees - feeFirst - feeSecond);

        (, uint256 feeFirst_, uint256 amountFirst_) = depositor.slips(1);
        (, uint256 feeSecond_, uint256 amountSecond_) = depositor.slips(2);
        assertEq(feeFirst_, 0);
        assertEq(feeSecond_, 0);
        assertEq(amountFirst_, 0);
        assertEq(amountSecond_, 0);
    }

    function testExecuteUpdatesSlipNonceFeesWhenFillAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();
        uint256 fees = depositor.fees();
        (, uint256 fee, uint256 amount) = depositor.slips(nonce);
        assertTrue(amount > 32 ether); // min deposit for deposit contract
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        (, uint256 fee_, uint256 amount_) = depositor.slips(nonce);
        assertEq(fee_, 0);
        assertEq(amount_, 0);

        assertEq(depositor.fees(), fees - fee);
        assertEq(depositor.nonceSubmit(), nonce + 1);
    }

    function testExecuteMaxStakers() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_DEPOSIT_FEE;
        uint256 value = InfraredBERAConstants.MINIMUM_DEPOSIT + fee;

        uint256 reserves = depositor.reserves();
        uint256 fees = depositor.fees();

        vm.deal(
            address(ibera),
            InfraredBERAConstants.INITIAL_DEPOSIT
                + fee * InfraredBERAConstants.INITIAL_DEPOSIT
                    / InfraredBERAConstants.MINIMUM_DEPOSIT
        );
        assertTrue(address(ibera).balance >= value);

        vm.startPrank(address(ibera));
        for (uint256 i; i < 320; i++) {
            depositor.queue{value: value}(value - fee);
        }
        vm.stopPrank();

        assertEq(depositor.reserves(), reserves + 32 ether);
        assertEq(depositor.fees(), fees + 320 * fee);

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        uint256 initGas = gasleft();

        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        assertLt(initGas - gasleft(), 1000000);
    }

    function testExecuteUpdatesSlipNonceFeesWhenPartialAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();
        uint256 fees = depositor.fees();
        (, uint256 fee, uint256 _amount) = depositor.slips(nonce);
        uint256 amount = ((3 * _amount / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether); // min deposit for deposit contract
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        (, uint256 fee_, uint256 amount_) = depositor.slips(nonce);
        assertEq(fee_, 0);
        assertEq(amount_, _amount - amount);

        assertEq(depositor.fees(), fees - fee);
        assertEq(depositor.nonceSubmit(), nonce); // same nonce since didnt fill
    }

    function testExecuteUpdatesSlipsNonceFeesWhenPartialLastAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();
        uint256 fees = depositor.fees();
        (, uint256 feeFirst, uint256 amountFirst) = depositor.slips(nonce);
        (, uint256 feeSecond, uint256 amountSecond) = depositor.slips(nonce + 1);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        // nonce submit should have been bumped up by only 1 given fully processed 1 slip
        assertEq(depositor.nonceSubmit(), nonce + 1);
        assertEq(depositor.fees(), fees - feeFirst - feeSecond);

        (, uint256 feeFirst_, uint256 amountFirst_) = depositor.slips(nonce);
        (, uint256 feeSecond_, uint256 amountSecond_) =
            depositor.slips(nonce + 1);
        assertEq(feeFirst_, 0);
        assertEq(feeSecond_, 0);
        assertEq(amountFirst_, 0);
        assertEq(amountSecond_, amountSecond - (amount - amountFirst));
    }

    function testExecuteDepositsToDepositContract() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();
        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);
        uint64 amountInGwei = uint64(amount / 1 gwei);
        bytes memory credentials = abi.encodePacked(
            depositor.ETH1_ADDRESS_WITHDRAWAL_PREFIX(),
            uint88(0),
            ibera.withdrawor()
        ); // TODO: check

        address DEPOSIT_CONTRACT = depositor.DEPOSIT_CONTRACT();
        uint64 depositCount = BeaconDeposit(DEPOSIT_CONTRACT).depositCount();
        uint256 balanceZero = address(0).balance;

        vm.expectEmit();
        emit IBeaconDeposit.Deposit(
            pubkey0, credentials, amountInGwei, signature0, depositCount
        );

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        assertEq(address(0).balance, balanceZero + amount);
    }

    function testExecuteRegistersDeposit() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        uint256 stake = ibera.stakes(pubkey0);
        vm.expectEmit();
        emit IInfraredBERA.Register(pubkey0, int256(amount), stake + amount);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
        assertEq(ibera.stakes(pubkey0), stake + amount);
    }

    function testExecuteTransfersETH() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (, uint256 feeFirst, uint256 amountFirst) = depositor.slips(nonce);
        (, uint256 feeSecond, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceKeeper = address(keeper).balance;
        uint256 balanceZero = address(0).balance;

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        assertEq(address(keeper).balance, balanceKeeper + feeFirst + feeSecond);
        assertEq(address(0).balance, balanceZero + amount);
        assertEq(
            address(depositor).balance,
            balanceDepositor - amount - feeFirst - feeSecond
        );
    }

    function testExecuteEmitsExecute() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        vm.expectEmit();
        emit IInfraredBERADepositor.Execute(pubkey0, nonce, nonce + 1, amount);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountExceedsSlips() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);
        uint256 amount = 1000 ether;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSenderNotKeeper() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert();
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenNotEnoughTime() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (uint256 timestampSecond,, uint256 amountSecond) =
            depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert();
        depositor.execute(pubkey0, amount);

        // check can push it through once enough time has passed
        vm.warp(timestampSecond + InfraredBERAConstants.FORCED_MIN_DELAY + 10);
        vm.prank(alice);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenInvalidValidator() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(keeper);
        depositor.execute(bytes(""), amount);
    }

    function testExecuteRevertsWhenAmountZero() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);
        uint256 amount = 0;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountNotDivisibleByGwei() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);
        amount += 1;

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSignatureNotSet() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 nonce = depositor.nonceSubmit();

        (,, uint256 amountFirst) = depositor.slips(nonce);
        (,, uint256 amountSecond) = depositor.slips(nonce + 1);

        assertEq(ibera.signatures(pubkey1).length, 0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > 32 ether);
        assertTrue(amount % 1 gwei == 0);
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.expectRevert(Errors.InvalidSignature.selector);
        vm.prank(keeper);
        depositor.execute(pubkey1, InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testExecuteRevertsWhenAmountGreaterThanMax() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);
        uint256 stake = ibera.stakes(pubkey0);
        uint256 amount = uint256(type(uint64).max) * (1 gwei) - stake + 1 gwei;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteValidatesOperatorForSubsequentDeposits() public {
        // Setup and do initial deposit
        testQueueMultiple();
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Do initial deposit
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Get next valid deposit amount from slip
        uint256 nonce = depositor.nonceSubmit();
        (,, uint256 slipAmount) = depositor.slips(nonce);
        uint256 amount = ((slipAmount) / 1 gwei) * 1 gwei;
        assertTrue(amount >= InfraredBERAConstants.INITIAL_DEPOSIT);

        // Should succeed with subsequent deposit
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        // Verify final state
        assertEq(
            ibera.stakes(pubkey0),
            InfraredBERAConstants.INITIAL_DEPOSIT + amount
        );
    }

    function testExecuteRevertsWhenFirstDepositWithWrongAmount() public {
        testQueueMultiple();
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Test various invalid amounts for first deposit
        uint256[] memory invalidAmounts = new uint256[](3);
        invalidAmounts[0] = InfraredBERAConstants.INITIAL_DEPOSIT - 1;
        invalidAmounts[1] = InfraredBERAConstants.INITIAL_DEPOSIT + 1;
        invalidAmounts[2] = 1 ether;

        for (uint256 i = 0; i < invalidAmounts.length; i++) {
            vm.expectRevert(Errors.InvalidAmount.selector);
            vm.prank(keeper);
            depositor.execute(pubkey0, invalidAmounts[i]);
        }

        // Verify valid initial deposit succeeds
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testExecuteValidatesOperatorAndInitialDeposit() public {
        // Setup initial state using existing pattern
        testQueueMultiple();
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Test first deposit must be INITIAL_DEPOSIT
        uint256 invalidAmount = InfraredBERAConstants.INITIAL_DEPOSIT - 1;
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        depositor.execute(pubkey0, invalidAmount);

        // Do valid initial deposit
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Verify operator is set after initial deposit
        address operator =
            BeaconDeposit(depositor.DEPOSIT_CONTRACT()).getOperator(pubkey0);
        assertEq(operator, IInfraredBERA(depositor.InfraredBERA()).infrared());

        // Get balances for next slip
        uint256 nonce = depositor.nonceSubmit();
        (,, uint256 slipAmount) = depositor.slips(nonce);
        uint256 amount = ((slipAmount) / 1 gwei) * 1 gwei; // Must be gwei aligned
        assertTrue(amount >= InfraredBERAConstants.INITIAL_DEPOSIT); // Must meet minimum

        // Execute subsequent deposit with proper amount from slip
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

        // Verify stakes are updated correctly
        assertEq(
            ibera.stakes(pubkey0),
            InfraredBERAConstants.INITIAL_DEPOSIT + amount
        );
    }
}
