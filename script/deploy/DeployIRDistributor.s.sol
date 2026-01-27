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
import {InfraredV1_10} from "src/core/InfraredV1_10.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {IRAuction} from "src/periphery/IRAuction.sol";
import {IRRewardDistributor} from "src/periphery/IRRewardDistributor.sol";

contract DeployDistributor is Script {
    using SafeTransferLib for ERC20;

    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    // Deployment salts for deterministic addresses
    bytes32 public constant STAKED_IR_SALT = keccak256("infrared.stakedIR.v1");
    bytes32 public constant IR_AUCTION_SALT = keccak256("infrared.irAuction.v1");
    bytes32 public constant IR_REWARD_DISTRIBUTOR_SALT =
        keccak256("infrared.irRewardDistributor.v1");

    /// @notice Deploy IRRewardDistributor
    /// @param _irToken Address of the IR governance token
    /// @param _infrared Address of the Infrared protocol proxy
    /// @param _minIBGTAllocation Minimum allocation to iBGT vault in basis points (e.g., 2000 = 20%)
    function _deployDistributor(
        address _irToken,
        address _infrared,
        uint256 _minIBGTAllocation
    ) internal returns (address irRewardDistributor) {
        {
            // 3. Deploy IRRewardDistributor with proxy
            address irRewardDistributorImpl = address(new IRRewardDistributor());
            bytes memory irRewardDistributorInitData = abi.encodeWithSelector(
                IRRewardDistributor.initialize.selector,
                _infrared,
                SAFE,
                _irToken,
                _minIBGTAllocation
            );
            ERC1967Proxy irRewardDistributorProxy = new ERC1967Proxy(
                irRewardDistributorImpl, irRewardDistributorInitData
            );
            irRewardDistributor = address(irRewardDistributorProxy);
        }

        // Verify IRRewardDistributor initialization
        if (
            !IRRewardDistributor(irRewardDistributor).hasRole(
                IRRewardDistributor(irRewardDistributor).GOVERNANCE_ROLE(), SAFE
            )
        ) {
            revert("Initialization front-run or failed: incorrect safe");
        }
        if (IRRewardDistributor(irRewardDistributor).IR_TOKEN() != _irToken) {
            revert(
                "IRRewardDistributor initialization failed: incorrect IR_TOKEN"
            );
        }
    }

    /// @notice Deploy Distributor
    /// @param _infraredProxy Address of the Infrared proxy
    /// @param _irToken Address of the IR governance token
    /// @param _minIBGTAllocation Minimum allocation to iBGT vault in basis points (e.g., 2000 = 20%)
    function deployDistributor(
        address _infraredProxy,
        address _irToken,
        uint256 _minIBGTAllocation
    ) external {
        vm.startBroadcast();

        _deployDistributor(_irToken, _infraredProxy, _minIBGTAllocation);

        vm.stopBroadcast();
    }

    /// @notice Helper to setup proxy
    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }
}
