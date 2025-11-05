// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// Core contracts
import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {IInfraredBERA} from "src/depreciated/interfaces/IInfraredBERA.sol";
import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
import {IBeaconDeposit} from "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

/**
 * @title InfraredBERAInvariantHandler
 * @notice Handler for InfraredBERA invariant testing
 * @dev Tracks and manages actions on the InfraredBERA ecosystem for invariant tests
 */
contract InfraredBERAInvariantHandler is Test {
    // Core contracts
    InfraredBERAV2 public ibera;
    InfraredBERADepositor public depositor;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAFeeReceivor public receivor;

    // Addresses
    address public infrared;
    address public depositContract;
    address public admin;
    address public keeper;
    address public infraredGovernance;

    // Test users
    address[] public users;

    // Validator data
    bytes[] public validatorPubkeys;
    mapping(bytes32 => bytes) public validatorSignatures;
    mapping(bytes32 => bool) public validatorExited;

    // Tracking data for invariant testing
    uint256 public totalDeposited;
    uint256 public totalCompounded;
    uint256 public totalWithdrawn;
    uint256 public totalFees;

    // User balances tracking
    mapping(address => uint256) public userSharesGhost;

    // Tracking validator data
    mapping(bytes32 => uint256) public validatorStakesGhost;

    // Tracking for actions
    struct DepositAction {
        address user;
        uint256 beraAmount;
        uint256 previewShares;
        uint256 sharesReceived;
        uint256 timestamp;
        uint256 rate; // shares per BERA, scaled by 1e18
    }

    struct CompoundAction {
        uint256 amount;
        uint256 fees;
        uint256 timestamp;
        uint256 exchangeRateBefore;
        uint256 exchangeRateAfter;
        uint256 totalValueBefore;
        uint256 totalValueAfter;
    }

    struct ValidatorAction {
        bytes pubkey;
        uint256 amount;
        bool isDeposit; // true = deposit, false = withdrawal
        uint256 timestamp;
    }

    DepositAction[] public deposits;
    CompoundAction[] public compounds;
    ValidatorAction[] public validatorActions;

    constructor(
        InfraredBERAV2 _ibera,
        InfraredBERADepositor _depositor,
        InfraredBERAWithdrawor _withdrawor,
        InfraredBERAFeeReceivor _receivor,
        address _infrared,
        address _depositContract,
        address _infraredGovernance,
        address _keeper
    ) {
        ibera = _ibera;
        depositor = _depositor;
        withdrawor = _withdrawor;
        receivor = _receivor;
        infrared = _infrared;
        depositContract = _depositContract;
        infraredGovernance = _infraredGovernance;
        keeper = _keeper;

        // Create test users
        users.push(address(0xA11CE));
        users.push(address(0xB0B));
        users.push(address(0xCA7E));
        users.push(address(0xDEA1));

        // Fund users
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 100000 ether);
        }

        // Create test validator pubkeys (using same pattern from your tests)
        for (uint256 i = 0; i < 5; i++) {
            // Create pubkey format matching your test setup
            bytes memory pubkey = abi.encodePacked(
                bytes32(keccak256(abi.encodePacked("v", i))), bytes16("")
            );
            validatorPubkeys.push(pubkey);

            // Create signature for validator
            bytes memory signature = abi.encodePacked(
                bytes32(keccak256(abi.encodePacked("v", i))),
                bytes32(""),
                bytes32("")
            );
            validatorSignatures[keccak256(pubkey)] = signature;

            // Mock validator status for infrared
            vm.mockCall(
                infrared,
                abi.encodeWithSelector(
                    IInfrared.isInfraredValidator.selector, pubkey
                ),
                abi.encode(true)
            );
        }
    }

    // --- User actions ---

    function mint(uint8 userIdx, uint96 amount0) external {
        address user = _pickUser(userIdx);
        uint256 amount = bound(uint256(amount0), 0.001 ether, 10000 ether);
        uint256 previewShares = ibera.previewMint(amount);
        vm.startPrank(user);
        uint256 shares = ibera.mint{value: amount}(user);
        uint256 rate = (shares * 1e18) / amount;
        userSharesGhost[user] += previewShares;
        totalDeposited += amount;
        deposits.push(
            DepositAction({
                user: user,
                beraAmount: amount,
                previewShares: previewShares,
                sharesReceived: shares,
                timestamp: block.timestamp,
                rate: rate
            })
        );
        // } catch {
        //     // Mint failed, do nothing
        // }
        vm.stopPrank();
    }

    function compound() external {
        uint256 totalValueBefore = ibera.deposits();
        (uint256 amount, uint256 fees) = receivor.distribution();
        if (amount == 0) return;
        uint256 exchangeRateBefore = ibera.previewMint(1e18) - amount; // exclude compound amount from before calc (as it's included in previewMint by default)
        ibera.compound();

        uint256 exchangeRateAfter = ibera.previewMint(1e18);
        uint256 totalValueAfter = ibera.deposits();
        // if (amount > 0 || fees > 0) {
        totalCompounded += amount;
        totalFees += fees;
        compounds.push(
            CompoundAction({
                amount: amount,
                fees: fees,
                timestamp: block.timestamp,
                exchangeRateBefore: exchangeRateBefore,
                exchangeRateAfter: exchangeRateAfter,
                totalValueBefore: totalValueBefore,
                totalValueAfter: totalValueAfter
            })
        );
    }

    // --- Keeper actions ---

    function executeDeposit(uint8 validatorIdx, uint96 amount0) external {
        if (uint256(validatorIdx) >= validatorPubkeys.length) return;
        bytes memory pubkey = validatorPubkeys[uint256(validatorIdx)];
        bytes32 pubkeyHash = keccak256(pubkey);

        // Ensure validator not exited
        if (validatorExited[pubkeyHash]) return;

        // Ensure signature is set
        if (ibera.signatures(pubkey).length == 0) {
            // Set validator signature
            vm.prank(infraredGovernance);
            ibera.setDepositSignature(pubkey, validatorSignatures[pubkeyHash]);
        }

        // Bound amount to reasonable value that should be in reserves
        uint256 reserves = depositor.reserves();
        if (reserves < InfraredBERAConstants.INITIAL_DEPOSIT) return;

        uint256 amount = bound(
            uint256(amount0), InfraredBERAConstants.INITIAL_DEPOSIT, reserves
        );

        // If this would be the first deposit, ensure it's INITIAL_DEPOSIT
        address operatorBeacon =
            IBeaconDeposit(depositContract).getOperator(pubkey);
        if (operatorBeacon == address(0)) {
            amount = InfraredBERAConstants.INITIAL_DEPOSIT;
            if (amount > reserves) return; // Not enough reserves for initial deposit
        }

        vm.prank(keeper);
        depositor.execute(pubkey, amount);

        validatorStakesGhost[pubkeyHash] += amount;

        validatorActions.push(
            ValidatorAction({
                pubkey: pubkey,
                amount: amount,
                isDeposit: true,
                timestamp: block.timestamp
            })
        );
        // } catch {
        //     // Execute failed, do nothing
        // }
    }

    // --- Admin actions ---

    function setFeeDivisorShareholders(uint16 feeDivisor) external {
        feeDivisor = uint16(bound(feeDivisor, 4, 100));

        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(feeDivisor);
    }

    function toggleWithdrawals(bool enabled) external {
        // vm.prank(infraredGovernance);
        // try ibera.setWithdrawalsEnabled(enabled) {
        //     // Successfully updated withdrawals flag
        // } catch {
        //     // Update failed, do nothing
        // }
    }

    // --- Simulation helpers ---

    function simulateYield(uint64 amount0) external {
        uint256 amount = bound(uint256(amount0), 0.01 ether, 10 ether);

        // Send some BERA directly to receivor to simulate EL rewards
        vm.deal(address(receivor), address(receivor).balance + amount);
    }

    function advanceTimeAndBlocks(uint24 seconds_) external {
        uint256 boundedSeconds = bound(uint256(seconds_), 2, 100 days);
        uint256 blocks_ = boundedSeconds / 2;
        vm.warp(block.timestamp + boundedSeconds);
        vm.roll(block.number + blocks_);
    }

    // --- Utility functions ---

    function _pickUser(uint8 idx) internal view returns (address) {
        return users[bound(uint256(idx), 0, users.length - 1)];
    }

    // --- Getters for invariant testing ---

    function getDeposits() external view returns (DepositAction[] memory) {
        return deposits;
    }

    function getCompounds() external view returns (CompoundAction[] memory) {
        return compounds;
    }

    function getValidatorActions()
        external
        view
        returns (ValidatorAction[] memory)
    {
        return validatorActions;
    }

    function getUserList() external view returns (address[] memory) {
        return users;
    }

    function getValidatorList() external view returns (bytes[] memory) {
        return validatorPubkeys;
    }
}
