// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {IROFTAdapter} from "src/periphery/IROFTAdapter.sol";
import {IROFT} from "src/periphery/IROFT.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title Verify OFT Setup Script
 * @notice Verifies that the OFT bridge is properly configured
 * @dev Can be run on either chain to verify the setup
 *
 * Usage:
 * forge script script/VerifyOFTSetup.s.sol:VerifyAdapterSetup --rpc-url $BERACHAIN_RPC
 * forge script script/VerifyOFTSetup.s.sol:VerifyOFTSetup --rpc-url $BINANCE_RPC
 */
contract VerifyAdapterSetup is Script {
    /**
     * @notice Verify IROFTAdapter configuration on Berachain Testnet
     */
    function run() external view {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        address expectedOftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID_TESTNET"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);

        console.log("=== Verifying IROFTAdapter Setup ===");
        console.log("Adapter Address:", adapterAddress);
        console.log("");

        // Check token
        address token = adapter.token();
        console.log("Token Address:", token);
        console.log("Token Name:", ERC20(token).name());
        console.log("Token Symbol:", ERC20(token).symbol());
        console.log("");

        // Check owner
        address owner = adapter.owner();
        console.log("Owner:", owner);
        console.log("");

        // Check peer configuration
        bytes32 peer = adapter.peers(binanceEid);
        address peerAddress = address(uint160(uint256(peer)));
        console.log(
            "Configured Peer (Binance EID", binanceEid, "):", peerAddress
        );
        console.log("Expected OFT Address:", expectedOftAddress);

        if (peerAddress == expectedOftAddress) {
            console.log("PEER CONFIGURATION: CORRECT");
        } else {
            console.log("PEER CONFIGURATION: INCORRECT");
            console.log("Please run ConfigureOFTPeers.s.sol");
        }
        console.log("");

        // Check endpoint
        address endpoint = address(adapter.endpoint());
        console.log("LayerZero Endpoint:", endpoint);
        console.log("");

        console.log("=== Verification Complete ===");
    }
}

contract VerifyOFTSetup is Script {
    /**
     * @notice Verify IROFT configuration on Binance Testnet
     */
    function run() external view {
        address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        address expectedAdapterAddress =
            vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID_TESTNET"));

        IROFT oft = IROFT(oftAddress);

        console.log("=== Verifying IROFT Setup ===");
        console.log("OFT Address:", oftAddress);
        console.log("");

        // Check token details
        console.log("Token Name:", oft.name());
        console.log("Token Symbol:", oft.symbol());
        console.log("Token Decimals:", oft.decimals());
        console.log("Total Supply:", oft.totalSupply());
        console.log("");

        // Check owner
        address owner = oft.owner();
        console.log("Owner:", owner);
        console.log("");

        // Check peer configuration
        bytes32 peer = oft.peers(berachainEid);
        address peerAddress = address(uint160(uint256(peer)));
        console.log(
            "Configured Peer (Berachain EID", berachainEid, "):", peerAddress
        );
        console.log("Expected Adapter Address:", expectedAdapterAddress);

        if (peerAddress == expectedAdapterAddress) {
            console.log("PEER CONFIGURATION: CORRECT");
        } else {
            console.log("PEER CONFIGURATION: INCORRECT");
            console.log("Please run ConfigureOFTPeers.s.sol");
        }
        console.log("");

        // Check endpoint
        address endpoint = address(oft.endpoint());
        console.log("LayerZero Endpoint:", endpoint);
        console.log("");

        console.log("=== Verification Complete ===");
    }
}

/**
 * @title Verify Adapter Setup Mainnet
 * @notice Verifies IROFTAdapter configuration on Berachain Mainnet
 */
contract VerifyAdapterSetupMainnet is Script {
    /**
     * @notice Verify IROFTAdapter configuration on Berachain Mainnet
     */
    function run() external view {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        address expectedOftAddress = vm.envAddress("OFT_ADDRESS");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);

        console.log("=== Verifying IROFTAdapter Setup (Mainnet) ===");
        console.log("Adapter Address:", adapterAddress);
        console.log("");

        // Check token
        address token = adapter.token();
        console.log("Token Address:", token);
        console.log("Token Name:", ERC20(token).name());
        console.log("Token Symbol:", ERC20(token).symbol());
        console.log("");

        // Check owner
        address owner = adapter.owner();
        console.log("Owner:", owner);
        console.log("");

        // Check peer configuration
        bytes32 peer = adapter.peers(binanceEid);
        address peerAddress = address(uint160(uint256(peer)));
        console.log(
            "Configured Peer (Binance EID", binanceEid, "):", peerAddress
        );
        console.log("Expected OFT Address:", expectedOftAddress);

        if (peerAddress == expectedOftAddress) {
            console.log("PEER CONFIGURATION: CORRECT");
        } else {
            console.log("PEER CONFIGURATION: INCORRECT");
            console.log("Please run ConfigureOFTPeers.s.sol");
        }
        console.log("");

        // Check endpoint
        address endpoint = address(adapter.endpoint());
        console.log("LayerZero Endpoint:", endpoint);
        console.log("");

        console.log("=== Verification Complete ===");
    }
}

/**
 * @title Verify OFT Setup Mainnet
 * @notice Verifies IROFT configuration on Binance Mainnet
 */
contract VerifyOFTSetupMainnet is Script {
    /**
     * @notice Verify IROFT configuration on Binance Mainnet
     */
    function run() external view {
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        address expectedAdapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID"));

        IROFT oft = IROFT(oftAddress);

        console.log("=== Verifying IROFT Setup (Mainnet) ===");
        console.log("OFT Address:", oftAddress);
        console.log("");

        // Check token details
        console.log("Token Name:", oft.name());
        console.log("Token Symbol:", oft.symbol());
        console.log("Token Decimals:", oft.decimals());
        console.log("Total Supply:", oft.totalSupply());
        console.log("");

        // Check owner
        address owner = oft.owner();
        console.log("Owner:", owner);
        console.log("");

        // Check peer configuration
        bytes32 peer = oft.peers(berachainEid);
        address peerAddress = address(uint160(uint256(peer)));
        console.log(
            "Configured Peer (Berachain EID", berachainEid, "):", peerAddress
        );
        console.log("Expected Adapter Address:", expectedAdapterAddress);

        if (peerAddress == expectedAdapterAddress) {
            console.log("PEER CONFIGURATION: CORRECT");
        } else {
            console.log("PEER CONFIGURATION: INCORRECT");
            console.log("Please run ConfigureOFTPeers.s.sol");
        }
        console.log("");

        // Check endpoint
        address endpoint = address(oft.endpoint());
        console.log("LayerZero Endpoint:", endpoint);
        console.log("");

        console.log("=== Verification Complete ===");
    }
}
