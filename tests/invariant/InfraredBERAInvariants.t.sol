// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAInvariantHandler} from "./InfraredBERAInvariantHandler.sol";
import {InfraredBERABaseTest} from "tests/unit/staking/InfraredBERABase.t.sol";
import {InfraredBERAV2BaseTest} from
    "tests/unit/staking/upgrades/InfraredBERAV2Base.t.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";

/**
 * @title InfraredBERAInvariants
 * @notice Invariant tests for the InfraredBERA
 * @dev Uses the InfraredBERABaseTest setup pattern
 */
contract InfraredBERAInvariants is InfraredBERAV2BaseTest {
    InfraredBERAInvariantHandler public handler;

    BeaconDeposit public depositContract;

    ValidatorTypes.Validator[] public infraredValidators;

    function setUp() public virtual override {
        super.setUp();

        pubkey0 = validatorStruct.pubkey;

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
        withdrawor.initializeV2(0x00000961Ef480Eb55e80D19ad83579A64c007002);

        // etch deposit contract at depositor constant deposit contract address
        // depositContract = new BeaconDeposit();
        // address DEPOSIT_CONTRACT = depositor.DEPOSIT_CONTRACT();
        // vm.etch(DEPOSIT_CONTRACT, address(depositContract).code);

        // etch withdraw precompile at withdraw precompile contract address
        address WITHDRAW_PRECOMPILE = withdrawor.WITHDRAW_PRECOMPILE();
        vm.etch(WITHDRAW_PRECOMPILE, withdrawPrecompile);

        // mock precompile calls until hard fork (~7 May)
        vm.mockCall(WITHDRAW_PRECOMPILE, bytes(""), abi.encode(10));

        uint64 amount = uint64(26000000000000000000 / 1 gwei);
        vm.mockCall(
            WITHDRAW_PRECOMPILE,
            10,
            abi.encodePacked(pubkey0, amount),
            abi.encode(true)
        );

        vm.mockCall(
            WITHDRAW_PRECOMPILE,
            10,
            abi.encodePacked(pubkey1, amount),
            abi.encode(true)
        );

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

        // Create handler for invariant testing
        handler = new InfraredBERAInvariantHandler(
            ibera,
            InfraredBERADepositor(address(depositor)),
            withdrawor,
            receivor,
            address(infrared),
            address(depositContract),
            address(infraredGovernance),
            address(keeper)
        );

        targetContract(address(handler));
    }

    // --- Invariant Tests ---

    /**
     * @notice Invariant: User balances in contract must match accumulated previewShares in userSharesGhost variable
     */
    function invariant_userBalancesMatchPreviews() external view {
        address[] memory userList = handler.getUserList();
        for (uint256 i = 0; i < userList.length; i++) {
            address user = userList[i];
            assertEq(
                ibera.balanceOf(user),
                handler.userSharesGhost(user),
                "User balance != ghost tracking"
            );
        }
    }

    /**
     * @notice Invariant: Deposits must match the sum of validator stakes plus pending
     */
    function invariant_depositAccounting() external view {
        // InfraredBERA's accounting
        uint256 deposits = ibera.deposits();
        uint256 pending = ibera.pending(); // pending + rebalancing
        uint256 confirmed = ibera.confirmed();

        // Check basic accounting identity
        assertEq(
            deposits, pending + confirmed, "deposits != pending + confirmed"
        );

        // Validator stakes accounting
        uint256 sumValidatorStakes = 0;
        bytes[] memory pubkeys = handler.getValidatorList();
        for (uint256 i = 0; i < pubkeys.length; i++) {
            sumValidatorStakes += ibera.stakes(pubkeys[i]);
        }

        // Depositor + withdrawor accounting
        uint256 depositorReserves = depositor.reserves();
        uint256 withdraworRebalancing = 0; // for lite version, or actual in full version

        // Check that all deposits are accounted for
        assertEq(
            deposits,
            sumValidatorStakes + depositorReserves + withdraworRebalancing,
            "deposits != stakes + reserves + rebalancing"
        );
    }

    /**
     * @notice Invariant: Validator stakes must match internal tracking
     */
    function invariant_validatorStakesMatchInternal() external view {
        bytes[] memory pubkeys = handler.getValidatorList();
        for (uint256 i = 0; i < pubkeys.length; i++) {
            bytes memory pubkey = pubkeys[i];
            bytes32 pubkeyHash = keccak256(pubkey);

            // If the validator hasn't interacted, skip
            if (
                handler.validatorStakesGhost(pubkeyHash) == 0
                    && ibera.stakes(pubkey) == 0
            ) {
                continue;
            }

            assertEq(
                ibera.stakes(pubkey),
                handler.validatorStakesGhost(pubkeyHash),
                "Validator stake != ghost tracking"
            );

            // If validator has exited, stake should be zero
            if (handler.validatorExited(pubkeyHash)) {
                assertEq(
                    ibera.stakes(pubkey),
                    0,
                    "Exited validator has non-zero stake"
                );

                assertTrue(
                    ibera.hasExited(pubkey),
                    "Exited validator not marked as exited"
                );
            }
        }
    }

    /**
     * @notice Invariant: Exchange rate should never decrease (no value extraction)
     */
    function invariant_exchangeRateNeverDecreases() external view {
        // Get deposit history
        InfraredBERAInvariantHandler.DepositAction[] memory depositHistory =
            handler.getDeposits();

        // Skip if no deposits or only one deposit
        if (depositHistory.length <= 1) return;

        // Initial exchange rate (shares per BERA)
        uint256 initialShares = depositHistory[0].sharesReceived;
        uint256 initialBera = depositHistory[0].beraAmount;

        // Skip if initial deposit was zero
        if (initialBera == 0) return;

        uint256 initialRate = (initialShares * 1e18) / initialBera;

        // For each subsequent deposit, exchange rate shouldn't be worse
        for (uint256 i = 1; i < depositHistory.length; i++) {
            uint256 shares = depositHistory[i].sharesReceived;
            uint256 bera = depositHistory[i].beraAmount;

            // Skip if this deposit was zero
            if (bera == 0) continue;

            uint256 currentRate = (shares * 1e18) / bera;

            // Rate shouldn't increase (more shares per BERA = worse deal for user)
            // Allow 0.1% slippage for rounding and potential gas differences
            assertLe(
                currentRate, initialRate * 1001 / 1000, "Exchange rate worsened"
            );
        }
    }

    /**
     * @notice Invariant: Exchange rate should improve after compounding
     */
    function invariant_compoundingImprovesExchangeRate() external view {
        // Get compound history
        InfraredBERAInvariantHandler.CompoundAction[] memory compoundHistory =
            handler.getCompounds();

        // Skip if no compounds
        if (compoundHistory.length == 0) return;

        // Sum up total compounded amount
        uint256 totalCompoundedAmount = 0;
        for (uint256 i = 0; i < compoundHistory.length; i++) {
            totalCompoundedAmount += compoundHistory[i].amount;
        }

        // Skip if no actual compounding happened
        if (totalCompoundedAmount == 0) return;

        // If we have compounding but no user shares, it's still good
        if (ibera.totalSupply() <= 10 ether) return; // Only the minimum mint amount

        // Check the current exchange rate - it should be better than 1:1
        uint256 totalSupply = ibera.totalSupply();
        uint256 deposits = ibera.deposits();

        // Current rate (shares per BERA) - lower is better
        uint256 currentRate = (totalSupply * 1e18) / deposits;

        // Check rate is better than 1:1 (accounting for minimum mint)
        assertLt(
            currentRate,
            1e18, // 1:1 rate
            "Compounding did not improve exchange rate"
        );
    }

    /**
     * @notice Invariant: Validator stake must never exceed MAX_EFFECTIVE_BALANCE
     */
    function invariant_maxEffectiveBalance() external view {
        bytes[] memory pubkeys = handler.getValidatorList();
        for (uint256 i = 0; i < pubkeys.length; i++) {
            bytes memory pubkey = pubkeys[i];
            uint256 stake = ibera.stakes(pubkey);

            assertLe(
                stake,
                InfraredBERAConstants.MAX_EFFECTIVE_BALANCE,
                "Validator stake exceeds MAX_EFFECTIVE_BALANCE"
            );
        }
    }

    /**
     * @notice Invariant: Deposits tracked by the contract should match the sum of validator stakes plus pending deposits
     */
    function invariant_depositsMatchStakesPlusPending() external view {
        uint256 deposits = ibera.deposits();
        uint256 pending = ibera.pending();
        uint256 totalValidatorStakes = 0;

        bytes[] memory pubkeys = handler.getValidatorList();
        for (uint256 i = 0; i < pubkeys.length; i++) {
            totalValidatorStakes += ibera.stakes(pubkeys[i]);
        }

        assertEq(
            deposits,
            totalValidatorStakes + pending,
            "Deposits != stakes + pending"
        );
    }

    /**
     * @notice Invariant: Contract balances should always be consistent with accounting
     */
    function invariant_contractBalancesConsistent() external view {
        // depositor.reserves() should be <= depositor.balance
        assertLe(
            depositor.reserves(),
            address(depositor).balance,
            "Depositor reserves > balance"
        );

        // withdrawor.reserves() + withdrawor.fees() should be <= withdrawor.balance
        // assertLe(
        //     withdrawor.reserves() + withdrawor.fees(),
        //     address(withdrawor).balance,
        //     "Withdrawor reserves + fees > balance"
        // );

        // receivor shareholderFees should be <= receivor.balance
        assertLe(
            receivor.shareholderFees(),
            address(receivor).balance,
            "FeeReceivor shareholderFees > balance"
        );
    }

    /**
     * @notice Invariant: Validator stakes should never go negative
     */
    function invariant_validatorStakesNonNegative() external view {
        bytes[] memory pubkeys = handler.getValidatorList();
        for (uint256 i = 0; i < pubkeys.length; i++) {
            bytes memory pubkey = pubkeys[i];
            uint256 stake = ibera.stakes(pubkey);

            assertTrue(stake >= 0, "Validator stake is negative");

            // If validator has exited, stake should be zero
            if (handler.validatorExited(keccak256(pubkey))) {
                assertEq(stake, 0, "Exited validator has non-zero stake");
            }
        }
    }

    /**
     * @notice Invariant: After compounding, deposits should increase by at least the amount swept
     */
    function invariant_compoundingIncreasesDeposits() external view {
        InfraredBERAInvariantHandler.CompoundAction[] memory compoundHistory =
            handler.getCompounds();

        // Skip if no compounds
        if (compoundHistory.length == 0) return;

        uint256 totalCompoundAmount = 0;
        for (uint256 i = 0; i < compoundHistory.length; i++) {
            totalCompoundAmount += compoundHistory[i].amount;
        }

        // Total deposits should have increased by at least the sum of compound amounts
        // Note: This is approximate since other operations also affect deposits
        assertGe(
            ibera.deposits(),
            handler.totalDeposited() - handler.totalWithdrawn()
                + totalCompoundAmount,
            "Deposits did not increase by expected compound amount"
        );
    }

    /**
     * @notice Invariant: No unauthorized users should have roles
     */
    function invariant_rolesSecurity() external view {
        // Check DEFAULT_ADMIN_ROLE
        assertTrue(
            ibera.hasRole(ibera.DEFAULT_ADMIN_ROLE(), infraredGovernance),
            "Admin doesn't have admin role"
        );

        // Check GOVERNANCE_ROLE
        assertTrue(
            ibera.hasRole(ibera.GOVERNANCE_ROLE(), infraredGovernance),
            "Admin doesn't have governance role"
        );

        // Check KEEPER_ROLE
        assertTrue(
            ibera.hasRole(ibera.KEEPER_ROLE(), keeper),
            "Keeper doesn't have keeper role"
        );

        // Test a random address shouldn't have any roles
        address randomUser = address(0xBAD);
        assertFalse(
            ibera.hasRole(ibera.DEFAULT_ADMIN_ROLE(), randomUser),
            "Random user has admin role"
        );
        assertFalse(
            ibera.hasRole(ibera.GOVERNANCE_ROLE(), randomUser),
            "Random user has governance role"
        );
        assertFalse(
            ibera.hasRole(ibera.KEEPER_ROLE(), randomUser),
            "Random user has keeper role"
        );
    }
}
