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

contract UpgradeInfraredV1_10 is BatchScript {
    using SafeTransferLib for ERC20;

    address public constant SAFE = 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f; // Infrared gov safe

    // Deployment salts for deterministic addresses
    bytes32 public constant STAKED_IR_SALT = keccak256("infrared.stakedIR.v1");
    bytes32 public constant IR_AUCTION_SALT = keccak256("infrared.irAuction.v1");
    bytes32 public constant IR_REWARD_DISTRIBUTOR_SALT =
        keccak256("infrared.irRewardDistributor.v1");

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

    /// @notice Deploy StakedIR, IRAuction, and IRRewardDistributor for testnet
    /// @param _irToken Address of the IR governance token
    /// @param _infrared Address of the Infrared protocol proxy
    /// @param _keeper Address with keeper role
    /// @param stakedIR staked IR address
    /// @param _payoutAmount Amount of IR required per auction claim
    function _deployAuction(
        address _irToken,
        address _infrared,
        address _keeper,
        address stakedIR,
        uint256 _payoutAmount
    ) internal returns (address irAuction) {
        {
            // 2. Deploy IRAuction with proxy
            address irAuctionImpl = address(new IRAuction());
            bytes memory irAuctionInitData = abi.encodeWithSelector(
                IRAuction.initialize.selector,
                _infrared,
                SAFE,
                _keeper,
                _irToken,
                stakedIR,
                _payoutAmount
            );
            ERC1967Proxy irAuctionProxy =
                new ERC1967Proxy(irAuctionImpl, irAuctionInitData);
            irAuction = address(irAuctionProxy);
        }

        // Verify IRAuction initialization
        if (
            !IRAuction(irAuction).hasRole(
                IRAuction(irAuction).GOVERNANCE_ROLE(), SAFE
            )
        ) {
            revert("Initialization front-run or failed: incorrect safe");
        }
        if (
            !IRAuction(irAuction).hasRole(
                IRAuction(irAuction).KEEPER_ROLE(), _keeper
            )
        ) {
            revert("Initialization front-run or failed: incorrect keeper");
        }
        if (IRAuction(irAuction).payoutToken() != _irToken) {
            revert("IRAuction initialization failed: incorrect payoutToken");
        }
        if (IRAuction(irAuction).payoutAmount() != _payoutAmount) {
            revert("IRAuction initialization failed: incorrect payoutAmount");
        }
    }

    /// @notice Upgrade Infrared to V1_10 on testnet
    /// @param _infraredProxy Address of the Infrared proxy
    /// @param _irToken Address of the IR governance token
    /// @param _keeper Address with keeper role
    /// @param stakedIR staked IR address
    /// @param _payoutAmount Amount of IR required per auction claim
    function upgradeInfraredTestnet(
        address _infraredProxy,
        address _irToken,
        address _keeper,
        address stakedIR,
        uint256 _payoutAmount
    ) external {
        if (_infraredProxy == address(0) || _irToken == address(0)) {
            revert("Zero address");
        }

        vm.startBroadcast();

        // Deploy new Infrared implementation
        address newInfraredImpl = address(new InfraredV1_10());

        address _irAuction = _deployAuction(
            _irToken, _infraredProxy, _keeper, stakedIR, _payoutAmount
        );

        // Upgrade and initialize
        InfraredV1_10(payable(_infraredProxy)).upgradeToAndCall(
            newInfraredImpl,
            abi.encodeWithSelector(
                InfraredV1_10.initializeV1_10.selector, _irToken, _irAuction
            )
        );

        vm.stopBroadcast();
    }

    /// @notice Full upgrade flow for mainnet using Safe multisig
    /// @param _send Whether to send the batch transaction
    /// @param _infraredProxy Address of the Infrared proxy
    /// @param _irToken Address of the IR governance token
    /// @param _ibgt Address of the iBGT token
    /// @param _keeper Address with keeper role
    /// @param stakedIR staked IR address
    /// @param _payoutAmount Amount of IR required per auction claim
    function upgradeInfrared(
        bool _send,
        address _infraredProxy,
        address _irToken,
        address _ibgt,
        address _keeper,
        address stakedIR,
        uint256 _payoutAmount
    ) external isBatch(SAFE) {
        if (
            _infraredProxy == address(0) || _irToken == address(0)
                || _keeper == address(0) || _ibgt == address(0)
        ) {
            revert("Zero address");
        }

        vm.startBroadcast();

        // Deploy new Infrared implementation
        address newInfraredImpl = address(new InfraredV1_10());

        address _irAuction = _deployAuction(
            _irToken, _infraredProxy, _keeper, stakedIR, _payoutAmount
        );

        vm.stopBroadcast();

        // Whitelist IR token as reward
        // function updateWhiteListedRewardTokens(address _token, bool _whitelisted)
        // bytes memory data = abi.encodeWithSignature(
        //     "updateWhiteListedRewardTokens(address,bool)", _irToken, true
        // );
        // addToBatch(_infraredProxy, 0, data);

        // Add IR as reward to iBGT vault with default duration of 24 hrs
        // function addReward(
        //     address _stakingToken,
        //     address _rewardsToken,
        //     uint256 _rewardsDuration
        // )
        // bytes memory data = abi.encodeWithSignature(
        //     "addReward(address,address,uint256)", _ibgt, _irToken, 86400
        // );
        // addToBatch(_infraredProxy, 0, data);

        // Upgrade Infrared and initialize V1_10
        bytes memory upgradeData = abi.encodeWithSignature(
            "upgradeToAndCall(address,bytes)",
            newInfraredImpl,
            abi.encodeWithSelector(
                InfraredV1_10.initializeV1_10.selector, _irToken, _irAuction
            )
        );
        addToBatch(_infraredProxy, 0, upgradeData);

        // set ir split ratio to 5%
        bytes memory data =
            abi.encodeWithSignature("updateIRBribeSplit(uint256)", 1000);
        addToBatch(_infraredProxy, 0, data);

        executeBatch(_send);
    }

    /// @notice Helper to setup proxy
    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }
}
