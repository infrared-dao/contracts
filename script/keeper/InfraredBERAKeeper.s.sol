// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";

contract InfraredBERAKeeper is Script {
    using stdJson for string;

    bytes32[] validatorProof;
    bytes32[] balanceProof;
    uint256 validatorIndex;
    // bytes32 stateRoot;
    bytes32 validatorLeaf;
    bytes32 balancesRoot;
    bytes32 balanceLeaf;
    BeaconRootsVerify.BeaconBlockHeader header;
    BeaconRootsVerify.Validator validatorStruct;

    bytes32 stateRoot;
    uint256 nextBlockTimestamp;

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

    /// @dev queue's a ticket to rebalance entire stak of given validator
    function queueExitRebalance(
        address _withdrawor,
        address _ibera,
        bytes calldata _pubkey
    ) external {
        uint256 _stake = InfraredBERAV2(_ibera).stakes(_pubkey);
        address _depositor = InfraredBERAV2(_ibera).depositor();
        vm.startBroadcast();
        InfraredBERAWithdrawor(payable(_withdrawor)).queue(_depositor, _stake);
        vm.stopBroadcast();
    }

    function executeWithdrawProofs(
        address _withdrawor,
        uint256 amount,
        string calldata proofFilePath
    ) external {
        // set proof data
        string memory json;
        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, proofFilePath);
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

        // bytes32 expectedRoot =
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);

        // bytes32 rootByTimestamp =
        //     BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp);

        if (
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header)
                != BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp)
        ) revert();

        vm.startBroadcast();
        InfraredBERAWithdrawor(payable(_withdrawor)).execute{
            value: InfraredBERAWithdrawor(payable(_withdrawor)).getFee()
        }(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        vm.stopBroadcast();
    }

    function executeDepositProofs(
        address _depositor,
        uint256 amount,
        string calldata proofFilePath
    ) external {
        // set proof data
        string memory json;
        {
            string memory root = vm.projectRoot();
            string memory path = string.concat(root, proofFilePath);
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

        // bytes32 expectedRoot =
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);

        // bytes32 rootByTimestamp =
        //     BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp);

        if (
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header)
                != BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp)
        ) revert();
        // console.logBytes32(BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header));
        // revert();

        vm.startBroadcast();
        InfraredBERADepositorV2(payable(_depositor)).execute(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            amount,
            nextBlockTimestamp
        );
        vm.stopBroadcast();
    }

    function findUnclaimedTickets(address _withdrawor) public view {
        uint256 len =
            InfraredBERAWithdrawor(payable(_withdrawor)).requestLength();
        for (uint256 i; i < len; i++) {
            (InfraredBERAWithdrawor.RequestState state,,,,) =
                InfraredBERAWithdrawor(payable(_withdrawor)).requests(i);
            if (uint8(state) == 1) {
                console.logUint(i);
            }
        }
    }

    function toAsciiString(address addr)
        internal
        pure
        returns (string memory)
    {
        bytes memory characters = "0123456789abcdef";
        bytes memory asciiAddress = new bytes(42);

        asciiAddress[0] = "0";
        asciiAddress[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            uint8 byteValue = uint8(uint160(addr) >> (8 * (19 - i)));
            asciiAddress[2 + i * 2] = characters[byteValue >> 4];
            asciiAddress[3 + i * 2] = characters[byteValue & 0x0f];
        }

        return string(asciiAddress);
    }

    // Helper: Convert bytes to hex string
    function toHexString(bytes memory data)
        internal
        pure
        returns (string memory)
    {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    // Helper: Convert byte to ASCII character
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
