// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";
import {CuttingBoardSyndicate} from "src/periphery/CuttingBoardSyndicate.sol";
import {CuttingBoardSlotNFT} from "src/periphery/CuttingBoardSlotNFT.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCuttingBoardSyndicate
 * @notice Deploys the CuttingBoardSyndicate (UUPS proxy) and CuttingBoardSlotNFT
 * @dev Deployment order:
 *      1. Pre-compute all contract addresses using nonces
 *      2. CuttingBoardSyndicate implementation
 *      3. CuttingBoardSyndicate proxy (at pre-computed address)
 *      4. CuttingBoardSlotNFT (with syndicate proxy address)
 *      5. Call setSlotNFT on syndicate proxy
 *
 * Prerequisites:
 *   - CuttingBoardDutchAuction, CuttingBoardManager, and CuttingBoardNFT
 *     must already be deployed
 *
 * Required environment variables:
 *   PRIVATE_KEY, OWNER_ADDRESS, DUTCH_AUCTION_ADDRESS, CONTROL_MANAGER_ADDRESS,
 *   CONTROL_NFT_ADDRESS, CHEF_ADDRESS, KEEPER_ADDRESS, MIN_SLOT_WEIGHT
 *
 * Optional:
 *   SLOT_NFT_BASE_URI
 */
contract DeployCuttingBoardSyndicate is BatchScript {
    address constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;

    function run() external isBatch(SAFE) {
        _validateAndPrintConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Step 1: Pre-compute all contract addresses using nonces
        console.log("Step 1: Pre-computing contract addresses...");
        uint64 currentNonce = vm.getNonce(deployer);

        // Deployment order and nonces:
        // nonce + 0: Syndicate implementation
        // nonce + 1: Syndicate proxy
        // nonce + 2: SlotNFT
        address predictedSyndicateImpl =
            vm.computeCreateAddress(deployer, currentNonce);
        address predictedSyndicateProxy =
            vm.computeCreateAddress(deployer, currentNonce + 1);
        address predictedSlotNFT =
            vm.computeCreateAddress(deployer, currentNonce + 2);

        console.log("Predicted Syndicate impl:", predictedSyndicateImpl);
        console.log("Predicted Syndicate proxy:", predictedSyndicateProxy);
        console.log("Predicted SlotNFT:", predictedSlotNFT);

        // Step 2: Deploy Syndicate implementation
        console.log("");
        console.log("Step 2: Deploying CuttingBoardSyndicate implementation...");
        CuttingBoardSyndicate syndicateImpl = new CuttingBoardSyndicate();
        console.log(
            "CuttingBoardSyndicate implementation:", address(syndicateImpl)
        );
        require(
            address(syndicateImpl) == predictedSyndicateImpl,
            "Syndicate impl address mismatch"
        );

        // Step 3: Deploy Syndicate proxy
        CuttingBoardSyndicate syndicate;
        {
            console.log("");
            console.log("Step 3: Deploying CuttingBoardSyndicate proxy...");
            bytes memory initData = abi.encodeCall(
                CuttingBoardSyndicate.initialize, _getSyndicateInitParams()
            );
            ERC1967Proxy syndicateProxy =
                new ERC1967Proxy(address(syndicateImpl), initData);
            syndicate = CuttingBoardSyndicate(address(syndicateProxy));
        }
        console.log(
            "CuttingBoardSyndicate proxy deployed at:", address(syndicate)
        );
        require(
            address(syndicate) == predictedSyndicateProxy,
            "Syndicate proxy address mismatch"
        );
        require(
            syndicate.hasRole(syndicate.DEFAULT_ADMIN_ROLE(), owner),
            "Wrong syndicate admin"
        );
        require(
            syndicate.hasRole(syndicate.GOVERNANCE_ROLE(), owner),
            "Wrong syndicate governance"
        );

        // Step 4: Deploy SlotNFT
        CuttingBoardSlotNFT slotNFT;
        {
            console.log("");
            console.log("Step 4: Deploying CuttingBoardSlotNFT...");
            string memory baseURI = vm.envOr("SLOT_NFT_BASE_URI", string(""));
            slotNFT =
                new CuttingBoardSlotNFT(address(syndicate), owner, baseURI);
        }
        console.log("CuttingBoardSlotNFT deployed at:", address(slotNFT));
        require(
            address(slotNFT) == predictedSlotNFT, "SlotNFT address mismatch"
        );

        vm.stopBroadcast();

        // Step 5: Set SlotNFT on Syndicate
        console.log("");
        console.log("Step 5: Setting SlotNFT on Syndicate...");
        // syndicate.setSlotNFT(address(slotNFT));
        bytes memory data =
            abi.encodeWithSignature("setSlotNFT(address)", address(slotNFT));
        addToBatch(address(syndicate), 0, data);
        executeBatch(true);
        console.log("SlotNFT tx sent to safe for signing successfully");

        // Print deployment summary
        console.log("");
        console.log("================================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("================================================");
        console.log("CuttingBoardSyndicate:  ", address(syndicate));
        console.log("CuttingBoardSlotNFT:    ", address(slotNFT));
        console.log("");
    }

    function _validateAndPrintConfig() internal view {
        address dutchAuction = vm.envAddress("DUTCH_AUCTION_ADDRESS");
        address controlManager = vm.envAddress("CONTROL_MANAGER_ADDRESS");
        address controlNFT = vm.envAddress("CONTROL_NFT_ADDRESS");
        address chef = vm.envAddress("CHEF_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        uint256 minSlotWeight = vm.envUint("MIN_SLOT_WEIGHT");

        require(dutchAuction != address(0), "DUTCH_AUCTION_ADDRESS not set");
        require(controlManager != address(0), "CONTROL_MANAGER_ADDRESS not set");
        require(controlNFT != address(0), "CONTROL_NFT_ADDRESS not set");
        require(chef != address(0), "CHEF_ADDRESS not set");
        require(owner != address(0), "OWNER_ADDRESS not set");
        require(keeper != address(0), "KEEPER_ADDRESS not set");

        console.log("================================================");
        console.log("DEPLOYING CUTTING BOARD SYNDICATE SYSTEM");
        console.log("================================================");
        console.log("Dutch Auction:", dutchAuction);
        console.log("Control Manager:", controlManager);
        console.log("Control NFT:", controlNFT);
        console.log("BeraChef:", chef);
        console.log("Owner:", owner);
        console.log("Keeper:", keeper);
        console.log("Min Slot Weight:", minSlotWeight, "(0 = default 100)");
        console.log("");
    }

    function _getSyndicateInitParams()
        internal
        view
        returns (CuttingBoardSyndicate.InitParams memory)
    {
        return CuttingBoardSyndicate.InitParams({
            dutchAuction: vm.envAddress("DUTCH_AUCTION_ADDRESS"),
            controlManager: vm.envAddress("CONTROL_MANAGER_ADDRESS"),
            controlNFT: vm.envAddress("CONTROL_NFT_ADDRESS"),
            chef: vm.envAddress("CHEF_ADDRESS"),
            governance: vm.envAddress("OWNER_ADDRESS"),
            keeper: vm.envAddress("KEEPER_ADDRESS"),
            minSlotWeight: uint96(vm.envUint("MIN_SLOT_WEIGHT"))
        });
    }
}
