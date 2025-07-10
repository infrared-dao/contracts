// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/upgrades/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {Errors} from "src/utils/Errors.sol";
import {InfraredBERABaseE2ETest} from "./InfraredBERABase.t.sol";

contract InfraredBERAWithdraworE2ETest is InfraredBERABaseE2ETest {
    function setUp() public virtual override {
        super.setUp();
        uint256 value = 20000 ether + 1 ether;
        ibera.mint{value: value}(alice);

        uint256 amount = value - InfraredBERAConstants.INITIAL_DEPOSIT;

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

    function testSetUp() public virtual override {
        super.testSetUp();
    }

    function testQueueUpdatesFees() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        assertTrue(amount <= ibera.confirmed());
        vm.deal(address(ibera), fee);

        uint256 reserves = withdrawor.reserves();
        vm.prank(address(ibera));
        withdrawor.queue(receiver, amount);

        assertEq(withdrawor.reserves(), reserves);
    }

    function testQueueUpdatesNonce() public {
        uint256 fee = InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1;
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.deal(address(ibera), fee);
        uint256 nonce = withdrawor.requestLength();
        vm.prank(address(ibera));
        withdrawor.queue(receiver, amount);
        assertEq(withdrawor.requestLength(), nonce + 1);
    }

    function testQueueStoresRequest() public {
        uint256 confirmed = ibera.confirmed();
        assertTrue(1 ether <= confirmed);
        vm.deal(address(ibera), InfraredBERAConstants.MINIMUM_WITHDRAW_FEE + 1);
        uint256 nonce = withdrawor.requestLength();
        (
            ,
            uint88 _timestamp,
            address _receiver,
            uint256 _amountSubmit,
            uint256 _amountProcess
        ) = withdrawor.requests(nonce);
        assertEq(_receiver, address(0));
        assertEq(_timestamp, 0);

        assertEq(_amountSubmit, 0);
        assertEq(_amountProcess, 0);
        vm.prank(address(ibera));
        nonce = withdrawor.queue(alice, 1 ether);
        (
            ,
            uint88 timestamp_,
            address receiver_,
            uint256 amountSubmit_,
            uint256 amountProcess_
        ) = withdrawor.requests(nonce);
        assertEq(receiver_, alice);
        assertEq(timestamp_, uint88(block.timestamp));

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
        uint256 nonce = withdrawor.requestLength();
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Queue(receiver, nonce + 1, amount);
        vm.prank(address(ibera));
        withdrawor.queue(receiver, amount);
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

        reservesT1 = withdrawor.reserves();
        uint256 nonce = withdrawor.requestLength();
        vm.prank(address(keeper));
        withdrawor.queue(address(depositor), 12 ether);
        vm.prank(address(ibera));
        withdrawor.queue(alice, 14 ether);
        vm.prank(address(ibera));
        withdrawor.queue(bob, 16 ether);
        assertEq(withdrawor.requestLength(), nonce + 3);

        assertEq(withdrawor.reserves(), reservesT1);

        {
            (
                ,
                uint88 timestampFirst,
                address receiverFirst,
                uint256 amountSubmitFirst,
                uint256 amountProcessFirst
            ) = withdrawor.requests(nonce + 1);
            assertEq(receiverFirst, address(depositor));
            assertEq(timestampFirst, uint88(block.timestamp));

            assertEq(amountSubmitFirst, 12 ether);
            assertEq(amountProcessFirst, 12 ether);
        }
        {
            (
                ,
                uint88 timestampSecond,
                address receiverSecond,
                uint256 amountSubmitSecond,
                uint256 amountProcessSecond
            ) = withdrawor.requests(nonce + 2);
            assertEq(receiverSecond, address(alice));
            assertEq(timestampSecond, uint88(block.timestamp));

            assertEq(amountSubmitSecond, 14 ether);
            assertEq(amountProcessSecond, 14 ether + 12 ether);
        }
        {
            (
                ,
                uint88 timestampThird,
                address receiverThird,
                uint256 amountSubmitThird,
                uint256 amountProcessThird
            ) = withdrawor.requests(nonce + 3);
            assertEq(receiverThird, address(bob));
            assertEq(timestampThird, uint88(block.timestamp));

            assertEq(amountSubmitThird, 16 ether);
            assertEq(amountProcessThird, 16 ether + 14 ether + 12 ether);
        }
    }

    function testQueueRevertsWhenUnauthorized() public {
        uint256 amount = 1 ether;
        address receiver = alice;
        uint256 confirmed = ibera.confirmed();
        assertTrue(amount <= confirmed);
        vm.expectRevert();
        vm.prank(alice);
        withdrawor.queue(receiver, amount);
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
        withdrawor.queue(receiver, amount);
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
        withdrawor.queue(receiver, amount);
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
        withdrawor.queue(receiver, amount);
    }

    struct RequestData {
        IInfraredBERAWithdrawor.RequestState state;
        uint88 timestamp;
        address receiver;
        uint256 amountSubmit;
        uint256 amountProcess;
    }

    function testExecuteUpdatesRequestsNonceFeesWhenFillAmounts() public {
        testQueueMultiple();

        // Retrieving the initial state before the function call
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        uint256 reserves = withdrawor.reserves();

        // Asserting initial values for nonces
        assertEq(nonceRequest, 3);
        assertEq(nonceProcess, 0);

        // Retrieve request details and use structs to manage data groups
        RequestData memory requestFirst = getWithdraworRequestData(1);
        RequestData memory requestSecond = getWithdraworRequestData(2);

        uint256 amount = requestFirst.amountSubmit + requestSecond.amountSubmit;
        assertTrue(amount % 1 gwei == 0);

        // Perform the execute operation
        uint256 fee = withdrawor.getFee();
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
        uint256 overflowAmount =
            withdrawor.getQueuedAmount() - withdrawor.reserves() + 2 gwei;
        vm.expectRevert();
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            overflowAmount,
            nextBlockTimestamp
        );

        uint256 currentBlock = block.number;
        // clean execute
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );

        // Verify the updated state
        assertStateAfterExecution(
            nonceRequest, nonceProcess, reserves, requestFirst, requestSecond
        );

        assertEq(
            withdrawor.getTotalPendingWithdrawals(
                keccak256(validatorStruct.pubkey)
            ),
            amount
        );
        (, uint96 refundBlock,) = withdrawor.pendingWithdrawals(
            withdrawor.pendingWithdrawalsLength() - 1
        );
        assertEq(uint256(refundBlock), ((currentBlock / 192) + 256) * 192);

        // expect revert for double withdraw
        vm.deal(address(this), amount);
        (bool success,) = address(withdrawor).call{value: amount}("");
        assertTrue(success);

        vm.expectRevert(Errors.WaitForPending.selector);
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        // burn amount
        vm.prank(address(withdrawor));
        (success,) = address(0).call{value: amount}("");
    }

    // Helper function to get request data as a struct
    function getWithdraworRequestData(uint256 index)
        internal
        view
        returns (RequestData memory)
    {
        (
            IInfraredBERAWithdrawor.RequestState state,
            uint88 timestamp,
            address receiver,
            uint256 amountSubmit,
            uint256 amountProcess
        ) = withdrawor.requests(index);
        return
            RequestData(state, timestamp, receiver, amountSubmit, amountProcess);
    }

    // Helper function to validate state after execution
    function assertStateAfterExecution(
        uint256 nonceRequest,
        uint256 nonceProcess,
        uint256 reserves,
        RequestData memory requestFirst,
        RequestData memory requestSecond
    ) internal view {
        assertEq(withdrawor.requestLength(), nonceRequest);
        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess);
        assertEq(withdrawor.reserves(), reserves);

        // Assert for first request after execution
        RequestData memory updatedFirst = getWithdraworRequestData(1);
        assertEq(updatedFirst.receiver, requestFirst.receiver);
        assertEq(updatedFirst.timestamp, requestFirst.timestamp);

        assertEq(updatedFirst.amountSubmit, requestFirst.amountSubmit);
        assertEq(updatedFirst.amountProcess, requestFirst.amountProcess);

        // Assert for second request after execution
        RequestData memory updatedSecond = getWithdraworRequestData(2);
        assertEq(updatedSecond.receiver, requestSecond.receiver);
        assertEq(updatedSecond.timestamp, requestSecond.timestamp);

        assertEq(updatedSecond.amountSubmit, requestSecond.amountSubmit);
        assertEq(updatedSecond.amountProcess, requestSecond.amountProcess);
    }

    function testExecuteUpdatesRequestNonceFeesWhenFillAmount() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        uint256 reserves = withdrawor.reserves();
        (
            ,
            uint88 timestampFirst,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        uint256 amount = amountSubmitFirst;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
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
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        assertEq(withdrawor.requestLength(), nonceRequest);

        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess);
        assertEq(withdrawor.reserves(), reserves);

        (
            ,
            uint88 timestampFirst_,
            address receiverFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);

        assertEq(amountSubmitFirst_, amountSubmitFirst);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    function testExecuteUpdatesRequestNonceFeesWhenPartialAmount() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        uint256 reserves = withdrawor.reserves();
        (
            ,
            uint88 timestampFirst,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        uint256 amount = amountSubmitFirst / 4;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
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
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        assertEq(withdrawor.requestLength(), nonceRequest);

        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess);

        assertEq(withdrawor.reserves(), reserves);

        (
            ,
            uint88 timestampFirst_,
            address receiverFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);

        assertEq(amountSubmitFirst_, amountSubmitFirst);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    // test specific storage to circumvent stack to deep error
    uint256 nonceRequestT2;

    uint256 nonceProcessT2;
    uint256 feesT2;
    uint256 rebalancingT2;
    uint256 reservesT2;

    function testExecuteUpdatesRequestsNonceFeesWhenPartialLastAmount()
        public
    {
        testQueueMultiple();
        nonceRequestT2 = withdrawor.requestLength();

        nonceProcessT2 = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequestT2, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcessT2, 0); // nonce processed yet
        reservesT2 = withdrawor.reserves();
        (
            ,
            uint88 timestampFirst,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(1);
        (
            ,
            uint88 timestampSecond,
            address receiverSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(2);

        assertTrue((amountSubmitFirst + amountSubmitSecond / 4) % 1 gwei == 0);
        vm.startPrank(keeper);
        iberaV2.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        withdrawor.execute{value: withdrawor.getFee()}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amountSubmitFirst + amountSubmitSecond / 4,
            nextBlockTimestamp
        );
        vm.stopPrank();
        assertEq(withdrawor.requestLength(), nonceRequestT2);

        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcessT2);

        assertEq(withdrawor.reserves(), reservesT2);

        verifyReceiverFirst(
            receiverFirst, timestampFirst, amountSubmitFirst, amountProcessFirst
        );
        {
            (
                ,
                uint96 timestampSecond_,
                address receiverSecond_,
                uint256 amountSubmitSecond_,
                uint256 amountProcessSecond_
            ) = withdrawor.requests(2);
            assertEq(receiverSecond_, receiverSecond);
            assertEq(timestampSecond_, timestampSecond);

            assertEq(amountSubmitSecond_, amountSubmitSecond);
            assertEq(amountProcessSecond_, amountProcessSecond);
        }
    }

    function verifyReceiverFirst(
        address receiverFirst,
        uint88 timestampFirst,
        uint256 submitFirst,
        uint256 amountProcessFirst
    ) internal view {
        (
            ,
            uint88 timestampFirst_,
            address receiverFirst_,
            uint256 amountSubmitFirst_,
            uint256 amountProcessFirst_
        ) = withdrawor.requests(1);
        assertEq(receiverFirst_, receiverFirst);
        assertEq(timestampFirst_, timestampFirst);

        assertEq(amountSubmitFirst_, submitFirst);
        assertEq(amountProcessFirst_, amountProcessFirst);
    }

    function testExecuteRegistersWithdraw() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet

        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
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
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        assertEq(ibera.stakes(pubkey0), stake - amount);
    }

    function testExecuteTransfersETH() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet

        vm.deal(keeper, 10 ether);

        uint256 balanceWithdrawor = address(withdrawor).balance;
        uint256 balanceKeeper = address(keeper).balance;
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
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
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        assertEq(address(withdrawor).balance, balanceWithdrawor);

        assertEq(address(keeper).balance, balanceKeeper);
    }

    function testExecuteEmitsExecute() public {
        testQueueMultiple();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(withdrawor.requestLength(), 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
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
        emit IInfraredBERAWithdrawor.Execute(pubkey0, amount);
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
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

    function testExecuteRevertsWhenAmountExceedsStake() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet

        uint256 fee = withdrawor.getFee();
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
        uint256 amount = stake + 1;
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
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

    function testExecuteRevertsWhenAmountNotInGwei() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        amount++;
        assertTrue(amount % 1 gwei != 0);
        uint256 fee = withdrawor.getFee();
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
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(keeper);
        withdrawor.execute{value: fee}(
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

    function testExecuteRevertsWhenUnauthorized() public {
        testQueueMultiple();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (,,, uint256 amountSubmitFirst,) = withdrawor.requests(1);
        (,,, uint256 amountSubmitSecond,) = withdrawor.requests(2);
        uint256 amount = amountSubmitFirst + amountSubmitSecond / 4;
        assertTrue(amount % 1 gwei == 0);
        uint256 fee = withdrawor.getFee();
        vm.deal(address(10), 1 ether);
        vm.expectRevert();
        vm.prank(address(10));
        withdrawor.execute{value: fee}(
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

    function testProcessUpdatesRequestNonce() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(withdrawor.requestLength(), 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        // {
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);

        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);

        // process first request which is a rebalance
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess + 1);
        {
            (,,, uint256 amountSubmitFirst_, uint256 amountProcessFirst_) =
                withdrawor.requests(nonceProcess);
            assertEq(amountSubmitFirst_, 0);
            assertEq(amountProcessFirst_, 0);
            // process second first which is a claim to alice
            (
                ,
                ,
                address receiverSecond,
                uint256 amountSubmitSecond,
                uint256 amountProcessSecond
            ) = withdrawor.requests(nonceProcess + 2);
            assertEq(receiverSecond, address(alice));
            assertEq(amountSubmitSecond, 14 ether);
            assertTrue(amountProcessSecond > 0);
            // simulate withdraw request funds being filled from CL

            vm.deal(
                address(withdrawor),
                address(withdrawor).balance + amountProcessSecond
            );
        }

        // process second request which is a claim for alice
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 2);
        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess + 2);
        {
            (IInfraredBERAWithdrawor.RequestState state,,,,) =
                withdrawor.requests(nonceProcess + 1);
            // Depositor requests are automatically set to CLAIMED state after processing
            assertTrue(state == IInfraredBERAWithdrawor.RequestState.CLAIMED);
        }
    }

    function testProcessUpdatesRebalancingWhenRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        // cache rebalancing amount

        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
    }

    function testProcessTransfersETH() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (,,,, uint256 amountProcessFirst) =
            withdrawor.requests(nonceProcess + 1);
        (,,,, uint256 amountProcessSecond) =
            withdrawor.requests(nonceProcess + 2);
        // simulate withdraw request funds being filled from CL
        vm.deal(
            address(withdrawor),
            address(withdrawor).balance + amountProcessSecond
        );
        uint256 balanceWithdrawor = address(withdrawor).balance;
        uint256 balanceDepositor = address(depositor).balance;

        // process first request which is a rebalance
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess + 1);
        assertEq(
            address(withdrawor).balance, balanceWithdrawor - amountProcessFirst
        );
        assertEq(
            address(depositor).balance, balanceDepositor + amountProcessFirst
        );
        // process second request which is a claim for alice
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 2);
        assertEq(withdrawor.requestsFinalisedUntil(), nonceProcess + 2);
        assertEq(address(withdrawor).balance, 14 ether);
    }

    function testProcessQueuesToDepositorWhenRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
    }

    function testProcessQueuesToClaimorWhenNotRebalancing() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
        // process second first which is a claim to alice
        (
            ,
            ,
            address receiverSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 2);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 14 ether);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessSecond);
        // process second request which is a claim for alice
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 2);
        (IInfraredBERAWithdrawor.RequestState state,,,,) =
            withdrawor.requests(nonceProcess + 2);
        assertEq(uint8(state), 1);
        uint256 balBefore = receiverSecond.balance;
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.Claimed(
            alice, nonceProcess + 2, amountSubmitSecond
        );
        vm.prank(alice);
        withdrawor.claim(nonceProcess + 2);
        assertEq(receiverSecond.balance - balBefore, amountSubmitSecond);
        (state,,,,) = withdrawor.requests(nonceProcess + 2);
        assertEq(uint8(state), 2);
    }

    function testProcessEmitsProcess() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessFirst);
        // process first request which is a rebalance
        vm.prank(keeper);
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.ProcessRange(
            nonceProcess + 1, nonceProcess + 1
        );
        withdrawor.process(nonceProcess + 1);
        // process second first which is a claim to alice
        (
            ,
            ,
            address receiverSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 2);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 14 ether);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessSecond);
        // process second request which is a claim for alice
        vm.prank(keeper);
        vm.expectEmit();
        emit IInfraredBERAWithdrawor.ProcessRange(
            nonceProcess + 2, nonceProcess + 2
        );
        withdrawor.process(nonceProcess + 2);
    }

    function testProcessRevertsWhenAllRequestsProcessed() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        (
            ,
            ,
            address receiverSecond,
            uint256 amountSubmitSecond,
            uint256 amountProcessSecond
        ) = withdrawor.requests(nonceProcess + 2);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        assertEq(receiverSecond, address(alice));
        assertEq(amountSubmitSecond, 14 ether);
        assertTrue(amountProcessSecond > 0);
        // simulate withdraw request funds being filled from CL
        uint256 balanceWithdrawor = address(withdrawor).balance;
        vm.deal(address(withdrawor), balanceWithdrawor + amountProcessSecond);
        // first two should succeed
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 1);
        vm.prank(keeper);
        withdrawor.process(nonceProcess + 2);
        // last should not
        // assertEq(withdrawor.requestsFinalisedUntil(), nonceSubmit);
        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        withdrawor.process(nonceProcess + 3);
    }

    function testProcessRevertsWhenRequestAmountGreaterThanReserves() public {
        testExecuteUpdatesRequestsNonceFeesWhenFillAmounts();
        uint256 nonceRequest = withdrawor.requestLength();

        uint256 nonceProcess = withdrawor.requestsFinalisedUntil();
        // should have the min deposit from iibera.initialize call to push through
        assertEq(nonceRequest, 3); // 0 on init, 3 on test multiple

        assertEq(nonceProcess, 0); // nonce processed yet
        (
            ,
            ,
            address receiverFirst,
            uint256 amountSubmitFirst,
            uint256 amountProcessFirst
        ) = withdrawor.requests(nonceProcess + 1);
        assertEq(receiverFirst, address(depositor));
        assertEq(amountSubmitFirst, 12 ether);
        assertTrue(amountProcessFirst > 0);
        // process first request which is a rebalance wont go thru with not enough reserves
        vm.prank(keeper);
        vm.deal(
            address(withdrawor),
            address(withdrawor).balance + amountProcessFirst - 1
        );
        vm.expectRevert(Errors.InsufficientBalance.selector);
        withdrawor.process(nonceProcess + 1);
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
        withdrawor.sweepForcedExit(
            header,
            validatorStruct,
            validatorIndex,
            validatorProof,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsWhenValidatorExited() public {
        // First sweep the validator
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        // Try to execute a new deposit - should revert
        uint256 value = InfraredBERAConstants.INITIAL_DEPOSIT;
        ibera.mint{value: value}(alice);
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, signature0);

        vm.prank(keeper);
        vm.expectRevert(Errors.AlreadyInitiated.selector);
        depositorV2.executeInitialDeposit(validatorStruct.pubkey);
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
        vm.expectRevert();
        withdrawor.sweepForcedExit(
            header,
            validatorStruct,
            validatorIndex,
            validatorProof,
            nextBlockTimestamp
        );
    }

    function testSweepRevertsWhenInsufficientBalance() public {
        uint256 validatorStake = ibera.stakes(pubkey0);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        // Deal less than validator stake
        vm.deal(address(withdrawor), validatorStake - 1 ether);

        vm.prank(infraredGovernance);
        vm.expectRevert();
        withdrawor.sweepForcedExit(
            header,
            validatorStruct,
            validatorIndex,
            validatorProof,
            nextBlockTimestamp
        );
    }

    // Helper function to queue a ticket (used in multiple tests)
    function queueTicket(address receiver, uint256 amount, address caller)
        internal
        returns (uint256 requestId)
    {
        vm.prank(caller);
        return withdrawor.queue(receiver, amount);
    }

    // Test pause/unpause functionality
    function testPauseUnpause() public {
        // Test unauthorized pause
        vm.prank(address(10));
        vm.expectRevert(); // Assuming onlyGovernor reverts with a specific error
        withdrawor.pause();

        // Test successful pause
        vm.prank(infraredGovernance);
        withdrawor.pause();
        assertTrue(withdrawor.paused(), "Contract should be paused");

        // Test functions revert when paused
        vm.prank(keeper);
        vm.expectRevert();
        withdrawor.queue(alice, 1 ether);

        uint256 fee = withdrawor.getFee();
        vm.prank(keeper);
        vm.expectRevert();
        withdrawor.execute{value: fee}(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            1 ether,
            nextBlockTimestamp
        );

        vm.prank(keeper);
        vm.expectRevert();
        withdrawor.process(1);

        vm.prank(alice);
        vm.expectRevert();
        withdrawor.claim(1);

        vm.prank(alice);
        vm.expectRevert();
        withdrawor.claimBatch(new uint256[](1), alice);

        vm.prank(infraredGovernance);
        vm.expectRevert();
        withdrawor.sweepForcedExit(
            header,
            validatorStruct,
            validatorIndex,
            validatorProof,
            nextBlockTimestamp
        );

        vm.prank(infraredGovernance);
        vm.expectRevert();
        withdrawor.sweepUnaccountedForFunds(1 ether);

        // Test unauthorized unpause
        vm.prank(address(10));
        vm.expectRevert();
        withdrawor.unpause();

        // Test successful unpause
        vm.prank(infraredGovernance);
        withdrawor.unpause();
        assertFalse(withdrawor.paused(), "Contract should be unpaused");
    }

    // Test queue edge cases
    function testQueueEdgeCases() public {
        // Test zero amount for non-depositor (should revert)
        vm.prank(keeper);
        vm.expectRevert();
        withdrawor.queue(alice, 0);

        // Test Queue event emission
        vm.expectEmit(true, true, false, true);
        emit IInfraredBERAWithdrawor.Queue(
            alice, withdrawor.requestLength() + 1, 1 ether
        );
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        queueTicket(alice, 1 ether, address(ibera));
    }

    // Test process with newRequestsFinalisedUntil == 0
    function testProcessRevertsWhenZeroRequestsFinalisedUntil() public {
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        withdrawor.process(0);
    }

    // Test process with finalised == 0
    function testProcessWithInitialFinalisedZero() public {
        // Queue a ticket
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId = queueTicket(alice, 1 ether, address(ibera));
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            0,
            "Initial requestsFinalisedUntil should be 0"
        );

        // Simulate funds
        vm.deal(address(withdrawor), 1 ether);

        // Process first ticket
        vm.prank(keeper);
        withdrawor.process(requestId);
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            requestId,
            "requestsFinalisedUntil should update"
        );
        assertEq(
            withdrawor.totalClaimable(),
            1 ether,
            "totalClaimable should reflect ticket amount"
        );
        (IInfraredBERAWithdrawor.RequestState state,,,,) =
            withdrawor.requests(requestId);
        assertEq(
            uint8(state),
            uint8(IInfraredBERAWithdrawor.RequestState.PROCESSED),
            "Ticket should be PROCESSED"
        );
    }

    // Test claim edge cases
    function testClaimEdgeCases() public {
        // Queue and process a ticket
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId = queueTicket(alice, 1 ether, address(ibera));
        vm.deal(address(withdrawor), 1 ether);
        vm.prank(keeper);
        withdrawor.process(requestId);

        // Test claim already CLAIMED
        vm.prank(alice);
        withdrawor.claim(requestId);
        vm.prank(alice);
        vm.expectRevert(Errors.InvalidState.selector);
        withdrawor.claim(requestId);

        // Test claim QUEUED ticket
        uint256 requestId2 = queueTicket(alice, 1 ether, address(ibera));
        vm.prank(alice);
        vm.expectRevert(Errors.NotFinalised.selector);
        withdrawor.claim(requestId2);

        // Test claim depositor ticket
        uint256 requestId3 = queueTicket(address(depositor), 1 ether, keeper);
        vm.deal(address(withdrawor), 10 ether);
        vm.prank(keeper);
        withdrawor.process(requestId3);
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidState.selector);
        withdrawor.claim(requestId3);
    }

    // Test claimBatch
    function testClaimBatch() public {
        // Queue and process multiple tickets
        uint256[] memory requestIds = new uint256[](3);
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < 3; i++) {
            vm.mockCall(
                address(ibera),
                abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
                abi.encode(1 ether)
            );
            requestIds[i] = queueTicket(alice, 1 ether, address(ibera));
            totalAmount += 1 ether;
        }
        vm.deal(address(withdrawor), totalAmount);
        vm.prank(keeper);
        withdrawor.process(requestIds[2]);

        // Test successful batch claim
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IInfraredBERAWithdrawor.Claimed(alice, requestIds[0], 1 ether);
        emit IInfraredBERAWithdrawor.Claimed(alice, requestIds[1], 1 ether);
        emit IInfraredBERAWithdrawor.Claimed(alice, requestIds[2], 1 ether);
        withdrawor.claimBatch(requestIds, alice);
        assertEq(
            alice.balance - balanceBefore,
            totalAmount,
            "Alice should receive total amount"
        );
        assertEq(
            withdrawor.totalClaimable(), 0, "totalClaimable should be zero"
        );
        for (uint256 i = 0; i < 3; i++) {
            (IInfraredBERAWithdrawor.RequestState state,,,,) =
                withdrawor.requests(requestIds[i]);
            assertEq(
                uint8(state),
                uint8(IInfraredBERAWithdrawor.RequestState.CLAIMED),
                "Ticket should be CLAIMED"
            );
        }

        // Test batch with invalid requestId
        requestIds[0] = requestIds[2] + 1; // Non-finalized ID
        vm.prank(alice);
        vm.expectRevert(Errors.NotFinalised.selector);
        withdrawor.claimBatch(requestIds, alice);
    }

    // Test sweepUnaccountedForFunds
    function testSweepUnaccountedForFunds() public {
        // Disable withdrawals
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        // Simulate excess funds
        uint256 amount = 1 ether;
        vm.deal(address(withdrawor), amount);

        // Test unauthorized caller
        vm.prank(address(10));
        vm.expectRevert();
        withdrawor.sweepUnaccountedForFunds(amount);

        // Test insufficient balance
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.InvalidAmount.selector);
        withdrawor.sweepUnaccountedForFunds(amount + 1 ether);

        // Test withdrawals enabled
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(true);

        // Test successful sweep
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);
        address receivor = ibera.receivor();
        uint256 receivorBalanceBefore = receivor.balance;
        vm.prank(infraredGovernance);
        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAWithdrawor.Sweep(receivor, amount);
        withdrawor.sweepUnaccountedForFunds(amount);
        assertEq(
            receivor.balance - receivorBalanceBefore,
            amount,
            "Receivor should receive amount"
        );
        assertEq(
            address(withdrawor).balance, 0, "Withdrawor balance should be zero"
        );
    }

    // Test reserves accuracy
    function testReservesAccuracy() public {
        // Queue and process tickets
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(2 ether)
        );
        uint256 requestId1 = queueTicket(alice, 1 ether, address(ibera));
        uint256 requestId2 = queueTicket(alice, 1 ether, address(ibera));
        vm.deal(address(withdrawor), 2 ether);
        vm.prank(keeper);
        withdrawor.process(requestId2);

        // Verify reserves before claim
        assertEq(
            withdrawor.reserves(),
            0,
            "Reserves should be zero with claimable funds"
        );
        assertEq(
            withdrawor.totalClaimable(),
            2 ether,
            "totalClaimable should reflect tickets"
        );

        // Claim one ticket
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        withdrawor.claim(requestId1);
        assertEq(
            alice.balance - balBefore,
            1 ether,
            "Alice should have claimed amount"
        );
        assertEq(
            withdrawor.totalClaimable(),
            1 ether,
            "totalClaimable should decrease"
        );
    }

    // Test reentrancy safety (simplified, requires mock depositor)
    function testProcessReentrancySafety() public {
        // Deploy a mock malicious depositor that attempts reentrancy
        MaliciousDepositor maliciousDepositor =
            new MaliciousDepositor(address(withdrawor));
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.depositor.selector),
            abi.encode(address(maliciousDepositor))
        );

        // Queue a depositor ticket
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId =
            queueTicket(address(maliciousDepositor), 1 ether, keeper);
        vm.deal(address(withdrawor), 1 ether);

        // Process ticket (should not allow reentrancy due to gas limit)
        vm.prank(keeper);
        withdrawor.process(requestId);
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            requestId,
            "Ticket should be processed"
        );
        assertFalse(
            maliciousDepositor.reentered(), "Reentrancy should not occur"
        );
    }

    // Test upgrade storage compatibility
    function testUpgradeStorageCompatibility() public {
        // Verify new state
        assertEq(withdrawor.requestLength(), 0, "requestLength should be set");
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            0,
            "requestsFinalisedUntil should be zero"
        );
        assertEq(
            withdrawor.totalClaimable(), 0, "totalClaimable should be zero"
        );

        // Queue a ticket to ensure requests mapping is unaffected
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId = queueTicket(alice, 1 ether, address(ibera));
        (
            IInfraredBERAWithdrawor.RequestState state,
            ,
            address receiver,
            uint128 amount,
        ) = withdrawor.requests(requestId);
        assertEq(
            uint8(state),
            uint8(IInfraredBERAWithdrawor.RequestState.QUEUED),
            "New ticket should be QUEUED"
        );
        assertEq(receiver, alice, "Receiver should be correct");
        assertEq(amount, 1 ether, "Amount should be correct");
    }

    function testGetRequestsToProcess() public {
        // Test empty queue
        assertEq(
            withdrawor.getRequestsToProcess(),
            0,
            "Should return 0 for empty queue"
        );

        // Queue tickets
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(3 ether)
        );
        uint256 requestId1 = queueTicket(alice, 1 ether, address(ibera));

        uint256 requestId3 = queueTicket(alice, 1 ether, address(ibera));

        // Test with insufficient reserves
        vm.deal(address(withdrawor), 1.5 ether);
        assertEq(
            withdrawor.getRequestsToProcess(),
            requestId1,
            "Should process one ticket with limited reserves"
        );

        // Test with sufficient reserves
        vm.deal(address(withdrawor), 3 ether);
        assertEq(
            withdrawor.getRequestsToProcess(),
            requestId3,
            "Should process all tickets with sufficient reserves"
        );

        // Test after partial processing
        vm.prank(keeper);
        withdrawor.process(requestId1);
        assertEq(
            withdrawor.getRequestsToProcess(),
            requestId3,
            "Should process remaining tickets"
        );

        // Test with finalised == requestLength
        vm.prank(keeper);
        withdrawor.process(requestId3);
        assertEq(
            withdrawor.getRequestsToProcess(),
            0,
            "Should return 0 when all tickets processed"
        );
    }

    function testGetRequestsToProcessFinalisedZero() public {
        // Queue a ticket
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId = queueTicket(alice, 1 ether, address(ibera));
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            0,
            "Initial requestsFinalisedUntil should be 0"
        );

        // Test with sufficient reserves
        vm.deal(address(withdrawor), 1 ether);
        assertEq(
            withdrawor.getRequestsToProcess(),
            requestId,
            "Should process first ticket"
        );
    }

    // Test getQueuedAmount with single queued ticket
    function testGetQueuedAmountSingleTicket() public {
        // Queue a ticket
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(1 ether)
        );
        uint256 requestId = queueTicket(alice, 1 ether, address(ibera));
        assertEq(
            withdrawor.getQueuedAmount(), 1 ether, "Should return ticket amount"
        );
        (,,, uint128 amount, uint128 accumulatedAmount) =
            withdrawor.requests(requestId);
        assertEq(amount, 1 ether, "Ticket amount should be correct");
        assertEq(
            accumulatedAmount,
            1 ether,
            "Ticket accumulatedAmount should be correct"
        );
    }

    // Test getQueuedAmount with multiple queued tickets
    function testGetQueuedAmountMultipleTickets() public {
        // Queue multiple tickets
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(3 ether)
        );
        queueTicket(alice, 1 ether, address(ibera));
        queueTicket(alice, 1 ether, address(ibera));
        uint256 requestId3 = queueTicket(address(depositor), 1 ether, keeper);

        assertEq(
            withdrawor.getQueuedAmount(),
            3 ether,
            "Should return total queued amount"
        );
        (,,,, uint128 accumulatedAmount) = withdrawor.requests(requestId3);
        assertEq(
            accumulatedAmount,
            3 ether,
            "Final accumulatedAmount should be correct"
        );
    }

    // Test getQueuedAmount after partial processing
    function testGetQueuedAmountAfterPartialProcess() public {
        // Queue multiple tickets
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(3 ether)
        );
        uint256 requestId1 = queueTicket(alice, 1 ether, address(ibera));
        queueTicket(alice, 1 ether, address(ibera));
        queueTicket(address(depositor), 1 ether, keeper);

        // Process first ticket
        vm.deal(address(withdrawor), 3 ether);
        vm.prank(keeper);
        withdrawor.process(requestId1);

        assertEq(
            withdrawor.getQueuedAmount(),
            2 ether,
            "Should return remaining queued amount"
        );
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            requestId1,
            "requestsFinalisedUntil should be updated"
        );
    }

    // Test getQueuedAmount when all tickets processed
    function testGetQueuedAmountAllProcessed() public {
        // Queue multiple tickets
        vm.mockCall(
            address(ibera),
            abi.encodeWithSelector(IInfraredBERA.confirmed.selector),
            abi.encode(2 ether)
        );

        uint256 requestId2 = queueTicket(alice, 1 ether, address(ibera));

        // Process all tickets
        vm.deal(address(withdrawor), 2 ether);
        vm.prank(keeper);
        withdrawor.process(requestId2);

        assertEq(
            withdrawor.getQueuedAmount(),
            0,
            "Should return 0 when all tickets processed"
        );
        assertEq(
            withdrawor.requestLength(),
            requestId2,
            "requestLength should be correct"
        );
        assertEq(
            withdrawor.requestsFinalisedUntil(),
            requestId2,
            "requestsFinalisedUntil should match requestLength"
        );
    }
}

// Mock malicious depositor for reentrancy test
contract MaliciousDepositor {
    address public withdrawor;
    bool public reentered;

    constructor(address _withdrawor) {
        withdrawor = _withdrawor;
    }

    function queue() external payable {
        try IInfraredBERAWithdrawor(withdrawor).process(1) {
            reentered = true;
        } catch {}
    }
}
