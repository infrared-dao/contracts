// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Testing Libraries.
import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

// Mocks
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";

import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from
    "src/staking/upgrades/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {ConsensusLayerVerifierTest} from
    "tests/e2e/ConsensusLayerVerifier.t.sol";
import {InfraredBERADepositorV2} from
    "src/staking/upgrades/InfraredBERADepositorV2.sol";
import {InfraredBERAV2} from "src/staking/upgrades/InfraredBERAV2.sol";

contract InfraredBERABaseE2ETest is ConsensusLayerVerifierTest {
    using stdJson for string;

    BeaconDeposit public depositContract;
    bytes public constant withdrawPrecompile = abi.encodePacked(
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f556101f480602d5f395ff33373fffffffffffffffffffffffffffffffffffffffe1460c7573615156028575f545f5260205ff35b36603814156101f05760115f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff146101f057600182026001905f5b5f821115608057810190830284830290049160010191906065565b9093900434106101f057600154600101600155600354806003026004013381556001015f35815560010160203590553360601b5f5260385f601437604c5fa0600101600355005b6003546002548082038060101160db575060105b5f5b81811461017f5780604c02838201600302600401805490600101805490600101549160601b83528260140152807fffffffffffffffffffffffffffffffff0000000000000000000000000000000016826034015260401c906044018160381c81600701538160301c81600601538160281c81600501538160201c81600401538160181c81600301538160101c81600201538160081c81600101535360010160dd565b9101809214610191579060025561019c565b90505f6002555f6003555b5f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff14156101c957505f5b6001546002828201116101de5750505f6101e4565b01600290035b5f555f600155604c025ff35b5f5ffd"
    );

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    address public validator0 = makeAddr("v0");
    address public validator1 = makeAddr("v1");
    bytes public pubkey0; // = abi.encodePacked(bytes32("v0"), bytes16("")); // must be len 48
    bytes public pubkey1 = abi.encodePacked(bytes32("v1"), bytes16(""));
    bytes public signature0 =
        abi.encodePacked(bytes32("v0"), bytes32(""), bytes32("")); // must be len 96
    bytes public signature1 =
        abi.encodePacked(bytes32("v1"), bytes32(""), bytes32(""));

    ValidatorTypes.Validator[] public infraredValidators;

    bytes32[] validatorProof;
    bytes32[] balanceProof;
    uint256 validatorIndex;
    // bytes32 stateRoot;
    bytes32 validatorLeaf;
    bytes32 balancesRoot;
    bytes32 balanceLeaf;

    InfraredBERAV2 iberaV2;
    InfraredBERADepositorV2 depositorV2;

    function setUp() public virtual override {
        super.setUp();

        pubkey0 = validatorStruct.pubkey;

        // deploy new implementation
        InfraredBERAWithdrawor withdraworNew = new InfraredBERAWithdrawor();

        // perform upgrade
        vm.prank(infraredGovernance);
        (bool success,) = address(withdrawor).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(withdraworNew), ""
            )
        );
        require(success, "Upgrade failed");

        // initialize
        vm.prank(infraredGovernance);
        withdrawor.initializeV2(0x00000961Ef480Eb55e80D19ad83579A64c007002);

        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        vm.etch(WITHDRAW_PRECOMPILE, withdrawPrecompile);

        // mock precompile calls until hard fork (~7 May)
        vm.mockCall(WITHDRAW_PRECOMPILE, bytes(""), abi.encode(10));

        uint64 amount = uint64(26000000000000000000 / 1 gwei);
        vm.mockCall(
            WITHDRAW_PRECOMPILE,
            10,
            abi.encodePacked(pubkey0, amount),
            abi.encode(true)
        );

        vm.mockCall(
            WITHDRAW_PRECOMPILE,
            10,
            abi.encodePacked(pubkey1, amount),
            abi.encode(true)
        );

        // deal to alice and bob + approve ibera to spend for them
        vm.deal(alice, 20000 ether);
        vm.deal(bob, 20000 ether);
        vm.prank(alice);
        ibera.approve(address(ibera), type(uint256).max);
        vm.prank(bob);
        ibera.approve(address(ibera), type(uint256).max);

        // add validators to infrared
        ValidatorTypes.Validator memory infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey0, addr: address(infrared)});
        infraredValidators.push(infraredValidator);
        infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey1, addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        vm.startPrank(infraredGovernance);

        ibera.setFeeDivisorShareholders(0);
        vm.stopPrank();

        // upgrade iBERA to V2
        address depositorV2Impl = address(new InfraredBERADepositorV2());
        address iberaV2Impl = address(new InfraredBERAV2());
        vm.startPrank(infraredGovernance);
        depositor.upgradeToAndCall(depositorV2Impl, "");
        ibera.upgradeToAndCall(iberaV2Impl, "");
        iberaV2 = InfraredBERAV2(address(ibera));
        depositorV2 = InfraredBERADepositorV2(address(depositor));
        depositorV2.initializeV2();
        iberaV2.initializeV2();
        vm.stopPrank();

        // set proof data
        string memory json;
        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/tests/data/proof2.json");
            json = vm.readFile(path);
        }

        bytes memory strRaw = json.parseRaw(".validator_proof");
        validatorProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".balance_proof");
        balanceProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".state_root");
        stateRoot = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".validator_index");
        validatorIndex = abi.decode(strRaw, (uint256));

        strRaw = json.parseRaw(".validator_leaf");
        validatorLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".balance_leaf");
        balanceLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".metadata.timestamp");
        nextBlockTimestamp = abi.decode(strRaw, (uint256));
        nextBlockTimestamp = nextBlockTimestamp + 2;

        strRaw = json.parseRaw(".validator_data");
        JsonValidator memory _validator = abi.decode(strRaw, (JsonValidator));

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
    }

    function testSetUp() public virtual {
        assertTrue(address(depositor) != address(0), "depositor == address(0)");
        assertTrue(
            address(withdrawor) != address(0), "withdrawor == address(0)"
        );
        assertTrue(address(receivor) != address(0), "receivor == address(0)");

        assertEq(ibera.allowance(alice, address(ibera)), type(uint256).max);
        assertEq(ibera.allowance(bob, address(ibera)), type(uint256).max);
        assertEq(alice.balance, 20000 ether);
        assertEq(bob.balance, 20000 ether);

        assertTrue(infrared.isInfraredValidator(pubkey0));

        assertTrue(
            ibera.hasRole(ibera.DEFAULT_ADMIN_ROLE(), infraredGovernance)
        );
        assertTrue(ibera.keeper(keeper));
        assertTrue(ibera.governor(infraredGovernance));

        address DEPOSIT_CONTRACT = depositorV2.DEPOSIT_CONTRACT();
        assertTrue(DEPOSIT_CONTRACT.code.length > 0);

        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        assertTrue(WITHDRAW_PRECOMPILE.code.length > 0);
    }
}
