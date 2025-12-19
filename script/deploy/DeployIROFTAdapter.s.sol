// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IROFTAdapter} from "src/periphery/IROFTAdapter.sol";

/**
 * @title Deploy IROFTAdapter Script
 * @notice Deploys the OFTAdapter on the source chain (Berachain) where IR token already exists
 * @dev Usage: forge script script/DeployIROFTAdapter.s.sol --rpc-url $RPC_URL --broadcast
 *
 * Required environment variables:
 * - IR_TOKEN_ADDRESS: Address of the existing InfraredGovernanceToken
 * - LZ_ENDPOINT_BERACHAIN: LayerZero endpoint address on Berachain
 * - ADAPTER_OWNER: Address that will own the adapter (typically multisig)
 *
 * Example:
 * forge script script/DeployIROFTAdapter.s.sol \
 *   --rpc-url $BERACHAIN_RPC \
 *   --broadcast \
 *   --verify
 */
contract DeployIROFTAdapter is Script {
    /**
     * @notice Deploy IROFTAdapter on Berachain Testnet
     */
    function run() external returns (IROFTAdapter adapter) {
        // Load environment variables
        address irToken = vm.envAddress("IR_TOKEN_ADDRESS_TESTNET");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN_TESTNET");
        address owner = vm.envAddress("ADAPTER_OWNER_TESTNET");

        console.log("Deploying IROFTAdapter with:");
        console.log("  IR Token:", irToken);
        console.log("  LZ Endpoint:", lzEndpoint);
        console.log("  Owner:", owner);

        vm.startBroadcast();

        adapter = new IROFTAdapter(irToken, lzEndpoint, owner);

        vm.stopBroadcast();

        console.log("IROFTAdapter deployed at:", address(adapter));
        console.log("\nNext steps:");
        console.log("1. Deploy IROFT on destination chain (Binance)");
        console.log("2. Set config using SetConfig.s.sol");
        console.log("3. Configure peers using ConfigureOFTPeers.s.sol");
        console.log("4. Verify setup using VerifyOFTSetup.s.sol");
    }

    /**
     * @notice Deploy IROFTAdapter on Berachain Mainnet
     */
    function runMainnet() external returns (IROFTAdapter adapter) {
        // Load environment variables
        address irToken = vm.envAddress("IR_TOKEN_ADDRESS");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT_BERACHAIN");
        address owner = vm.envAddress("ADAPTER_OWNER");

        console.log("Deploying IROFTAdapter (Mainnet) with:");
        console.log("  IR Token:", irToken);
        console.log("  LZ Endpoint:", lzEndpoint);
        console.log("  Owner:", owner);

        vm.startBroadcast();

        adapter = new IROFTAdapter(irToken, lzEndpoint, owner);

        vm.stopBroadcast();

        console.log("IROFTAdapter deployed at:", address(adapter));
        console.log("\nNext steps:");
        console.log("1. Deploy IROFT on destination chain (Binance)");
        console.log("2. Set config using SetConfig.s.sol");
        console.log(
            "3. Configure peers using ConfigureOFTPeers.s.sol:runMultisig"
        );
        console.log("4. Verify setup using VerifyOFTSetup.s.sol");
    }
}
