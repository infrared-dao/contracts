// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Testing Libraries.
import "forge-std/Test.sol";

// Mocks
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";

// external
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdraworLite} from
    "src/depreciated/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";

contract InfraredBERABaseTest is Test {
    // Minimal IBERA V0 setup - only what's needed for testing

    // Mock contracts
    MockInfrared public infrared;
    MockERC20 public mockIBGT;
    MockERC20 public mockIR;
    MockERC20 public mockRewardsFactory;

    // IBERA V0 contracts
    InfraredBERA public iberaV0;
    InfraredBERADepositor public depositorV0;
    InfraredBERAWithdraworLite public withdraworLite;
    InfraredBERAFeeReceivor public receivor;

    // Test setup
    BeaconDeposit public depositContract;
    bytes public constant withdrawPrecompile = abi.encodePacked(
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff5f556101f480602d5f395ff3"
    );

    // Test addresses
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public infraredGovernance = makeAddr("infraredGovernance");
    address public keeper = makeAddr("keeper");

    // Validator setup
    address public validator0 = makeAddr("v0");
    address public validator1 = makeAddr("v1");
    bytes public pubkey0 = abi.encodePacked(bytes32("v0"), bytes16("")); // must be len 48
    bytes public pubkey1 = abi.encodePacked(bytes32("v1"), bytes16(""));
    bytes public signature0 =
        abi.encodePacked(bytes32("v0"), bytes32(""), bytes32("")); // must be len 96
    bytes public signature1 =
        abi.encodePacked(bytes32("v1"), bytes32(""), bytes32(""));

    function setUp() public virtual {
        // Deploy mock contracts
        mockIBGT = new MockERC20("MockIBGT", "mIBGT", 18);
        mockIR = new MockERC20("MockIR", "mIR", 18);
        mockRewardsFactory = new MockERC20("MockRewardsFactory", "mRF", 18);

        // Deploy mock infrared
        infrared = new MockInfrared(
            address(mockIBGT), address(mockIR), address(mockRewardsFactory)
        );

        // Deploy beacon deposit contract
        depositContract = new BeaconDeposit();

        // Deploy IBERA V0 contracts as proxies
        iberaV0 = InfraredBERA(_deployProxy(address(new InfraredBERA())));
        depositorV0 = InfraredBERADepositor(
            _deployProxy(address(new InfraredBERADepositor()))
        );
        withdraworLite = InfraredBERAWithdraworLite(
            payable(_deployProxy(address(new InfraredBERAWithdraworLite())))
        );
        receivor = InfraredBERAFeeReceivor(
            payable(_deployProxy(address(new InfraredBERAFeeReceivor())))
        );

        // Initialize contracts
        depositorV0.initialize(
            infraredGovernance,
            keeper,
            address(iberaV0),
            address(depositContract)
        );
        withdraworLite.initialize(infraredGovernance, keeper, address(iberaV0));
        receivor.initialize(
            infraredGovernance, keeper, address(iberaV0), address(infrared)
        );

        // Initialize IBERA with initial deposit to avoid inflation attack
        iberaV0.initialize{value: 10 ether}(
            infraredGovernance,
            keeper,
            address(infrared),
            address(depositorV0),
            address(withdraworLite),
            address(receivor)
        );

        // Setup withdraw precompile
        address WITHDRAW_PRECOMPILE = withdraworLite.WITHDRAW_PRECOMPILE();
        vm.etch(WITHDRAW_PRECOMPILE, withdrawPrecompile);

        // Setup test users
        vm.deal(alice, 20000 ether);
        vm.deal(bob, 20000 ether);

        // Add validators to mock infrared
        infrared.addValidator(validator0, pubkey0);
        infrared.addValidator(validator1, pubkey1);

        // Set fee divisor to 0 (no fees)
        vm.prank(infraredGovernance);
        iberaV0.setFeeDivisorShareholders(0);
    }

    function _deployProxy(address implementation) internal returns (address) {
        return address(new ERC1967Proxy(implementation, ""));
    }

    function testSetUp() public virtual {
        assertTrue(
            address(depositorV0) != address(0), "depositor == address(0)"
        );
        assertTrue(
            address(withdraworLite) != address(0),
            "withdraworLite == address(0)"
        );
        assertTrue(address(receivor) != address(0), "receivor == address(0)");

        assertEq(alice.balance, 20000 ether);
        assertEq(bob.balance, 20000 ether);

        assertTrue(
            iberaV0.hasRole(iberaV0.DEFAULT_ADMIN_ROLE(), infraredGovernance)
        );
        assertTrue(iberaV0.keeper(keeper));
        assertTrue(iberaV0.governor(infraredGovernance));

        address DEPOSIT_CONTRACT = depositorV0.DEPOSIT_CONTRACT();
        assertTrue(DEPOSIT_CONTRACT.code.length > 0);

        address WITHDRAW_PRECOMPILE = withdraworLite.WITHDRAW_PRECOMPILE();
        assertTrue(WITHDRAW_PRECOMPILE.code.length > 0);
    }
}
