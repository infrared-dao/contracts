// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

/// @notice Adds a delegate account to gnosis safe for proposing batch txs
/// @dev should be called by one of the safe owners for signature
contract AddSafeDelegate is Script {
    using stdJson for string;

    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
    }

    struct Delegate {
        address delegateAddress;
        uint256 totp;
    }

    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId)");
    bytes32 constant DELEGATE_TYPEHASH =
        keccak256("Delegate(address delegateAddress,uint256 totp)");

    bytes32 public domainSeparator;

    function run(
        address safe,
        address delegateAddress,
        address delegator,
        string calldata safeTxService
    ) external {
        // Parameters
        string memory name = "Safe Transaction Service";
        string memory version = "1.0";
        uint256 chainId = block.chainid; // Get current chain ID
        uint256 totp = block.timestamp / 3600; // Calculate TOTP based on epoch time

        // Compute domain separator
        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId
            )
        );

        bytes memory signature;
        {
            // Compute message hash
            bytes32 messageHash =
                keccak256(abi.encode(DELEGATE_TYPEHASH, delegateAddress, totp));

            // Compute the EIP-712 hash
            bytes32 dataHash = keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, messageHash)
            );

            // Sign the hash with a private key
            uint256 privateKey = vm.envUint("PRIVATE_KEY"); // Load private key from environment
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, dataHash);
            // Combine into bytes
            signature = abi.encodePacked(r, s, v);
        }

        string memory jsonPayload;
        {
            // Prepare JSON payload for the curl request
            string memory label = "Delegate account";
            string memory placeholder = "";
            placeholder.serialize("safe", safe);
            placeholder.serialize("delegate", delegateAddress);
            placeholder.serialize("delegator", delegator);
            placeholder.serialize("signature", signature);
            jsonPayload = placeholder.serialize("label", label);
        }

        // string memory jsonPayload = string(
        //     abi.encodePacked(
        //         '{"safe":"', toAsciiString(safe), '",',
        //         '"delegate":"', toAsciiString(delegateAddress), '",',
        //         '"delegator":"', toAsciiString(delegator), '",',
        //         '"signature":"', toHexString(signature), '",',
        //         '"label":"Delegate account"}'
        //     )
        // );

        // Write payload to a temporary JSON file
        string memory tempFile = "temp-payload.json";
        // vm.writeFile(tempFile, jsonPayload);
        vm.writeJson(jsonPayload, tempFile);

        // Prepare curl command
        string[] memory inputs = new string[](8);
        inputs[0] = "curl";
        inputs[1] = "-X";
        inputs[2] = "POST";
        inputs[3] = string.concat(safeTxService, "api/v2/delegates/");
        inputs[4] = "-H";
        inputs[5] = "Content-Type: application/json";
        inputs[6] = "-d";
        inputs[7] = string(abi.encodePacked("@", tempFile));

        // Execute curl command using vm.ffi
        bytes memory response = vm.ffi(inputs);

        // vm.removeFile(tempFile);

        // Log the response
        console2.log("Response from server:");
        console2.log(string(response));
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
