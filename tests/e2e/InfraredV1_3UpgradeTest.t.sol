// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import {Infrared, IInfrared} from "src/core/Infrared.sol";
import {InfraredV1_2} from "src/core/upgrades/InfraredV1_2.sol";
import {InfraredV1_3, IInfraredV1_3} from "src/core/upgrades/InfraredV1_3.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

contract InfraredV1_3UpgradeTest is Test {
    string constant RPC_URL = "https://rpc.berachain.com";

    Infrared public infrared;
    InfraredV1_3 public newInfrared;

    uint256 internal fork;

    IBeraChef chef;

    address public infraredGovernance =
        0x182a31A27A0D39d735b31e80534CFE1fCd92c38f;
    address public keeper = 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7;
    address public user = 0x9AF55da5Aac157d36e9034A045Cc5eFc34A7e2F3;

    bytes public validatorPubkey =
        hex"88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f";
    uint96 public testCommissionRate = 10000; // 100%

    function setUp() public {
        // Create fork
        fork = vm.createFork(RPC_URL, 2712485);
        vm.selectFork(fork);

        // Get the existing Infrared contract
        infrared = Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));

        // Deploy V1_3 contract (the upgrade)
        newInfrared = new InfraredV1_3();

        // Perform the upgrade
        vm.startPrank(infraredGovernance);
        (bool success,) = address(infrared).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(newInfrared), ""
            )
        );
        require(success, "Upgrade failed");
        vm.stopPrank();

        // Now point newInfrared to the proxy address
        newInfrared = InfraredV1_3(payable(address(infrared)));

        require(
            newInfrared.isInfraredValidator(validatorPubkey),
            "Validator not added"
        );

        chef = newInfrared.chef();
    }

    function testQueueValCommission_OnlyGovernor() public {
        // Attempt as non-governor should fail
        vm.prank(user);
        vm.expectRevert();
        newInfrared.queueValCommission(validatorPubkey, testCommissionRate);

        uint32 _block = uint32(block.number);

        // Attempt as governor should succeed
        vm.prank(infraredGovernance);
        newInfrared.queueValCommission(validatorPubkey, testCommissionRate);

        IBeraChef.QueuedCommissionRateChange memory comm =
            chef.getValQueuedCommissionOnIncentiveTokens(validatorPubkey);

        assertEq(comm.commissionRate, testCommissionRate);
        assertEq(comm.blockNumberLast, _block);
    }

    function testQueueValCommission_InvalidValidator() public {
        // Create an invalid pubkey
        bytes memory invalidPubkey =
            hex"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

        // Attempt with invalid validator pubkey should fail, even as governor
        vm.prank(infraredGovernance);
        vm.expectRevert();
        newInfrared.queueValCommission(invalidPubkey, testCommissionRate);
    }

    function testActivateQueuedValCommission_AnyoneCanCall() public {
        // first queue
        vm.prank(infraredGovernance);
        newInfrared.queueValCommission(validatorPubkey, testCommissionRate);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1 days / 2);

        // Anyone can call activate (including regular users)
        vm.prank(user);
        newInfrared.activateQueuedValCommission(validatorPubkey);

        assertEq(
            chef.getValCommissionOnIncentiveTokens(validatorPubkey),
            uint96(testCommissionRate)
        );
    }

    function testActivateQueuedValCommission_InvalidValidator() public {
        // Create an invalid pubkey
        bytes memory invalidPubkey =
            hex"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

        // Attempt with invalid validator pubkey should fail
        vm.prank(user);
        vm.expectRevert();
        newInfrared.activateQueuedValCommission(invalidPubkey);
    }

    function testQueueValCommission_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ValidatorCommissionQueued(
            infraredGovernance, validatorPubkey, testCommissionRate
        );

        vm.prank(infraredGovernance);
        newInfrared.queueValCommission(validatorPubkey, testCommissionRate);
    }

    function testActivateQueuedValCommission_EmitsEvent() public {
        // first queue
        vm.prank(infraredGovernance);
        newInfrared.queueValCommission(validatorPubkey, testCommissionRate);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1 days / 2);

        vm.expectEmit(true, true, true, true);
        emit ValidatorCommissionActivated(
            user, validatorPubkey, testCommissionRate
        );

        vm.prank(user);
        newInfrared.activateQueuedValCommission(validatorPubkey);
    }

    // Test events not directly accessible from contract, declare them here
    event ValidatorCommissionQueued(
        address indexed operator, bytes pubkey, uint96 commissionRate
    );
    event ValidatorCommissionActivated(
        address indexed operator, bytes pubkey, uint96 commissionRate
    );
}
