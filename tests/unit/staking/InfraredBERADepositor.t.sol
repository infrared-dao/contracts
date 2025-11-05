// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/depreciated/interfaces/IInfraredBERA.sol";
import {IInfraredBERADepositor} from "src/interfaces/IInfraredBERADepositor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";

contract InfraredBERADepositorTest is InfraredBERABaseTest {
    uint256 internal constant amountFirst = 25000 ether;
    uint256 internal constant amountSecond = 30000 ether;
    uint256 internal constant amountThird = 35000 ether;

    function testQueueUpdatesFees() public {
        uint256 value = 12 ether;

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();
    }

    function testQueueUpdatesNonce() public {
        uint256 value = 11 ether;

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();
    }

    function testQueueStoresSlip() public {
        uint256 value = 11 ether;

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();
    }

    function testQueueUpdatesReserves() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        uint256 balanceDepositor = address(depositorV0).balance;
        uint256 reserves = depositorV0.reserves();
        assertEq(reserves, balanceDepositor);

        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();

        assertEq(depositorV0.reserves(), reserves + amount);
    }

    function testQueueWhenSenderWithdrawor() public {
        uint256 value = 11 ether;

        vm.deal(address(withdraworLite), value);
        assertTrue(address(withdraworLite).balance >= value);

        vm.prank(address(withdraworLite));
        depositorV0.queue{value: value}();
    }

    function testQueueEmitsQueue() public {
        uint256 value = 11 ether;
        uint256 amount = value;

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        vm.expectEmit();
        emit IInfraredBERADepositor.Queue(amount);
        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();
    }

    function testQueueMultiple() public {
        uint256 value = 90000 ether;
        uint256 reserves = depositorV0.reserves();

        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        vm.prank(address(iberaV0));
        depositorV0.queue{value: 25000 ether}();
        vm.prank(address(iberaV0));
        depositorV0.queue{value: 30000 ether}();
        vm.prank(address(iberaV0));
        depositorV0.queue{value: 35000 ether}();

        assertEq(depositorV0.reserves(), reserves + 90000 ether);
        assertEq(address(depositorV0).balance, reserves + 90000 ether);
    }

    function testQueueRevertsWhenSenderUnauthorized() public {
        uint256 value = 1 ether;

        vm.expectRevert();
        depositorV0.queue{value: value}();
    }

    function testExecuteUpdatesSlipsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();

        uint256 amount = amountFirst + amountSecond;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositorV0.execute(
            pubkey0, amount - InfraredBERAConstants.INITIAL_DEPOSIT
        );
    }

    function testExecuteMaxStakers() public {
        uint256 value = 10 ether;

        uint256 reserves = depositorV0.reserves();

        vm.deal(
            address(iberaV0),
            (
                InfraredBERAConstants.INITIAL_DEPOSIT
                    * InfraredBERAConstants.INITIAL_DEPOSIT
            )
        );
        assertTrue(address(iberaV0).balance >= value);

        vm.startPrank(address(iberaV0));
        uint256 maxIterations = InfraredBERAConstants.INITIAL_DEPOSIT / value;
        for (uint256 i; i < maxIterations; i++) {
            depositorV0.queue{value: value}();
        }
        vm.stopPrank();

        assertEq(
            depositorV0.reserves(),
            reserves + InfraredBERAConstants.INITIAL_DEPOSIT
        );

        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testExecuteUpdatesSlipNonceFeesWhenPartialAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 _amount = amountSecond;

        uint256 amount = (((3 * _amount) / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT); // min deposit for deposit contract
        assertTrue(amount % 1 gwei == 0);

        assertEq(iberaV0.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteUpdatesSlipsNonceFeesWhenPartialLastAmount() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        assertEq(iberaV0.signatures(pubkey0), signature0);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteDepositsToDepositContract() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        uint64 amountInGwei = uint64(amount / 1 gwei);
        bytes memory credentials = abi.encodePacked(
            depositorV0.ETH1_ADDRESS_WITHDRAWAL_PREFIX(),
            uint88(0),
            iberaV0.withdrawor()
        ); // TODO: check

        address DEPOSIT_CONTRACT = depositorV0.DEPOSIT_CONTRACT();
        uint64 depositCount = BeaconDeposit(DEPOSIT_CONTRACT).depositCount();
        uint256 balanceZero = address(0).balance;

        vm.expectEmit();
        emit IBeaconDeposit.Deposit(
            pubkey0, credentials, amountInGwei, signature0, depositCount
        );

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);

        assertEq(address(0).balance, balanceZero + amount);
    }

    function testBypassAttackInitDepositReverts() public {
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        assertEq(iberaV0.signatures(pubkey0), signature0);
        address user = address(560);
        deal(address(user), InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(user);
        iberaV0.mint{value: InfraredBERAConstants.INITIAL_DEPOSIT}(user);

        address DEPOSIT_CONTRACT = depositorV0.DEPOSIT_CONTRACT();
        uint256 balanceZero = address(0).balance;

        // bypass attack
        address attacker = address(690);
        deal(attacker, InfraredBERAConstants.INITIAL_DEPOSIT);
        bytes memory credFaulty = abi.encodePacked(
            depositorV0.ETH1_ADDRESS_WITHDRAWAL_PREFIX(), uint88(0), attacker
        );
        vm.prank(attacker);
        BeaconDeposit(DEPOSIT_CONTRACT).deposit{
            value: InfraredBERAConstants.INITIAL_DEPOSIT
        }(pubkey0, credFaulty, signature1, address(infrared));

        vm.prank(keeper);
        vm.expectRevert(Errors.OperatorAlreadySet.selector);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        assertEq(
            address(0).balance,
            balanceZero + InfraredBERAConstants.INITIAL_DEPOSIT
        );
    }

    function testOperatorAttackInitDepositReverts() public {
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        assertEq(iberaV0.signatures(pubkey0), signature0);
        address user = address(560);
        deal(address(user), InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(user);
        iberaV0.mint{value: InfraredBERAConstants.INITIAL_DEPOSIT}(user);

        address DEPOSIT_CONTRACT = depositorV0.DEPOSIT_CONTRACT();
        uint256 balanceZero = address(0).balance;

        // bypass attack
        address attacker = address(690);
        deal(attacker, InfraredBERAConstants.INITIAL_DEPOSIT);
        bytes memory credFaulty = abi.encodePacked(
            depositorV0.ETH1_ADDRESS_WITHDRAWAL_PREFIX(), uint88(0), attacker
        );
        vm.prank(attacker);
        BeaconDeposit(DEPOSIT_CONTRACT).deposit{
            value: InfraredBERAConstants.INITIAL_DEPOSIT
        }(pubkey0, credFaulty, signature1, attacker);

        vm.prank(keeper);
        vm.expectRevert(Errors.UnauthorizedOperator.selector);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        assertEq(
            address(0).balance,
            balanceZero + InfraredBERAConstants.INITIAL_DEPOSIT
        );
    }

    function testExecuteRegistersDeposit() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        uint256 stake = iberaV0.stakes(pubkey0);
        vm.expectEmit();
        emit IInfraredBERA.Register(pubkey0, int256(amount), stake + amount);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
        assertEq(iberaV0.stakes(pubkey0), stake + amount);
    }

    function testExecuteTransfersETH() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        uint256 balanceDepositor = address(depositorV0).balance;
        uint256 balanceKeeper = address(keeper).balance;
        uint256 balanceZero = address(0).balance;

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);

        assertEq(address(keeper).balance, balanceKeeper);
        assertEq(address(0).balance, balanceZero + amount);
        assertEq(address(depositorV0).balance, balanceDepositor - amount);
    }

    function testExecuteEmitsExecute() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.expectEmit();
        emit IInfraredBERADepositor.Execute(pubkey0, amount);

        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountExceedsSlips() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(iberaV0.signatures(pubkey0), signature0);
        uint256 amount = 200000 ether;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSenderNotKeeper() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert();
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenInvalidValidator() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);

        vm.expectRevert(Errors.InvalidValidator.selector);
        vm.prank(keeper);
        depositorV0.execute(bytes(""), amount);
    }

    function testExecuteRevertsWhenAmountZero() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(iberaV0.signatures(pubkey0), signature0);
        uint256 amount = 0;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountNotDivisibleByGwei() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();
        assertEq(iberaV0.signatures(pubkey0), signature0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        amount += 1;

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenSignatureNotSet() public {
        testExecuteUpdatesSlipsNonceFeesWhenFillAmounts();

        assertEq(iberaV0.signatures(pubkey1).length, 0);

        uint256 amount = ((amountFirst + amountSecond / 4) / 1 gwei) * 1 gwei;
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(amount % 1 gwei == 0);
        assertTrue(amount > InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.expectRevert(Errors.InvalidSignature.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey1, InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testExecuteValidatesOperatorForSubsequentDeposits() public {
        // Setup and do initial deposit
        testQueueMultiple();
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        // Do initial deposit
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Get next valid deposit amount from slip
        uint256 amount = ((amountFirst) / 1 gwei) * 1 gwei;
        assertTrue(amount >= InfraredBERAConstants.INITIAL_DEPOSIT);

        // Should succeed with subsequent deposit
        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);

        // Verify final state
        assertEq(
            iberaV0.stakes(pubkey0),
            InfraredBERAConstants.INITIAL_DEPOSIT + amount
        );
    }

    function testExecuteValidatesOperatorAndInitialDeposit() public {
        // Setup initial state using existing pattern
        testQueueMultiple();
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        // Test first deposit must be INITIAL_DEPOSIT
        uint256 invalidAmount = InfraredBERAConstants.INITIAL_DEPOSIT - 1;
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        depositorV0.execute(pubkey0, invalidAmount);

        // Do valid initial deposit
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Verify operator is set after initial deposit
        address operator =
            BeaconDeposit(depositorV0.DEPOSIT_CONTRACT()).getOperator(pubkey0);
        assertEq(operator, IInfraredBERA(depositorV0.InfraredBERA()).infrared());

        // Get balances for next slip
        uint256 amount = ((amountFirst) / 1 gwei) * 1 gwei; // Must be gwei aligned
        assertTrue(amount >= InfraredBERAConstants.INITIAL_DEPOSIT); // Must meet minimum

        // Execute subsequent deposit with proper amount from slip
        vm.prank(keeper);
        depositorV0.execute(pubkey0, amount);

        // Verify stakes are updated correctly
        assertEq(
            iberaV0.stakes(pubkey0),
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
        iberaV0.setDepositSignature(pubkey0, signature0);

        // Execute the initial deposit
        vm.prank(keeper);
        depositorV0.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Verify the validator's staked balance after the initial deposit
        uint256 currentStake = iberaV0.stakes(pubkey0);
        assertEq(currentStake, InfraredBERAConstants.INITIAL_DEPOSIT);

        // Queue additional funds for the excess deposit
        uint256 remainingSpace = maxEffectiveBalance - currentStake;
        uint256 excessAmount = remainingSpace + 1 gwei; // This would push the total stake over the limit
        _queueFundsForDeposit(excessAmount);

        // Attempt to deposit the excess amount
        vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey0, excessAmount);
    }

    function testExecuteRevertsWhenForcedExitedValidatorExists() public {
        // Minimum amount a validator can stake.
        uint256 minimumDeposit = InfraredBERAConstants.INITIAL_DEPOSIT;

        // Queue the initial deposit amount
        _queueFundsForDeposit(minimumDeposit);

        // Set the deposit signature for the validator
        vm.prank(infraredGovernance);
        iberaV0.setDepositSignature(pubkey0, signature0);

        // Deal funds to the withdraworLite contract to simulate a forced exit
        vm.deal(address(withdraworLite), minimumDeposit);

        // Attempt to execute a deposit.
        vm.expectRevert(Errors.HandleForceExitsBeforeDeposits.selector);
        vm.prank(keeper);
        depositorV0.execute(pubkey0, minimumDeposit);
    }

    function _queueFundsForDeposit(uint256 amount) internal {
        uint256 value = amount;

        // Ensure the ibera contract has enough funds
        vm.deal(address(iberaV0), value);
        assertTrue(address(iberaV0).balance >= value);

        // Queue the funds for deposit
        vm.prank(address(iberaV0));
        depositorV0.queue{value: value}();
    }
}
