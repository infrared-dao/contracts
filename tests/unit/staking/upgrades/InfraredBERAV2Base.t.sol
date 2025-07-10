// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../core/Infrared/Helper.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {Errors} from "src/utils/Errors.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

contract InfraredBERAV2BaseTest is Helper {
    using stdJson for string;

    bytes public constant withdrawPrecompile = abi.encodePacked(
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f556101f480602d5f395ff33373fffffffffffffffffffffffffffffffffffffffe1460c7573615156028575f545f5260205ff35b36603814156101f05760115f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff146101f057600182026001905f5b5f821115608057810190830284830290049160010191906065565b9093900434106101f057600154600101600155600354806003026004013381556001015f35815560010160203590553360601b5f5260385f601437604c5fa0600101600355005b6003546002548082038060101160db575060105b5f5b81811461017f5780604c02838201600302600401805490600101805490600101549160601b83528260140152807fffffffffffffffffffffffffffffffff0000000000000000000000000000000016826034015260401c906044018160381c81600701538160301c81600601538160281c81600501538160201c81600401538160181c81600301538160101c81600201538160081c81600101535360010160dd565b9101809214610191579060025561019c565b90505f6002555f6003555b5f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff14156101c957505f5b6001546002828201116101de5750505f6101e4565b01600290035b5f555f600155604c025ff35b5f5ffd"
    );

    address WITHDRAW_PRECOMPILE = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    address public validator0 = validator0;
    address public validator1 = validator1;
    bytes public pubkey0 = abi.encodePacked(bytes32("v0"), bytes16("")); // must be len 48
    bytes public pubkey1 = abi.encodePacked(bytes32("v1"), bytes16(""));
    bytes public signature0 =
        abi.encodePacked(bytes32("v0"), bytes32(""), bytes32("")); // must be len 96
    bytes public signature1 =
        abi.encodePacked(bytes32("v1"), bytes32(""), bytes32(""));

    // Proof data
    bytes32[] public validatorProof;
    bytes32[] public balanceProof;
    bytes32 public stateRoot;
    uint256 public validatorIndex;
    bytes32 public validatorLeaf;
    bytes32 public balanceLeaf;
    uint256 public nextBlockTimestamp;
    BeaconRootsVerify.Validator public validatorStruct;
    BeaconRootsVerify.BeaconBlockHeader public header;

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

    function setUp() public virtual override {
        super.setUp();
        // Setup test users
        vm.deal(alice, 20000 ether);
        vm.deal(bob, 20000 ether);
        vm.deal(charlie, 20000 ether);

        _prepareWithdrawPrecompile();

        address withdraworImpl = address(new InfraredBERAWithdrawor());
        vm.startPrank(infraredGovernance);
        // Upgrade withdrawor to V2
        withdraworLite.upgradeToAndCall(withdraworImpl, "");
        withdrawor = InfraredBERAWithdrawor(payable(address(withdraworLite)));
        withdrawor.initializeV2(WITHDRAW_PRECOMPILE);
        vm.stopPrank();

        // Load proof data
        _loadProofData();

        // Setup beacon roots mock
        _setupBeaconRootsMock();
    }

    function _prepareWithdrawPrecompile() internal {
        // etch deposit contract at depositor constant deposit contract address
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
    }

    function _loadProofData() internal {
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

    function _setupBeaconRootsMock() internal {
        bytes32 expectedRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);

        vm.mockCall(
            BeaconRootsVerify.BEACON_ROOTS,
            abi.encode(nextBlockTimestamp),
            abi.encode(expectedRoot)
        );
    }

    function setupWithdrawalProof(address user, uint256 amount, bool isValid)
        internal
        pure
        returns (bytes32[] memory)
    {
        if (isValid) {
            bytes32[] memory proof = new bytes32[](1);
            proof[0] = keccak256(abi.encodePacked(user, amount));
            return proof;
        } else {
            bytes32[] memory proof = new bytes32[](1);
            proof[0] = bytes32(uint256(0xDEADBEEF));
            return proof;
        }
    }

    function getTestBalance() internal view returns (uint256) {
        // Extract balance from balance leaf (4 balances packed per 32 bytes)
        uint256 balance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;
        return balance;
    }

    // Helper functions for mocking
    function mockValidatorBalanceVerification(
        BeaconRootsVerify.BeaconBlockHeader memory _header,
        bytes32[] memory _balanceProof,
        uint256 _validatorIndex,
        uint256 _balance,
        bytes32 _balanceLeaf,
        uint256 _nextBlockTimestamp,
        bool shouldPass
    ) internal {
        vm.mockCall(
            address(depositor),
            abi.encodeWithSignature(
                "verifyValidatorBalance((uint64,uint64,bytes32,bytes32,bytes32),bytes32[],uint256,uint256,bytes32,uint256)",
                _header,
                _balanceProof,
                _validatorIndex,
                _balance,
                _balanceLeaf,
                _nextBlockTimestamp
            ),
            abi.encode(shouldPass)
        );
    }

    function mockWithdrawalAddressVerification(
        bytes32 _stateRoot,
        BeaconRootsVerify.Validator memory _validator,
        bytes32[] memory _validatorProof,
        uint256 _validatorIndex,
        address _withdrawalAddress,
        bool shouldPass
    ) internal {
        vm.mockCall(
            address(depositor),
            abi.encodeWithSignature(
                "verifyValidatorWithdrawalAddress(bytes32,(bytes,bytes32,uint64,bool,uint64,uint64,uint64,uint64),bytes32[],uint256,address)",
                _stateRoot,
                _validator,
                _validatorProof,
                _validatorIndex,
                _withdrawalAddress
            ),
            abi.encode(shouldPass)
        );
    }

    function setValidatorStake(bytes memory pubkey, uint256 stake) internal {
        bytes32 pubkeyHash = keccak256(pubkey);

        // 1. Set the stake amount in _stakes mapping (slot 25)
        bytes32 stakesSlot = keccak256(abi.encode(pubkeyHash, uint256(25)));
        vm.store(address(ibera), stakesSlot, bytes32(stake));

        // 2. Set _staked to true if stake > 0 (slot 26)
        bytes32 stakedSlot = keccak256(abi.encode(pubkeyHash, uint256(26)));
        vm.store(
            address(ibera), stakedSlot, bytes32(uint256(stake > 0 ? 1 : 0))
        );

        // 3. Mock the BeaconDeposit contract to return the correct operator
        address operator = ibera.infrared();

        // Calculate storage slot for _operatorByPubKey[pubkey]

        // For dynamic bytes as mapping keys, Solidity uses keccak256(bytes . uint256(slot))
        bytes32 operatorSlot = keccak256(abi.encodePacked(pubkey, uint256(2)));

        // Set the operator in BeaconDeposit storage
        vm.store(
            depositor.DEPOSIT_CONTRACT(),
            operatorSlot,
            bytes32(uint256(uint160(operator)))
        );

        assertEq(
            BeaconDeposit(depositor.DEPOSIT_CONTRACT()).getOperator(pubkey),
            operator
        );
    }

    function setupValidatorWithProof() internal {
        // Set withdrawor to match the proof's withdrawal credentials
        bytes32 withdraworSlot = bytes32(uint256(22));
        address proofWithdrawor = 0x8c0E122960dc2E97dc0059c07d6901Dce72818E1;
        vm.store(
            address(ibera),
            withdraworSlot,
            bytes32(uint256(uint160(proofWithdrawor)))
        );

        // Set validator stake to match proof balance
        uint256 proofBalance = uint256(
            BeaconRootsVerify.extractBalance(balanceLeaf, validatorIndex % 4)
        ) * 1 gwei;
        setValidatorStake(validatorStruct.pubkey, proofBalance);

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
    }
}
