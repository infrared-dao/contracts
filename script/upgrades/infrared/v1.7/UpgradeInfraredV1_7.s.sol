// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; // Use Unsafe for manual control; validations done separately
import {InfraredV1_7} from "src/depreciated/core/InfraredV1_7.sol";
import {HarvestBaseCollector} from
    "src/depreciated/staking/HarvestBaseCollector.sol";

contract UpgradeInfraredV1_7 is BatchScript {
    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    function validate() public {
        Options memory opts;
        // opts.unsafeAllow = "state-variable-assignment,state-variable-immutable,external-library-linking,struct-definition,enum-definition,constructor,delegatecall,selfdestruct,missing-public-upgradeto,internal-function-storage,missing-initializer,missing-initializer-call,duplicate-initializer-call,incorrect-initializer-order";  // Skips assembly/opcode validations if SafeTransferLib's assembly triggers dereferencer during opcode checks
        // opts.unsafeSkipStorageCheck = true;    // Skips storage layout if needed; manually verify below
        // opts.unsafeSkipProxyAdminCheck = true;
        // opts.unsafeAllowRenames =true;
        // opts.unsafeSkipAllChecks = true;

        // For the new implementation (HarvestBaseCollector)
        Upgrades.validateImplementation(
            "HarvestBaseCollector.sol:HarvestBaseCollector", opts
        );

        // For the upgrade (InfraredV1_7)
        opts.referenceContract = "InfraredV1_5.sol";
        Upgrades.validateUpgrade("InfraredV1_7.sol", opts);
    }

    function deployCollector(
        address _infraredProxy,
        address _keeper,
        address _ibgt,
        address _wbera,
        address _receivor,
        uint256 _payoutAmount
    ) external returns (address proxyAddr) {
        if (
            _infraredProxy == address(0) || _keeper == address(0)
                || _ibgt == address(0) || _wbera == address(0)
                || _receivor == address(0) || _payoutAmount == 0
        ) {
            revert();
        }

        // Prepare initializer data
        bytes memory initializerData = abi.encodeCall(
            HarvestBaseCollector.initialize,
            (
                _infraredProxy,
                SAFE,
                _keeper,
                _ibgt,
                _wbera,
                _receivor,
                _payoutAmount
            )
        );
        vm.startBroadcast();
        proxyAddr =
            setupProxy(address(new HarvestBaseCollector()), initializerData);
        // use foundry upgrades tool to prtect against front running initialize
        // proxyAddr = Upgrades.deployUUPSProxy(
        //     "HarvestBaseCollector.sol",
        //     initializerData
        // );

        // test init data
        HarvestBaseCollector collector =
            HarvestBaseCollector(payable(proxyAddr));
        if (address(collector.infrared()) != _infraredProxy) {
            revert(
                "Initialization front-run or failed: incorrect infraredProxy"
            );
        }
        if (!collector.hasRole(collector.GOVERNANCE_ROLE(), SAFE)) {
            revert("Initialization front-run or failed: incorrect safe");
        }
        if (!collector.hasRole(collector.KEEPER_ROLE(), _keeper)) {
            revert("Initialization front-run or failed: incorrect keeper");
        }
        if (address(collector.ibgt()) != _ibgt) {
            revert("Initialization front-run or failed: incorrect ibgt");
        }
        if (address(collector.wbera()) != _wbera) {
            revert("Initialization front-run or failed: incorrect wbera");
        }
        if (collector.feeReceivor() != _receivor) {
            revert("Initialization front-run or failed: incorrect receiver");
        }
        if (collector.payoutAmount() != _payoutAmount) {
            revert("Initialization front-run or failed: incorrect payoutAmount");
        }

        vm.stopBroadcast();
    }

    function deployInfraredImp() external returns (address newInfraredImp) {
        vm.startBroadcast();
        newInfraredImp = address(new InfraredV1_7());
        vm.stopBroadcast();
    }

    function upgradeInfrared(
        bool _send,
        address _infraredProxy,
        address newInfraredImp,
        address proxyAddr
    ) external isBatch(SAFE) {
        if (
            _infraredProxy == address(0) || newInfraredImp == address(0)
                || proxyAddr == address(0)
        ) {
            revert();
        }

        // Call upgrade and initialize
        bytes memory initializerData =
            abi.encodeCall(InfraredV1_7.initializeV1_7, (proxyAddr));
        bytes memory upgradeData = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)", newInfraredImp, initializerData
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
