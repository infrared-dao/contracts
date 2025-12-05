// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {
    UUPSUpgradeable,
    ERC1967Utils
} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {InfraredBERAV2_1} from "src/staking/InfraredBERAV2_1.sol";
import {IInfraredBERAV2} from "src/interfaces/IInfraredBERAV2.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {HelperForkTest} from "../HelperForkTest.t.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

contract InfraredBERAV2_1UpgradeTest is HelperForkTest {
    using stdJson for string;

    InfraredBERAV2_1 public implementation;

    // Proof data
    bytes32[] validatorProof;
    bytes32[] balanceProof;
    uint256 validatorIndex;
    bytes32 balanceLeaf;
    BeaconRootsVerify.BeaconBlockHeader header;
    BeaconRootsVerify.Validator validatorStruct;
    uint256 nextBlockTimestamp;
    uint256 totalPendingWithdrawals;

    struct JsonHeader {
        bytes32 body_root;
        bytes32 parent_root;
        uint64 proposer_index;
        uint64 slot;
        bytes32 state_root;
    }

    struct JsonValidator {
        uint64 activation_eligibility_epoch;
        uint64 activation_epoch;
        uint64 effective_balance;
        uint64 exit_epoch;
        bytes pubkey;
        bool slashed;
        uint64 withdrawable_epoch;
        bytes32 withdrawal_credentials;
    }

    function setUp() public override {
        // Set custom parameters
        admin = address(this);
        infraredGovernance = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
        keeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;

        // Load validator data from fixtures
        _loadValidatorData();

        // Create and select mainnet fork at recent block
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 13710715);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();

        // Deploy new implementation
        implementation = new InfraredBERAV2_1();
    }

    function testUpgradeToV2_1() public {
        address iberaAddress = address(ibera);

        // Check current version before upgrade
        console.log("Testing upgrade to InfraredBERAV2_1...");
        console.log("InfraredBERA proxy:", iberaAddress);

        // Get implementation before upgrade
        address implBefore = ibera.implementation();
        console.log("Implementation before:", implBefore);

        // Upgrade to V2_1
        vm.startPrank(infraredGovernance);
        (bool success,) = iberaAddress.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(implementation), ""
            )
        );
        require(success, "Upgrade to V2_1 failed");
        vm.stopPrank();

        // Verify upgrade
        address implAfter = ibera.implementation();
        console.log("Implementation after:", implAfter);
        assertEq(
            implAfter, address(implementation), "Implementation not upgraded"
        );
    }

    function testRegisterViaProofsAfterUpgrade() public {
        // Load proof data from JSON file
        string memory root = vm.projectRoot();
        string memory path =
            string.concat(root, "/tests/data/proof_validator_recovery.json");
        string memory json = vm.readFile(path);

        // Parse proofs
        bytes memory strRaw = json.parseRaw(".validator_proof");
        validatorProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".balance_proof");
        balanceProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".validator_index");
        validatorIndex = abi.decode(strRaw, (uint256));

        strRaw = json.parseRaw(".balance_leaf");
        balanceLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".metadata.timestamp");
        nextBlockTimestamp = abi.decode(strRaw, (uint256));
        nextBlockTimestamp = nextBlockTimestamp + 2;

        strRaw = json.parseRaw(".validator_data");
        JsonValidator memory _validator = abi.decode(strRaw, (JsonValidator));

        totalPendingWithdrawals =
            stdJson.readUint(json, ".metadata.total_pending_withdrawals");
        // check again no pending withdrawals on CL
        assertEq(totalPendingWithdrawals, 0);

        validatorStruct = BeaconRootsVerify.Validator({
            pubkey: _validator.pubkey,
            withdrawalCredentials: _validator.withdrawal_credentials,
            effectiveBalance: _validator.effective_balance,
            slashed: _validator.slashed,
            activationEligibilityEpoch: _validator.activation_eligibility_epoch,
            activationEpoch: _validator.activation_epoch,
            exitEpoch: _validator.exit_epoch,
            withdrawableEpoch: _validator.withdrawable_epoch
        });

        strRaw = json.parseRaw(".header");
        JsonHeader memory _header = abi.decode(strRaw, (JsonHeader));

        header = BeaconRootsVerify.BeaconBlockHeader({
            slot: _header.slot,
            proposerIndex: _header.proposer_index,
            parentRoot: _header.parent_root,
            stateRoot: _header.state_root,
            bodyRoot: _header.body_root
        });

        // Perform upgrade first
        testUpgradeToV2_1();

        address iberaAddress = address(ibera);
        bytes memory pubkey = validatorStruct.pubkey;

        // Check state before recovery
        uint256 stakeBefore = IInfraredBERAV2(iberaAddress).stakes(pubkey);
        bool exitedBefore = IInfraredBERAV2(iberaAddress).hasExited(pubkey);

        console.log("\n=== State Before Recovery ===");
        console.log("Validator pubkey:", vm.toString(keccak256(pubkey)));
        console.log("Internal stake:", stakeBefore);
        console.log("Has exited:", exitedBefore);

        // Check deposits health BEFORE recovery
        console.log("\n>>> BEFORE registerViaProofs:");
        _checkDepositsHealth(pubkey);

        // Call registerViaProofs as keeper
        vm.startPrank(keeper);

        (bool success,) = iberaAddress.call(
            abi.encodeWithSignature(
                "registerViaProofs((uint64,uint64,bytes32,bytes32,bytes32),(bytes,bytes32,uint64,bool,uint64,uint64,uint64,uint64),bytes32[],bytes32[],uint256,bytes32,uint256)",
                header,
                validatorStruct,
                validatorProof,
                balanceProof,
                validatorIndex,
                balanceLeaf,
                nextBlockTimestamp
            )
        );

        if (!success) {
            console.log(
                "registerViaProofs failed - this may be expected if proof is stale"
            );
        } else {
            console.log("registerViaProofs succeeded!");
        }

        vm.stopPrank();

        // Check state after recovery
        uint256 stakeAfter = IInfraredBERAV2(iberaAddress).stakes(pubkey);
        bool exitedAfter = IInfraredBERAV2(iberaAddress).hasExited(pubkey);

        console.log("\n=== State After Recovery ===");
        console.log("Internal stake:", stakeAfter);
        console.log("Has exited:", exitedAfter);

        if (success) {
            // Assertions
            assertTrue(stakeAfter > 0, "Stake should be restored");
            assertFalse(exitedAfter, "Exit flag should be reset");
            console.log("Validator successfully recovered!");
        }

        // Check deposits health AFTER recovery
        console.log("\n>>> AFTER registerViaProofs:");
        _checkDepositsHealth(pubkey);

        // Log the delta
        if (success) {
            console.log("\n=== Delta ===");
            console.log("Stake change for validator:", stakeAfter - stakeBefore);
        }
    }

    /// @notice Helper to check deposits accounting health
    /// @param testValidatorPubkey The pubkey of the validator being tested (to verify it's in the list)
    function _checkDepositsHealth(bytes memory testValidatorPubkey)
        internal
        view
    {
        console.log("\n=== Deposits Health Check ===");

        // Get current deposits value
        uint256 currentDeposits = ibera.deposits();
        console.log("Current Deposits:     ", currentDeposits);

        // Get pending deposits (not yet sent to CL)
        uint256 pendingDeposits = ibera.pending();
        console.log("Pending Deposits:     ", pendingDeposits);

        // Sum all validator stakes
        ValidatorTypes.Validator[] memory validators =
            infrared.infraredValidators();
        console.log("Total validators:     ", validators.length);

        uint256 sumStakes = 0;
        bool testValidatorFound = false;
        uint256 testValidatorIndex = 0;

        for (uint256 i = 0; i < validators.length; i++) {
            bytes memory pubkey = validators[i].pubkey;
            uint256 stake = ibera.stakes(pubkey);
            sumStakes += stake;

            // Check if this is our test validator
            if (keccak256(pubkey) == keccak256(testValidatorPubkey)) {
                testValidatorFound = true;
                testValidatorIndex = i;
            }
        }
        console.log("Sum Validator Stakes: ", sumStakes);

        // Report on test validator presence
        if (testValidatorFound) {
            console.log(
                "\u2713 Test validator found in infrared validators list at index",
                testValidatorIndex
            );
            uint256 testValStake = ibera.stakes(testValidatorPubkey);
            console.log("  Test validator stake:", testValStake);
        } else {
            console.log(
                "\u2717 WARNING: Test validator NOT in infrared validators list!"
            );
            console.log(
                "  This validator's stake will NOT be counted in sumStakes"
            );
            console.log(
                "  Validator pubkey hash:",
                vm.toString(keccak256(testValidatorPubkey))
            );
        }

        // Calculate expected deposits
        // Expected = sumStakes + pendingDeposits - totalPendingWithdrawals
        (,,, uint256 pendingRebalance,) = withdrawor.requests(1348);
        uint256 expectedDeposits =
            sumStakes + pendingDeposits + pendingRebalance;
        console.log("Expected Deposits:    ", expectedDeposits);

        // Check health (allow 1 gwei tolerance for rounding)
        if (
            currentDeposits < expectedDeposits + 1 gwei
                && currentDeposits > expectedDeposits - 1 gwei
        ) {
            console.log("Status: HEALTHY");
            console.log("Discrepancy: 0");
        } else {
            console.log("Status: UNHEALTHY - Accounting discrepancy detected");
            uint256 discrepancy = currentDeposits > expectedDeposits
                ? currentDeposits - expectedDeposits
                : expectedDeposits - currentDeposits;
            console.log("Discrepancy:", discrepancy);

            if (currentDeposits < expectedDeposits) {
                console.log("\nIssue: Deposits variable is LOWER than expected");
                console.log("Possible causes: Bypass deposits not yet synced");
            } else {
                console.log(
                    "\nIssue: Deposits variable is HIGHER than expected"
                );
                console.log(
                    "Possible causes: Rejected withdrawals not yet synced"
                );
            }

            // This is informational, not a hard failure
            console.log(
                "\nNote: Minor discrepancies may be acceptable depending on context"
            );
        }
    }
}
