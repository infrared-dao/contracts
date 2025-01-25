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
    uint256 internal constant amountFirst = 25000 ether;
    uint256 internal constant amountSecond = 30000 ether;
    uint256 internal constant amountThird = 35000 ether;

    function testQueueUpdatesFees() public {
        uint256 value = 12 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositor.queue{value: value}();
    }

    function testQueueUpdatesNonce() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositor.queue{value: value}();
    }

    function testQueueStoresSlip() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositor.queue{value: value}();
    }

    function testQueueUpdatesReserves() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 reserves = depositor.reserves();
        assertEq(reserves, balanceDepositor);

        vm.prank(address(ibera));
        depositor.queue{value: value}();

        assertEq(depositor.reserves(), reserves + amount);
    }

    function testQueueWhenSenderWithdrawor() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(withdrawor), value);
        assertTrue(address(withdrawor).balance >= value);

        vm.prank(address(withdrawor));
        depositor.queue{value: value}();
    }

    function testQueueEmitsQueue() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.expectEmit();
        emit IInfraredBERADepositor.Queue(amount);
        vm.prank(address(ibera));
        depositor.queue{value: value}();
    }

    function testQueueMultiple() public {
        uint256 value = 90000 ether;
        uint256 reserves = depositor.reserves();

        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        vm.prank(address(ibera));
        depositor.queue{value: 25000 ether}();
        vm.prank(address(ibera));
        depositor.queue{value: 30000 ether}();
        vm.prank(address(ibera));
        depositor.queue{value: 35000 ether}();

        assertEq(depositor.reserves(), reserves + 90000 ether);
        assertEq(address(depositor).balance, reserves + 90000 ether);
    }

    function testQueueRevertsWhenSenderUnauthorized() public {
        uint256 value = 1 ether;
        uint256 amount = value;

        vm.expectRevert();
        depositor.queue{value: value}();
    }

    function testExecuteUpdatesSlipsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();

        uint256 amountFirst = 25000 ether;
        uint256 amountSecond = 30000 ether;

        uint256 amount = amountFirst + amountSecond;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(
            pubkey0, amount - InfraredBERAConstants.INITIAL_DEPOSIT
        );
    }

    function testExecuteMaxStakers() public {
        uint256 value = InfraredBERAConstants.MINIMUM_DEPOSIT;

        uint256 reserves = depositor.reserves();

        vm.deal(
            address(ibera),
            InfraredBERAConstants.INITIAL_DEPOSIT
                * InfraredBERAConstants.INITIAL_DEPOSIT
                / InfraredBERAConstants.MINIMUM_DEPOSIT
        );
        assertTrue(address(ibera).balance >= value);

        vm.startPrank(address(ibera));
        uint256 maxIterations = InfraredBERAConstants.INITIAL_DEPOSIT
            / InfraredBERAConstants.MINIMUM_DEPOSIT;
        for (uint256 i; i < maxIterations; i++) {
            depositor.queue{value: value}();
        }
        vm.stopPrank();

        assertEq(
            depositor.reserves(),
            reserves + InfraredBERAConstants.INITIAL_DEPOSIT
        );

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        uint256 initGas = gasleft();

        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        assertLt(initGas - gasleft(), 3000000);
    }

    function testExecuteUpdatesSlipNonceFeesWhenPartialAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 _amount = amountSecond;

        uint256 amount = ((3 * _amount / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT); // min deposit for deposit contract
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteUpdatesSlipsNonceFeesWhenPartialLastAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        assertEq(ibera.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteDepositsToDepositContract() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
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

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
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

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceKeeper = address(keeper).balance;
        uint256 balanceZero = address(0).balance;

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);

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

        vm.expectEmit();
        emit IInfraredBERADepositor.Execute(pubkey0, amount);

        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountExceedsSlips() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(ibera.signatures(pubkey0), signature0);
        uint256 amount = 200000 ether;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSenderNotKeeper() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert();
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenInvalidValidator() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
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

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        amount += 1;

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSignatureNotSet() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(ibera.signatures(pubkey1).length, 0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.expectRevert(Errors.InvalidSignature.selector);
        vm.prank(keeper);
        depositor.execute(pubkey1, InfraredBERAConstants.INITIAL_DEPOSIT);
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
        uint256 amount = ((amountFirst) / 1 gwei) * 1 gwei;
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
        uint256 amount = ((amountFirst) / 1 gwei) * 1 gwei; // Must be gwei aligned
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

    function testExecuteRevertsWhenExceedsMaxEffectiveBalance() public {
        // Define MAX_EFFECTIVE_BALANCE in gwei (10 million BERA)
        uint256 maxEffectiveBalance =
            InfraredBERAConstants.MAX_EFFECTIVE_BALANCE;

        // Queue the initial deposit amount
        _queueFundsForDeposit(InfraredBERAConstants.INITIAL_DEPOSIT);

        // Set the deposit signature for the validator
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        // Execute the initial deposit
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Verify the validator's staked balance after the initial deposit
        uint256 currentStake = ibera.stakes(pubkey0);
        assertEq(currentStake, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Queue additional funds for the excess deposit
        uint256 remainingSpace = maxEffectiveBalance - currentStake;
        uint256 excessAmount = remainingSpace + 1 gwei; // This would push the total stake over the limit
        _queueFundsForDeposit(excessAmount);

        // Attempt to deposit the excess amount
        vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
        vm.prank(keeper);
        depositor.execute(pubkey0, excessAmount);
    }

    function _queueFundsForDeposit(uint256 amount) internal {
        uint256 value = amount;

        // Ensure the ibera contract has enough funds
        vm.deal(address(ibera), value);
        assertTrue(address(ibera).balance >= value);

        // Queue the funds for deposit
        vm.prank(address(ibera));
        depositor.queue{value: value}();
    }
}
