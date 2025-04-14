// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Infrared, IInfrared} from "src/core/Infrared.sol";
import {InfraredV1_4} from "src/core/upgrades/InfraredV1_4.sol";
import {IInfraredV1_4} from "src/interfaces/upgrades/IInfraredV1_4.sol";
import {IInfraredV1_2} from "src/interfaces/upgrades/IInfraredV1_2.sol";
import {Errors} from "src/utils/Errors.sol";
import {BGT} from "@berachain/pol/BGT.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {IBGTIncentiveDistributor} from
    "lib/contracts/src/pol/interfaces/IBGTIncentiveDistributor.sol";

contract InfraredV1_4UpgradeTest is Test {
    // --- Constants ---
    string constant RPC_URL = "https://rpc.berachain.com";
    uint256 constant FORK_BLOCK = 3159231; // Block *before* V1.4 upgrade

    address constant INFRARED_PROXY_ADDRESS =
        0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126;
    address constant INFRARED_GOVERNANCE =
        0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
    address constant KEEPER_ADDRESS = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;
    address constant BGT_DISTRIBUTOR_ADDRESS_ON_NETWORK =
        0xBDDba144482049382eC79CadfA02f0fa0F462dE3;

    bytes constant KNOWN_INFRARED_VALIDATOR_PUBKEY =
        hex"88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f";
    // ** IMPORTANT: Replace with a REAL external validator pubkey from Berachain explorer at block FORK_BLOCK **
    bytes constant KNOWN_EXTERNAL_VALIDATOR_PUBKEY =
        hex"83199315cf36ebcf6a50bab572800d79324835fae832a3da9238f399c39feceb62de41339eab4cc8f79a6d4e6bcb825c";

    address constant BGT_ADDRESS = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
    address constant IBGT_ADDRESS = 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b;

    IInfraredV1_4 infraredV1_4Proxy;
    BGT bgt;
    IInfraredBGT ibgt;

    function setUp() public {
        uint256 fork = vm.createFork(RPC_URL, FORK_BLOCK);
        vm.selectFork(fork);

        InfraredV1_4 newImplementation = new InfraredV1_4();
        assertTrue(
            address(newImplementation) != address(0), "Deploy V1_4 failed"
        );

        vm.startPrank(INFRARED_GOVERNANCE);
        (bool success,) = INFRARED_PROXY_ADDRESS.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(newImplementation),
                ""
            )
        );
        require(success, "Upgrade call failed");
        vm.stopPrank();

        infraredV1_4Proxy = IInfraredV1_4(payable(INFRARED_PROXY_ADDRESS));
        bgt = BGT(BGT_ADDRESS);
        ibgt = IInfraredBGT(IBGT_ADDRESS); // Initialize iBGT instance

        // Sanity check validator statuses
        assertTrue(
            infraredV1_4Proxy.isInfraredValidator(
                KNOWN_INFRARED_VALIDATOR_PUBKEY
            ),
            "Known Infrared validator check failed"
        );
        require(
            KNOWN_EXTERNAL_VALIDATOR_PUBKEY.length > 10,
            "Please replace placeholder external pubkey"
        );
        assertFalse(
            infraredV1_4Proxy.isInfraredValidator(
                KNOWN_EXTERNAL_VALIDATOR_PUBKEY
            ),
            "External validator check failed - is it actually external?"
        );
    }

    /// Test boosting an EXTERNAL validator after upgrade succeeds (assuming library check removed).
    function testForkUpgradeBoostExternalValidator() public {
        // Arrange
        uint128 boostAmount = 100 ether; // Amount to boost

        // Check Infrared's current *unboosted* BGT balance on the fork
        uint256 availableBgt = bgt.unboostedBalanceOf(INFRARED_PROXY_ADDRESS);
        console.log("Infrared Proxy Unboosted BGT Balance:", availableBgt);
        require(
            availableBgt >= boostAmount,
            "Infrared contract does not have enough unboosted BGT on fork"
        );

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = KNOWN_EXTERNAL_VALIDATOR_PUBKEY;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = boostAmount;

        // Act & Assert
        vm.startPrank(KEEPER_ADDRESS);
        // Expect success and the event
        vm.expectEmit(true, false, false, true, INFRARED_PROXY_ADDRESS);
        emit IInfraredV1_2.QueuedBoosts(KEEPER_ADDRESS, pubkeys, amounts); // Emit via proxy instance

        infraredV1_4Proxy.queueBoosts(pubkeys, amounts); // This should now succeed
        vm.stopPrank();

        // Verify queue state in BGT contract
        (, uint128 boostedQueueBalance) = bgt.boostedQueue(
            INFRARED_PROXY_ADDRESS, KNOWN_EXTERNAL_VALIDATOR_PUBKEY
        );
        assertEq(
            boostedQueueBalance,
            boostAmount,
            "External queued boost balance mismatch"
        );
        console.log("Boosting external validator successful.");
    }

    /// Test boosting a REGISTERED Infrared validator still works after upgrade.
    function testForkUpgradeBoostRegisteredValidator() public {
        // Arrange
        uint128 boostAmount = 100 ether; // Use same amount for consistency check

        // Check Infrared's current *unboosted* BGT balance
        uint256 availableBgt = bgt.unboostedBalanceOf(INFRARED_PROXY_ADDRESS);
        console.log("Infrared Proxy Unboosted BGT Balance:", availableBgt);
        require(
            availableBgt >= boostAmount,
            "Infrared contract does not have enough unboosted BGT on fork"
        );

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = KNOWN_INFRARED_VALIDATOR_PUBKEY;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = boostAmount;

        // Act & Assert
        vm.startPrank(KEEPER_ADDRESS);
        vm.expectEmit(true, false, false, true, INFRARED_PROXY_ADDRESS);
        emit IInfraredV1_2.QueuedBoosts(KEEPER_ADDRESS, pubkeys, amounts); // Emit via proxy instance

        infraredV1_4Proxy.queueBoosts(pubkeys, amounts);
        vm.stopPrank();

        // Verify queue state in BGT contract
        (, uint128 boostedQueueBalance) = bgt.boostedQueue(
            INFRARED_PROXY_ADDRESS, KNOWN_INFRARED_VALIDATOR_PUBKEY
        );
        assertEq(
            boostedQueueBalance,
            boostAmount,
            "Registered queued boost balance mismatch"
        );
        console.log("Boosting registered validator successful.");
    }

    function testForkUpgradeClaimIncentives() public {
        // https://berascan.com/tx/0x1d68cc9b383d68c4822cc283987ff5f0550dc4aabc05dd4dac5fbd6b349b2edf
        IBGTIncentiveDistributor.Claim[] memory _claims =
            new IBGTIncentiveDistributor.Claim[](1);
        _claims[0].identifier = bytes32(
            0x092453b479b9c4a4b94a7431b17072f06b77a44504a6cbc688454104cc3f55d6
        );
        _claims[0].account = 0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126;
        _claims[0].amount = 805755269380254751;
        bytes32[] memory proofs = new bytes32[](8);
        proofs[0] = bytes32(
            0xb01434e94f82b435eb840e5f16d89e9acc4dab98c2cf86d52e577f6b1b8ee662
        );
        proofs[1] = bytes32(
            0x868893fcd0298be41f8b8ec533760197db248312adf49f43ba1a1e48b47dd456
        );
        proofs[2] = bytes32(
            0x50e8d266e1ecbb51fbcf3e468b09f7a357d3e7e406a19cc44cf55773826f1f34
        );
        proofs[3] = bytes32(
            0x6e75575479421b5ed59440d5d614c9539728d79ac81e42308feb8b272407b728
        );
        proofs[4] = bytes32(
            0xe67a397852575ebd5d52029df2a747e621ce95b4d7824deccfe48d3f89e583e0
        );
        proofs[5] = bytes32(
            0x151a8e9158c1b7e271cb0492eb44c82f38253c89892f10232976988d7a021f0c
        );
        proofs[6] = bytes32(
            0x942592da9f6697b93c0ae1fdf6bd65e06776734662a2d4285185b46bb6f7d7f7
        );
        proofs[7] = bytes32(
            0x46e53ef8db7fc823ebf31cb2b2bca539661b6b0cf3cd3f7894be6c8878e678e1
        );
        _claims[0].merkleProof = proofs;

        uint256 balBefore = ERC20(infraredV1_4Proxy.honey()).balanceOf(
            address(infraredV1_4Proxy)
        );

        vm.startPrank(KEEPER_ADDRESS);
        infraredV1_4Proxy.claimBGTIncentives(_claims);

        assertEq(
            ERC20(infraredV1_4Proxy.honey()).balanceOf(
                address(infraredV1_4Proxy)
            ),
            balBefore + _claims[0].amount
        );
    }
}
