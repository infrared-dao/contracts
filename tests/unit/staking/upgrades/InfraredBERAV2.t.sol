// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./InfraredBERAV2Base.t.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {IInfraredBERA} from "src/depreciated/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Errors} from "src/utils/Errors.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {ProofHelper} from "./proofgeneration/ProofHelper.sol";

contract InfraredBERAV2Test is InfraredBERAV2BaseTest {
    ProofHelper public proofHelper;

    function setUp() public override {
        super.setUp();

        // Deploy proof helper
        proofHelper = new ProofHelper();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeV2() public view {
        // Should start with withdrawals enabled and burn fee set
        assertTrue(ibera.withdrawalsEnabled());
        assertEq(ibera.burnFee(), InfraredBERAConstants.MINIMUM_WITHDRAW_FEE);
    }

    function testInitializeV2OnlyGovernor() public {
        // Test access control on already initialized contract
        // We need to test a function that requires governance role

        vm.expectRevert();
        vm.prank(alice);
        ibera.setWithdrawalsEnabled(false);

        // Should work with governor
        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        assertFalse(ibera.withdrawalsEnabled());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              PROOF TIMESTAMP BUFFER TESTS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testInitializeV2SetsProofTimestampBuffer() public view {
        // proofTimestampBuffer should be initialized to 10 minutes
        assertEq(ibera.proofTimestampBuffer(), 10 minutes);
    }

    function testUpdateProofTimestampBuffer() public {
        uint256 newBuffer = 15 minutes;

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAV2.ProofTimestampBufferUpdated(newBuffer);

        vm.prank(infraredGovernance);
        ibera.updateProofTimestampBuffer(newBuffer);

        assertEq(ibera.proofTimestampBuffer(), newBuffer);
    }

    function testUpdateProofTimestampBufferOnlyGovernor() public {
        uint256 newBuffer = 5 minutes;

        vm.expectRevert();
        vm.prank(alice);
        ibera.updateProofTimestampBuffer(newBuffer);

        // Should work with governor
        vm.prank(infraredGovernance);
        ibera.updateProofTimestampBuffer(newBuffer);

        assertEq(ibera.proofTimestampBuffer(), newBuffer);
    }

    function testUpdateProofTimestampBufferRevertsOnZero() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(infraredGovernance);
        ibera.updateProofTimestampBuffer(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MINT TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testMintBasicFunctionality() public {
        uint256 amount = 12 ether;
        uint256 initialDeposits = ibera.deposits();
        uint256 initialSupply = ibera.totalSupply();

        uint256 shares = ibera.mint{value: amount}(alice);

        // Check shares calculation: first mint should be 1:1 if no prior deposits
        uint256 expectedShares = (initialDeposits == 0 && initialSupply == 0)
            ? amount
            : (initialSupply * amount) / initialDeposits;

        assertEq(shares, expectedShares);
        assertEq(ibera.balanceOf(alice), expectedShares);
        assertEq(ibera.deposits(), initialDeposits + amount);
        assertEq(ibera.totalSupply(), initialSupply + expectedShares);
    }

    function testMintEmitsMintEvent() public {
        uint256 amount = 5 ether;
        uint256 expectedShares = amount; // First mint

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Mint(alice, amount, expectedShares);

        ibera.mint{value: amount}(alice);
    }

    function testMintRevertsWithZeroShares() public {
        // This would happen if amount is 0 or calculation results in 0
        vm.expectRevert(Errors.InvalidShares.selector);
        ibera.mint{value: 0}(alice);
    }

    function testMintCompoundsBeforeMinting() public {
        // First mint to establish state
        ibera.mint{value: 10 ether}(alice);

        // Add rewards to receivor
        uint256 rewardsAmount = 2 ether;
        (bool success,) = address(receivor).call{value: rewardsAmount}("");
        assertTrue(success);

        uint256 depositsBefore = ibera.deposits();

        // In V2, rewards are subject to fee collection (feeDivisorShareholders = 4, so 75% to shareholders)
        uint256 expectedSweepAmount = (rewardsAmount * 3) / 4; // 75% after fees
        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Sweep(expectedSweepAmount);

        // Second mint should compound first
        ibera.mint{value: 5 ether}(bob);

        // Deposits should include the compounded amount (after fees)
        assertEq(
            ibera.deposits(), depositsBefore + expectedSweepAmount + 5 ether
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      BURN TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testBurnBasicFunctionality() public {
        // Setup: mint enough tokens to cover initial deposit (10k ether)
        uint256 mintAmount = 20_000 ether; // More than INITIAL_DEPOSIT
        ibera.mint{value: mintAmount}(alice);

        // Setup validator for withdrawals
        setupValidatorForTesting(pubkey0);
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        uint256 burnFee = ibera.burnFee();
        uint256 sharesToBurn = 5 ether;
        assertTrue(
            sharesToBurn > burnFee, "Shares to burn must exceed burn fee"
        );

        uint256 netShares = sharesToBurn - burnFee;
        uint256 totalSupplyBefore = ibera.totalSupply();
        uint256 depositsBefore = ibera.deposits();
        uint256 aliceBalanceBefore = ibera.balanceOf(alice);
        uint256 contractBalanceBefore = ibera.balanceOf(address(ibera));

        uint256 expectedAmount =
            (depositsBefore * netShares) / totalSupplyBefore;

        vm.prank(alice);
        (uint256 nonce, uint256 amount) = ibera.burn(bob, sharesToBurn);

        // Check return values
        assertEq(amount, expectedAmount);
        assertTrue(nonce > 0, "Nonce should be greater than 0");

        // Check state changes
        assertEq(ibera.balanceOf(alice), aliceBalanceBefore - sharesToBurn);
        assertEq(ibera.totalSupply(), totalSupplyBefore - netShares);
        assertEq(ibera.deposits(), depositsBefore - expectedAmount);

        // Check exit fees are collected (V2 uses exitFeesToCollect + transfer to self)
        assertEq(
            ibera.balanceOf(address(ibera)), contractBalanceBefore + burnFee
        );
    }

    function testBurnRevertsWhenWithdrawalsDisabled() public {
        ibera.mint{value: 10 ether}(alice);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        vm.prank(alice);
        vm.expectRevert(Errors.WithdrawalsNotEnabled.selector);
        ibera.burn(alice, 1 ether);
    }

    function testBurnRevertsWithInsufficientFee() public {
        ibera.mint{value: 10 ether}(alice);

        uint256 burnFee = ibera.burnFee();
        uint256 insufficientShares = burnFee - 1;

        vm.prank(alice);
        vm.expectRevert(Errors.MinExitFeeNotMet.selector);
        ibera.burn(alice, insufficientShares);
    }

    function testBurnRevertsWithZeroShares() public {
        ibera.mint{value: 10 ether}(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.MinExitFeeNotMet.selector);
        ibera.burn(alice, 0);
    }

    function testBurnRevertsWithZeroAddress() public {
        ibera.mint{value: 10 ether}(alice);

        uint256 shares = 5 ether;
        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        ibera.burn(address(0), shares);
    }

    function testBurnEmitsBurnEvent() public {
        ibera.mint{value: 20_000 ether}(alice);
        setupValidatorForTesting(pubkey0);
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        uint256 shares = 5 ether;
        uint256 burnFee = ibera.burnFee();
        uint256 netShares = shares - burnFee;
        uint256 expectedAmount =
            (ibera.deposits() * netShares) / ibera.totalSupply();
        uint256 expectedNonce = withdrawor.requestLength() + 1;

        vm.expectEmit(true, true, false, true);
        emit IInfraredBERA.Burn(
            bob, expectedNonce, expectedAmount, shares, burnFee
        );

        vm.prank(alice);
        ibera.burn(bob, shares);
    }

    function testBurnCompoundsBeforeBurning() public {
        ibera.mint{value: 20_000 ether}(alice);
        setupValidatorForTesting(pubkey0);
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        // Add rewards
        uint256 rewardsAmount = 3 ether;
        (bool success,) = address(receivor).call{value: rewardsAmount}("");
        assertTrue(success);

        uint256 depositsBefore = ibera.deposits();

        // In V2, rewards are subject to fee collection (feeDivisorShareholders = 4, so 75% to shareholders)
        uint256 expectedSweepAmount = (rewardsAmount * 3) / 4; // 75% after fees
        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Sweep(expectedSweepAmount);

        vm.prank(alice);
        ibera.burn(bob, 5 ether);

        // Check that rewards were compounded
        assertTrue(ibera.deposits() > depositsBefore - 5 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ADMIN FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testSetWithdrawalsEnabled() public {
        bool currentState = ibera.withdrawalsEnabled();

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAV2.WithdrawalFlagSet(!currentState);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(!currentState);

        assertEq(ibera.withdrawalsEnabled(), !currentState);
    }

    function testSetWithdrawalsEnabledOnlyGovernor() public {
        vm.expectRevert();
        vm.prank(alice);
        ibera.setWithdrawalsEnabled(false);
    }

    function testUpdateBurnFee() public {
        uint256 newFee = 0.005 ether;

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAV2.BurnFeeUpdated(newFee);

        vm.prank(infraredGovernance);
        ibera.updateBurnFee(newFee);

        assertEq(ibera.burnFee(), newFee);
    }

    function testUpdateBurnFeeOnlyGovernor() public {
        vm.expectRevert();
        vm.prank(alice);
        ibera.updateBurnFee(0.01 ether);
    }

    function testSetFeeDivisorShareholders() public {
        // Add some rewards first to test compounding
        (bool success,) = address(receivor).call{value: 5 ether}("");
        assertTrue(success);

        uint16 newDivisor = 200;
        uint16 oldDivisor = ibera.feeDivisorShareholders();

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.SetFeeShareholders(oldDivisor, newDivisor);

        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(newDivisor);

        assertEq(ibera.feeDivisorShareholders(), newDivisor);
    }

    function testSetDepositSignature() public {
        bytes memory newSignature =
            abi.encodePacked(bytes32("new"), bytes32("sig"), bytes32("here"));
        bytes memory oldSignature = ibera.signatures(pubkey0);

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.SetDepositSignature(
            pubkey0, oldSignature, newSignature
        );

        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey0, newSignature);

        assertEq(ibera.signatures(pubkey0), newSignature);
    }

    function testSetDepositSignatureInvalidLength() public {
        bytes memory invalidSignature = abi.encodePacked(bytes32("short"));

        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.InvalidSignature.selector);
        ibera.setDepositSignature(pubkey0, invalidSignature);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    VALIDATOR MANAGEMENT                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testRegisterPositiveDelta() public {
        uint256 amount = 32 ether;
        uint256 initialStake = ibera.stakes(pubkey0);

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Register(
            pubkey0, int256(amount), initialStake + amount
        );

        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(amount));

        assertEq(ibera.stakes(pubkey0), initialStake + amount);
        assertTrue(ibera.staked(pubkey0));
    }

    function testRegisterNegativeDelta() public {
        // First add some stake
        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(32 ether));

        uint256 withdrawAmount = 10 ether;
        uint256 initialStake = ibera.stakes(pubkey0);

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Register(
            pubkey0, -int256(withdrawAmount), initialStake - withdrawAmount
        );

        vm.prank(address(withdrawor));
        ibera.register(pubkey0, -int256(withdrawAmount));

        assertEq(ibera.stakes(pubkey0), initialStake - withdrawAmount);
    }

    function testRegisterFullExit() public {
        uint256 amount = 32 ether;
        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(amount));

        // Full exit (stake goes to 0)
        vm.prank(address(withdrawor));
        ibera.register(pubkey0, -int256(amount));

        assertEq(ibera.stakes(pubkey0), 0);
        assertFalse(ibera.staked(pubkey0));
        assertTrue(ibera.hasExited(pubkey0));
    }

    function testRegisterUnauthorized() public {
        vm.expectRevert();
        vm.prank(alice);
        ibera.register(pubkey0, int256(32 ether));
    }

    function testRegisterExitedValidator() public {
        // First register and then exit
        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(32 ether));
        vm.prank(address(withdrawor));
        ibera.register(pubkey0, -int256(32 ether));

        // Try to register again on exited validator
        vm.prank(address(depositor));
        vm.expectRevert(Errors.ValidatorForceExited.selector);
        ibera.register(pubkey0, int256(1 ether));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  REGISTER VIA PROOFS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testRegisterViaProofsSuccess() public {
        uint256 clBalance = 5934426930679472000000000;
        uint256 initialStake = 32 ether;

        // First register some stake
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(initialStake));

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAV2.RegisterViaProof(
            validatorStruct.pubkey, clBalance, initialStake
        );

        vm.prank(keeper);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        assertEq(ibera.stakes(validatorStruct.pubkey), clBalance);
    }

    function testRegisterViaProofsSameBalance() public {
        uint256 balance = getTestBalance();

        // Set internal stake to match CL balance
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(balance));

        // Should return early without changes
        vm.prank(keeper);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        assertEq(ibera.stakes(validatorStruct.pubkey), balance);
    }

    function testRegisterViaProofsBalanceMismatch() public {
        // Set up stake to be different from balance so function proceeds
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(1 ether));

        // Create an invalid balance proof that will fail verification
        bytes32[] memory invalidBalanceProof =
            new bytes32[](balanceProof.length);
        for (uint256 i = 0; i < balanceProof.length; i++) {
            invalidBalanceProof[i] = bytes32(uint256(i * 2 + 1)); // Invalid proof data
        }

        vm.prank(keeper);
        vm.expectRevert(Errors.BalanceMissmatch.selector);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            invalidBalanceProof, // This should cause balance verification to fail
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
    }

    function testRegisterViaProofsInvalidValidator() public {
        // Set up stake to be different from balance so function proceeds
        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(1 ether));

        // Create invalid validator proof that will fail verification
        bytes32[] memory invalidValidatorProof = new bytes32[](41);
        for (uint256 i = 0; i < 41; i++) {
            invalidValidatorProof[i] = bytes32(uint256(i)); // Invalid proof data
        }

        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroBalance.selector);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            invalidValidatorProof, // This should cause verification to fail
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
    }

    function testRegisterViaProofsOnlyKeeper() public {
        vm.expectRevert();
        vm.prank(alice);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              REGISTER VIA PROOFS WITH PROOFHELPER         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testRegisterViaProofsWithGeneratedProofsSuccess() public {
        // Setup validator for proof test using ProofHelper
        setupValidatorForProofTestWithHelper();

        // Extract expected CL balance from proof
        uint256 expectedBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Set initial stake different from CL balance to trigger update
        uint256 initialStake = 10 ether;
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(initialStake));

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERAV2.RegisterViaProof(
            validatorStruct.pubkey, expectedBalance, initialStake
        );

        vm.prank(keeper);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        // Verify stake was updated to match CL balance
        assertEq(ibera.stakes(validatorStruct.pubkey), expectedBalance);
    }

    function testRegisterViaProofsWithWrongValidator() public {
        // Setup validator for proof test using ProofHelper
        setupValidatorForProofTestWithHelper();

        // Set initial stake different from CL balance to trigger update
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(10 ether));

        // Create invalid validator proof
        bytes32[] memory invalidValidatorProof =
            new bytes32[](validatorProof.length);
        for (uint256 i = 0; i < validatorProof.length; i++) {
            invalidValidatorProof[i] = bytes32(uint256(i + 1)); // Invalid proof data
        }

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidValidator.selector);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            invalidValidatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
    }

    function testRegisterViaProofsWithInvalidBalanceProof() public {
        // Setup validator for proof test using ProofHelper
        setupValidatorForProofTestWithHelper();

        // Set initial stake different from CL balance to trigger update
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(10 ether));

        // Create invalid balance proof
        bytes32[] memory invalidBalanceProof =
            new bytes32[](balanceProof.length);
        for (uint256 i = 0; i < balanceProof.length; i++) {
            invalidBalanceProof[i] = bytes32(uint256(i * 2 + 1)); // Invalid proof data
        }

        vm.prank(keeper);
        vm.expectRevert(Errors.BalanceMissmatch.selector);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            invalidBalanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );
    }

    function testRegisterViaProofsWithSameBalance() public {
        // Setup validator for proof test using ProofHelper
        setupValidatorForProofTestWithHelper();

        // Extract CL balance from proof
        uint256 clBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Set internal stake to exactly match CL balance
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(clBalance));

        uint256 stakeBeforeCall = ibera.stakes(validatorStruct.pubkey);

        // Should return early without changes since stakes match
        vm.prank(keeper);
        ibera.registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            nextBlockTimestamp
        );

        // Verify stake remains unchanged
        assertEq(ibera.stakes(validatorStruct.pubkey), stakeBeforeCall);
        assertEq(ibera.stakes(validatorStruct.pubkey), clBalance);
    }

    function setupValidatorForProofTestWithHelper() internal {
        // Register validator in Infrared using existing proof data
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: validatorStruct.pubkey,
            addr: address(infrared)
        });
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Set deposit signature
        bytes memory signature =
            abi.encodePacked(bytes32("sig1"), bytes32("sig2"), bytes32("sig3"));
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(validatorStruct.pubkey, signature);

        // Set withdrawor to match proof expectation
        bytes32 withdraworSlot = bytes32(uint256(22));
        address proofWithdrawor = 0x8c0E122960dc2E97dc0059c07d6901Dce72818E1;
        vm.store(
            address(ibera),
            withdraworSlot,
            bytes32(uint256(uint160(proofWithdrawor)))
        );
        // introduce mock call for botched withdrawor address created above
        vm.mockCall(
            proofWithdrawor,
            abi.encodeWithSelector(
                withdrawor.getTotalPendingWithdrawals.selector,
                keccak256(validatorStruct.pubkey)
            ),
            abi.encode(0)
        );
    }

    function testRegisterViaProofsWithSlashedValidator() public {
        // Use ProofHelper to create a slashed validator
        bytes memory slashedPubkey =
            abi.encodePacked(bytes32("slashed"), bytes16(""));
        BeaconRootsVerify.Validator memory slashedValidator = proofHelper
            .createSlashedValidator(
            slashedPubkey,
            0x8c0E122960dc2E97dc0059c07d6901Dce72818E1,
            32000000000 // 32 ETH in gwei
        );

        // Register slashed validator in Infrared
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: slashedValidator.pubkey,
            addr: address(infrared)
        });
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Set deposit signature
        bytes memory signature =
            abi.encodePacked(bytes32("sig1"), bytes32("sig2"), bytes32("sig3"));
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(slashedValidator.pubkey, signature);

        // Set initial stake to track the validator
        vm.prank(address(depositor));
        ibera.register(slashedValidator.pubkey, int256(32 ether));

        // Verify the validator is slashed
        assertTrue(slashedValidator.slashed);
        assertEq(ibera.stakes(slashedValidator.pubkey), 32 ether);
    }

    function testRegisterViaProofsWithCustomWithdrawalCredentials() public {
        // Use ProofHelper to create validator with specific withdrawal credentials
        bytes memory customPubkey =
            abi.encodePacked(bytes32("custom"), bytes16(""));
        address customWithdrawal = makeAddr("customWithdrawal");

        BeaconRootsVerify.Validator memory customValidator = proofHelper
            .createValidatorWithCredentials(
            customPubkey,
            customWithdrawal,
            32000000000 // 32 ETH in gwei
        );

        // Register custom validator in Infrared
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: customValidator.pubkey,
            addr: address(infrared)
        });
        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Set deposit signature
        bytes memory signature =
            abi.encodePacked(bytes32("sig1"), bytes32("sig2"), bytes32("sig3"));
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(customValidator.pubkey, signature);

        // Verify withdrawal credentials are set correctly
        assertEq(
            customValidator.withdrawalCredentials,
            bytes32(uint256(uint160(customWithdrawal)))
        );
        assertEq(customValidator.effectiveBalance, 32000000000);
        assertFalse(customValidator.slashed);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXIT FEES                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testClaimExitFees() public {
        // First create some exit fees through burns
        ibera.mint{value: 20_000 ether}(alice);
        setupValidatorForTesting(pubkey0);
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        uint256 burnFee = ibera.burnFee();
        uint256 contractBalanceBefore = ibera.balanceOf(address(ibera));

        vm.prank(alice);
        ibera.burn(bob, 5 ether);

        uint256 collectedFees = ibera.balanceOf(address(ibera));
        assertEq(collectedFees, contractBalanceBefore + burnFee);

        address recipient = makeAddr("recipient");

        vm.expectEmit(true, true, false, true);
        emit IInfraredBERAV2.ExitFeesCollected(burnFee, recipient); // Only the actual exit fees

        vm.prank(infraredGovernance);
        ibera.claimExitFees(recipient);

        assertEq(ibera.balanceOf(recipient), burnFee);
        assertEq(ibera.balanceOf(address(ibera)), collectedFees - burnFee); // Contract retains compounding tokens
    }

    function testClaimExitFeesOnlyGovernor() public {
        vm.expectRevert();
        vm.prank(alice);
        ibera.claimExitFees(alice);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PREVIEW FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testPreviewMint() public {
        uint256 amount = 10 ether;

        // Before any mints
        uint256 previewShares = ibera.previewMint(amount);
        assertEq(previewShares, amount);

        // After first mint
        ibera.mint{value: amount}(alice);
        uint256 previewShares2 = ibera.previewMint(amount);
        uint256 expectedShares =
            (ibera.totalSupply() * amount) / ibera.deposits();
        assertEq(previewShares2, expectedShares);
    }

    function testPreviewMintWithCompounding() public {
        ibera.mint{value: 10 ether}(alice);

        // Add rewards
        (bool success,) = address(receivor).call{value: 2 ether}("");
        assertTrue(success);

        uint256 amount = 5 ether;
        uint256 previewShares = ibera.previewMint(amount);

        // Actually mint and compare
        uint256 actualShares = ibera.mint{value: amount}(bob);
        assertEq(previewShares, actualShares);
    }

    function testPreviewBurn() public {
        ibera.mint{value: 20 ether}(alice);

        uint256 shares = 5 ether;
        uint256 burnFee = ibera.burnFee();

        (uint256 previewAmount,) = ibera.previewBurn(shares);
        uint256 expectedAmount = shares > burnFee
            ? (ibera.deposits() * (shares - burnFee)) / ibera.totalSupply()
            : 0;

        assertEq(previewAmount, expectedAmount);
    }

    function testPreviewBurnWithFeeExceeded() public {
        ibera.mint{value: 20 ether}(alice);

        uint256 burnFee = ibera.burnFee();
        uint256 shares = burnFee - 1; // Less than fee

        (uint256 previewAmount,) = ibera.previewBurn(shares);
        assertEq(previewAmount, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ERC4626 COMPLIANCE                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testAsset() public view {
        assertEq(ibera.asset(), address(0)); // Native BERA
    }

    function testTotalAssets() public {
        assertEq(ibera.totalAssets(), ibera.deposits());

        ibera.mint{value: 15 ether}(alice);
        assertEq(ibera.totalAssets(), ibera.deposits());
    }

    function testMaxDeposit() public view {
        assertEq(ibera.maxDeposit(alice), type(uint256).max);
    }

    function testMaxMint() public view {
        assertEq(ibera.maxMint(alice), type(uint256).max);
    }

    function testMaxWithdrawEnabled() public {
        ibera.mint{value: 10 ether}(alice);
        uint256 aliceAssets = ibera.convertToAssets(
            ibera.balanceOf(alice) - InfraredBERAConstants.MINIMUM_WITHDRAW_FEE
        );
        assertEq(ibera.maxWithdraw(alice), aliceAssets);
    }

    function testMaxWithdrawDisabled() public {
        ibera.mint{value: 10 ether}(alice);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        assertEq(ibera.maxWithdraw(alice), 0);
    }

    function testMaxRedeemEnabled() public {
        ibera.mint{value: 10 ether}(alice);
        assertEq(ibera.maxRedeem(alice), ibera.balanceOf(alice));
    }

    function testMaxRedeemDisabled() public {
        ibera.mint{value: 10 ether}(alice);

        vm.prank(infraredGovernance);
        ibera.setWithdrawalsEnabled(false);

        assertEq(ibera.maxRedeem(alice), 0);
    }

    function testConvertToShares() public {
        uint256 assets = 100 ether;

        // Before any supply
        assertEq(ibera.convertToShares(assets), assets);

        // After minting
        ibera.mint{value: 50 ether}(alice);
        uint256 expectedShares =
            (assets * ibera.totalSupply()) / ibera.totalAssets();
        assertEq(ibera.convertToShares(assets), expectedShares);
    }

    function testConvertToAssets() public {
        uint256 shares = 100 ether;

        // Before any supply
        assertEq(ibera.convertToAssets(shares), shares);

        // After minting
        ibera.mint{value: 50 ether}(alice);
        uint256 expectedAssets =
            (shares * ibera.totalAssets()) / ibera.totalSupply();
        assertEq(ibera.convertToAssets(shares), expectedAssets);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testPending() public {
        uint256 amount = 10 ether;
        uint256 pendingBefore = ibera.pending();
        ibera.mint{value: amount}(alice);
        assertEq(ibera.pending(), pendingBefore + amount);
    }

    function testConfirmed() public {
        uint256 amount = 20_000 ether;
        ibera.mint{value: amount}(alice);

        // Before any deposits to CL, all should be pending
        assertEq(ibera.confirmed(), 0);

        // After depositing to CL
        setupValidatorForTesting(pubkey0);
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        uint256 confirmed = ibera.confirmed();
        assertTrue(confirmed > 0);
        assertEq(confirmed + ibera.pending(), ibera.deposits());
    }

    function testValidatorFunctions() public {
        // Test stakes
        assertEq(ibera.stakes(pubkey0), 0);

        vm.prank(address(depositor));
        ibera.register(pubkey0, int256(32 ether));
        assertEq(ibera.stakes(pubkey0), 32 ether);

        // Test staked
        assertTrue(ibera.staked(pubkey0));

        // Test hasExited
        assertFalse(ibera.hasExited(pubkey0));

        // Test signatures
        setupValidatorForTesting(pubkey0);
        assertTrue(ibera.signatures(pubkey0).length > 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     SWEEP FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testSweepFromReceiver() public {
        uint256 depositsBefore = ibera.deposits();
        uint256 amount = 5 ether;

        // Give the receiver contract enough balance
        vm.deal(address(receivor), amount);

        vm.expectEmit(true, false, false, true);
        emit IInfraredBERA.Sweep(amount);

        vm.prank(address(receivor));
        ibera.sweep{value: amount}();

        assertEq(ibera.deposits(), depositsBefore + amount);
    }

    function testSweepUnauthorized() public {
        uint256 amount = 5 ether;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, alice)
        );
        vm.prank(alice);
        ibera.sweep{value: amount}();
    }

    function testCollectFromInfrared() public {
        // Mock return value
        uint256 expectedShares = 100 ether;
        vm.mockCall(
            address(receivor),
            abi.encodeWithSignature("collect()"),
            abi.encode(expectedShares)
        );

        vm.prank(address(infrared));
        uint256 shares = ibera.collect();

        assertEq(shares, expectedShares);
    }

    function testCollectUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, alice)
        );
        vm.prank(alice);
        ibera.collect();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                STALE PROOF VALIDATION TESTS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Test that registerViaProofs reverts when proof data is stale
    function testRegisterViaProofsRevertsOnStaleProof() public {
        // Setup validator
        bytes memory pubkey = abi.encodePacked(bytes32("testval"), bytes16(""));
        setupValidatorForTesting(pubkey);

        // Set initial stake
        vm.prank(address(depositor));
        ibera.register(pubkey, int256(32 ether));

        // Create test proof data
        BeaconRootsVerify.BeaconBlockHeader memory testHeader =
        BeaconRootsVerify.BeaconBlockHeader({
            slot: 100,
            proposerIndex: 1,
            parentRoot: bytes32(uint256(1)),
            stateRoot: bytes32(uint256(2)),
            bodyRoot: bytes32(uint256(3))
        });

        BeaconRootsVerify.Validator memory testValidator = BeaconRootsVerify
            .Validator({
            pubkey: pubkey,
            withdrawalCredentials: bytes32(uint256(uint160(address(withdrawor)))),
            effectiveBalance: 32000000000,
            slashed: false,
            activationEligibilityEpoch: 0,
            activationEpoch: 0,
            exitEpoch: type(uint64).max,
            withdrawableEpoch: type(uint64).max
        });

        bytes32[] memory validatorProof = new bytes32[](1);
        validatorProof[0] = bytes32(uint256(1));

        bytes32[] memory balanceProof = new bytes32[](1);
        balanceProof[0] = bytes32(uint256(2));

        uint256 validatorIndex = 3;
        bytes32 balanceLeaf = bytes32(uint256(32 ether));
        uint256 testTimestamp = block.timestamp;

        // Mock beacon roots
        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(testTimestamp),
            abi.encode(
                BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(testHeader)
            )
        );

        // Fast forward time to make proof stale
        uint256 buffer = ibera.proofTimestampBuffer();
        vm.warp(block.timestamp + buffer + 1 seconds);

        // Should revert with StaleProof
        vm.expectRevert(Errors.StaleProof.selector);
        vm.prank(keeper);
        ibera.registerViaProofs(
            testHeader,
            testValidator,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            testTimestamp
        );
    }

    /// @notice Test that registerViaProofs succeeds when proof is within timestamp buffer
    function testRegisterViaProofsSucceedsWithinTimestampBuffer() public {
        // Setup validator using the actual validator from proof data
        setupValidatorForTesting(validatorStruct.pubkey);

        // Set initial stake different from proof balance
        vm.prank(address(depositor));
        ibera.register(validatorStruct.pubkey, int256(30 ether));

        // Get current stake and create valid proof data
        uint256 targetStake = 32 ether;
        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey,
            address(withdrawor),
            uint64(targetStake / 1 gwei)
        );

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, targetStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
        BeaconRootsVerify.BeaconBlockHeader({
            slot: header.slot,
            proposerIndex: header.proposerIndex,
            parentRoot: header.parentRoot,
            stateRoot: stateRoot,
            bodyRoot: header.bodyRoot
        });

        // Fast forward time but stay within buffer
        uint256 buffer = ibera.proofTimestampBuffer();
        vm.warp(block.timestamp + buffer - 1 seconds);

        // Use a timestamp that makes the proof within buffer
        uint256 testTimestamp = block.timestamp - buffer + 2 seconds;

        // Mock beacon roots with proper header
        bytes32 headerRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(customHeader);
        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(testTimestamp),
            abi.encode(headerRoot)
        );

        // Should succeed and update stake
        vm.prank(keeper);
        ibera.registerViaProofs(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            testTimestamp
        );

        // Verify stake was updated to proof balance
        assertEq(ibera.stakes(validatorStruct.pubkey), targetStake);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setupValidatorForTesting(bytes memory pubkey) internal {
        // Register validator in main Infrared contract first
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: pubkey,
            addr: address(0x999) // Mock validator address
        });

        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Set deposit signature in iBERA
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(
            pubkey,
            abi.encodePacked(bytes32("sig1"), bytes32("sig2"), bytes32("sig3"))
        );
    }
}
