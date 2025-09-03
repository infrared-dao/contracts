// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./InfraredBERAV2Base.t.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERAV2} from "src/interfaces/upgrades/IInfraredBERAV2.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {ProofHelper} from "./proofgeneration/ProofHelper.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract InfraredBERADepositorV2Test is InfraredBERAV2BaseTest {
    using stdStorage for StdStorage;

    BeaconDeposit public depositContract;
    address public constant DEPOSIT_CONTRACT_ADDRESS =
        0x4242424242424242424242424242424242424242;

    uint256 public constant MIN_ACTIVATION_DEPOSIT = 500_000 ether;
    uint256 public initialReserves; // Track initial reserves

    ProofHelper public proofHelper;

    event Queue(uint256 amount);
    event Execute(bytes pubkey, uint256 amount);
    event MinActivationDepositUpdated(uint256 newMinActivationDeposit);

    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        // Deploy and set up mock beacon deposit contract
        depositContract = new BeaconDeposit();
        vm.etch(DEPOSIT_CONTRACT_ADDRESS, address(depositContract).code);

        // Initialize depositor V2
        vm.prank(infraredGovernance);
        depositor.initializeV2();

        // Verify initialization
        assertEq(depositor.minActivationDeposit(), MIN_ACTIVATION_DEPOSIT);

        // Add validators to infrared
        ValidatorTypes.Validator memory infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey0, addr: address(infrared)});
        infraredValidators.push(infraredValidator);
        infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey1, addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        vm.startPrank(infraredGovernance);
        infrared.addValidators(infraredValidators);
        ibera.setFeeDivisorShareholders(4);
        vm.stopPrank();

        // Track initial reserves
        initialReserves = depositor.reserves();

        // Deploy proof helper
        proofHelper = new ProofHelper();
    }

    // Helper to setup validator for proof-based tests
    function setupValidatorForProofTest() internal {
        // Only setup the validator registration, not the stake
        // Register validator in Infrared
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

        // Set withdrawor to match proof
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

    // Helper to queue deposits from a specific address
    function queueDepositsFrom(address from, uint256 amount) internal {
        vm.deal(from, amount);
        vm.prank(from);
        depositor.queue{value: amount}();
    }

    // For tests that need proofs, we can check and setup as needed
    modifier withProofSetup() {
        setupValidatorForProofTest();
        _;
    }

    function setupValidatorWithSignature(bytes memory pubkey) internal {
        // Check if already added to avoid duplicate addition
        bytes memory signature =
            abi.encodePacked(bytes32("sig1"), bytes32("sig2"), bytes32("sig3"));

        if (infrared.isInfraredValidator(pubkey)) {
            // Just set the signature if validator already exists
            vm.prank(infraredGovernance);
            ibera.setDepositSignature(pubkey, signature);
            return;
        }

        // Add validator to infrared
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] =
            ValidatorTypes.Validator({pubkey: pubkey, addr: address(infrared)});

        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        // Set signature in iBERA
        vm.prank(infraredGovernance);
        ibera.setDepositSignature(pubkey, signature);
    }

    function queueDeposits(uint256 amount) internal {
        vm.deal(address(ibera), amount);
        vm.prank(address(ibera));
        depositor.queue{value: amount}();
    }

    /*////////////////////////////////////////////// ////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitializeV2() public view {
        assertEq(depositor.minActivationDeposit(), MIN_ACTIVATION_DEPOSIT);
    }

    function testInitializeV2OnlyGovernor() public {
        // Deploy new instance to test initialization
        InfraredBERADepositorV2 newDepositor = new InfraredBERADepositorV2();

        vm.expectRevert();
        vm.prank(alice);
        newDepositor.initializeV2();
    }

    /*//////////////////////////////////////////////////////////////
                            QUEUE TESTS
    //////////////////////////////////////////////////////////////*/

    function testQueueUpdatesReserves() public {
        uint256 amount = 100 ether;
        uint256 reservesBefore = depositor.reserves();

        queueDeposits(amount);

        assertEq(depositor.reserves(), reservesBefore + amount);
        assertEq(address(depositor).balance, reservesBefore + amount);
    }

    function testQueueFromIBERA() public {
        uint256 amount = 50 ether;

        vm.deal(address(ibera), amount);
        vm.expectEmit(true, true, true, true);
        emit Queue(amount);

        vm.prank(address(ibera));
        depositor.queue{value: amount}();

        // Account for initial reserves
        assertEq(depositor.reserves(), initialReserves + amount);
    }

    function testQueueFromWithdrawor() public {
        uint256 amount = 75 ether;

        vm.deal(address(withdrawor), amount);
        vm.expectEmit(true, true, true, true);
        emit Queue(amount);

        vm.prank(address(withdrawor));
        depositor.queue{value: amount}();

        // Account for initial reserves
        assertEq(depositor.reserves(), initialReserves + amount);
    }

    function testQueueRevertsUnauthorized() public {
        vm.deal(alice, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, alice)
        );
        vm.prank(alice);
        depositor.queue{value: 10 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTE INITIAL DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testExecuteInitialDepositSuccess() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        uint256 reservesBefore = depositor.reserves();

        vm.expectEmit(true, true, true, true);
        emit Execute(pubkey0, InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        assertEq(
            depositor.reserves(),
            reservesBefore - InfraredBERAConstants.INITIAL_DEPOSIT
        );
        assertEq(ibera.stakes(pubkey0), InfraredBERAConstants.INITIAL_DEPOSIT);
    }

    function testExecuteInitialDepositRegistersStake() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.expectEmit(true, true, true, true);
        emit IInfraredBERAV2.Register(
            pubkey0,
            int256(InfraredBERAConstants.INITIAL_DEPOSIT),
            InfraredBERAConstants.INITIAL_DEPOSIT
        );

        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        assertEq(ibera.stakes(pubkey0), InfraredBERAConstants.INITIAL_DEPOSIT);
        assertTrue(ibera.staked(pubkey0));
    }

    function testExecuteInitialDepositSetsOperator() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        // Read from the actual deposit contract
        address operator =
            BeaconDeposit(depositor.DEPOSIT_CONTRACT()).getOperator(pubkey0);
        assertEq(operator, address(infrared));
    }

    function testExecuteInitialDepositRevertsInvalidValidator() public {
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        // Use a pubkey that's NOT registered in infrared
        bytes memory unregisteredPubkey =
            abi.encodePacked(bytes32("unregistered"), bytes16(""));

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidValidator.selector);
        depositor.executeInitialDeposit(unregisteredPubkey);
    }

    function testExecuteInitialDepositRevertsAlreadyInitiated() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT * 2);

        // First deposit succeeds
        vm.prank(keeper);
        depositor.executeInitialDeposit(pubkey0);

        // Second attempt should fail
        vm.prank(keeper);
        vm.expectRevert(Errors.AlreadyInitiated.selector);
        depositor.executeInitialDeposit(pubkey0);
    }

    function testExecuteInitialDepositRevertsOperatorAlreadySet() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        // Mock the getOperator call to return a different operator
        vm.mockCall(
            depositor.DEPOSIT_CONTRACT(),
            abi.encodeWithSelector(BeaconDeposit.getOperator.selector, pubkey0),
            abi.encode(address(0x1234))
        );

        vm.prank(keeper);
        vm.expectRevert(Errors.AlreadyInitiated.selector);
        depositor.executeInitialDeposit(pubkey0);
    }

    function testExecuteInitialDepositRevertsNoSignature() public {
        // Create a new validator that's not in the setUp
        bytes memory newPubkey = abi.encodePacked(bytes32("nosig"), bytes16(""));

        // Add validator but don't set signature
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = ValidatorTypes.Validator({
            pubkey: newPubkey,
            addr: address(infrared)
        });

        vm.prank(infraredGovernance);
        infrared.addValidators(validators);

        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidSignature.selector);
        depositor.executeInitialDeposit(newPubkey);
    }

    function testExecuteInitialDepositOnlyKeeper() public {
        setupValidatorWithSignature(pubkey0);
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);

        vm.expectRevert();
        vm.prank(alice);
        depositor.executeInitialDeposit(pubkey0);
    }

    /*//////////////////////////////////////////////////////////////
                    EXECUTE SUBSEQUENT DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testExecuteSubsequentDepositSuccess() public withProofSetup {
        // Get the actual balance from the proof
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Use the helper to set validator stake to match proof
        setValidatorStake(validatorStruct.pubkey, proofBalance);

        // Now queue enough for the subsequent deposit
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // The validator already has the proof balance, so we can do subsequent deposit
        uint256 stakeBefore = ibera.stakes(validatorStruct.pubkey);

        vm.expectEmit(true, true, true, true);
        emit Execute(validatorStruct.pubkey, MIN_ACTIVATION_DEPOSIT);

        vm.prank(keeper);
        depositor.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );

        assertEq(
            ibera.stakes(validatorStruct.pubkey),
            stakeBefore + MIN_ACTIVATION_DEPOSIT
        );
    }

    function testExecuteVerifiesValidatorProof() public withProofSetup {
        // Set the validator stake to match the proof
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Use the helper method instead
        setValidatorStake(validatorStruct.pubkey, proofBalance);

        // Queue deposits for the test
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Create invalid balance proof
        bytes32[] memory invalidBalanceProof =
            new bytes32[](balanceProof.length);
        for (uint256 i = 0; i < balanceProof.length; i++) {
            invalidBalanceProof[i] = bytes32(uint256(i * 3));
        }

        vm.prank(keeper);
        vm.expectRevert(Errors.BalanceMissmatch.selector);
        depositor.execute(
            header,
            validatorStruct,
            validatorProof,
            invalidBalanceProof,
            validatorIndex,
            balanceLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsNotInitialized() public withProofSetup {
        // Get the actual balance from the proof
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Use the helper to set validator stake
        setValidatorStake(validatorStruct.pubkey, proofBalance);

        // Now override the operator to be address(0) to simulate not initialized
        vm.mockCall(
            depositor.DEPOSIT_CONTRACT(),
            abi.encodeWithSelector(
                BeaconDeposit.getOperator.selector, validatorStruct.pubkey
            ),
            abi.encode(address(0)) // No operator set
        );

        // Queue deposits for the test
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should revert because validator is not initialized (no operator)
        vm.prank(keeper);
        vm.expectRevert(Errors.NotInitialized.selector);
        depositor.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    function testExecuteRevertsExceedsMaxBalance() public withProofSetup {
        // For this test, we need the validator to have a very high stake already
        // Since the proof has a specific balance, we'll work with that
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Set validator stake to match proof
        setValidatorStake(validatorStruct.pubkey, proofBalance);

        // Queue deposits
        queueDeposits(InfraredBERAConstants.MAX_EFFECTIVE_BALANCE);

        assertEq(
            withdrawor.getTotalPendingWithdrawals(
                keccak256(validatorStruct.pubkey)
            ),
            0
        );

        // Calculate how much we can deposit before hitting max
        uint256 maxBalance = InfraredBERAConstants.MAX_EFFECTIVE_BALANCE;

        if (proofBalance >= maxBalance) {
            // If proof balance already exceeds max, any deposit should fail
            vm.prank(keeper);
            vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
            depositor.execute(
                header,
                validatorStruct,
                validatorProof,
                balanceProof,
                validatorIndex,
                balanceLeaf,
                1 gwei, // Even 1 gwei should fail
                nextBlockTimestamp
            );
        } else {
            // Try to deposit more than allowed
            uint256 remainingCapacity = maxBalance - proofBalance;
            uint256 excessAmount = remainingCapacity + 1 ether;

            vm.prank(keeper);
            vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
            depositor.execute(
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
    }

    function testExecuteSubsequentDepositsSetOperatorToZero()
        public
        withProofSetup
    {
        // Get the actual balance from the proof
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;

        // Use the helper method to set up the validator as if initial deposit was done
        // This sets stake, staked flag, and operator all at once
        setValidatorStake(validatorStruct.pubkey, proofBalance);

        // Queue deposits for subsequent deposit
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Get the actual withdrawor address that will be used
        address actualWithdrawor = ibera.withdrawor();

        // Build expected credentials with actual withdrawor
        bytes memory expectedCredentials = abi.encodePacked(
            depositor.ETH1_ADDRESS_WITHDRAWAL_PREFIX(),
            uint88(0),
            actualWithdrawor
        );

        // Get the actual signature that will be used
        bytes memory actualSignature = ibera.signatures(validatorStruct.pubkey);

        // Set up expectCall with the exact parameters
        // The key point is that operator should be address(0) for subsequent deposits
        vm.expectCall(
            depositor.DEPOSIT_CONTRACT(),
            abi.encodeWithSelector(
                BeaconDeposit.deposit.selector,
                validatorStruct.pubkey,
                expectedCredentials,
                actualSignature,
                address(0) // This is what we're testing - operator should be zero
            )
        );

        // Execute subsequent deposit
        vm.prank(keeper);
        depositor.execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );

        // Verify the deposit was successful
        assertEq(
            ibera.stakes(validatorStruct.pubkey),
            proofBalance + MIN_ACTIVATION_DEPOSIT,
            "Stake should increase by deposit amount"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetMinActivationDeposit() public {
        uint256 newMinDeposit = 250_000 ether;

        vm.expectEmit(true, true, true, true);
        emit MinActivationDepositUpdated(newMinDeposit);

        vm.prank(infraredGovernance);
        depositor.setMinActivationDeposit(newMinDeposit);

        assertEq(depositor.minActivationDeposit(), newMinDeposit);
    }

    function testSetMinActivationDepositOnlyGovernor() public {
        vm.expectRevert();
        vm.prank(alice);
        depositor.setMinActivationDeposit(100_000 ether);
    }

    function testSetMinActivationDepositBoundsChecking() public {
        // Should revert if value >= MAX_EFFECTIVE_BALANCE - INITIAL_DEPOSIT
        uint256 maxBound = InfraredBERAConstants.MAX_EFFECTIVE_BALANCE
            - InfraredBERAConstants.INITIAL_DEPOSIT;

        vm.expectRevert(Errors.ExceedsMaxEffectiveBalance.selector);
        vm.prank(infraredGovernance);
        depositor.setMinActivationDeposit(maxBound);

        // Should work with value just below the bound
        uint256 validValue = maxBound - 1;
        vm.prank(infraredGovernance);
        depositor.setMinActivationDeposit(validValue);

        assertEq(depositor.minActivationDeposit(), validValue);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleValidatorDeposits() public {
        // Setup two validators
        setupValidatorWithSignature(pubkey0);
        setupValidatorWithSignature(pubkey1);

        // Queue deposits for both
        uint256 amountPerValidator = InfraredBERAConstants.INITIAL_DEPOSIT;
        queueDeposits(amountPerValidator * 2);

        // Initial deposits for both validators
        vm.startPrank(keeper);
        depositor.executeInitialDeposit(pubkey0);
        depositor.executeInitialDeposit(pubkey1);
        vm.stopPrank();

        assertEq(ibera.stakes(pubkey0), InfraredBERAConstants.INITIAL_DEPOSIT);
        assertEq(ibera.stakes(pubkey1), InfraredBERAConstants.INITIAL_DEPOSIT);
        assertEq(depositor.reserves(), initialReserves); // Should equal initial reserves, not 0
    }

    /*//////////////////////////////////////////////////////////////
                        PROOF VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test successful execute with generated proofs
    function testExecuteWithGeneratedProofsSuccess() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        // Create validator with correct withdrawal credentials
        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey,
            ibera.withdrawor(),
            32000000000 // 32 ETH in gwei
        );

        // Get current stake and generate proof for matching balance
        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        // Create header with generated state root
        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        // Queue deposits for subsequent deposit
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Execute should succeed
        vm.deal(keeper, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit Execute(validatorStruct.pubkey, MIN_ACTIVATION_DEPOSIT);

        vm.prank(keeper);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );

        // Verify stake was increased
        assertEq(
            ibera.stakes(validatorStruct.pubkey),
            currentStake + MIN_ACTIVATION_DEPOSIT
        );
    }

    /// @notice Test execute with wrong withdrawal credentials
    function testExecuteWithWrongWithdrawalCredentials() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        // Create validator with WRONG withdrawal credentials
        BeaconRootsVerify.Validator memory wrongValidator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey,
            address(0xDEADBEEF), // Wrong address
            32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(
            wrongValidator, validatorIndex, currentStake
        );

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail with FieldMismatch (from BeaconRootsVerify when credentials don't match)
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(BeaconRootsVerify.FieldMismatch.selector);
        depositor.execute(
            customHeader,
            wrongValidator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with balance mismatch
    function testExecuteWithBalanceMismatch() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        // Generate proof for DIFFERENT balance than current stake
        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(
            validator, validatorIndex, currentStake + 10 ether
        ); // Wrong balance!

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail with BalanceMissmatch
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.BalanceMissmatch.selector);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with exited validator
    function testExecuteWithExitedValidator() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        // Create validator that has exited
        BeaconRootsVerify.Validator memory exitedValidator = BeaconRootsVerify
            .Validator({
            pubkey: validatorStruct.pubkey,
            withdrawalCredentials: bytes32(uint256(uint160(ibera.withdrawor()))),
            effectiveBalance: 32000000000,
            slashed: false,
            activationEligibilityEpoch: 0,
            activationEpoch: 0,
            exitEpoch: 100, // Has exited!
            withdrawableEpoch: 150
        });

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(
            exitedValidator, validatorIndex, currentStake
        );

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail with AlreadyExited
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.AlreadyExited.selector);
        depositor.execute(
            customHeader,
            exitedValidator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with invalid validator proof paths
    function testExecuteWithInvalidValidatorProof() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        // Corrupt the validator proof
        vProof[0] = bytes32(uint256(0xDEADBEEF));

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail at validator proof verification
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidWithdrawalAddress.selector); // This is what the depositor returns for bad validator proofs
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with invalid balance proof paths
    function testExecuteWithInvalidBalanceProof() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        // Corrupt the balance proof
        bProof[bProof.length - 1] = bytes32(uint256(0xBADD4741));

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail at balance proof verification
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.BalanceMissmatch.selector);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with wrong validator index
    function testExecuteWithWrongValidatorIndex() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        // Generate proof for correct index but use wrong index in call
        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Use wrong validator index
        uint256 wrongIndex = 99;

        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(); // Will revert in BeaconRootsVerify proof verification
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            wrongIndex, // Wrong index!
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with invalid beacon header timestamp
    function testExecuteWithInvalidTimestamp() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);

        // Mock beacon roots to return wrong root for timestamp
        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(nextBlockTimestamp),
            abi.encode(bytes32(uint256(0xDEADBEEF)))
        );

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Should fail at beacon roots verification
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(); // Will revert in BeaconRootsVerify timestamp verification
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            nextBlockTimestamp
        );
    }

    /// @notice Helper functions for proof tests
    function _createHeaderWithStateRoot(bytes32 stateRoot)
        internal
        view
        returns (BeaconRootsVerify.BeaconBlockHeader memory)
    {
        return BeaconRootsVerify.BeaconBlockHeader({
            slot: header.slot,
            proposerIndex: header.proposerIndex,
            parentRoot: header.parentRoot,
            stateRoot: stateRoot,
            bodyRoot: header.bodyRoot
        });
    }

    function _mockBeaconRoots(
        BeaconRootsVerify.BeaconBlockHeader memory customHeader
    ) internal {
        bytes32 headerRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(customHeader);
        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(nextBlockTimestamp),
            abi.encode(headerRoot)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test execute with amount not divisible by gwei
    function testExecuteWithInvalidAmount() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        // Create validator with correct credentials
        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        // Queue enough deposits
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Try to deposit amount not divisible by gwei
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            1 ether + 1, // Not gwei aligned - should fail
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with zero amount
    function testExecuteWithZeroAmount() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Try to deposit zero amount
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidAmount.selector);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            0, // Zero amount - should fail
            nextBlockTimestamp
        );
    }

    /// @notice Test execute with amount less than minimum activation deposit
    function testExecuteWithAmountBelowMinActivation() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey, ibera.withdrawor(), 32000000000
        );

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);
        _mockBeaconRoots(customHeader);

        // Queue sufficient amount but try to deposit less than minimum
        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Try to deposit less than minimum activation deposit
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        vm.expectRevert(
            Errors.DepositMustBeGreaterThanMinActivationBalance.selector
        );
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            1 ether, // Less than MIN_ACTIVATION_DEPOSIT - should fail
            nextBlockTimestamp
        );
    }

    function testQueueFromRebalancing() public {
        // Simulate withdrawor having funds from validator exit
        uint256 rebalanceAmount = 32 ether;
        vm.deal(address(withdrawor), rebalanceAmount);

        uint256 reservesBefore = depositor.reserves();

        vm.prank(address(withdrawor));
        depositor.queue{value: rebalanceAmount}();

        assertEq(depositor.reserves(), reservesBefore + rebalanceAmount);
    }

    /// @notice Test that execute reverts when proof data is stale
    function testExecuteRevertsOnStaleProof() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        // Now test stale proof for subsequent deposit
        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);
        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey,
            address(withdrawor),
            uint64(currentStake / 1 gwei)
        );

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Setup beacon roots mock
        _mockBeaconRoots(customHeader);

        // Fast forward time to make proof stale
        uint256 buffer = ibera.proofTimestampBuffer();
        vm.warp(block.timestamp + buffer + 1 seconds);

        // Use a stale nextBlockTimestamp value
        uint256 staleNextBlockTimestamp = block.timestamp - buffer - 2 seconds;

        vm.deal(keeper, 100 ether);
        vm.expectRevert(Errors.StaleProof.selector);
        vm.prank(keeper);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            staleNextBlockTimestamp
        );
    }

    /// @notice Test that execute succeeds when proof is within timestamp buffer
    function testExecuteSucceedsWithinTimestampBuffer() public {
        setupValidatorForProofTest();

        // First do initial deposit
        queueDeposits(InfraredBERAConstants.INITIAL_DEPOSIT);
        vm.prank(keeper);
        depositor.executeInitialDeposit(validatorStruct.pubkey);

        uint256 currentStake = ibera.stakes(validatorStruct.pubkey);
        BeaconRootsVerify.Validator memory validator = proofHelper
            .createValidatorWithCredentials(
            validatorStruct.pubkey,
            ibera.withdrawor(), // Use the actual withdrawor contract address
            uint64(currentStake / 1 gwei)
        );

        (
            bytes32[] memory vProof,
            bytes32[] memory bProof,
            bytes32 bLeaf,
            bytes32 stateRoot
        ) = proofHelper.generateProof(validator, validatorIndex, currentStake);

        BeaconRootsVerify.BeaconBlockHeader memory customHeader =
            _createHeaderWithStateRoot(stateRoot);

        queueDeposits(MIN_ACTIVATION_DEPOSIT);

        // Fast forward time but stay within buffer
        uint256 buffer = ibera.proofTimestampBuffer();
        vm.warp(block.timestamp + buffer - 1 seconds);

        // Use a recent nextBlockTimestamp value that makes the proof within buffer
        uint256 recentNextBlockTimestamp = block.timestamp - buffer + 2 seconds;

        // Setup beacon roots mock with the adjusted timestamp
        bytes32 headerRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(customHeader);
        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(recentNextBlockTimestamp),
            abi.encode(headerRoot)
        );

        // Should succeed
        vm.deal(keeper, 100 ether);
        vm.prank(keeper);
        depositor.execute(
            customHeader,
            validator,
            vProof,
            bProof,
            validatorIndex,
            bLeaf,
            MIN_ACTIVATION_DEPOSIT,
            recentNextBlockTimestamp
        );

        // Verify deposit was registered
        assertEq(
            ibera.stakes(validatorStruct.pubkey),
            currentStake + MIN_ACTIVATION_DEPOSIT
        );
    }
}
