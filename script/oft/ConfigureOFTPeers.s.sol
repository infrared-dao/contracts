// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {IROFTAdapter} from "src/periphery/IROFTAdapter.sol";
import {IROFT} from "src/periphery/IROFT.sol";

/**
 * @title Configure OFT Peers Script
 * @notice Sets up peer connections between OFTAdapter (Berachain) and OFT (Binance)
 * @dev This script must be run on BOTH chains after both contracts are deployed
 *
 * LayerZero Chain IDs (Endpoint V2):
 * - Berachain: 30362
 * - Binance Chain (BSC): 30102
 *
 * Required environment variables:
 * When running on Berachain:
 * - ADAPTER_ADDRESS: Address of deployed IROFTAdapter
 * - OFT_ADDRESS: Address of deployed IROFT on Binance
 * - BINANCE_EID: LayerZero endpoint ID for Binance Chain (30102)
 *
 * When running on Binance:
 * - OFT_ADDRESS: Address of deployed IROFT
 * - ADAPTER_ADDRESS: Address of deployed IROFTAdapter on Berachain
 * - BERACHAIN_EID: LayerZero endpoint ID for Berachain
 *
 * Example for Berachain:
 * forge script script/ConfigureOFTPeers.s.sol:ConfigureAdapterPeer \
 *   --rpc-url $BERACHAIN_RPC \
 *   --broadcast
 *
 * Example for Binance:
 * forge script script/ConfigureOFTPeers.s.sol:ConfigureOFTPeer \
 *   --rpc-url $BINANCE_RPC \
 *   --broadcast
 */
contract ConfigureAdapterPeer is BatchScript {
    /**
     * @notice Configure peer on the OFTAdapter (run on Berachain)
     */
    function run() external {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID_TESTNET"));

        console.log("Configuring IROFTAdapter peer:");
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Binance EID:", binanceEid);

        // Convert address to bytes32 (OFT uses bytes32 for peers)
        bytes32 peerBytes32 = bytes32(uint256(uint160(oftAddress)));

        vm.startBroadcast();

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);
        adapter.setPeer(binanceEid, peerBytes32);

        vm.stopBroadcast();

        console.log("Peer configured successfully!");
        console.log("Next: Run ConfigureOFTPeer on Binance Chain");
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));

        console.log("Configuring IROFTAdapter peer:");
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Binance EID:", binanceEid);

        // Convert address to bytes32 (OFT uses bytes32 for peers)
        bytes32 peerBytes32 = bytes32(uint256(uint160(oftAddress)));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);
        // adapter.setPeer(binanceEid, peerBytes32);

        bytes memory data = abi.encodeWithSignature(
            "setPeer(uint32,bytes32)", binanceEid, peerBytes32
        );

        addToBatch(address(adapter), 0, data);

        executeBatch(_send);
    }
}

contract ConfigureOFTPeer is BatchScript {
    /**
     * @notice Configure peer on the OFT (run on Binance)
     */
    function run() external {
        address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID_TESTNET"));

        console.log("Configuring IROFT peer:");
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  Berachain EID:", berachainEid);

        // Convert address to bytes32 (OFT uses bytes32 for peers)
        bytes32 peerBytes32 = bytes32(uint256(uint160(adapterAddress)));

        vm.startBroadcast();

        IROFT oft = IROFT(oftAddress);
        oft.setPeer(berachainEid, peerBytes32);

        vm.stopBroadcast();

        console.log("Peer configured successfully!");
        console.log("Bridge is now ready to use!");
        console.log("Run VerifyOFTSetup.s.sol to verify the configuration");
    }

    function runMultisig(bool _send, address _safe) external isBatch(_safe) {
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID"));

        console.log("Configuring IROFT peer:");
        console.log("  OFT (Binance):", oftAddress);
        console.log("  Adapter (Berachain):", adapterAddress);
        console.log("  Berachain EID:", berachainEid);

        // Convert address to bytes32 (OFT uses bytes32 for peers)
        bytes32 peerBytes32 = bytes32(uint256(uint160(adapterAddress)));

        IROFT oft = IROFT(oftAddress);
        // oft.setPeer(berachainEid, peerBytes32);

        bytes memory data = abi.encodeWithSignature(
            "setPeer(uint32,bytes32)", berachainEid, peerBytes32
        );

        addToBatch(address(oft), 0, data);

        executeBatch(_send);
    }
}
