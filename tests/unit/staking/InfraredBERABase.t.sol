// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Testing Libraries.
import "forge-std/Test.sol";

// Mocks
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";

import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {Helper} from "tests/unit/core/Infrared/Helper.sol";

contract InfraredBERABaseTest is Helper {
    BeaconDeposit public depositContract;
    bytes public constant withdrawPrecompile = abi.encodePacked(
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f556101f480602d5f395ff33373fffffffffffffffffffffffffffffffffffffffe1460c7573615156028575f545f5260205ff35b36603814156101f05760115f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff146101f057600182026001905f5b5f821115608057810190830284830290049160010191906065565b9093900434106101f057600154600101600155600354806003026004013381556001015f35815560010160203590553360601b5f5260385f601437604c5fa0600101600355005b6003546002548082038060101160db575060105b5f5b81811461017f5780604c02838201600302600401805490600101805490600101549160601b83528260140152807fffffffffffffffffffffffffffffffff0000000000000000000000000000000016826034015260401c906044018160381c81600701538160301c81600601538160281c81600501538160201c81600401538160181c81600301538160101c81600201538160081c81600101535360010160dd565b9101809214610191579060025561019c565b90505f6002555f6003555b5f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff14156101c957505f5b6001546002828201116101de5750505f6101e4565b01600290035b5f555f600155604c025ff35b5f5ffd"
    );

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    address public validator0 = makeAddr("v0");
    address public validator1 = makeAddr("v1");
    bytes public pubkey0 = abi.encodePacked(bytes32("v0"), bytes16("")); // must be len 48
    bytes public pubkey1 = abi.encodePacked(bytes32("v1"), bytes16(""));
    bytes public signature0 =
        abi.encodePacked(bytes32("v0"), bytes32(""), bytes32("")); // must be len 96
    bytes public signature1 =
        abi.encodePacked(bytes32("v1"), bytes32(""), bytes32(""));

    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        // deploy new implementation
        withdrawor = new InfraredBERAWithdrawor();

        // perform upgrade
        vm.prank(infraredGovernance);
        (bool success,) = address(withdraworLite).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(withdrawor), ""
            )
        );
        require(success, "Upgrade failed");

        // point at proxy
        withdrawor = InfraredBERAWithdrawor(payable(address(withdraworLite)));

        // initialize
        vm.prank(infraredGovernance);
        withdrawor.initializeV2(
            address(claimor), 0x00A3ca265EBcb825B45F985A16CEFB49958cE017
        );

        // etch deposit contract at depositor constant deposit contract address
        // depositContract = new BeaconDeposit();
        // address DEPOSIT_CONTRACT = depositor.DEPOSIT_CONTRACT();
        // vm.etch(DEPOSIT_CONTRACT, address(depositContract).code);

        // etch withdraw precompile at withdraw precompile contract address
        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        vm.etch(WITHDRAW_PRECOMPILE, withdrawPrecompile);

        // deal to alice and bob + approve ibera to spend for them
        vm.deal(alice, 20000 ether);
        vm.deal(bob, 20000 ether);
        vm.prank(alice);
        ibera.approve(address(ibera), type(uint256).max);
        vm.prank(bob);
        ibera.approve(address(ibera), type(uint256).max);

        // add validators to infrared
        ValidatorTypes.Validator memory infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey0, addr: address(infrared)});
        infraredValidators.push(infraredValidator);
        infraredValidator =
            ValidatorTypes.Validator({pubkey: pubkey1, addr: address(infrared)});
        infraredValidators.push(infraredValidator);

        vm.startPrank(infraredGovernance);
        infrared.addValidators(infraredValidators);

        ibera.setFeeDivisorShareholders(0);
        vm.stopPrank();
    }

    function testSetUp() public virtual {
        assertTrue(address(depositor) != address(0), "depositor == address(0)");
        assertTrue(
            address(withdrawor) != address(0), "withdrawor == address(0)"
        );
        assertTrue(address(claimor) != address(0), "claimor == address(0)");
        assertTrue(address(receivor) != address(0), "receivor == address(0)");

        assertEq(ibera.allowance(alice, address(ibera)), type(uint256).max);
        assertEq(ibera.allowance(bob, address(ibera)), type(uint256).max);
        assertEq(alice.balance, 20000 ether);
        assertEq(bob.balance, 20000 ether);

        assertTrue(infrared.isInfraredValidator(pubkey0));
        assertTrue(infrared.isInfraredValidator(pubkey1));

        assertTrue(
            ibera.hasRole(ibera.DEFAULT_ADMIN_ROLE(), infraredGovernance)
        );
        assertTrue(ibera.keeper(keeper));
        assertTrue(ibera.governor(infraredGovernance));

        address DEPOSIT_CONTRACT = depositor.DEPOSIT_CONTRACT();
        assertTrue(DEPOSIT_CONTRACT.code.length > 0);

        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        assertTrue(WITHDRAW_PRECOMPILE.code.length > 0);
    }
}
