// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {InfraredV1_5} from "src/core/upgrades/InfraredV1_5.sol";
import {BatchClaimer} from "src/periphery/BatchClaimer.sol";

contract BatchClaimerTest is Test {
    BatchClaimer public multi;
    uint256 blockNumber = 5919695;
    string constant MAINNET_RPC_URL = "https://rpc.berachain.com";
    uint256 mainnetFork;
    InfraredV1_5 internal constant infrared =
        InfraredV1_5(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    address gov = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL, blockNumber);
        vm.selectFork(mainnetFork);
        multi = new BatchClaimer();
        vm.prank(gov);
        infrared.grantRole(keccak256("KEEPER_ROLE"), address(multi));
    }

    function test_Send() public {
        address user = 0x6767Fb0993bDA99cE11b7A6D5De52Fd78183850c;
        address asset = 0x68Cac522833F38E088EEC5e356956C02F0268063;
        address[] memory assets = new address[](1);
        assets[0] = asset;

        multi.batchClaim(user, assets);
    }
}
