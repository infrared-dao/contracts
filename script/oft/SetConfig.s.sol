// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {ILayerZeroEndpointV2} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from
    "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from
    "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

/// @title LayerZero Send Configuration Script (A → B)
/// @notice Defines and applies ULN (DVN) + Executor configs for cross‑chain messages sent from Chain A to Chain B via LayerZero Endpoint V2.
contract SetSendConfig is BatchScript {
    uint32 constant EXECUTOR_CONFIG_TYPE = 1;
    uint32 constant ULN_CONFIG_TYPE = 2;

    /// @notice Broadcasts transactions to set both Send ULN and Executor configurations for messages sent from Chain A to Chain B
    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN_TESTNET"); // Chain A Endpoint
        address oapp = vm.envAddress("ADAPTER_ADDRESS_TESTNET"); // OApp on Chain A
        uint32 eid = uint32(vm.envUint("BINANCE_EID_TESTNET")); // Endpoint ID for Chain B
        address sendLib = vm.envAddress("BERA_SEND_LIB_ADDRESS_TESTNET"); // SendLib for A → B
        address signer = vm.envAddress("ADAPTER_OWNER_TESTNET");
        address beraDVN0 = vm.envAddress("BERA_DVN_0_TESTNET");

        console.log("Configuring Berachain DVN:");
        console.log("  Adapter (Berachain):", oapp);
        console.log("  Binance EID:", eid);
        console.log("  Bera SendLib:", sendLib);
        console.log("  Bera governance:", signer);
        console.log("  Bera dvn:", beraDVN0);

        /// @notice ULNConfig defines security parameters (DVNs + confirmation threshold) for A → B
        /// @notice Send config requests these settings to be applied to the DVNs and Executor for messages sent from A to B
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = beraDVN0;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // minimum block confirmations required on A before sending to B
            requiredDVNCount: 1, // number of DVNs required
            optionalDVNCount: type(uint8).max, // optional DVNs count, uint8
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0) // sorted list of optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, ULN_CONFIG_TYPE, encodedUln);

        vm.startBroadcast(signer);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, sendLib, params); // Set config for messages sent from A to B
        vm.stopBroadcast();
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN"); // Chain A Endpoint
        address oapp = vm.envAddress("ADAPTER_ADDRESS"); // OApp on Chain A
        uint32 eid = uint32(vm.envUint("BINANCE_EID")); // Endpoint ID for Chain B
        address sendLib = vm.envAddress("BERA_SEND_LIB_ADDRESS"); // SendLib for A → B
        address signer = vm.envAddress("ADAPTER_OWNER");
        address beraDVN0 = vm.envAddress("BERA_DVN_0");
        address beraDVN1 = vm.envAddress("BERA_DVN_1");

        console.log("Configuring Berachain DVN:");
        console.log("  Adapter (Berachain):", oapp);
        console.log("  Binance EID:", eid);
        console.log("  Bera SendLib:", sendLib);
        console.log("  Bera governance:", signer);
        console.log("  Bera dvn0:", beraDVN0);
        console.log("  Bera dvn1:", beraDVN1);

        /// @notice ULNConfig defines security parameters (DVNs + confirmation threshold) for A → B
        /// @notice Send config requests these settings to be applied to the DVNs and Executor for messages sent from A to B
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = beraDVN0;
        requiredDVNs[1] = beraDVN1;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // minimum block confirmations required on A before sending to B
            requiredDVNCount: 2, // number of DVNs required
            optionalDVNCount: type(uint8).max, // optional DVNs count, uint8
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0) // sorted list of optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, ULN_CONFIG_TYPE, encodedUln);

        bytes memory data = abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])",
            oapp,
            sendLib,
            params
        );

        addToBatch(endpoint, 0, data);

        executeBatch(_send);
    }
}

