// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

import {InfraredBERABaseE2ETest} from "./InfraredBERABase.t.sol";

contract InfraredBERADepositorE2ETest is InfraredBERABaseE2ETest {
    uint256 internal constant amountFirst = 25000 ether;
    uint256 internal constant amountSecond = 30000 ether;
    uint256 internal constant amountThird = 35000 ether;

    function testQueueUpdatesFees() public {
        uint256 value = 12 ether;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositorV2.queue{value: value}();
    }

    function testQueueUpdatesNonce() public {
        uint256 value = 11 ether;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositorV2.queue{value: value}();
    }

    function testQueueStoresSlip() public {
        uint256 value = 11 ether;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositorV2.queue{value: value}();
    }

    function testQueueUpdatesReserves() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 reserves = depositorV2.reserves();
        assertEq(reserves, balanceDepositor);

        vm.prank(address(ibera));
        depositorV2.queue{value: value}();

        assertEq(depositorV2.reserves(), reserves + amount);
    }

    function testQueueWhenSenderWithdrawor() public {
        uint256 value = 11 ether;

        vm.deal(address(withdrawor), value);
        assertTrue(address(withdrawor).balance >= value);

        vm.prank(address(withdrawor));
        depositorV2.queue{value: value}();
    }

    function testQueueEmitsQueue() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.expectEmit();
        emit IInfraredBERADepositor.Queue(amount);
        vm.prank(address(ibera));
        depositorV2.queue{value: value}();
    }

    function testQueueMultiple() public {
        uint256 value = 90000 ether;
        uint256 reserves = depositorV2.reserves();

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositorV2.queue{value: 25000 ether}();
        vm.prank(address(ibera));
        depositorV2.queue{value: 30000 ether}();
        vm.prank(address(ibera));
        depositorV2.queue{value: 35000 ether}();

        assertEq(depositorV2.reserves(), reserves + 90000 ether);
        assertEq(address(depositor).balance, reserves + 90000 ether);
    }

    function testQueueRevertsWhenSenderUnauthorized() public {
        uint256 value = 1 ether;

        vm.expectRevert();
        depositorV2.queue{value: value}();
    }

    function testExecuteUpdatesSlipsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();

        uint256 amount = amountFirst + amountSecond;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount - InfraredBERAConstants.INITIAL_DEPOSIT,
            nextBlockTimestamp
        );
    }

    function testExecuteUpdatesSlipNonceFeesWhenPartialAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 _amount = amountSecond;

        uint256 amount = (((3 * _amount) / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT); // min deposit for deposit contract
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteUpdatesSlipsNonceFeesWhenPartialLastAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        // sync balances to pass verification
        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteDepositsToDepositContract() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        uint64 amountInGwei = uint64(amount / 1 gwei);
        bytes memory credentials = abi.encodePacked(
            depositorV2.ETH1_ADDRESS_WITHDRAWAL_PREFIX(),
            uint88(0),
            ibera.withdrawor()
        ); // TODO: check

        address DEPOSIT_CONTRACT = depositorV2.DEPOSIT_CONTRACT();
        uint64 depositCount = BeaconDeposit(DEPOSIT_CONTRACT).depositCount();
        uint256 balanceZero = address(0).balance;

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        vm.expectEmit();
        emit IBeaconDeposit.Deposit(
            pubkey0, credentials, amountInGwei, signature0, depositCount
        );

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );

        assertEq(address(0).balance, balanceZero + amount);
    }

    function testExecuteRegistersDeposit() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
        uint256 stake = ibera.stakes(pubkey0);
        vm.expectEmit();
        emit IInfraredBERA.Register(pubkey0, int256(amount), stake + amount);

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        assertEq(ibera.stakes(pubkey0), stake + amount);
    }

    function testExecuteTransfersETH() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceKeeper = address(keeper).balance;
        uint256 balanceZero = address(0).balance;

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );

        assertEq(address(keeper).balance, balanceKeeper);
        assertEq(address(0).balance, balanceZero + amount);
        assertEq(address(depositor).balance, balanceDepositor - amount);
    }

    function testExecuteEmitsExecute() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
        vm.expectEmit();
        emit IInfraredBERADepositor.Execute(pubkey0, amount);

        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenSenderNotKeeper() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert();
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenAmountZero() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);
        uint256 amount = 0;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenAmountNotDivisibleByGwei() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        amount += 1;

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenExceedsMaxEffectiveBalance() public {
        // Define MAX_EFFECTIVE_BALANCE in gwei (10 million BERA)
        uint256 maxEffectiveBalance =
            InfraredBERAConstants.MAX_EFFECTIVE_BALANCE;

        // Queue the initial deposit amount
        _queueFundsForDeposit(InfraredBERAConstants.INITIAL_DEPOSIT);

        // Set the deposit signature for the validator
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Verify the validator's staked balance after the initial deposit
        uint256 currentStake = ibera.stakes(pubkey0);

        // Queue additional funds for the excess deposit
        uint256 remainingSpace = maxEffectiveBalance - currentStake;
        uint256 excessAmount = remainingSpace + 1 gwei; // This would push the total stake over the limit
        _queueFundsForDeposit(excessAmount);

        vm.prank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        // Attempt to deposit the excess amount
        vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
        vm.prank(keeper);
        depositorV2.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            excessAmount,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenForcedExitedValidatorExists() public {
        // Minimum amount a validator can stake.
        uint256 minimumDeposit = InfraredBERAConstants.INITIAL_DEPOSIT;

        // Queue the initial deposit amount
        _queueFundsForDeposit(minimumDeposit);

        // Set the deposit signature for the validator
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Deal funds to the withdrawor contract to simulate a forced exit
        vm.deal(address(withdrawor), minimumDeposit);
    }

    function _queueFundsForDeposit(uint256 amount) internal {
        uint256 value = amount;

        // Ensure the ibera contract has enough funds
        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        // Queue the funds for deposit
        vm.prank(address(ibera));
        depositorV2.queue{value: value}();
    }
}
