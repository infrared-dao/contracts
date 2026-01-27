// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";

import {IROFTAdapter} from "src/periphery/IROFTAdapter.sol";
import {IROFT} from "src/periphery/IROFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IOFT,
    MessagingFee,
    MessagingReceipt,
    SendParam
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from
    "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title Test OFT Bridge Script
 * @notice Scripts for testing cross-chain token transfers
 * @dev Includes functions for quoting fees and sending test transfers
 *
 * Usage examples:
 *
 * Quote fee from Berachain to Binance:
 * forge script script/TestOFTBridge.s.sol:QuoteSendFee --rpc-url $BERACHAIN_RPC
 *
 * Send tokens from Berachain to Binance:
 * forge script script/TestOFTBridge.s.sol:SendFromBerachain --rpc-url $BERACHAIN_RPC --broadcast
 *
 * Send tokens from Binance to Berachain:
 * forge script script/TestOFTBridge.s.sol:SendFromBinance --rpc-url $BINANCE_RPC --broadcast
 */
contract QuoteSendFee is Script {
    using OptionsBuilder for bytes;

    /**
     * @notice Quote the fee for sending tokens from Berachain to Binance (Testnet)
     */
    function run() external view {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID_TESTNET"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);

        console.log("=== Quoting Send Fee ===");
        console.log("From: Berachain (Adapter)");
        console.log("To: Binance (EID:", binanceEid, ")");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination (increased for safety)
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: binanceEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        console.log("Native Fee:", fee.nativeFee);
        console.log("LZ Token Fee:", fee.lzTokenFee);
        console.log("");
        console.log(
            "To send, you need to pay:", fee.nativeFee, "wei in native gas"
        );
    }

    function runMainnet() external view {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);

        console.log("=== Quoting Send Fee ===");
        console.log("From: Berachain (Adapter)");
        console.log("To: Binance (EID:", binanceEid, ")");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: binanceEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);

        console.log("Native Fee:", fee.nativeFee);
        console.log("LZ Token Fee:", fee.lzTokenFee);
        console.log("");
        console.log(
            "To send, you need to pay:", fee.nativeFee, "wei in native gas"
        );
    }
}

contract SendFromBerachain is BatchScript {
    using OptionsBuilder for bytes;

    /**
     * @notice Send IR tokens from Berachain to Binance (Testnet)
     */
    function run() external returns (MessagingReceipt memory receipt) {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS_TESTNET");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID_TESTNET"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);
        address token = adapter.token();

        console.log("=== Sending IR Tokens ===");
        console.log("From: Berachain");
        console.log("To: Binance");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination (increased for safety)
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: binanceEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);
        console.log("Native Fee Required:", fee.nativeFee);

        vm.startBroadcast();

        // Approve adapter to spend tokens
        IERC20(token).approve(adapterAddress, amount);
        console.log("Approved adapter to spend", amount, "tokens");

        // Send tokens
        (receipt,) = adapter.send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(msg.sender) // refund address
        );

        vm.stopBroadcast();

        console.log("");
        console.log("Transfer initiated!");
        console.log("GUID:", vm.toString(receipt.guid));
        console.log("Nonce:", receipt.nonce);
        console.log("");
        console.log("Monitor the transfer at: https://layerzeroscan.com/");
    }

    function runMainnet(bool _send, address _safe) external isBatch(_safe) {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 binanceEid = uint32(vm.envUint("BINANCE_EID"));

        IROFTAdapter adapter = IROFTAdapter(adapterAddress);
        address token = adapter.token();

        console.log("=== Sending IR Tokens ===");
        console.log("From: Berachain");
        console.log("To: Binance");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: binanceEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = adapter.quoteSend(sendParam, false);
        console.log("Native Fee Required:", fee.nativeFee);
        // add native fee buffer for delayed execution
        fee.nativeFee = fee.nativeFee * 120 / 100;
        console.log("Adjusted Fee:", fee.nativeFee);

        // Approve adapter to spend tokens
        // IERC20(token).approve(adapterAddress, amount);
        bytes memory data = abi.encodeWithSelector(
            IERC20.approve.selector, adapterAddress, amount
        );

        addToBatch(token, 0, data);

        // Send tokens
        // (receipt,) = adapter.send{value: fee.nativeFee}(
        //     sendParam,
        //     fee,
        //     payable(msg.sender) // refund address
        // );
        data = abi.encodeWithSelector(IOFT.send.selector, sendParam, fee, _safe);

        addToBatch(address(adapter), fee.nativeFee, data);

        executeBatch(_send);
    }
}

