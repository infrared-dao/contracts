// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/depreciated/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {LibSort} from "solady/src/utils/LibSort.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

import {HelperForkTest} from "./HelperForkTest.t.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {EndianHelper} from "src/utils/EndianHelper.sol";

contract ConsensusLayerVerifierTest is HelperForkTest {
    using stdJson for string;

    uint256 forkBlockNumber = 5788402;

    BeaconRootsVerify.BeaconBlockHeader header;
    BeaconRootsVerify.Validator validatorStruct;
    bytes32[] proof;
    bytes32 stateRoot;
    uint256 nextBlockTimestamp;

    function setUp() public virtual override {
        // Set custom parameters
        admin = address(this);
        keeper = address(0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0);
        infraredGovernance = address(0x182a31A27A0D39d735b31e80534CFE1fCd92c38f);

        // Load validator data from fixtures
        _loadValidatorData();

        // Create and select mainnet fork
        uint256 blockNumber = forkBlockNumber + 1;
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, blockNumber);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();

        uint256 timestamp = 1748773066;
        nextBlockTimestamp = timestamp + 2;

        // data pulled from https://github.com/infrared-dao/bera-proofs/
        header = BeaconRootsVerify.BeaconBlockHeader({
            slot: 5788402,
            proposerIndex: 51,
            parentRoot: bytes32(
                hex"155f296b0f1125544889bf879fdcef2378af621cce314682da092ecc6adf8ec8"
            ),
            stateRoot: bytes32(
                hex"7aac2bab3ed70e35ba9123b739f6375caed3b51c8c947703087b911d54b0cc9f"
            ),
            bodyRoot: bytes32(
                hex"ea41d9a12d46e604dd4c8c52da906a1840635955cd105e5a8fbfa685964c593b"
            )
        });

        // use despread validator details so can fork test deposits and withdrawals
        validatorStruct = BeaconRootsVerify.Validator({
            pubkey: hex"ab2f79eeae163596276d5a56e52be4796df33377b157531a839a0174a68ca36e245bee122c4b5364176cf25ec2e0e8fc",
            withdrawalCredentials: bytes32(
                hex"0100000000000000000000008c0e122960dc2e97dc0059c07d6901dce72818e1"
            ),
            effectiveBalance: uint64(5930000000000000),
            slashed: false,
            activationEligibilityEpoch: uint64(21945),
            activationEpoch: uint64(21946),
            exitEpoch: uint64(0xffffffffffffffff),
            withdrawableEpoch: uint64(0xffffffffffffffff)
        });

        proof.push(
            0xff17ab50a9aea8b75d21da48b6fd79e833647edc151e72fb5fda91798a530734
        );
        proof.push(
            0xbeddf18d73fa8029a9109280ff0d9a6007384340b45d29f90358cb90591c2a6b
        );
        proof.push(
            0x5e9040b6021f8f63336beafabaa1780a3847b16dc3fe67242c2aa255736eebd0
        );
        proof.push(
            0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c
        );
        proof.push(
            0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c
        );
        proof.push(
            0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30
        );
        proof.push(
            0xc7e06a08e31d93595b36caa8c850e6923536be9de6fabe63f4162d8c1bd22e90
        );
        proof.push(
            0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c
        );
        proof.push(
            0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193
        );
        proof.push(
            0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1
        );
        proof.push(
            0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b
        );
        proof.push(
            0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220
        );
        proof.push(
            0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f
        );
        proof.push(
            0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e
        );
        proof.push(
            0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784
        );
        proof.push(
            0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb
        );
        proof.push(
            0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb
        );
        proof.push(
            0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab
        );
        proof.push(
            0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4
        );
        proof.push(
            0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f
        );
        proof.push(
            0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa
        );
        proof.push(
            0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c
        );
        proof.push(
            0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167
        );
        proof.push(
            0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7
        );
        proof.push(
            0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0
        );
        proof.push(
            0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544
        );
        proof.push(
            0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765
        );
        proof.push(
            0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4
        );
        proof.push(
            0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1
        );
        proof.push(
            0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636
        );
        proof.push(
            0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c
        );
        proof.push(
            0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7
        );
        proof.push(
            0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff
        );
        proof.push(
            0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5
        );
        proof.push(
            0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d
        );
        proof.push(
            0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c
        );
        proof.push(
            0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327
        );
        proof.push(
            0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74
        );
        proof.push(
            0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76
        );
        proof.push(
            0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f
        );
        proof.push(
            0x4500000000000000000000000000000000000000000000000000000000000000
        );
        proof.push(
            0x6c1d76195c93d80260c2d4134aacdb969907113de90909da620100fa579eb0c5
        );
        proof.push(
            0xe77e818a42faeab9d38056fd218bd82bc9a9b145010a22cf8106eebb8a3fac3e
        );
        proof.push(
            0x1b8afbf6f0034f939f0cfc6e3b03362631bdce35a43b65cbb8f732fa08373b69
        );
        proof.push(
            0xfbad9a092ada7c1c0f9c3ae9d7bd048ee458e53a987fd40a69b4d9752c6f47db
        );

        stateRoot =
            0x7aac2bab3ed70e35ba9123b739f6375caed3b51c8c947703087b911d54b0cc9f;

        // Mock a previously valid BEACON_ROOTS for unit tests
        bytes32 expectedRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);
        assertEq(
            expectedRoot,
            bytes32(
                0x3d6dded8aa57791988455356078cd96ac75091735152b7e8adf33de25082da9b
            )
        );
        // uint256 timestamp =
        // BeaconRootsVerify.calculateTimestampBySlot(header.slot + 1);
        // vm.mockCall(
        //     BeaconRootsVerify.BEACON_ROOTS,
        //     abi.encode(timestamp),
        //     abi.encode(expectedRoot)
        // );
        // ref: parent hash slot number + 1
        // $ curl -s -X GET     "${BEACON_RPC}/eth/v1/beacon/headers/5788403"     -H "accept: a
        //     pplication/json"|jq
        //     {
        //         "execution_optimistic": false,
        //         "finalized": true,
        //         "data": {
        //             "root": "0x804e3d753a20e99f0a5f8167060315d8e969cfb654c4448301304ee7a9801685",
        //             "canonical": true,
        //             "header": {
        //             "message": {
        //                 "slot": "5788403",
        //                 "proposer_index": "54",
        //                 "parent_root": "0x3d6dded8aa57791988455356078cd96ac75091735152b7e8adf33de25082da9b",
        //                 "state_root": "0x4af89dda65b0c3eaed154978b0ead72e91bb3aa50f50329a516e7b844929269c",
        //                 "body_root": "0x804e3d753a20e99f0a5f8167060315d8e969cfb654c4448301304ee7a9801685"
        //             },
        //             "signature": ""
        //             }
        //         }
        //     }
    }

    function testProof() public view {
        bytes32[] memory proofs = proof;
        // verify validator against state root
        bool valid = BeaconRootsVerify.verifyValidator(
            stateRoot, validatorStruct, proofs, 67
        );
        assertTrue(valid);
    }

    struct Meta {
        uint256 field_index;
        uint256 proof_length;
        uint256 validator_count;
    }

    // json imports order structs alphabetically
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

    struct ProofImport {
        uint256 gindex;
        JsonHeader header;
        bytes32 leaf;
        Meta metadata;
        bytes32[] proof;
        bytes32 root;
        JsonValidator validator_data;
        uint256 validator_index;
    }

    function testJsonProof() public view {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/tests/data/proof.json");
        string memory json = vm.readFile(path);

        bytes memory strProof = json.parseRaw(".proof");
        bytes32[] memory proofs = abi.decode(strProof, (bytes32[]));
        bytes memory strRoot = json.parseRaw(".root");
        bytes32 _root = abi.decode(strRoot, (bytes32));
        // console.logBytes32(_root);
        // console.logBytes32(proofs[1]);

        bytes memory strValidatorIndex = json.parseRaw(".validator_index");
        uint256 _validatorIndex = abi.decode(strValidatorIndex, (uint256));

        bytes memory strValidator = json.parseRaw(".validator_data");
        JsonValidator memory _validator =
            abi.decode(strValidator, (JsonValidator));

        bytes memory strHeader = json.parseRaw(".header");
        JsonHeader memory _header = abi.decode(strHeader, (JsonHeader));

        strHeader = json.parseRaw(".metadata.timestamp");
        uint256 nextTimestamp = abi.decode(strHeader, (uint256));
        nextTimestamp = nextTimestamp + 2;

        // bytes memory data = vm.parseJson(json);
        // ProofImport memory proofImport = abi.decode(data, (ProofImport));
        // // console.logBytes32(proofImport.root);

        bool valid = BeaconRootsVerify.verifyValidator(
            _root,
            BeaconRootsVerify.Validator({
                pubkey: _validator.pubkey,
                withdrawalCredentials: _validator.withdrawal_credentials,
                effectiveBalance: _validator.effective_balance,
                slashed: _validator.slashed,
                activationEligibilityEpoch: _validator.activation_eligibility_epoch,
                activationEpoch: _validator.activation_epoch,
                exitEpoch: _validator.exit_epoch,
                withdrawableEpoch: _validator.withdrawable_epoch
            }),
            proofs,
            _validatorIndex
        );
        assertTrue(valid);

        valid = BeaconRootsVerify.verifyValidator(
            BeaconRootsVerify.BeaconBlockHeader({
                slot: _header.slot,
                proposerIndex: _header.proposer_index,
                parentRoot: _header.parent_root,
                stateRoot: _header.state_root,
                bodyRoot: _header.body_root
            }),
            BeaconRootsVerify.Validator({
                pubkey: _validator.pubkey,
                withdrawalCredentials: _validator.withdrawal_credentials,
                effectiveBalance: _validator.effective_balance,
                slashed: _validator.slashed,
                activationEligibilityEpoch: _validator.activation_eligibility_epoch,
                activationEpoch: _validator.activation_epoch,
                exitEpoch: _validator.exit_epoch,
                withdrawableEpoch: _validator.withdrawable_epoch
            }),
            proofs,
            _validatorIndex,
            nextTimestamp
        );
        assertTrue(valid);
    }

    function testJsonProof2() public view {
        string memory json;
        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, "/tests/data/proof2.json");
            json = vm.readFile(path);
        }

        bytes memory strRaw = json.parseRaw(".validator_proof");
        bytes32[] memory validatorProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".balance_proof");
        bytes32[] memory balanceProof = abi.decode(strRaw, (bytes32[]));

        strRaw = json.parseRaw(".state_root");
        bytes32 _stateRoot = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".validator_index");
        uint256 validatorIndex = abi.decode(strRaw, (uint256));

        strRaw = json.parseRaw(".balance_leaf");
        bytes32 balanceLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".validator_data");
        JsonValidator memory _validator = abi.decode(strRaw, (JsonValidator));

        strRaw = json.parseRaw(".metadata.timestamp");
        uint256 timestamp = abi.decode(strRaw, (uint256));
        timestamp = timestamp + 2;

        BeaconRootsVerify.Validator memory validatorStruct2 = BeaconRootsVerify
            .Validator({
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

        BeaconRootsVerify.BeaconBlockHeader memory header2 = BeaconRootsVerify
            .BeaconBlockHeader({
            slot: _header.slot,
            proposerIndex: _header.proposer_index,
            parentRoot: _header.parent_root,
            stateRoot: _header.state_root,
            bodyRoot: _header.body_root
        });

        bool valid = BeaconRootsVerify.verifyValidator(
            _stateRoot, validatorStruct2, validatorProof, validatorIndex
        );
        assertTrue(valid);

        valid = BeaconRootsVerify.verifyValidator(
            header2, validatorStruct2, validatorProof, validatorIndex, timestamp
        );
        assertTrue(valid);

        valid = BeaconRootsVerify.verifyValidatorBalance(
            header2,
            balanceProof,
            validatorIndex,
            5934426930679472 * 1 gwei,
            balanceLeaf,
            timestamp
        );
        assertTrue(valid);
    }

    function testProofHeader() public view {
        bytes32[] memory proofs = proof;
        // verify validator against state root
        bool valid = BeaconRootsVerify.verifyValidator(
            header, validatorStruct, proofs, 67, nextBlockTimestamp
        );
        assertTrue(valid);
    }

    // Test verifyValidatorEffectiveBalance
    function testVerifyValidatorEffectiveBalanceSuccess() public view {
        bytes32[] memory proofs = proof;
        bool valid = BeaconRootsVerify.verifyValidatorEffectiveBalance(
            header,
            validatorStruct,
            proofs,
            67,
            validatorStruct.effectiveBalance,
            nextBlockTimestamp
        );
        assertTrue(valid, "Effective balance verification failed");
    }

    function testVerifyValidatorEffectiveBalanceMismatch() public {
        bytes32[] memory proofs = proof;
        vm.expectRevert(BeaconRootsVerify.FieldMismatch.selector);
        BeaconRootsVerify.verifyValidatorEffectiveBalance(
            header,
            validatorStruct,
            proofs,
            67,
            validatorStruct.effectiveBalance + 1,
            nextBlockTimestamp
        );
    }

    // Test verifyValidatorWithdrawalAddress
    function testVerifyValidatorWithdrawalAddressSuccess() public view {
        bytes32[] memory proofs = proof;
        address withdrawalAddress =
            address(uint160(uint256(validatorStruct.withdrawalCredentials)));
        bool valid = BeaconRootsVerify.verifyValidatorWithdrawalAddress(
            stateRoot, validatorStruct, proofs, 67, withdrawalAddress
        );
        assertTrue(valid, "Withdrawal address verification failed");
    }

    function testVerifyValidatorWithdrawalAddressMismatch() public {
        bytes32[] memory proofs = proof;
        vm.expectRevert(BeaconRootsVerify.FieldMismatch.selector);
        BeaconRootsVerify.verifyValidatorWithdrawalAddress(
            stateRoot, validatorStruct, proofs, 67, address(0x999)
        );
    }

    function testExtractBalance() public pure {
        // Sample chunk
        bytes32 chunk =
            0x00a0724e1809000000e038035059080000a0724e18090000b00e267154151500;

        // Offsets: 0, 1, 2, 3
        uint64[4] memory expectedBigEndian = [
            uint64(0x000009184e72a000), // offset 0
            uint64(0x000859500338e000), // offset 1
            uint64(0x000009184e72a000), // offset 2
            uint64(0x0015155471260eb0) // offset 3
        ];

        for (uint256 offset = 0; offset < 4; offset++) {
            uint64 value = extractBalance(chunk, offset);
            assertEq(
                value,
                expectedBigEndian[offset],
                string(
                    abi.encodePacked("Offset ", vm.toString(offset), " failed")
                )
            );
        }
    }

    function extractBalance(bytes32 chunk, uint256 offset)
        internal
        pure
        returns (uint64)
    {
        require(offset < 4, "Invalid offset");
        // console.log("Chunk", uint256(chunk));
        // console.log("Shifted", uint256(chunk) >> ((3 - offset) * 64));

        uint256 chunkValue = uint256(chunk);
        uint256 shiftBits = (3 - offset) * 64;

        uint64 leBalance =
            uint64((chunkValue >> shiftBits) & 0xFFFFFFFFFFFFFFFF);
        // console.log("LE", leBalance);
        // console.log("BE", EndianHelper.reverseBytes64(leBalance));

        // Convert from little-endian to big-endian
        return EndianHelper.reverseBytes64(leBalance);
    }
}
