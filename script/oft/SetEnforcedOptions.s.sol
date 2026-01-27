// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {IROFTAdapter} from "src/periphery/IROFTAdapter.sol";
import {IROFT} from "src/periphery/IROFT.sol";
import {EnforcedOptionParam} from
    "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from
    "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title LayerZero OFT Enforced Options Configuration Script
 * @notice Sets enforced execution options for specific message types and destinations
 * @dev This script configures minimum gas limits for cross-chain messages to ensure reliable execution
 *
 * LayerZero Chain IDs (Endpoint V2):
 * - Berachain: 30362 (mainnet), 40371 (testnet)
 * - Binance Chain (BSC): 30102 (mainnet), 40102 (testnet)
 *
 * Message Types (OFT Standard):
 * - SEND = 1: Token transfer
 * - SEND_AND_CALL = 2: Token transfer with payload execution
 *
 * Gas Recommendations:
 * - Basic token transfer: 50,000 - 100,000 gas
 * - Complex operations: 150,000 - 200,000 gas
 * - For safety, we use 200,000 gas for SEND operations
 *
 * Required environment variables:
 * For Berachain (Adapter):
 * - ADAPTER_ADDRESS[_TESTNET]: Address of deployed IROFTAdapter
 * - ADAPTER_OWNER[_TESTNET]: Owner address with permissions
 * - BINANCE_EID[_TESTNET]: LayerZero endpoint ID for Binance Chain
 *
 * For Binance (OFT):
 * - OFT_ADDRESS[_TESTNET]: Address of deployed IROFT
 * - OFT_OWNER[_TESTNET]: Owner address with permissions
 * - BERACHAIN_EID[_TESTNET]: LayerZero endpoint ID for Berachain
 *
 * Example usage:
 * Testnet:
 * forge script script/oft/SetEnforcedOptions.s.sol:SetEnforcedOptionsAdapter \
 *   --rpc-url $BERACHAIN_RPC \
 *   --broadcast
 *
 * Mainnet (via Safe):
 * forge script script/oft/SetEnforcedOptions.s.sol:SetEnforcedOptionsAdapter:runMultisig \
 *   --rpc-url $BERACHAIN_RPC \
 *   --sig "runMultisig(bool,address)" \
 *   true \
 *   $SAFE_ADDRESS
 */

/// @title Set Enforced Options for IROFTAdapter (Berachain → Binance)
/// @notice Configure minimum gas limits for messages sent from Berachain to Binance
contract SetEnforcedOptionsAdapter is BatchScript {
    using OptionsBuilder for bytes;

    // OFT message types
    uint16 constant SEND = 1;
    uint16 constant SEND_AND_CALL = 2;

    /**
     * @notice Set enforced options on IROFTAdapter for testnet
     * @dev Configures gas limits for token transfers from Berachain to Binance
     */
    function run() external {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        address signer = vm.envAddress("ADAPTER_OWNER_TESTNET");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID_TESTNET"));

        console.log("Setting enforced options on IROFTAdapter:");
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  Destination EID (Binance):", binanceEid);
        console.log("  Signer:", signer);

        // Build options: addExecutorLzReceiveOption(gasLimit, msgValue)
        // For SEND operations, we use 200,000 gas and 0 msg.value
        bytes memory optionsSend =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Create enforced options array
        EnforcedOptionParam[] memory enforcedOptions =
            new EnforcedOptionParam[](1);

        // Set enforced options for SEND message type
        enforcedOptions[0] = EnforcedOptionParam({
            eid: binanceEid,
            msgType: SEND,
            options: optionsSend
        });

        vm.startBroadcast(signer);

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);
        adapter.setEnforcedOptions(enforcedOptions);

        vm.stopBroadcast();

        console.log("Enforced options set successfully!");
        console.log("  Message Type: 1 (SEND)");
        console.log("  Gas Limit: 200000");
        console.log("  Msg Value: 0");
        console.log("Next: Run SetEnforcedOptionsOFT on Binance Chain");
    }

    /**
     * @notice Set enforced options on IROFTAdapter for mainnet via Safe multisig
     * @param _send Whether to execute the batch immediately
     * @param _safe Address of the Safe multisig
     */
    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));

        console.log("Setting enforced options on IROFTAdapter:");
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  Destination EID (Binance):", binanceEid);
        console.log("  Safe:", _safe);

        // Build options for SEND operations
        bytes memory optionsSend =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Create enforced options array
        EnforcedOptionParam[] memory enforcedOptions =
            new EnforcedOptionParam[](1);

        enforcedOptions[0] = EnforcedOptionParam({
            eid: binanceEid,
            msgType: SEND,
            options: optionsSend
        });

        // Encode the function call
        bytes memory data = abi.encodeWithSignature(
            "setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions
        );

        addToBatch(adapterAddress, 0, data);

        executeBatch(_send);

        console.log("Batch prepared successfully!");
        console.log("  Message Type: 1 (SEND)");
        console.log("  Gas Limit: 200000");
    }
}

