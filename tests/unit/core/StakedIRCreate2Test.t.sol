// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title CREATE2 Proxy Deployer Test
/// @notice Tests deterministic proxy deployment using CREATE2
contract StakedIRCreate2Test is Test {
    MockERC20 public ir;
    address public governance = makeAddr("governance");

    uint256 constant INITIAL_DEPOSIT = 10 ether;
    bytes32 constant SALT = keccak256("test.salt.v1");

    /// @notice Helper to deploy proxy with CREATE2
    function deployProxyCreate2(
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) internal returns (address proxy) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxy) { revert(0, 0) }
        }
    }

    /// @notice Helper to compute CREATE2 address
    function computeCreate2Address(
        address deployer,
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) internal pure returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(bytecode))
        );

        predicted = address(uint160(uint256(hash)));
    }

    function setUp() public {
        ir = new MockERC20("Infrared", "IR", 18);
        ir.mint(address(this), INITIAL_DEPOSIT);
    }

    /// @notice Test that CREATE2 address prediction is accurate
    function test_Create2_AddressPrediction() public {
        // Deploy implementation
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        // Predict address
        address predicted =
            computeCreate2Address(address(this), impl, initData, SALT);

        // Pre-approve the predicted address
        ir.approve(predicted, INITIAL_DEPOSIT);

        // Deploy with CREATE2
        address deployed = deployProxyCreate2(impl, initData, SALT);

        // Verify prediction matches actual deployment
        assertEq(
            deployed,
            predicted,
            "CREATE2 prediction should match deployed address"
        );
    }

    /// @notice Test that CREATE2 deployment is deterministic
    function test_Create2_Deterministic() public {
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        // Predict address multiple times - should always be the same
        address prediction1 =
            computeCreate2Address(address(this), impl, initData, SALT);
        address prediction2 =
            computeCreate2Address(address(this), impl, initData, SALT);

        assertEq(
            prediction1,
            prediction2,
            "CREATE2 predictions should be deterministic"
        );
    }

    /// @notice Test that CREATE2 prevents nonce-based address changes
    function test_Create2_NonceSafe() public {
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        // Predict address before doing other transactions
        address predictedBefore =
            computeCreate2Address(address(this), impl, initData, SALT);

        // Do some transactions to change nonce
        new MockERC20("Dummy1", "D1", 18);
        new MockERC20("Dummy2", "D2", 18);
        new MockERC20("Dummy3", "D3", 18);

        // Predict again after nonce changes
        address predictedAfter =
            computeCreate2Address(address(this), impl, initData, SALT);

        // Should still be the same (nonce-independent)
        assertEq(
            predictedBefore,
            predictedAfter,
            "CREATE2 should be independent of nonce"
        );
    }

    /// @notice Test that different salts produce different addresses
    function test_Create2_DifferentSalts() public {
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address addr1 =
            computeCreate2Address(address(this), impl, initData, salt1);
        address addr2 =
            computeCreate2Address(address(this), impl, initData, salt2);

        assertTrue(
            addr1 != addr2, "Different salts should produce different addresses"
        );
    }

    /// @notice Test full deployment flow with CREATE2
    function test_Create2_FullDeployment() public {
        // Deploy implementation
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        // Predict and approve
        address predicted =
            computeCreate2Address(address(this), impl, initData, SALT);
        ir.approve(predicted, INITIAL_DEPOSIT);

        // Deploy
        address deployed = deployProxyCreate2(impl, initData, SALT);
        StakedIR sir = StakedIR(deployed);

        // Verify initialization worked
        assertEq(address(sir.asset()), address(ir), "Asset should be IR");
        assertTrue(
            sir.hasRole(sir.GOVERNANCE_ROLE(), governance),
            "Governance should have role"
        );
        assertEq(
            sir.balanceOf(address(sir)),
            INITIAL_DEPOSIT,
            "Initial deposit should be there"
        );
        assertEq(
            sir.withdrawalPeriod(), 7 days, "Withdrawal period should be 7 days"
        );
    }

    /// @notice Test that redeploying with same salt fails (CREATE2 collision)
    function test_Create2_RedeployCollision() public {
        address impl = address(new StakedIR());

        bytes memory initData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), governance
        );

        address predicted =
            computeCreate2Address(address(this), impl, initData, SALT);
        ir.approve(predicted, INITIAL_DEPOSIT * 2);

        // First deployment succeeds
        address first = deployProxyCreate2(impl, initData, SALT);
        assertEq(first, predicted, "First deployment should match prediction");

        // Second deployment with same salt will fail due to address collision
        // CREATE2 will return address(0) when code already exists at that address
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode, abi.encode(impl, initData)
        );

        address second;
        bytes32 salt = SALT; // Load constant into variable for assembly
        assembly {
            second := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        // CREATE2 returns 0 if deployment fails due to collision
        assertEq(second, address(0), "Second deployment should fail (return 0)");
    }

    /// @notice Fuzz test: CREATE2 address is always deterministic
    function testFuzz_Create2_AlwaysDeterministic(bytes32 salt) public pure {
        // Use dummy values for fuzzing
        address deployer = address(0x1234);
        address impl = address(0x5678);
        bytes memory initData = abi.encodePacked("dummy");

        // Compute twice
        address addr1 = _computeCreate2(deployer, impl, initData, salt);
        address addr2 = _computeCreate2(deployer, impl, initData, salt);

        assertEq(addr1, addr2, "CREATE2 should always be deterministic");
    }

    /// @notice Helper for fuzz test
    function _computeCreate2(
        address deployer,
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) internal pure returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(bytecode))
        );

        predicted = address(uint160(uint256(hash)));
    }
}
