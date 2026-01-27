// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title Check OFT Prerequisites Script
 * @notice Verifies that all prerequisites are met before OFT deployment
 * @dev Run this script before starting the deployment process
 *
 * Usage:
 * forge script script/CheckOFTPrerequisites.s.sol --rpc-url $BERACHAIN_RPC
 */
contract CheckOFTPrerequisites is Script {
    struct PrerequisiteCheck {
        bool envVariablesSet;
        bool irTokenExists;
        bool irTokenHasSupply;
        bool lzEndpointExists;
        bool ownerIsSet;
        bool ownerIsMultisig;
        bool deployerHasBalance;
    }

    /**
     * @notice Check all prerequisites on Berachain
     */
    function run(bool _mainnet) external view {
        console.log("=== Checking OFT Deployment Prerequisites ===");
        console.log("");

        PrerequisiteCheck memory checks;

        // 1. Check environment variables
        console.log("1. Checking environment variables...");
        checks.envVariablesSet = checkEnvironmentVariables(_mainnet);
        console.log("");

        // 2. Check IR token
        console.log("2. Checking IR token...");
        checks.irTokenExists = checkIRToken(_mainnet);
        console.log("");

        // 3. Check LayerZero endpoint
        console.log("3. Checking LayerZero endpoint...");
        checks.lzEndpointExists = checkLayerZeroEndpoint(_mainnet);
        console.log("");

        // 4. Check owner configuration
        console.log("4. Checking owner configuration...");
        checks.ownerIsSet = checkOwnerConfiguration(_mainnet);
        console.log("");

        // 5. Check deployer balance
        console.log("5. Checking deployer balance...");
        checks.deployerHasBalance = checkDeployerBalance();
        console.log("");

        // Summary
        console.log("=== Prerequisites Summary ===");
        console.log("");
        logCheckResult("Environment Variables", checks.envVariablesSet);
        logCheckResult("IR Token Exists", checks.irTokenExists);
        logCheckResult("LayerZero Endpoint", checks.lzEndpointExists);
        logCheckResult("Owner Configured", checks.ownerIsSet);
        logCheckResult("Deployer Has Balance", checks.deployerHasBalance);
        console.log("");

        bool allPassed = checks.envVariablesSet && checks.irTokenExists
            && checks.lzEndpointExists && checks.ownerIsSet
            && checks.deployerHasBalance;

        if (allPassed) {
            console.log("STATUS: READY TO DEPLOY");
            console.log("");
            console.log("Next steps:");
            console.log("1. Review .env configuration");
            console.log(
                "2. Run: forge script script/DeployIROFTAdapter.s.sol --rpc-url $BERACHAIN_RPC --broadcast"
            );
        } else {
            console.log("STATUS: NOT READY");
            console.log("");
            console.log("Please fix the issues above before deploying.");
        }
    }

    function checkEnvironmentVariables(bool _mainnet)
        internal
        view
        returns (bool)
    {
        bool allSet = true;

        // Check required variables
        string[] memory requiredVars = new string[](7);
        requiredVars[0] =
            _mainnet ? "IR_TOKEN_ADDRESS" : "IR_TOKEN_ADDRESS_TESTNET";
        requiredVars[1] =
            _mainnet ? "LZ_ENDPOINT_BERACHAIN" : "LZ_ENDPOINT_BERACHAIN_TESTNET";
        requiredVars[2] = _mainnet ? "ADAPTER_OWNER" : "ADAPTER_OWNER_TESTNET";
        requiredVars[3] = _mainnet ? "BERACHAIN_EID" : "BERACHAIN_EID_TESTNET";
        requiredVars[4] =
            _mainnet ? "LZ_ENDPOINT_BINANCE" : "LZ_ENDPOINT_BINANCE_TESTNET";
        requiredVars[5] = _mainnet ? "OFT_OWNER" : "OFT_OWNER_TESTNET";
        requiredVars[6] = _mainnet ? "BINANCE_EID" : "BINANCE_EID_TESTNET";

        for (uint256 i = 0; i < requiredVars.length; i++) {
            try vm.envAddress(requiredVars[i]) returns (address) {
                console.log("  ", requiredVars[i], ": SET");
            } catch {
                try vm.envUint(requiredVars[i]) returns (uint256) {
                    console.log("  ", requiredVars[i], ": SET");
                } catch {
                    console.log("  ", requiredVars[i], ": MISSING");
                    allSet = false;
                }
            }
        }

        return allSet;
    }

    function checkIRToken(bool _mainnet) internal view returns (bool) {
        string memory _irStr =
            _mainnet ? "IR_TOKEN_ADDRESS" : "IR_TOKEN_ADDRESS_TESTNET";
        try vm.envAddress(_irStr) returns (address irToken) {
            console.log("  IR Token Address:", irToken);

            // Check if address has code
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(irToken)
            }

            if (codeSize == 0) {
                console.log("  ERROR: No code at IR token address");
                return false;
            }

            console.log("  Contract exists: YES");

            // Try to get token details
            try ERC20(irToken).totalSupply() returns (uint256 supply) {
                console.log("  Total Supply:", supply);
                if (supply > 0) {
                    console.log("  Has supply: YES");
                }
            } catch {
                console.log("  WARNING: Could not read total supply");
            }

            try ERC20(irToken).name() returns (string memory name) {
                console.log("  Name:", name);
            } catch {}

            try ERC20(irToken).symbol() returns (string memory symbol) {
                console.log("  Symbol:", symbol);
            } catch {}

            return true;
        } catch {
            console.log("  ERROR: IR_TOKEN_ADDRESS not set");
            return false;
        }
    }

    function checkLayerZeroEndpoint(bool _mainnet)
        internal
        view
        returns (bool)
    {
        string memory _lzStr =
            _mainnet ? "LZ_ENDPOINT_BERACHAIN" : "LZ_ENDPOINT_BERACHAIN_TESTNET";
        try vm.envAddress(_lzStr) returns (address endpoint) {
            console.log("  LZ Endpoint:", endpoint);

            // Check if address has code
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(endpoint)
            }

            if (codeSize == 0) {
                console.log("  ERROR: No code at LayerZero endpoint address");
                console.log(
                    "  Please verify the endpoint address for this network"
                );
                return false;
            }

            console.log("  Contract exists: YES");
            return true;
        } catch {
            console.log("  ERROR: LZ_ENDPOINT_BERACHAIN not set");
            return false;
        }
    }

    function checkOwnerConfiguration(bool _mainnet)
        internal
        view
        returns (bool)
    {
        string memory _oftStr =
            _mainnet ? "ADAPTER_OWNER" : "ADAPTER_OWNER_TESTNET";
        try vm.envAddress(_oftStr) returns (address owner) {
            console.log("  Adapter Owner:", owner);

            if (owner == address(0)) {
                console.log("  ERROR: Owner is zero address");
                return false;
            }

            // Check if it's likely a multisig (has code)
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(owner)
            }

            if (codeSize > 0) {
                console.log("  Is contract (likely multisig): YES");
            } else {
                console.log("  WARNING: Owner is EOA, not a multisig");
                console.log("  RECOMMENDATION: Use multisig for production");
            }

            return true;
        } catch {
            console.log("  ERROR: ADAPTER_OWNER not set");
            return false;
        }
    }

    function checkDeployerBalance() internal view returns (bool) {
        address deployer = msg.sender;
        console.log("  Deployer:", deployer);

        uint256 balance = deployer.balance;
        console.log("  Balance:", balance, "wei");

        // Estimate minimum required balance (rough estimate)
        // OFTAdapter deployment typically costs ~0.01 ETH on most chains
        uint256 minRequired = 0.01 ether;

        if (balance < minRequired) {
            console.log("  WARNING: Balance may be too low");
            console.log("  Recommended minimum:", minRequired, "wei");
            return false;
        }

        console.log("  Balance sufficient: YES");
        return true;
    }

    function logCheckResult(string memory check, bool passed) internal pure {
        if (passed) {
            console.log("  [PASS]", check);
        } else {
            console.log("  [FAIL]", check);
        }
    }
}