/// @title Set Enforced Options for IROFT (Binance → Berachain)
/// @notice Configure minimum gas limits for messages sent from Binance to Berachain
contract SetEnforcedOptionsOFT is BatchScript {
    using OptionsBuilder for bytes;

    // OFT message types
    uint16 constant SEND = 1;
    uint16 constant SEND_AND_CALL = 2;

    /**
     * @notice Set enforced options on IROFT for testnet
     * @dev Configures gas limits for token transfers from Binance to Berachain
     */
    function run() external {
        address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        address signer = vm.envAddress("OFT_OWNER_TESTNET");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID_TESTNET"));

        console.log("Setting enforced options on IROFT:");
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Destination EID (Berachain):", berachainEid);
        console.log("  Signer:", signer);

        // Build options: addExecutorLzReceiveOption(gasLimit, msgValue)
        // For SEND operations, we use 200,000 gas and 0 msg.value
        bytes memory optionsSend =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Create enforced options array
        EnforcedOptionParam[] memory enforcedOptions =
            new EnforcedOptionParam[](1);

        // Set enforced options for SEND message type
        enforcedOptions[0] = EnforcedOptionParam({
            eid: berachainEid,
            msgType: SEND,
            options: optionsSend
        });

        vm.startBroadcast(signer);

        IROFT oft = IROFT(oftAddress);
        oft.setEnforcedOptions(enforcedOptions);

        vm.stopBroadcast();

        console.log("Enforced options set successfully!");
        console.log("  Message Type: 1 (SEND)");
        console.log("  Gas Limit: 200000");
        console.log("  Msg Value: 0");
        console.log("Bridge enforced options are now configured!");
    }

    /**
     * @notice Set enforced options on IROFT for mainnet via Safe multisig
     * @param _send Whether to execute the batch immediately
     * @param _safe Address of the Safe multisig
     */
    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID"));

        console.log("Setting enforced options on IROFT:");
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Destination EID (Berachain):", berachainEid);
        console.log("  Safe:", _safe);

        // Build options for SEND operations
        bytes memory optionsSend =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Create enforced options array
        EnforcedOptionParam[] memory enforcedOptions =
            new EnforcedOptionParam[](1);

        enforcedOptions[0] = EnforcedOptionParam({
            eid: berachainEid,
            msgType: SEND,
            options: optionsSend
        });

        // Encode the function call
        bytes memory data = abi.encodeWithSignature(
            "setEnforcedOptions((uint32,uint16,bytes)[])", enforcedOptions
        );

        addToBatch(oftAddress, 0, data);

        executeBatch(_send);

        console.log("Batch prepared successfully!");
        console.log("  Message Type: 1 (SEND)");
        console.log("  Gas Limit: 200000");
    }
}