contract SendFromBinance is BatchScript {
    using OptionsBuilder for bytes;

    /**
     * @notice Send IR tokens from Binance back to Berachain (Testnet)
     */
    function run() external returns (MessagingReceipt memory receipt) {
        address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID_TESTNET"));

        IROFT oft = IROFT(oftAddress);

        console.log("=== Sending IR Tokens ===");
        console.log("From: Binance");
        console.log("To: Berachain");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination (increased for safety)
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: berachainEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = oft.quoteSend(sendParam, false);
        console.log("Native Fee Required:", fee.nativeFee);

        vm.startBroadcast();

        // Send tokens (no approval needed, sender owns the tokens)
        (receipt,) = oft.send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(msg.sender) // refund address
        );

        vm.stopBroadcast();

        console.log("");
        console.log("Transfer initiated!");
        console.log("GUID:", vm.toString(receipt.guid));
        console.log("Nonce:", receipt.nonce);
        console.log("");
        console.log("Monitor the transfer at: https://layerzeroscan.com/");
    }

    function runMainnet(bool _send, address _safe) external isBatch(_safe) {
        address oftAddress = vm.envAddress("OFT_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT");
        uint32 berachainEid = uint32(vm.envUint("BERACHAIN_EID"));

        IROFT oft = IROFT(oftAddress);

        console.log("=== Sending IR Tokens ===");
        console.log("From: Binance");
        console.log("To: Berachain");
        console.log("Amount:", amount);
        console.log("Recipient:", recipient);
        console.log("");

        // Build proper LayerZero V2 options
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
            200000, // gas limit for lzReceive on destination
            0 // msg.value for lzReceive
        );

        // Prepare send parameters
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));
        SendParam memory sendParam = SendParam({
            dstEid: berachainEid,
            to: recipientBytes32,
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee
        MessagingFee memory fee = oft.quoteSend(sendParam, false);
        console.log("Native Fee Required:", fee.nativeFee);
        // add native fee buffer for delayed execution
        fee.nativeFee = fee.nativeFee * 120 / 100;
        console.log("Adjusted Fee:", fee.nativeFee);

        // Send tokens (no approval needed, sender owns the tokens)
        // (receipt,) = oft.send{value: fee.nativeFee}(
        //     sendParam,
        //     fee,
        //     payable(msg.sender) // refund address
        // );
        bytes memory data =
            abi.encodeWithSelector(IOFT.send.selector, sendParam, fee, _safe);

        addToBatch(address(oft), fee.nativeFee, data);

        executeBatch(_send);
    }
}

contract CheckBalance is Script {
    /**
     * @notice Check IR token balance on either chain (Testnet)
     */
    function run() external view {
        address user = vm.envAddress("USER");

        // Try to load adapter (Berachain)
        try vm.envAddress("ADAPTER_ADDRESS_TESTNET") returns (
            address adapterAddress
        ) {
            IROFTAdapter adapter = IROFTAdapter(adapterAddress);
            address token = adapter.token();
            uint256 balance = IERC20(token).balanceOf(user);

            console.log("=== Balance Check (Berachain) ===");
            console.log("User:", user);
            console.log("IR Balance:", balance);
            console.log("Adapter:", adapterAddress);
        } catch {
            // Try OFT (Binance)
            address oftAddress = vm.envAddress("OFT_ADDRESS_TESTNET");
            IROFT oft = IROFT(oftAddress);
            uint256 balance = oft.balanceOf(user);

            console.log("=== Balance Check (Binance) ===");
            console.log("User:", user);
            console.log("IR Balance:", balance);
            console.log("OFT:", oftAddress);
        }
    }

    function runMainnet() external view {
        address user = vm.envAddress("USER");

        // Try to load adapter (Berachain)
        try vm.envAddress("ADAPTER_ADDRESS") returns (address adapterAddress) {
            IROFTAdapter adapter = IROFTAdapter(adapterAddress);
            address token = adapter.token();
            uint256 balance = IERC20(token).balanceOf(user);

            console.log("=== Balance Check (Berachain) ===");
            console.log("User:", user);
            console.log("IR Balance:", balance);
            console.log("Adapter:", adapterAddress);
        } catch {
            // Try OFT (Binance)
            address oftAddress = vm.envAddress("OFT_ADDRESS");
            IROFT oft = IROFT(oftAddress);
            uint256 balance = oft.balanceOf(user);

            console.log("=== Balance Check (Binance) ===");
            console.log("User:", user);
            console.log("IR Balance:", balance);
            console.log("OFT:", oftAddress);
        }
    }
}