/// @title LayerZero Receive Configuration Script (B ← A)
/// @notice Defines and applies ULN (DVN) config for inbound message verification on Chain B for messages received from Chain A via LayerZero Endpoint V2.
contract SetReceiveConfig is BatchScript {
    uint32 constant RECEIVE_CONFIG_TYPE = 2;

    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BINANCE_TESTNET"); // Chain B Endpoint
        address oapp = vm.envAddress("OFT_ADDRESS_TESTNET"); // OApp on Chain B
        uint32 eid = uint32(vm.envUint("BERACHAIN_EID_TESTNET")); // Endpoint ID for Chain A
        address receiveLib = vm.envAddress("BNB_RECEIVE_LIB_ADDRESS_TESTNET"); // ReceiveLib for B ← A
        address signer = vm.envAddress("OFT_OWNER_TESTNET");
        address bnbDVN0 = vm.envAddress("BNB_DVN_0_TESTNET");

        console.log("Configuring Binance DVN:");
        console.log("  OFT (Binance):", oapp);
        console.log("  Berachain EID:", eid);
        console.log("  Binance ReceiveLib:", receiveLib);
        console.log("  Binance governance:", signer);
        console.log("  Binance dvn:", bnbDVN0);

        /// @notice UlnConfig controls verification threshold for incoming messages from A to B
        /// @notice Receive config enforces these settings have been applied to the DVNs for messages received from A
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = bnbDVN0;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // min block confirmations from source (A)
            requiredDVNCount: 1, // required DVNs for message acceptance
            optionalDVNCount: type(uint8).max, // optional DVNs count
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted required DVNs
            optionalDVNs: new address[](0) // no optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, RECEIVE_CONFIG_TYPE, encodedUln);

        vm.startBroadcast(signer);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params); // Set config for messages received on B from A
        vm.stopBroadcast();
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BINANCE"); // Chain B Endpoint
        address oapp = vm.envAddress("OFT_ADDRESS"); // OApp on Chain B
        uint32 eid = uint32(vm.envUint("BERACHAIN_EID")); // Endpoint ID for Chain A
        address receiveLib = vm.envAddress("BNB_RECEIVE_LIB_ADDRESS"); // ReceiveLib for B ← A
        address signer = vm.envAddress("OFT_OWNER");
        address bnbDVN0 = vm.envAddress("BNB_DVN_0");
        address bnbDVN1 = vm.envAddress("BNB_DVN_1");

        console.log("Configuring Binance DVN:");
        console.log("  OFT (Binance):", oapp);
        console.log("  Berachain EID:", eid);
        console.log("  Binance ReceiveLib:", receiveLib);
        console.log("  Binance governance:", signer);
        console.log("  Binance dvn0:", bnbDVN0);
        console.log("  Binance dvn1:", bnbDVN1);

        /// @notice UlnConfig controls verification threshold for incoming messages from A to B
        /// @notice Receive config enforces these settings have been applied to the DVNs for messages received from A
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = bnbDVN0;
        requiredDVNs[1] = bnbDVN1;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // min block confirmations from source (A)
            requiredDVNCount: 2, // required DVNs for message acceptance
            optionalDVNCount: type(uint8).max, // optional DVNs count
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted required DVNs
            optionalDVNs: new address[](0) // no optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, RECEIVE_CONFIG_TYPE, encodedUln);

        bytes memory data = abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])",
            oapp,
            receiveLib,
            params
        );

        addToBatch(endpoint, 0, data);

        executeBatch(_send);
    }
}

/// @title LayerZero Send Configuration Script (B → A)
/// @notice Defines and applies ULN (DVN) + Executor configs for cross‑chain messages sent from Chain B (Binance) to Chain A (Berachain) via LayerZero Endpoint V2.
contract SetSendConfigBinance is BatchScript {
    uint32 constant EXECUTOR_CONFIG_TYPE = 1;
    uint32 constant ULN_CONFIG_TYPE = 2;

    /// @notice Broadcasts transactions to set both Send ULN and Executor configurations for messages sent from Chain B to Chain A
    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BINANCE_TESTNET"); // Chain B Endpoint
        address oapp = vm.envAddress("OFT_ADDRESS_TESTNET"); // OApp on Chain B
        uint32 eid = uint32(vm.envUint("BERACHAIN_EID_TESTNET")); // Endpoint ID for Chain A
        address sendLib = vm.envAddress("BNB_SEND_LIB_ADDRESS_TESTNET"); // SendLib for B → A
        address signer = vm.envAddress("OFT_OWNER_TESTNET");
        address bnbDVN0 = vm.envAddress("BNB_DVN_0_TESTNET");

        console.log("Configuring Binance Send DVN (Binance -> Berachain):");
        console.log("  OFT (Binance):", oapp);
        console.log("  Berachain EID:", eid);
        console.log("  Binance SendLib:", sendLib);
        console.log("  Binance governance:", signer);
        console.log("  Binance dvn:", bnbDVN0);

        /// @notice ULNConfig defines security parameters (DVNs + confirmation threshold) for B → A
        /// @notice Send config requests these settings to be applied to the DVNs and Executor for messages sent from B to A
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = bnbDVN0;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // minimum block confirmations required on B before sending to A
            requiredDVNCount: 1, // number of DVNs required
            optionalDVNCount: type(uint8).max, // optional DVNs count, uint8
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0) // sorted list of optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, ULN_CONFIG_TYPE, encodedUln);

        vm.startBroadcast(signer);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, sendLib, params); // Set config for messages sent from B to A
        vm.stopBroadcast();
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BINANCE"); // Chain B Endpoint
        address oapp = vm.envAddress("OFT_ADDRESS"); // OApp on Chain B
        uint32 eid = uint32(vm.envUint("BERACHAIN_EID")); // Endpoint ID for Chain A
        address sendLib = vm.envAddress("BNB_SEND_LIB_ADDRESS"); // SendLib for B → A
        address signer = vm.envAddress("OFT_OWNER");
        address bnbDVN0 = vm.envAddress("BNB_DVN_0");
        address bnbDVN1 = vm.envAddress("BNB_DVN_1");

        console.log("Configuring Binance Send DVN (Binance -> Berachain):");
        console.log("  OFT (Binance):", oapp);
        console.log("  Berachain EID:", eid);
        console.log("  Binance SendLib:", sendLib);
        console.log("  Binance governance:", signer);
        console.log("  Binance dvn0:", bnbDVN0);
        console.log("  Binance dvn1:", bnbDVN1);

        /// @notice ULNConfig defines security parameters (DVNs + confirmation threshold) for B → A
        /// @notice Send config requests these settings to be applied to the DVNs and Executor for messages sent from B to A
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = bnbDVN0;
        requiredDVNs[1] = bnbDVN1;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // minimum block confirmations required on B before sending to A
            requiredDVNCount: 2, // number of DVNs required
            optionalDVNCount: type(uint8).max, // optional DVNs count, uint8
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0) // sorted list of optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, ULN_CONFIG_TYPE, encodedUln);

        bytes memory data = abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])",
            oapp,
            sendLib,
            params
        );

        addToBatch(endpoint, 0, data);

        executeBatch(_send);
    }
}

