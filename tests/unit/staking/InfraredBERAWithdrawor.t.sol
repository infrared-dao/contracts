// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {Errors} from "src/utils/Errors.sol";
import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";

contract InfraredBERAWithdraworTest is InfraredBERABaseTest {
    function setUp() public virtual override {
        super.setUp();
        uint256 value = 20000 ether + 1 ether;
        ibera.mint{value: value}(alice);

        uint256 amount = value - InfraredBERAConstants.INITIAL_DEPOSIT;
        vm.prank(infraredGovernance);

        ibera.setDepositSignature(pubkey0, signature0);
        vm.prank(keeper);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.execute(pubkey0, amount);
    }

    function testSetUp() public virtual override {
        super.testSetUp();
        assertEq(ibera.deposits(), 20000 ether + 11 ether);
        assertEq(ibera.confirmed(), 20001 ether);
        assertEq(ibera.pending(), 10000000000000000000);
    }

    function testQueueUpdatesFees() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        assertTrue(amount <= ibera.confirmed());
        vm.deal(address(ibera), fee);
        uint256 fees = withdrawor.fees();
        uint256 reserves = withdrawor.reserves();
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
        assertEq(withdrawor.fees(), fees + fee);
        assertEq(withdrawor.reserves(), reserves);
    }

    function testQueueUpdatesRebalancingWhenKeeper() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 100 ether;
        address receiver = address(depositor);
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        uint256 rebalancing = withdrawor.rebalancing();
        deal(keeper, fee);
        vm.prank(keeper);
        withdrawor.queue{value: fee}(receiver, amount);
        assertEq(withdrawor.rebalancing(), rebalancing + amount);
        assertEq(ibera.confirmed(), confirmed - amount);
    }

    function testQueueUpdatesNonce() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), fee);
        uint256 nonce = withdrawor.nonceRequest();
        vm.prank(address(ibera));
        uint256 nonce_ = withdrawor.queue{value: fee}(receiver, amount);
        assertEq(withdrawor.nonceRequest(), nonce + 1);
        assertEq(nonce_, nonce);
    }

    function testQueueStoresRequest() public {
        uint256 confirmed = ibera.confirmed();
        assertTrue(1 ether <= confirmed);
        vm.deal(address(ibera), InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1);
        uint256 nonce = withdrawor.nonceRequest();
        (
            address _receiver,
            uint96 _timestamp,
            uint256 _fee,
            uint256 _amountSubmit,
            uint256 _amountProcess
        ) = withdrawor.requests(nonce);
        assertEq(_receiver, address(0));
        assertEq(_timestamp, 0);
        assertEq(_fee, 0);
        assertEq(_amountSubmit, 0);
        assertEq(_amountProcess, 0);
        vm.prank(address(ibera));
        withdrawor.queue{value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1}(
            alice, 1 ether
        );
        (
            address receiver_,
            uint96 timestamp_,
            uint256 fee_,
            uint256 amountSubmit_,
            uint256 amountProcess_
        ) = withdrawor.requests(nonce);
        assertEq(receiver_, alice);
        assertEq(timestamp_, uint96(block.timestamp));
        assertEq(fee_, InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1);
        assertEq(amountSubmit_, 1 ether);
        assertEq(amountProcess_, 1 ether);
    }

    function testQueueEmitsQueue() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), 2 * fee);
        uint256 nonce = withdrawor.nonceRequest();
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Queue(receiver, nonce, amount);
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }

    // test specific storage to circumvent stack to deep error
    uint256 feeT1;
    uint256 feesT1;
    uint256 rebalancingT1;
    uint256 reservesT1;

    function testQueueMultiple() public {
        feeT1 = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE;
        uint256 confirmed = ibera.confirmed();
        assertTrue(42 ether <= confirmed);
        vm.deal(address(ibera), 2 * feeT1);
        vm.deal(address(keeper), 2 * feeT1);
        feesT1 = withdrawor.fees();
        rebalancingT1 = withdrawor.rebalancing();
        reservesT1 = withdrawor.reserves();
        uint256 nonce = withdrawor.nonceRequest();
        vm.prank(address(keeper));
        withdrawor.queue{value: feeT1}(address(depositor), 12 ether);
        vm.prank(address(ibera));
        withdrawor.queue{value: feeT1}(alice, 14 ether);
        vm.prank(address(ibera));
        withdrawor.queue{value: feeT1}(bob, 16 ether);
        assertEq(withdrawor.nonceRequest(), nonce + 3);
        assertEq(withdrawor.fees(), feesT1 + 3 * feeT1);
        assertEq(withdrawor.reserves(), reservesT1);
        assertEq(withdrawor.rebalancing(), rebalancingT1 + 12 ether);
        {
            (
                address receiverFirst,
                uint96 timestampFirst,
                uint256 feeFirst,
                uint256 amountSubmitFirst,
                uint256 amountProcessFirst
            ) = withdrawor.requests(nonce);
            assertEq(receiverFirst, address(depositor));
            assertEq(timestampFirst, uint96(block.timestamp));
            assertEq(feeFirst, feeT1);
            assertEq(amountSubmitFirst, 12 ether);
            assertEq(amountProcessFirst, 12 ether);
        }
        {
            (
                address receiverSecond,
                uint96 timestampSecond,
                uint256 feeSecond,
                uint256 amountSubmitSecond,
                uint256 amountProcessSecond
            ) = withdrawor.requests(nonce + 1);
            assertEq(receiverSecond, address(alice));
            assertEq(timestampSecond, uint96(block.timestamp));
            assertEq(feeSecond, feeT1);
            assertEq(amountSubmitSecond, 14 ether);
            assertEq(amountProcessSecond, 14 ether);
        }
        {
            (
                address receiverThird,
                uint96 timestampThird,
                uint256 feeThird,
                uint256 amountSubmitThird,
                uint256 amountProcessThird
            ) = withdrawor.requests(nonce + 2);
            assertEq(receiverThird, address(bob));
            assertEq(timestampThird, uint96(block.timestamp));
            assertEq(feeThird, feeT1);
            assertEq(amountSubmitThird, 16 ether);
            assertEq(amountProcessThird, 16 ether);
        }
    }

    function testQueueRevertsWhenUnauthorized() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.expectRevert();
        vm.prank(alice);
        withdrawor.queue{value: fee}(receiver, amount);
    }

    function testQueueRevertsWhenNotRebalancingReceiverDepositor() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = address(depositor);
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), fee);
        vm.expectRevert(Errors.InvalidReceiver.selector);
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }

    function testQueueRevertsWhenRebalancingReceiverNotDepositor() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(keeper, fee);
        vm.expectRevert(Errors.InvalidReceiver.selector);
        vm.prank(keeper);
        withdrawor.queue{value: fee}(receiver, amount);
    }

    function testQueueRevertsWhenAmountZero() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 0;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), fee);
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }

    // function testQueueRevertsWhenRebalancingAmountLessThanMinDepositFee()
    //     public
    // {
    //     uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
    //     address receiver = address(depositor);
    //     uint256 confirmed = ibera.confirmed();
    //     assertTrue(fee <= confirmed);
    //     vm.deal(address(keeper), fee);
    //     vm.expectRevert(Errors.InvalidAmount.selector);
    //     vm.prank(keeper);
    //     withdrawor.queue{value: InfraredBERAConstants.MINIMUM_WITHDRAW_FEE}(receiver, 1);
    // }

    function testQueueRevertsWhenAmountGreaterThanConfirmed() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        uint256 amount = confirmed + 1;
        vm.deal(address(ibera), fee);
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }

    function testQueueRevertsWhenFeeLessThanMin() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE - 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), fee);
        vm.expectRevert(Errors.InvalidFee.selector);
        vm.prank(address(ibera));
        withdrawor.queue{value: fee}(receiver, amount);
    }

    struct RequestData {
        address receiver;
        uint96 timestamp;
        uint256 fee;
        uint256 amountSubmit;
        uint256 amountProcess;
    }

    function testExecuteUpdatesRequestsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();

        // Retrieving the initial state before the function call
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        uint256 fees = withdrawor.fees();
        uint256 rebalancing = withdrawor.rebalancing();
        uint256 reserves = withdrawor.reserves();

        // Asserting initial values for nonces
        assertEq(nonceRequest, 4);
        assertEq(nonceSubmit, 1);
        assertEq(nonceProcess, 1);

        // Retrieve request details and use structs to manage data groups
        RequestData memory requestFirst = getWithdraworRequestData(1);
        RequestData memory requestSecond = getWithdraworRequestData(2);

        uint256 amount = requestFirst.amountSubmit + requestSecond.amountSubmit;
        assertTrue(amount % 1 gwei == 0);

        // Perform the execute operation
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);

        // Verify the updated state
        assertStateAfterExecution(
            nonceRequest,
            nonceSubmit,
            nonceProcess,
            fees,
            reserves,
            rebalancing,
            requestFirst,
            requestSecond
        );
    }

    // Helper function to get request data as a struct
    function getWithdraworRequestData(uint256 index)
        internal
        view
        returns (RequestData memory)
    {
        (
            address receiver,
            uint96 timestamp,
            uint256 fee,
            uint256 amountSubmit,
            uint256 amountProcess
        ) = withdrawor.requests(index);
        return
            RequestData(receiver, timestamp, fee, amountSubmit, amountProcess);
    }

    // Helper function to validate state after execution
    function assertStateAfterExecution(
        uint256 nonceRequest,
        uint256 nonceSubmit,
        uint256 nonceProcess,
        uint256 fees,
        uint256 reserves,
        uint256 rebalancing,
        RequestData memory requestFirst,
        RequestData memory requestSecond
    ) internal view {
        assertEq(withdrawor.nonceRequest(), nonceRequest);
        assertEq(withdrawor.nonceSubmit(), nonceSubmit + 2);
        assertEq(withdrawor.nonceProcess(), nonceProcess);
        assertEq(withdrawor.fees(), fees - requestFirst.fee - requestSecond.fee);
        assertEq(withdrawor.reserves(), reserves);
        assertEq(withdrawor.rebalancing(), rebalancing);

        // Assert for first request after execution
        RequestData memory updatedFirst = getWithdraworRequestData(1);
        assertEq(updatedFirst.receiver, requestFirst.receiver);
        assertEq(updatedFirst.timestamp, requestFirst.timestamp);
        assertEq(updatedFirst.fee, 0);
        assertEq(updatedFirst.amountSubmit, 0);
        assertEq(updatedFirst.amountProcess, requestFirst.amountProcess);

        // Assert for second request after execution
        RequestData memory updatedSecond = getWithdraworRequestData(2);
        assertEq(updatedSecond.receiver, requestSecond.receiver);
        assertEq(updatedSecond.timestamp, requestSecond.timestamp);
        assertEq(updatedSecond.fee, 0);
        assertEq(updatedSecond.amountSubmit, 0);
        assertEq(updatedSecond.amountProcess, requestSecond.amountProcess);
    }

    function testExecuteUpdatesRequestNonceFeesWhenFillAmount() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 fees = withdrawor.fees();
        uint256 rebalancing = withdrawor.rebalancing();
        uint256 reserves = withdrawor.reserves();
        (
            address receiverFirst,
            uint96 timestampFirst,
            uint256 feeFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        uint256 amount = amountSubmitFirst;
        assertTrue(amount % 1 gwei == 0);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
        assertEq(withdrawor.nonceRequest(), nonceRequest);
        assertEq(withdrawor.nonceSubmit(), nonceSubmit + 1);
        assertEq(withdrawor.nonceProcess(), nonceProcess);
        assertEq(withdrawor.fees(), fees - feeFirst);
        assertEq(withdrawor.reserves(), reserves);
        assertEq(withdrawor.rebalancing(), rebalancing);
        (
            address receiverFirst_,
            uint96 timestampFirst_,
            uint256 feeFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);
        assertEq(feeFirst_, 0);
        assertEq(amountSubmitFirst_, 0);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    function testExecuteUpdatesRequestNonceFeesWhenPartialAmount() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 fees = withdrawor.fees();
        uint256 rebalancing = withdrawor.rebalancing();
        uint256 reserves = withdrawor.reserves();
        (
            address receiverFirst,
            uint96 timestampFirst,
            uint256 feeFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        uint256 amount = amountSubmitFirst / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
        assertEq(withdrawor.nonceRequest(), nonceRequest);
        assertEq(withdrawor.nonceSubmit(), nonceSubmit);
        assertEq(withdrawor.nonceProcess(), nonceProcess);
        assertEq(withdrawor.fees(), fees - feeFirst);
        assertEq(withdrawor.reserves(), reserves);
        assertEq(withdrawor.rebalancing(), rebalancing);
        (
            address receiverFirst_,
            uint96 timestampFirst_,
            uint256 feeFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);
        assertEq(feeFirst_, 0);
        assertEq(amountSubmitFirst_, amountSubmitFirst - amount);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    // test specific storage to circumvent stack to deep error
    uint256 nonceRequestT2;
    uint256 nonceSubmitT2;
    uint256 nonceProcessT2;
    uint256 feesT2;
    uint256 rebalancingT2;
    uint256 reservesT2;

    function testExecuteUpdatesRequestsNonceFeesWhenPartialLastAmount()
        public
    {
        testQueueMultiple();
        nonceRequestT2 = withdrawor.nonceRequest();
        nonceSubmitT2 = withdrawor.nonceSubmit();
        nonceProcessT2 = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequestT2, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmitT2, 1); // none submitted yet
        assertEq(nonceProcessT2, 1); // nonce processed yet
        feesT2 = withdrawor.fees();
        rebalancingT2 = withdrawor.rebalancing();
        reservesT2 = withdrawor.reserves();
        (
            address receiverFirst,
            uint96 timestampFirst,
            uint256 feeFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        (
            address receiverSecond,
            uint96 timestampSecond,
            uint256 feeSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(2);
        // uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue((amountSubmitFirst + amountSubmitSecond / 4) % 1 gwei == 0);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amountSubmitFirst + amountSubmitSecond / 4);
        assertEq(withdrawor.nonceRequest(), nonceRequestT2);
        assertEq(withdrawor.nonceSubmit(), nonceSubmitT2 + 1);
        assertEq(withdrawor.nonceProcess(), nonceProcessT2);
        assertEq(withdrawor.fees(), feesT2 - feeFirst - feeSecond);
        assertEq(withdrawor.reserves(), reservesT2);
        assertEq(withdrawor.rebalancing(), rebalancingT2);

        verifyReceiverFirst(
            receiverFirst,
            timestampFirst,
            feeFirst,
            amountSubmitFirst,
            amountProcessFirst
        );
        {
            (
                address receiverSecond_,
                uint96 timestampSecond_,
                uint256 feeSecond_,
                uint256 amountSubmitSecond_,
                uint256 amountProcessSecond_
            ) = withdrawor.requests(2);
            assertEq(receiverSecond_, receiverSecond);
            assertEq(timestampSecond_, timestampSecond);
            assertEq(feeSecond_, 0);
            assertEq(
                amountSubmitSecond_, amountSubmitSecond - amountSubmitSecond / 4
            );
            assertEq(amountProcessSecond_, amountProcessSecond);
        }
    }

    function verifyReceiverFirst(
        address receiverFirst,
        uint96 timestampFirst,
        uint256,
        uint256,
        uint256 amountProcessFirst
    ) internal view {
        (
            address receiverFirst_,
            uint96 timestampFirst_,
            uint256 feeFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);
        assertEq(feeFirst_, 0);
        assertEq(amountSubmitFirst_, 0);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    // // TODO:
    // function testExecuteCallsWithrawPrecompile() public {}
    function testExecuteRegistersWithdraw() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 stake = ibera.stakes(pubkey0);
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
        assertEq(ibera.stakes(pubkey0), stake - amount);
    }

    function testExecuteTransfersETH() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 value = 0.002 ether; // some extra for precompile call in case
        vm.deal(keeper, 10 ether);
        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        uint256 balanceWithdrawPrecompile = address(WITHDRAW_PRECOMPILE).balance;
        uint256 balanceWithdrawor = address(withdrawor).balance;
        uint256 balanceKeeper = address(keeper).balance;
        (,, uint256 feeFirst, uint256 amountSubmitFirst,) =
            withdrawor.requests(1);
        (,, uint256 feeSecond, uint256 amountSubmitSecond,) =
            withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.prank(keeper);
        withdrawor.execute{value: value}(pubkey0, amount);
        assertEq(
            address(withdrawor).balance,
            balanceWithdrawor - feeFirst - feeSecond
        );
        uint256 deltaBalanceWithdrawPrecompile =
            address(WITHDRAW_PRECOMPILE).balance - balanceWithdrawPrecompile;
        assertTrue(deltaBalanceWithdrawPrecompile > 0);
        uint256 fee_ = feeFirst + feeSecond + value;
        uint256 excess = fee_ - deltaBalanceWithdrawPrecompile;
        assertEq(address(keeper).balance, balanceKeeper - value + excess);
    }

    function testExecuteEmitsExecute() public {
        testQueueMultiple();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(withdrawor.nonceRequest(), 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Execute(
            pubkey0, nonceSubmit, nonceSubmit + 1, amount
        );
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountZero() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 amount = 0;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountExceedsStake() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        uint256 stake = ibera.stakes(pubkey0);
        uint256 amount = stake + 1;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenAmountNotInGwei() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        amount++;
        assertTrue(amount % 1 gwei != 0);
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        withdrawor.execute(pubkey0, amount);
    }

    // // TODO: check why not recognizing actual invalid amount error even tho trace shows works
    // /*
    // function testExecuteRevertsWhenAmountExceedsRequests() public {
    //     testQueueMultiple();
    //     uint256 amount = 46 ether;
    //     assertTrue(amount % 1 gwei != 0);
    //     vm.expectRevert(IInfraredBERAWithdrawor.InvalidAmount.selector);
    //     vm.prank(keeper);
    //     withdrawor.execute(pubkey0, amount);
    // }
    // */
    function testExecuteRevertsWhenUnauthorized() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.expectRevert();
        vm.prank(address(10));
        withdrawor.execute(pubkey0, amount);
    }

    function testExecuteRevertsWhenNotEnoughTime() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 1); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        vm.expectRevert();
        vm.prank(address(10));
        withdrawor.execute(pubkey0, amount);
        // should now succeed
        vm.warp(block.timestamp + InfraredBERAConstants.FORCED_MIN_DELAY + 1);
        withdrawor.execute(pubkey0, amount);
    }

    function testProcessUpdatesRequestNonce() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        // uint256 nonceRequest = withdrawor.nonceRequest();
        // uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(withdrawor.nonceRequest(), 4); // 0 on init, 3 on test multiple
        assertEq(withdrawor.nonceSubmit(), 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        // {
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);

        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);

        // process first request which is a rebalance
        withdrawor.process();
        assertEq(withdrawor.nonceProcess(), nonceProcess + 1);
        {
            (,,, uint256 amountSubmitFirst_, uint256 amountProcessFirst_) =
                withdrawor.requests(nonceProcess);
            assertEq(amountSubmitFirst_, 0);
            assertEq(amountProcessFirst_, 0);
            // process second first which is a claim to alice
            (
                address receiverSecond,
                ,
                ,
                uint256 amountSubmitSecond,
                uint256 amountProcessSecond
            ) = withdrawor.requests(nonceProcess + 1);
            assertEq(receiverSecond, address(alice));
            assertEq(amountSubmitSecond, 0);
            assertTrue(amountProcessSecond > 0);
            // simulate withdraw request funds being filled from CL
            // balanceWithdrawor = address(withdrawor).balance;
            vm.deal(
                address(withdrawor),
                address(withdrawor).balance + amountProcessSecond
            );
        }

        // process second request which is a claim for alice
        withdrawor.process();
        assertEq(withdrawor.nonceProcess(), nonceProcess + 2);
        {
            (,,, uint256 amountSubmitSecond_, uint256 amountProcessSecond_) =
                withdrawor.requests(nonceProcess + 1);
            assertEq(amountSubmitSecond_, 0);
            assertEq(amountProcessSecond_, 0);
        }
    }

    function testProcessUpdatesRebalancingWhenRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        // cache rebalancing amount
        uint256 rebalancing = withdrawor.rebalancing();
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        withdrawor.process();
        assertEq(withdrawor.rebalancing(), rebalancing - amountProcessFirst);
    }

    function testProcessTransfersETH() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (,,,, uint256 amountProcessFirst) = withdrawor.requests(nonceProcess);
        (,,,, uint256 amountProcessSecond) =
            withdrawor.requests(nonceProcess + 1);
        // simulate withdraw request funds being filled from CL
        vm.deal(
            address(withdrawor),
            address(withdrawor).balance + amountProcessFirst
                + amountProcessSecond
        );
        uint256 balanceWithdrawor = address(withdrawor).balance;
        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceClaimor = address(claimor).balance;
        // process first request which is a rebalance
        withdrawor.process();
        assertEq(withdrawor.nonceProcess(), nonceProcess + 1);
        assertEq(
            address(withdrawor).balance, balanceWithdrawor - amountProcessFirst
        );
        assertEq(
            address(depositor).balance, balanceDepositor + amountProcessFirst
        );
        // process second request which is a claim for alice
        withdrawor.process();
        assertEq(withdrawor.nonceProcess(), nonceProcess + 2);
        assertEq(
            address(withdrawor).balance,
            balanceWithdrawor - amountProcessFirst - amountProcessSecond
        );
        assertEq(address(claimor).balance, balanceClaimor + amountProcessSecond);
    }

    function testProcessQueuesToDepositorWhenRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        withdrawor.process();
    }

    function testProcessQueuesToClaimorWhenNotRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        withdrawor.process();
        // process second first which is a claim to alice
        (
            address receiverSecond,
            ,
            ,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 0);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessSecond);
        // process second request which is a claim for alice
        uint256 claim = claimor.claims(receiverSecond);
        withdrawor.process();
        assertEq(claimor.claims(receiverSecond), claim + amountProcessSecond);
    }

    function testProcessEmitsProcess() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Process(
            receiverFirst, nonceProcess, amountProcessFirst
        );
        withdrawor.process();
        // process second first which is a claim to alice
        (
            address receiverSecond,
            ,
            ,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 0);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessSecond);
        // process second request which is a claim for alice
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Process(
            receiverSecond, nonceProcess + 1, amountProcessSecond
        );
        withdrawor.process();
    }

    function testProcessRevertsWhenAllRequestsProcessed() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        (
            address receiverSecond,
            ,
            ,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 0);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(
            address(withdrawor),
            balanceWithdrawor + amountProcessFirst + amountProcessSecond
        );
        // first two should succeed
        withdrawor.process();
        withdrawor.process();
        // last should not
        assertEq(withdrawor.nonceProcess(), nonceSubmit);
        vm.expectRevert(Errors.InvalidAmount.selector);
        withdrawor.process();
    }

    // TODO: why also this invalid amount even though errors properly on trace doesnt catch in test
    /*
    function testProcessRevertsWhenRequestPartialFilled() public {
        testExecuteUpdatesRequestsNonceFeesWhenPartialLastAmount();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 2); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            uint96 timestampFirst,
            uint256 feeFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        (
            address receiverSecond,
            uint96 timestampSecond,
            uint256 feeSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 0);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(
            address(withdrawor),
            balanceWithdrawor + amountProcessFirst + amountProcessSecond
        );
        // first should succeed
        withdrawor.process();
        // second should fail
        vm.expectRevert(IInfraredBERAWithdrawor.InvalidAmount.selector);
        withdrawor.process();
    }
    */
    function testProcessRevertsWhenRequestAmountGreaterThanReserves() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.nonceRequest();
        uint256 nonceSubmit = withdrawor.nonceSubmit();
        uint256 nonceProcess = withdrawor.nonceProcess();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 4); // 0 on init, 3 on test multiple
        assertEq(nonceSubmit, 3); // none submitted yet
        assertEq(nonceProcess, 1); // nonce processed yet
        (
            address receiverFirst,
            ,
            ,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 0);
        assertTrue(amountProcessFirst > 0);
        // process first request which is a rebalance wont go thru with not enough reserves
        vm.deal(
            address(withdrawor),
            address(withdrawor).balance + amountProcessFirst - 1
        );
        vm.expectRevert(Errors.InvalidReserves.selector);
        withdrawor.process();
    }

    function testSweep() public {
        // Get current stake from setup
        uint256 validatorStake = ibera.stakes(pubkey0);

        // Disable withdrawals (required for sweep)
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        // Simulate forced withdrawal by dealing ETH to withdrawor
        vm.deal(address(withdrawor), validatorStake);

        // Test unauthorized caller
        vm.prank(address(10));
        vm.expectRevert();
        withdrawor.sweep(pubkey0);

        // Test successful sweep
        vm.prank(keeper);
        withdrawor.sweep(pubkey0);

        // Verify stake and balance after sweep
        assertEq(ibera.stakes(pubkey0), 0, "Stake should be zero after sweep");
        assertEq(
            address(withdrawor).balance,
            0,
            "Withdrawor balance should be zero after sweep"
        );
    }

    function testExecuteRevertsWhenValidatorExited() public {
        // First sweep the validator
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        uint256 validatorStake = ibera.stakes(pubkey0);
        vm.deal(address(withdrawor), validatorStake);
        vm.prank(keeper);
        withdrawor.sweep(pubkey0);

        // Try to execute a new deposit - should revert
        uint256 value = InfraredBERAConstants.INITIAL_DEPOSIT;
        ibera.mint{value: value}(alice);
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        vm.expectRevert(Errors.ValidatorForceExited.selector);
        depositor.execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testSweepRevertsWhenWithdrawalsEnabled() public {
        uint256 validatorStake = ibera.stakes(pubkey0);
        vm.deal(address(withdrawor), validatorStake);

        // Enable withdrawals
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        // Verify withdrawals are enabled
        assertTrue(ibera.withdrawalsEnabled(), "Withdrawals should be enabled");

        // Should revert with unauthorized when trying to sweep with withdrawals enabled
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, keeper)
        );
        withdrawor.sweep(pubkey0);
    }

    function testSweepRevertsWhenInsufficientBalance() public {
        uint256 validatorStake = ibera.stakes(pubkey0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        // Deal less than validator stake
        vm.deal(address(withdrawor), validatorStake - 1 ether);

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        withdrawor.sweep(pubkey0);
    }

    function testSweepRevertsWhenValidatorAlreadyExited() public {
        uint256 validatorStake = ibera.stakes(pubkey0);

        // First sweep - exit the validator
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);
        vm.deal(address(withdrawor), validatorStake);
        vm.prank(keeper);
        withdrawor.sweep(pubkey0);

        // Verify validator state after first sweep
        assertEq(ibera.stakes(pubkey0), 0, "Stake should be zero after sweep");
        assertTrue(
            ibera.hasExited(pubkey0), "Validator should be marked as exited"
        );

        // Attempt second sweep - should revert because validator is exited
        vm.deal(address(withdrawor), InfraredBERAConstants.INITIAL_DEPOSIT); // Amount doesn't matter, should revert first
        vm.startPrank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ValidatorForceExited.selector)
        );
        withdrawor.sweep(pubkey0);
        vm.stopPrank();
    }
}
