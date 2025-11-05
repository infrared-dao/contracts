// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BatchScript} from "@forge-safe/BatchScript.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; // Use Unsafe for manual control; validations done separately
import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";
import {BatchClaimerV2_2} from "src/periphery/BatchClaimerV2_2.sol";

contract UpgradeInfraredV1_9 is BatchScript {
    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    function validate() public {
        Options memory opts;
        // opts.unsafeAllow = "state-variable-assignment,state-variable-immutable,external-library-linking,struct-definition,enum-definition,constructor,delegatecall,selfdestruct,missing-public-upgradeto,internal-function-storage,missing-initializer,missing-initializer-call,duplicate-initializer-call,incorrect-initializer-order";  // Skips assembly/opcode validations if SafeTransferLib's assembly triggers dereferencer during opcode checks
        // opts.unsafeSkipStorageCheck = true;    // Skips storage layout if needed; manually verify below
        // opts.unsafeSkipProxyAdminCheck = true;
        // opts.unsafeAllowRenames =true;
        // opts.unsafeSkipAllChecks = true;

        // For the upgrade (InfraredV1_9)
        opts.referenceContract = "InfraredV1_8.sol";
        Upgrades.validateUpgrade("InfraredV1_9.sol", opts);
    }

    function upgradeInfraredTestnet(address _infraredProxy, address _ibgt)
        external
    {
        if (_infraredProxy == address(0)) {
            revert();
        }

        vm.startBroadcast();

        address wiBGT = address(
            new WrappedRewardToken(
                ERC20(_ibgt), "Wrapped Infrared BGT", "wiBGT"
            )
        );
        address newInfraredImp = address(new InfraredV1_9());
        InfraredV1_9(payable(_infraredProxy)).upgradeToAndCall(
            newInfraredImp,
            abi.encodeWithSelector(InfraredV1_9.initializeV1_9.selector, wiBGT)
        );

        vm.stopBroadcast();
    }

    function deployWibgt(address _ibgt) external {
        if (_ibgt == address(0)) {
            revert();
        }

        vm.startBroadcast();
        address wiBGT = address(
            new WrappedRewardToken(
                ERC20(_ibgt), "Wrapped Infrared BGT", "wiBGT"
            )
        );
        address proxy = setupProxy(
            address(new BatchClaimerV2_2()),
            abi.encodeWithSelector(
                BatchClaimerV2_2.initialize.selector, SAFE, wiBGT
            )
        );
        // check proxy was initialized correctly
        if (address(BatchClaimerV2_2(proxy).wiBGT()) != wiBGT) {
            revert("Initialization front-run or failed: incorrect wiBGT");
        }
        if (address(BatchClaimerV2_2(proxy).owner()) != SAFE) {
            revert("Initialization front-run or failed: incorrect owner");
        }
        vm.stopBroadcast();
    }

    function upgradeInfrared(
        bool _send,
        address _infraredProxy,
        address _wibgt,
        address _ibgt,
        address _bribeCollector
    ) external isBatch(SAFE) {
        if (_infraredProxy == address(0) || _wibgt == address(0)) {
            revert();
        }

        vm.startBroadcast();
        address newInfraredImp = address(new InfraredV1_9());

        vm.stopBroadcast();

        // whitelist reward token
        // function updateWhiteListedRewardTokens(address _token, bool _whitelisted)
        bytes memory data = abi.encodeWithSignature(
            "updateWhiteListedRewardTokens(address,bool)", _wibgt, true
        );
        addToBatch(_infraredProxy, 0, data);

        // add reward to ibgt vault with default duration of 24 hrs
        // function addReward(
        //     address _stakingToken,
        //     address _rewardsToken,
        //     uint256 _rewardsDuration
        // )
        data = abi.encodeWithSignature(
            "addReward(address,address,uint256)", _ibgt, _wibgt, 86400
        );
        addToBatch(_infraredProxy, 0, data);

        // Call upgrade and initialize for infrared
        bytes memory upgradeData = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            newInfraredImp,
            abi.encodeWithSelector(InfraredV1_9.initializeV1_9.selector, _wibgt)
        );
        addToBatch(_infraredProxy, 0, upgradeData);

        // set bribe collector payout token to ibgt
        // function setPayoutToken(address _newPayoutToken)
        data = abi.encodeWithSignature("setPayoutToken(address)", _ibgt);
        addToBatch(_bribeCollector, 0, data);

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
