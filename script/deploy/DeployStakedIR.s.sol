// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; // Use Unsafe for manual control; validations done separately
import {StakedIR} from "src/core/StakedIR.sol";

/// @notice Helper contract for CREATE2 proxy deployment
contract ProxyDeployer {
    using SafeTransferLib for ERC20;

    /// @notice Deploy a proxy using CREATE2 for deterministic address
    /// @param implementation The implementation contract address
    /// @param initData The initialization data to pass to the proxy
    /// @param salt The salt for CREATE2 deployment
    /// @return proxy The deployed proxy address
    function deployProxyCreate2(
        address _irToken,
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) external returns (address proxy) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        address predictedAddress =
            computeProxyAddress(address(this), implementation, initData, salt);

        // Pre-approve the deterministic address (safe from front-running)
        ERC20(_irToken).safeApprove(predictedAddress, 10 ether);

        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(proxy) { revert(0, 0) }
        }
    }

    /// @notice Compute the CREATE2 address for a proxy deployment
    /// @param deployer The address that will deploy the proxy
    /// @param implementation The implementation contract address
    /// @param initData The initialization data
    /// @param salt The salt for CREATE2
    /// @return predicted The predicted proxy address
    function computeProxyAddress(
        address deployer,
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) public pure returns (address predicted) {
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

contract DeployStakedIR is Script {
    using SafeTransferLib for ERC20;

    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    // Deployment salts for deterministic addresses
    bytes32 public constant STAKED_IR_SALT = keccak256("infrared.stakedIR.v1");
    bytes32 public constant IR_AUCTION_SALT = keccak256("infrared.irAuction.v1");
    bytes32 public constant IR_REWARD_DISTRIBUTOR_SALT =
        keccak256("infrared.irRewardDistributor.v1");

    /// @notice Compute the CREATE2 address for a proxy deployment (pure function for off-chain use)
    /// @param deployer The ProxyDeployer contract address that will deploy
    /// @param implementation The implementation contract address
    /// @param initData The initialization data
    /// @param salt The salt for CREATE2
    /// @return predicted The predicted proxy address
    function computeCreate2ProxyAddress(
        address deployer,
        address implementation,
        bytes memory initData,
        bytes32 salt
    ) public pure returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(bytecode))
        );

        predicted = address(uint160(uint256(hash)));
    }

    function validate() public {
        Options memory opts;
        // opts.unsafeAllow = "state-variable-assignment,state-variable-immutable,external-library-linking,struct-definition,enum-definition,constructor,delegatecall,selfdestruct,missing-public-upgradeto,internal-function-storage,missing-initializer,missing-initializer-call,duplicate-initializer-order,incorrect-initializer-order";  // Skips assembly/opcode validations if SafeTransferLib's assembly triggers dereferencer during opcode checks
        // opts.unsafeSkipStorageCheck = true;    // Skips storage layout if needed; manually verify below
        // opts.unsafeSkipProxyAdminCheck = true;
        // opts.unsafeAllowRenames =true;
        // opts.unsafeSkipAllChecks = true;

        // For the upgrade (InfraredV1_10)
        opts.referenceContract = "InfraredV1_9.sol";
        Upgrades.validateUpgrade("InfraredV1_10.sol", opts);
    }

    /// @notice Deploy StakedIR
    /// @param _irToken Address of the IR governance token
    function _deployStakedIR(address _irToken)
        internal
        returns (address stakedIR)
    {
        // Deploy ProxyDeployer helper for CREATE2 deployments
        ProxyDeployer deployer = new ProxyDeployer();

        {
            // 1. Deploy StakedIR with CREATE2 proxy (needs initial deposit for inflation protection)
            address stakedIRImpl = address(new StakedIR());

            bytes memory stakedIRInitData = abi.encodeWithSelector(
                StakedIR.initialize.selector, _irToken, SAFE
            );

            // Compute CREATE2 proxy address deterministically
            address predictedAddress = deployer.computeProxyAddress(
                address(deployer),
                stakedIRImpl,
                stakedIRInitData,
                STAKED_IR_SALT
            );

            // Pre-approve the deterministic address (safe from front-running)
            ERC20(_irToken).safeTransfer(address(deployer), 10 ether);

            // Deploy proxy using CREATE2
            stakedIR = deployer.deployProxyCreate2(
                _irToken, stakedIRImpl, stakedIRInitData, STAKED_IR_SALT
            );

            // Verify the deployed address matches prediction
            if (stakedIR != predictedAddress) {
                revert(
                    "StakedIR: deployed address does not match CREATE2 prediction"
                );
            }

            // Verify StakedIR initialization
            if (
                !StakedIR(stakedIR).hasRole(
                    StakedIR(stakedIR).GOVERNANCE_ROLE(), SAFE
                )
            ) {
                revert("Initialization front-run or failed: incorrect safe");
            }

            if (address(StakedIR(stakedIR).asset()) != _irToken) {
                revert("StakedIR initialization failed: incorrect asset");
            }
        }
    }

    /// @notice Deploy StakedIR with 10 IR tokens as security deposit
    /// @param _irToken Address of the IR governance token
    function deployStakedIR(address _irToken) external {
        if (_irToken == address(0)) {
            revert("Zero address");
        }

        vm.startBroadcast();

        _deployStakedIR(_irToken);

        vm.stopBroadcast();
    }

    /// @notice Helper to compute CREATE2 address (from Foundry's vm)
    function computeCreate2Address(
        uint256 salt,
        bytes32 codeHash,
        address deployer
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, salt, codeHash)
                    )
                )
            )
        );
    }

    /// @notice Helper to setup proxy
    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }
}
