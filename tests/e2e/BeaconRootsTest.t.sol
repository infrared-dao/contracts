// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "src/utils/Errors.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {IInfraredBERAWithdrawor} from
    "src/interfaces/upgrades/IInfraredBERAWithdrawor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {LibSort} from "solady/src/utils/LibSort.sol";
import {BeaconRootsVerify} from "src/utils/BeaconRootsVerify.sol";

import {HelperForkTest} from "./HelperForkTest.t.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {EndianHelper} from "src/utils/EndianHelper.sol";

contract BeaconRootsTest is HelperForkTest {
    using stdJson for string;

    function setUp() public virtual override {
        // Set custom parameters
        admin = address(this);
        keeper = address(0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0);
        infraredGovernance = address(0x182a31A27A0D39d735b31e80534CFE1fCd92c38f);

        // Load validator data from fixtures
        // _loadValidatorData();

        // Create and select mainnet fork
        // 6186162
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, 6187537);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();
    }

    /// @dev beaconroots only stores 8192 slot history, so fresh header is needed for live test
    function testRoot() public view {
        BeaconRootsVerify.BeaconBlockHeader memory header = BeaconRootsVerify
            .BeaconBlockHeader({
            slot: 6186162,
            proposerIndex: 58,
            parentRoot: bytes32(
                hex"c13a3770bc4ca791930b6cd57c47570b92d054cd74f8beb4a4e759f6b2a08c1f"
            ),
            stateRoot: bytes32(
                hex"965992e03de908bf2b7c4fea6ed49ea000a2c2cbbea217617ff0dfa27e3bab55"
            ),
            bodyRoot: bytes32(
                hex"773cf900d8a2f4fb8943c404ac4075e448dd0916b2aa9e85d05b886766df1ac3"
            )
        });

        // Mock a previously valid BEACON_ROOTS for unit tests
        bytes32 expectedRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);
        // ref: slot + 1 header parent_root: 0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1

        assertEq(
            expectedRoot,
            bytes32(
                0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1
            )
        );

        // uint256 timestamp =
        //     BeaconRootsVerify.calculateTimestampBySlot(header.slot + 1);

        bytes32 beaconRoot =
            BeaconRootsVerify.getParentBeaconBlockRoot(uint256(1749544180));

        assertEq(beaconRoot, expectedRoot);

        // ref
        // ├─ [705] BeaconRootsVerify::calculateTimestampBySlot(6186163 [6.186e6]) [delegatecall]
        // │   └─ ← [Return] 1749544180 [1.749e9]
        // ├─ [7875] BeaconRootsVerify::getParentBeaconBlockRoot(1749544180 [1.749e9]) [delegatecall]
        // │   ├─ [4320] 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02::00000000(0000000000000000000000000000000000000000000000006847ecf4) [staticcall]
        // │   │   └─ ← [Return] 0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1
        // │   └─ ← [Return] 0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1
        // ├─ [0] VM::assertEq(0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1, 0xba5ae37543b0f26fbffbfe51704e580c8cb2d894f7e03cd01084ee6e7bf4beb1) [staticcall]
        // │   └─ ← [Return]
        // └─ ← [Stop]
    }

    function testRoot2() public view {
        BeaconRootsVerify.BeaconBlockHeader memory header = BeaconRootsVerify
            .BeaconBlockHeader({
            slot: 6187535,
            proposerIndex: 57,
            parentRoot: bytes32(
                hex"35237cb83d9b1369689722669d80830d02165c4fb176906de4b7e8b6c88d2b11"
            ),
            stateRoot: bytes32(
                hex"0492d3af241e5defcfe5a6debbba605f46a032046dd132207586c3e717bc0430"
            ),
            bodyRoot: bytes32(
                hex"ab55c8e66bcc10fef955e19278ccb7de7730da5da2d22168b66f9c2b973bb2fc"
            )
        });

        // Mock a previously valid BEACON_ROOTS for unit tests
        bytes32 expectedRoot =
            BeaconRootsVerify.calculateBeaconHeaderMerkleRoot(header);

        // uint256 timestamp =
        //     BeaconRootsVerify.calculateTimestampBySlot(header.slot + 1);

        bytes32 beaconRoot =
            BeaconRootsVerify.getParentBeaconBlockRoot(uint256(1749546861));

        assertEq(beaconRoot, expectedRoot);
    }

    // json imports order structs alphabetically
    struct JsonHeader {
        bytes32 body_root;
        bytes32 parent_root;
        uint64 proposer_index;
        uint64 slot;
        bytes32 state_root;
    }
}