/**
 * @title Check OFT Prerequisites on Binance
 * @notice Verifies prerequisites for deploying IROFT on Binance Chain
 */
contract CheckOFTPrerequisitesBinance is Script {
    function run(bool _mainnet) external view {
        console.log(
            "=== Checking OFT Deployment Prerequisites (Binance Testnet) ==="
        );
        console.log("");

        bool allPassed = true;

        // 1. Check LayerZero endpoint
        console.log("1. Checking LayerZero endpoint...");
        string memory _str =
            _mainnet ? "LZ_ENDPOINT_BINANCE" : "LZ_ENDPOINT_BINANCE_TESTNET";
        try vm.envAddress(_str) returns (address endpoint) {
            console.log("  LZ Endpoint:", endpoint);

            uint256 codeSize;
            assembly {
                codeSize := extcodesize(endpoint)
            }

            if (codeSize == 0) {
                console.log("  ERROR: No code at LayerZero endpoint");
                allPassed = false;
            } else {
                console.log("  Contract exists: YES");
            }
        } catch {
            console.log("  ERROR: LZ_ENDPOINT_BINANCE not set");
            allPassed = false;
        }
        console.log("");

        // 2. Check owner
        console.log("2. Checking owner configuration...");
        _str = _mainnet ? "OFT_OWNER" : "OFT_OWNER_TESTNET";
        try vm.envAddress(_str) returns (address owner) {
            console.log("  OFT Owner:", owner);

            if (owner == address(0)) {
                console.log("  ERROR: Owner is zero address");
                allPassed = false;
            } else {
                uint256 codeSize;
                assembly {
                    codeSize := extcodesize(owner)
                }

                if (codeSize > 0) {
                    console.log("  Is contract (likely multisig): YES");
                } else {
                    console.log("  WARNING: Owner is EOA, not a multisig");
                }
            }
        } catch {
            console.log("  ERROR: OFT_OWNER not set");
            allPassed = false;
        }
        console.log("");

        // 3. Check deployer balance
        console.log("3. Checking deployer balance...");
        address deployer = msg.sender;
        uint256 balance = deployer.balance;
        console.log("  Deployer:", deployer);
        console.log("  Balance:", balance, "wei");

        if (balance < 0.01 ether) {
            console.log("  WARNING: Balance may be too low");
            allPassed = false;
        }
        console.log("");

        // Summary
        if (allPassed) {
            console.log("STATUS: READY TO DEPLOY");
            console.log("");
            console.log("Next step:");
            console.log(
                "Run: forge script script/deploy/DeployIROFT.s.sol --rpc-url $BINANCE_RPC_TESTNET --broadcast"
            );
        } else {
            console.log("STATUS: NOT READY");
            console.log("Please fix the issues above before deploying.");
        }
    }
}
