// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAV2_1 as InfraredBERAV2} from
    "src/staking/InfraredBERAV2_1.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";

import {InfraredV1_10 as Infrared} from "src/core/InfraredV1_10.sol";
import {IBGT as IBerachainBGT} from "@berachain/pol/interfaces/IBGT.sol";

contract InfraredBERAKeeper is Script {
    Infrared infrared =
        Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    IBerachainBGT bgt =
        IBerachainBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);

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

    error PendingWithdrawals();

    /// @dev queue's a ticket to rebalance entire stak of given validator
    /// @dev remove validator from set after
    function queueExitRebalance(
        address _withdrawor,
        address _ibera,
        bytes calldata _pubkey,
        string calldata proofFilePath
    ) external {
        uint256 _stake = InfraredBERAV2(_ibera).stakes(_pubkey);
        address _depositor = InfraredBERAV2(_ibera).depositor();

        // check no pending withdrawals
        if (
            InfraredBERAWithdrawor(payable(_withdrawor))
                .getTotalPendingWithdrawals(keccak256(_pubkey)) > 0
        ) revert PendingWithdrawals();

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

        // strRaw = json.parseRaw(".validator_leaf");
        // validatorLeaf = abi.decode(strRaw, (bytes32));

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
        if (totalPendingWithdrawals > 0) revert PendingWithdrawals();

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

        // if (
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header)
        //         != BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp)
        // ) revert();

        uint128[] memory _amts = new uint128[](1);
        (, _amts[0]) =
            bgt.boostedQueue(address(infrared), validatorStruct.pubkey);
        bytes[] memory _pubkeys = new bytes[](1);
        _pubkeys[0] = validatorStruct.pubkey;

        vm.startBroadcast();
        // cancel queued boosts
        if (_amts[0] > 0) {
            infrared.cancelBoosts(_pubkeys, _amts);
        }

        // unboost bgt
        _amts[0] = bgt.boosted(address(infrared), validatorStruct.pubkey);
        if (_amts[0] > 0) {
            infrared.queueDropBoosts(_pubkeys, _amts);
        }

        // queue rebalance
        InfraredBERAWithdrawor(payable(_withdrawor)).queue(_depositor, _stake);
        // execute withdraw
        InfraredBERAWithdrawor(payable(_withdrawor)).execute{
            value: InfraredBERAWithdrawor(payable(_withdrawor)).getFee()
        }(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
            0,
            nextBlockTimestamp
        );

        vm.stopBroadcast();
    }

    function executeWithdrawProofs(
        address _withdrawor,
        address _ibera,
        uint256 amount,
        string calldata proofFilePath
    ) public {
        address _depositor = InfraredBERAV2(_ibera).depositor();
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

        // strRaw = json.parseRaw(".validator_leaf");
        // validatorLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".balance_leaf");
        balanceLeaf = abi.decode(strRaw, (bytes32));

        strRaw = json.parseRaw(".metadata.timestamp");
        nextBlockTimestamp = abi.decode(strRaw, (uint256));
        nextBlockTimestamp = nextBlockTimestamp + 2;

        strRaw = json.parseRaw(".validator_data");
        {
            JsonValidator memory _validator =
                abi.decode(strRaw, (JsonValidator));

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
        }

        strRaw = json.parseRaw(".header");
        {
            JsonHeader memory _header = abi.decode(strRaw, (JsonHeader));

            header = BeaconRootsVerify.BeaconBlockHeader({
                slot: _header.slot,
                proposerIndex: _header.proposer_index,
                parentRoot: _header.parent_root,
                stateRoot: _header.state_root,
                bodyRoot: _header.body_root
            });
        }

        // bytes32 expectedRoot =
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);

        // bytes32 rootByTimestamp =
        //     BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp);

        // if (
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header)
        //         != BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp)
        // ) revert();

        vm.startBroadcast();
        // queue rebalance
        InfraredBERAWithdrawor(payable(_withdrawor)).queue(_depositor, amount);
        // execute withdraw
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

    /// @dev Calls registerViaProofs to sync validator stake from consensus layer
    /// @param _ibera The InfraredBERA contract address
    /// @param proofFilePath Path to the JSON proof file
    function registerViaProofs(
        address _withdrawor,
        address _ibera,
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
        if (totalPendingWithdrawals > 0) revert PendingWithdrawals();

        if (
            InfraredBERAWithdrawor(payable(_withdrawor))
                .getTotalPendingWithdrawals(keccak256(_validator.pubkey)) > 0
        ) revert PendingWithdrawals();

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

        vm.startBroadcast();
        InfraredBERAV2(_ibera).registerViaProofs(
            header,
            validatorStruct,
            validatorProof,
            balanceProof,
            validatorIndex,
            balanceLeaf,
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

        // strRaw = json.parseRaw(".validator_leaf");
        // validatorLeaf = abi.decode(strRaw, (bytes32));

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

        // if (
        //     BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header)
        //         != BeaconRootsVerify.getParentBeaconBlockRoot(nextBlockTimestamp)
        // ) revert();
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