/// @title LayerZero Receive Configuration Script (A ← B)
/// @notice Defines and applies ULN (DVN) config for inbound message verification on Chain A (Berachain) for messages received from Chain B (Binance) via LayerZero Endpoint V2.
contract SetReceiveConfigBerachain is BatchScript {
    uint32 constant RECEIVE_CONFIG_TYPE = 2;

    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN_TESTNET"); // Chain A Endpoint
        address oapp = vm.envAddress("ADAPTER_ADDRESS_TESTNET"); // OApp on Chain A
        uint32 eid = uint32(vm.envUint("BINANCE_EID_TESTNET")); // Endpoint ID for Chain B
        address receiveLib = vm.envAddress("BERA_RECEIVE_LIB_ADDRESS_TESTNET"); // ReceiveLib for A ← B
        address signer = vm.envAddress("ADAPTER_OWNER_TESTNET");
        address beraDVN0 = vm.envAddress("BERA_DVN_0_TESTNET");

        console.log("Configuring Berachain Receive DVN (Berachain <- Binance):");
        console.log("  Adapter (Berachain):", oapp);
        console.log("  Binance EID:", eid);
        console.log("  Berachain ReceiveLib:", receiveLib);
        console.log("  Berachain governance:", signer);
        console.log("  Berachain dvn:", beraDVN0);

        /// @notice UlnConfig controls verification threshold for incoming messages from B to A
        /// @notice Receive config enforces these settings have been applied to the DVNs for messages received from B
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = beraDVN0;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // min block confirmations from source (B)
            requiredDVNCount: 1, // required DVNs for message acceptance
            optionalDVNCount: type(uint8).max, // optional DVNs count
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted required DVNs
            optionalDVNs: new address[](0) // no optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, RECEIVE_CONFIG_TYPE, encodedUln);

        vm.startBroadcast(signer);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params); // Set config for messages received on A from B
        vm.stopBroadcast();
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN"); // Chain A Endpoint
        address oapp = vm.envAddress("ADAPTER_ADDRESS"); // OApp on Chain A
        uint32 eid = uint32(vm.envUint("BINANCE_EID")); // Endpoint ID for Chain B
        address receiveLib = vm.envAddress("BERA_RECEIVE_LIB_ADDRESS"); // ReceiveLib for A ← B
        address signer = vm.envAddress("ADAPTER_OWNER");
        address beraDVN0 = vm.envAddress("BERA_DVN_0");
        address beraDVN1 = vm.envAddress("BERA_DVN_1");

        console.log("Configuring Berachain Receive DVN (Berachain <- Binance):");
        console.log("  Adapter (Berachain):", oapp);
        console.log("  Binance EID:", eid);
        console.log("  Berachain ReceiveLib:", receiveLib);
        console.log("  Berachain governance:", signer);
        console.log("  Berachain dvn0:", beraDVN0);
        console.log("  Berachain dvn1:", beraDVN1);

        /// @notice UlnConfig controls verification threshold for incoming messages from B to A
        /// @notice Receive config enforces these settings have been applied to the DVNs for messages received from B
        /// @dev 0 values will be interpretted as defaults, so to apply NIL settings, use:
        /// @dev uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
        /// @dev uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = beraDVN0;
        requiredDVNs[1] = beraDVN1;

        UlnConfig memory uln = UlnConfig({
            confirmations: 3, // min block confirmations from source (B)
            requiredDVNCount: 2, // required DVNs for message acceptance
            optionalDVNCount: type(uint8).max, // optional DVNs count
            optionalDVNThreshold: 0, // optional DVN threshold
            requiredDVNs: requiredDVNs, // sorted required DVNs
            optionalDVNs: new address[](0) // no optional DVNs
        });

        bytes memory encodedUln = abi.encode(uln);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(eid, RECEIVE_CONFIG_TYPE, encodedUln);

        bytes memory data = abi.encodeWithSignature(
            "setConfig(address,address,(uint32,uint32,bytes)[])",
            oapp,
            receiveLib,
            params
        );

        addToBatch(endpoint, 0, data);

        executeBatch(_send);
    }
}
