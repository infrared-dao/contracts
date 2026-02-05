// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {CuttingBoardDutchAuction} from
    "src/periphery/CuttingBoardDutchAuction.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManager} from "src/periphery/CuttingBoardManager.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCuttingBoardAuction
 * @notice Deploys the complete Cutting Board Auction system
 * @dev Deploys NFT, Manager, and Auction contracts in the correct order
 *      Uses nonce-based address prediction to resolve circular dependencies
 *
 * Deployment order:
 * 1. Pre-compute all contract addresses using nonces
 * 2. CuttingBoardDutchAuction implementation
 * 3. CuttingBoardNFT (with pre-computed auction proxy address)
 * 4. CuttingBoardManager implementation + proxy
 * 5. CuttingBoardDutchAuction proxy (at pre-computed address)
 *
 * Note: After deployment, grant KEEPER_ROLE to CuttingBoardManager on Infrared contract
 */
contract DeployCuttingBoardAuction is Script {
    function run() external {
        _validateAndPrintConfig();

        // Deploy contracts
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Step 1: Pre-compute all contract addresses using nonces
        console.log("Step 1: Pre-computing contract addresses...");
        uint64 currentNonce = vm.getNonce(deployer);

        // Deployment order and nonces:
        // nonce + 0: Auction implementation
        // nonce + 1: NFT
        // nonce + 2: Manager implementation
        // nonce + 3: Manager proxy
        // nonce + 4: Auction proxy
        address predictedAuctionImpl =
            vm.computeCreateAddress(deployer, currentNonce);
        address predictedNft =
            vm.computeCreateAddress(deployer, currentNonce + 1);
        address predictedManagerImpl =
            vm.computeCreateAddress(deployer, currentNonce + 2);
        address predictedManagerProxy =
            vm.computeCreateAddress(deployer, currentNonce + 3);
        address predictedAuctionProxy =
            vm.computeCreateAddress(deployer, currentNonce + 4);

        console.log("Predicted Auction impl:", predictedAuctionImpl);
        console.log("Predicted NFT:", predictedNft);
        console.log("Predicted Manager impl:", predictedManagerImpl);
        console.log("Predicted Manager proxy:", predictedManagerProxy);
        console.log("Predicted Auction proxy:", predictedAuctionProxy);

        // Step 2: Deploy Auction implementation
        console.log("");
        console.log(
            "Step 2: Deploying CuttingBoardDutchAuction implementation..."
        );
        CuttingBoardDutchAuction auctionImpl = new CuttingBoardDutchAuction();
        console.log(
            "CuttingBoardDutchAuction implementation:", address(auctionImpl)
        );
        require(
            address(auctionImpl) == predictedAuctionImpl,
            "Auction impl address mismatch"
        );

        // Step 3: Deploy NFT with pre-computed auction proxy address
        CuttingBoardNFT nft;
        {
            console.log("");
            console.log("Step 3: Deploying CuttingBoardNFT...");
            string memory baseURI = vm.envOr("NFT_BASE_URI", string(""));
            nft = new CuttingBoardNFT(
                predictedAuctionProxy, owner, predictedManagerProxy, baseURI
            );
        }
        console.log("CuttingBoardNFT deployed at:", address(nft));
        require(address(nft) == predictedNft, "NFT address mismatch");

        // Step 4: Deploy Manager (implementation + proxy)
        CuttingBoardManager manager;
        {
            console.log("");
            console.log("Step 4: Deploying CuttingBoardManager...");
            CuttingBoardManager managerImpl = new CuttingBoardManager();
            console.log(
                "CuttingBoardManager implementation:", address(managerImpl)
            );
            require(
                address(managerImpl) == predictedManagerImpl,
                "Manager impl address mismatch"
            );

            ERC1967Proxy managerProxy = new ERC1967Proxy(
                address(managerImpl),
                abi.encodeCall(
                    CuttingBoardManager.initialize,
                    (
                        vm.envAddress("INFRARED_ADDRESS"),
                        address(nft),
                        vm.envAddress("CHEF_ADDRESS"),
                        owner,
                        vm.envAddress("KEEPER_ADDRESS"),
                        vm.envUint("PROPOSAL_VALIDITY_DURATION")
                    )
                )
            );
            manager = CuttingBoardManager(address(managerProxy));
        }
        console.log("CuttingBoardManager proxy deployed at:", address(manager));
        require(
            address(manager) == predictedManagerProxy,
            "Manager proxy address mismatch"
        );
        require(
            manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), owner),
            "Wrong manager admin"
        );
        require(
            manager.hasRole(manager.GOVERNANCE_ROLE(), owner),
            "Wrong manager admin"
        );

        // Step 5: Deploy Auction proxy
        CuttingBoardDutchAuction auction;
        {
            console.log("");
            console.log("Step 5: Deploying CuttingBoardDutchAuction proxy...");
            bytes memory auctionInitData = abi.encodeCall(
                CuttingBoardDutchAuction.initialize,
                _getAuctionInitParams(address(nft), address(manager))
            );
            ERC1967Proxy auctionProxy =
                new ERC1967Proxy(address(auctionImpl), auctionInitData);
            auction = CuttingBoardDutchAuction(address(auctionProxy));
        }
        console.log(
            "CuttingBoardDutchAuction proxy deployed at:", address(auction)
        );
        require(
            address(auction) == predictedAuctionProxy,
            "Auction proxy address mismatch"
        );
        require(
            auction.hasRole(auction.DEFAULT_ADMIN_ROLE(), owner),
            "Wrong auction admin"
        );
        require(
            auction.hasRole(auction.GOVERNANCE_ROLE(), owner),
            "Wrong auction admin"
        );

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("================================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("================================================");
        console.log("CuttingBoardNFT:            ", address(nft));
        console.log("CuttingBoardManager:        ", address(manager));
        console.log("CuttingBoardDutchAuction:   ", address(auction));
        console.log("");
        // console.log("Network:", _getNetwork());
        console.log("");

        // Print setup instructions
        console.log("================================================");
        console.log("NEXT STEPS");
        console.log("================================================");
        console.log("");
        console.log("1. GRANT KEEPER ROLE TO MANAGER:");
        console.log("   Call on Infrared contract:");
        console.log("   grantRole(KEEPER_ROLE, %s)", address(manager));
        console.log("");
        console.log("2. SET INITIAL AUCTION PRICE:");
        console.log("   auction.setInitialPrice(uint256 price)");
        console.log("");
        console.log("3. ENSURE VAULTS ARE WHITELISTED:");
        console.log("   Verify vaults in BeraChef are whitelisted");
        console.log("");
        console.log("4. START FIRST AUCTION:");
        console.log("   As keeper:");
        console.log(
            "   auction.startCuttingBoardAuction(bytes validatorPubkey)"
        );
        console.log("");
        console.log("5. VERIFY CONTRACTS:");
        console.log("   Verify all three contracts on block explorer");
        console.log("");
        console.log("================================================");
        console.log("");
        console.log("For detailed documentation, see:");
        console.log("- docs/CUTTING_BOARD_AUCTION_GUIDE.md");
        console.log("");
    }

    function _getNetwork() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return "Mainnet";
        if (chainId == 5) return "Goerli";
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 80084) return "Berachain bArtio Testnet";
        if (chainId == 31337) return "Local";
        return string(abi.encodePacked("ChainId: ", vm.toString(chainId)));
    }

    function _validateAndPrintConfig() internal view {
        // Load and validate
        address paymentToken = vm.envAddress("PAYMENT_TOKEN");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        address chef = vm.envAddress("CHEF_ADDRESS");
        address infrared = vm.envAddress("INFRARED_ADDRESS");

        require(paymentToken != address(0), "PAYMENT_TOKEN not set");
        require(treasury != address(0), "TREASURY_ADDRESS not set");
        require(owner != address(0), "OWNER_ADDRESS not set");
        require(keeper != address(0), "KEEPER_ADDRESS not set");
        require(chef != address(0), "CHEF_ADDRESS not set");
        require(infrared != address(0), "INFRARED_ADDRESS not set");

        uint256 auctionDuration = vm.envUint("AUCTION_DURATION");
        uint256 allocationDuration = vm.envUint("ALLOCATION_DURATION");
        uint256 maxAuctions = vm.envUint("MAX_AUCTIONS");
        uint256 startingPriceMultiplier =
            vm.envUint("STARTING_PRICE_MULTIPLIER");
        uint256 basePriceDivisor = vm.envUint("BASE_PRICE_DIVISOR");
        uint256 minimumPrice = vm.envUint("MINIMUM_PRICE");
        uint256 proposalValidityDuration =
            vm.envUint("PROPOSAL_VALIDITY_DURATION");

        require(auctionDuration > 0, "AUCTION_DURATION not set");
        require(allocationDuration > 0, "ALLOCATION_DURATION not set");
        require(maxAuctions > 0, "MAX_AUCTIONS not set");
        require(
            startingPriceMultiplier > 1e18,
            "STARTING_PRICE_MULTIPLIER must be > 1e18"
        );
        require(basePriceDivisor > 1e18, "BASE_PRICE_DIVISOR must be > 1e18");
        require(minimumPrice > 0, "MINIMUM_PRICE not set");
        require(
            proposalValidityDuration > 0, "PROPOSAL_VALIDITY_DURATION not set"
        );

        console.log("================================================");
        console.log("DEPLOYING CUTTING BOARD AUCTION SYSTEM");
        console.log("================================================");
        console.log("Payment Token:", paymentToken);
        console.log("Treasury:", treasury);
        console.log("Owner:", owner);
        console.log("Keeper:", keeper);
        console.log("BeraChef:", chef);
        console.log("Infrared:", infrared);
        console.log("");
        console.log("Auction Duration:", auctionDuration, "seconds");
        console.log("Allocation Duration:", allocationDuration, "seconds");
        console.log("Max Auctions:", maxAuctions);
        console.log("Proposal Validity:", proposalValidityDuration, "seconds");
        console.log("");
    }

    function _getAuctionInitParams(address nft, address manager)
        internal
        view
        returns (CuttingBoardDutchAuction.InitParams memory)
    {
        return CuttingBoardDutchAuction.InitParams({
            infrared: vm.envAddress("INFRARED_ADDRESS"),
            paymentToken: vm.envAddress("PAYMENT_TOKEN"),
            treasury: vm.envAddress("TREASURY_ADDRESS"),
            chef: vm.envAddress("CHEF_ADDRESS"),
            controlNFT: nft,
            controlManager: manager,
            governance: vm.envAddress("OWNER_ADDRESS"),
            keeper: vm.envAddress("KEEPER_ADDRESS"),
            auctionDuration: vm.envUint("AUCTION_DURATION"),
            allocationDuration: vm.envUint("ALLOCATION_DURATION"),
            maxAuctions: vm.envUint("MAX_AUCTIONS"),
            startingPriceMultiplier: vm.envUint("STARTING_PRICE_MULTIPLIER"),
            basePriceDivisor: vm.envUint("BASE_PRICE_DIVISOR"),
            minimumPrice: vm.envUint("MINIMUM_PRICE")
        });
    }
}
