// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessageLibManager} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from
    "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

/**
 * @title Verify DVN Configuration
 * @notice Verifies that DVN configurations are properly set for the OFT bridge
 * @dev Checks both send and receive configurations for both directions
 */
contract VerifyDVNConfigBerachain is Script {
    uint32 constant ULN_CONFIG_TYPE = 2;

    function run() external view {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN");
        address adapter = vm.envAddress("ADAPTER_ADDRESS");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));
        address sendLib = vm.envAddress("BERA_SEND_LIB_ADDRESS");
        address receiveLib = vm.envAddress("BERA_RECEIVE_LIB_ADDRESS");

        console.log("=== Verifying Berachain DVN Configuration ===");
        console.log("Endpoint:", endpoint);
        console.log("Adapter:", adapter);
        console.log("Binance EID:", binanceEid);
        console.log("");

        // Check SEND configuration (Berachain -> Binance)
        console.log("--- SEND Configuration (Berachain -> Binance) ---");
        console.log("SendLib:", sendLib);

        try IMessageLibManager(endpoint).getConfig(
            adapter, sendLib, binanceEid, ULN_CONFIG_TYPE
        ) returns (bytes memory sendConfigBytes) {
            if (sendConfigBytes.length > 0) {
                UlnConfig memory sendConfig =
                    abi.decode(sendConfigBytes, (UlnConfig));
                console.log("Confirmations:", sendConfig.confirmations);
                console.log("Required DVN Count:", sendConfig.requiredDVNCount);
                console.log("Required DVNs:");
                for (uint256 i = 0; i < sendConfig.requiredDVNs.length; i++) {
                    console.log("  DVN", i, ":", sendConfig.requiredDVNs[i]);
                }
                console.log("SEND CONFIG: SET");
            } else {
                console.log("SEND CONFIG: NOT SET (using defaults)");
                console.log("Run: make oft-set-send-config");
            }
        } catch {
            console.log("SEND CONFIG: ERROR READING");
        }
        console.log("");

        // Check RECEIVE configuration (Berachain <- Binance)
        console.log("--- RECEIVE Configuration (Berachain <- Binance) ---");
        console.log("ReceiveLib:", receiveLib);

        try IMessageLibManager(endpoint).getConfig(
            adapter, receiveLib, binanceEid, ULN_CONFIG_TYPE
        ) returns (bytes memory receiveConfigBytes) {
            if (receiveConfigBytes.length > 0) {
                UlnConfig memory receiveConfig =
                    abi.decode(receiveConfigBytes, (UlnConfig));
                console.log("Confirmations:", receiveConfig.confirmations);
                console.log(
                    "Required DVN Count:", receiveConfig.requiredDVNCount
                );
                console.log("Required DVNs:");
                for (uint256 i = 0; i < receiveConfig.requiredDVNs.length; i++)
                {
                    console.log("  DVN", i, ":", receiveConfig.requiredDVNs[i]);
                }
                console.log("RECEIVE CONFIG: SET");
            } else {
                console.log("RECEIVE CONFIG: NOT SET (using defaults)");
                console.log("Run: make oft-set-receive-config-berachain");
            }
        } catch {
            console.log("RECEIVE CONFIG: ERROR READING");
        }
        console.log("");

        console.log("=== Verification Complete ===");
    }
}

contract VerifyDVNConfigBinance is Script {
    uint32 constant ULN_CONFIG_TYPE = 2;

    function run() external view {
        address endpoint = vm.envAddress("LZ_ENDPOINT_BINANCE");
        address oft = vm.envAddress("OFT_ADDRESS");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID"));
        address sendLib = vm.envAddress("BNB_SEND_LIB_ADDRESS");
        address receiveLib = vm.envAddress("BNB_RECEIVE_LIB_ADDRESS");

        console.log("=== Verifying Binance DVN Configuration ===");
        console.log("Endpoint:", endpoint);
        console.log("OFT:", oft);
        console.log("Berachain EID:", berachainEid);
        console.log("");

        // Check SEND configuration (Binance -> Berachain)
        console.log("--- SEND Configuration (Binance -> Berachain) ---");
        console.log("SendLib:", sendLib);

        try IMessageLibManager(endpoint).getConfig(
            oft, sendLib, berachainEid, ULN_CONFIG_TYPE
        ) returns (bytes memory sendConfigBytes) {
            if (sendConfigBytes.length > 0) {
                UlnConfig memory sendConfig =
                    abi.decode(sendConfigBytes, (UlnConfig));
                console.log("Confirmations:", sendConfig.confirmations);
                console.log("Required DVN Count:", sendConfig.requiredDVNCount);
                console.log("Required DVNs:");
                for (uint256 i = 0; i < sendConfig.requiredDVNs.length; i++) {
                    console.log("  DVN", i, ":", sendConfig.requiredDVNs[i]);
                }
                console.log("SEND CONFIG: SET");
            } else {
                console.log("SEND CONFIG: NOT SET (using defaults)");
                console.log("Run: make oft-set-send-config-binance");
            }
        } catch {
            console.log("SEND CONFIG: ERROR READING");
        }
        console.log("");

        // Check RECEIVE configuration (Binance <- Berachain)
        console.log("--- RECEIVE Configuration (Binance <- Berachain) ---");
        console.log("ReceiveLib:", receiveLib);

        try IMessageLibManager(endpoint).getConfig(
            oft, receiveLib, berachainEid, ULN_CONFIG_TYPE
        ) returns (bytes memory receiveConfigBytes) {
            if (receiveConfigBytes.length > 0) {
                UlnConfig memory receiveConfig =
                    abi.decode(receiveConfigBytes, (UlnConfig));
                console.log("Confirmations:", receiveConfig.confirmations);
                console.log(
                    "Required DVN Count:", receiveConfig.requiredDVNCount
                );
                console.log("Required DVNs:");
                for (uint256 i = 0; i < receiveConfig.requiredDVNs.length; i++)
                {
                    console.log("  DVN", i, ":", receiveConfig.requiredDVNs[i]);
                }
                console.log("RECEIVE CONFIG: SET");
            } else {
                console.log("RECEIVE CONFIG: NOT SET (using defaults)");
                console.log("Run: make oft-set-receive-config");
            }
        } catch {
            console.log("RECEIVE CONFIG: ERROR READING");
        }
        console.log("");

        console.log("=== Verification Complete ===");
    }
}
