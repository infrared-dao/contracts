// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "src/periphery/MerkleDistributor.sol";
import "@solmate/tokens/ERC20.sol";

/**
 * @title DeployMerkleDistributor
 * @notice Deployment using pre-computed merkle root (for 50k+ distributions)
 * @dev Use this after generating merkle root with Python
 */
contract DeployMerkleDistributor is Script {
    // ============================================
    // MAIN DEPLOYMENT FUNCTION
    // ============================================

    function run() external {
        // Load from environment variables (set by Python script output)
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        uint256 totalAllocation = vm.envUint("TOTAL_ALLOCATION");
        uint256 claimWindow = 1768176000 - block.timestamp;

        // Validate inputs
        require(tokenAddress != address(0), "TOKEN_ADDRESS not set");
        require(ownerAddress != address(0), "OWNER_ADDRESS not set");
        require(merkleRoot != bytes32(0), "MERKLE_ROOT not set");
        require(totalAllocation > 0, "TOTAL_ALLOCATION not set");
        require(claimWindow > 0, "CLAIM_WINDOW_DAYS not set");
        require(claimWindow < 27 days, "CLAIM_WINDOW_DAYS not set");

        console.log("========================================");
        console.log("DEPLOYING WITH PRE-COMPUTED MERKLE ROOT");
        console.log("========================================");
        console.log("Token:", tokenAddress);
        console.log("Owner:", ownerAddress);
        console.log("Merkle Root:", vm.toString(merkleRoot));
        console.log("Total Allocation:", totalAllocation / 1e18, "tokens");
        console.log("Claim Window:", claimWindow / (60 * 60 * 24), "days");
        console.log("");

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MerkleDistributor distributor = new MerkleDistributor(
            tokenAddress, merkleRoot, ownerAddress, claimWindow, totalAllocation
        );

        address distributorAddress = address(distributor);

        // Optional: Auto-fund
        if (vm.envBool("AUTO_FUND")) {
            ERC20 token = ERC20(tokenAddress);
            require(
                token.transfer(distributorAddress, totalAllocation),
                "Failed to fund distributor"
            );
            console.log(
                "Funded distributor with", totalAllocation / 1e18, "tokens"
            );
        }

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("========================================");
        console.log("Distributor Address:", distributorAddress);
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify on Etherscan");
        console.log("2. Fund contract (if not auto-funded)");
        console.log("3. Share API endpoint for proof retrieval");
        console.log("");
        console.log("Users can get proofs from:");
        console.log("https://api.yourproject.com/merkle-proof/{address}");
    }

    function _getNetwork() private view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 80094) return "berachain";
        if (chainId == 80069) return "bepolia";
        if (chainId == 31337) return "localhost";

        return vm.toString(chainId);
    }
}
