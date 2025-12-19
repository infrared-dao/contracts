// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {IROFT} from "src/periphery/IROFT.sol";

/**
 * @title Deploy IROFT Script
 * @notice Deploys the OFT on destination chains (e.g., Binance Chain) where IR doesn't exist
 * @dev Usage: forge script script/DeployIROFT.s.sol --rpc-url $RPC_URL --broadcast
 *
 * Required environment variables:
 * - LZ_ENDPOINT_BINANCE: LayerZero endpoint address on Binance Chain
 * - OFT_OWNER: Address that will own the OFT (typically multisig)
 *
 * Example:
 * forge script script/DeployIROFT.s.sol \
 *   --rpc-url $BINANCE_RPC \
 *   --broadcast \
 *   --verify
 */
contract DeployIROFT is Script {
    /**
     * @notice Deploy IROFT on Binance Testnet
     */
    function run() external returns (IROFT oft) {
        // Load environment variables
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT_BINANCE_TESTNET");
        address owner = vm.envAddress("OFT_OWNER_TESTNET");

        // Token details
        string memory name = "Infrared Governance Token";
        string memory symbol = "IR";

        console.log("Deploying IROFT with:");
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  LZ Endpoint:", lzEndpoint);
        console.log("  Owner:", owner);

        vm.startBroadcast();

        oft = new IROFT(name, symbol, lzEndpoint, owner);

        vm.stopBroadcast();

        console.log("IROFT deployed at:", address(oft));
        console.log("\nNext steps:");
        console.log(
            "1. Ensure IROFTAdapter is deployed on source chain (Berachain)"
        );
        console.log("2. Set config using SetConfig.s.sol");
        console.log("3. Configure peers using ConfigureOFTPeers.s.sol");
        console.log("4. Verify setup using VerifyOFTSetup.s.sol");
    }

    /**
     * @notice Deploy IROFT on Binance Mainnet
     */
    function runMainnet() external returns (IROFT oft) {
        // Load environment variables
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT_BINANCE");
        address owner = vm.envAddress("OFT_OWNER");

        // Token details
        string memory name = "Infrared Governance Token";
        string memory symbol = "IR";

        console.log("Deploying IROFT (Mainnet) with:");
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  LZ Endpoint:", lzEndpoint);
        console.log("  Owner:", owner);

        vm.startBroadcast();

        oft = new IROFT(name, symbol, lzEndpoint, owner);

        vm.stopBroadcast();

        console.log("IROFT deployed at:", address(oft));
        console.log("\nNext steps:");
        console.log(
            "1. Ensure IROFTAdapter is deployed on source chain (Berachain)"
        );
        console.log("2. Set config using SetConfig.s.sol");
        console.log(
            "3. Configure peers using ConfigureOFTPeers.s.sol:runMultisig"
        );
        console.log("4. Verify setup using VerifyOFTSetup.s.sol");
    }
}
