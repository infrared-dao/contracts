// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; // Use Unsafe for manual control; validations done separately
import {InfraredV1_8} from "src/depreciated/core/InfraredV1_8.sol";
import {BribeCollectorV1_4} from "src/core/BribeCollectorV1_4.sol";

contract UpgradeInfraredV1_8 is BatchScript {
    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    function validate() public {
        Options memory opts;
        // opts.unsafeAllow = "state-variable-assignment,state-variable-immutable,external-library-linking,struct-definition,enum-definition,constructor,delegatecall,selfdestruct,missing-public-upgradeto,internal-function-storage,missing-initializer,missing-initializer-call,duplicate-initializer-call,incorrect-initializer-order";  // Skips assembly/opcode validations if SafeTransferLib's assembly triggers dereferencer during opcode checks
        // opts.unsafeSkipStorageCheck = true;    // Skips storage layout if needed; manually verify below
        // opts.unsafeSkipProxyAdminCheck = true;
        // opts.unsafeAllowRenames =true;
        // opts.unsafeSkipAllChecks = true;

        // For the upgrade (BribeCollectorV1_3)
        opts.referenceContract = "BribeCollectorV1_3.sol";
        Upgrades.validateUpgrade("BribeCollectorV1_4.sol", opts);

        // For the upgrade (InfraredV1_8)
        opts.referenceContract = "InfraredV1_7.sol";
        Upgrades.validateUpgrade("InfraredV1_8.sol", opts);
    }

    function deployBribeCollectorImp()
        external
        returns (address newBribeCollectorImp)
    {
        vm.startBroadcast();
        newBribeCollectorImp = address(new BribeCollectorV1_4());
        vm.stopBroadcast();
    }

    function deployInfraredImp() external returns (address newInfraredImp) {
        vm.startBroadcast();
        newInfraredImp = address(new InfraredV1_8());
        vm.stopBroadcast();
    }

    function upgradeInfraredTestnet(
        address _bribeCollectorProxy,
        address _infraredProxy
    ) external {
        if (_infraredProxy == address(0) || _bribeCollectorProxy == address(0))
        {
            revert();
        }

        vm.startBroadcast();

        address newBribeCollectorImp = address(new BribeCollectorV1_4());
        address newInfraredImp = address(new InfraredV1_8());
        BribeCollectorV1_4(_bribeCollectorProxy).upgradeToAndCall(
            newBribeCollectorImp, ""
        );
        InfraredV1_8(payable(_infraredProxy)).upgradeToAndCall(
            newInfraredImp, ""
        );

        vm.stopBroadcast();
    }

    function upgradeInfrared(
        bool _send,
        address _bribeCollectorProxy,
        address _infraredProxy,
        address newInfraredImp,
        address newBribeCollectorImp
    ) external isBatch(SAFE) {
        if (
            _infraredProxy == address(0) || newInfraredImp == address(0)
                || newBribeCollectorImp == address(0)
        ) {
            revert();
        }

        // Call upgrade and initialize for bribe collector
        bytes memory upgradeData = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", newBribeCollectorImp, ""
        );
        addToBatch(_bribeCollectorProxy, 0, upgradeData);

        // Call upgrade and initialize for infrared
        upgradeData = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", newInfraredImp, ""
        );
        addToBatch(_infraredProxy, 0, upgradeData);

        executeBatch(_send);
    }

    // Helper to compute CREATE2 address (from Foundry's vm)
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

    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }
}
