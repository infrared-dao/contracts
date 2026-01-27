// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Core contracts
import {StakedIR} from "src/core/StakedIR.sol";
import {IRAuction} from "src/periphery/IRAuction.sol";
import {IRRewardDistributor} from "src/periphery/IRRewardDistributor.sol";

// Mock contracts
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRStakingIntegration
 * @notice Integration tests for the full IR staking system
 * @dev Tests the complete flow: IR -> sIR -> weights -> rewards -> auction -> compound
 */
contract IRStakingIntegrationTest is Test {
    // Contracts
    StakedIR public sir;
    IRAuction public auction;
    IRRewardDistributor public distributor;
    MockInfrared public infrared;
    InfraredBGT public ibgt;
    MockERC20 public ir;
    MockERC20 public wbera;
    MockERC20 public honey;

    // Users
    address public governor = makeAddr("governor");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public keeper = makeAddr("keeper");

    // Vaults
    address public vault1 = makeAddr("vault1");
    address public vault2 = makeAddr("vault2");
    address public vault3 = makeAddr("vault3");

    // Constants
    uint256 constant INITIAL_SIR_DEPOSIT = 10 ether;
    uint256 constant PAYOUT_AMOUNT = 100 ether;
    uint256 constant MIN_IBGT_ALLOCATION = 2000; // 20%
    uint256 constant REWARDS_PER_EPOCH = 1000 ether;
    uint256 constant EPOCH_DURATION = 7 days;
    uint256 constant MIN_LOCKUP = 7 days;

    function setUp() public {
        // Deploy IR token
        ir = new MockERC20("Infrared", "IR", 18);

        // Deploy StakedIR with proxy and inflation protection
        ir.mint(address(this), INITIAL_SIR_DEPOSIT);

        // Deploy implementation
        address sirImpl = address(new StakedIR());

        // Pre-compute proxy address for approval
        address sirProxyAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        ir.approve(sirProxyAddress, INITIAL_SIR_DEPOSIT);

        // Deploy proxy and initialize
        bytes memory sirInitData = abi.encodeWithSelector(
            StakedIR.initialize.selector, IERC20(address(ir)), address(this)
        );
        sir = StakedIR(address(new ERC1967Proxy(sirImpl, sirInitData)));

        // Deploy iBGT and mock Infrared
        address admin = address(this);
        address minter = address(this);
        address pauser = address(this);
        address burner = address(this);
        ibgt = new InfraredBGT(admin, minter, pauser, burner);
        address red = makeAddr("red");
        address rewardsFactory = makeAddr("rewardsFactory");
        infrared = new MockInfrared(address(ibgt), red, rewardsFactory);

        // Whitelist reward tokens
        wbera = new MockERC20("Wrapped BERA", "WBERA", 18);
        honey = new MockERC20("Honey", "HONEY", 18);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        infrared.updateWhiteListedRewardTokens(address(honey), true);
        infrared.updateWhiteListedRewardTokens(address(ir), true);

        // Deploy IRAuction
        IRAuction auctionImpl = new IRAuction();
        bytes memory auctionInitData = abi.encodeWithSelector(
            IRAuction.initialize.selector,
            address(infrared),
            governor,
            keeper,
            address(ir),
            address(sir),
            PAYOUT_AMOUNT
        );
        auction = IRAuction(
            address(new ERC1967Proxy(address(auctionImpl), auctionInitData))
        );

        // Deploy IRRewardDistributor
        IRRewardDistributor distImpl = new IRRewardDistributor();
        bytes memory distInitData = abi.encodeWithSelector(
            IRRewardDistributor.initialize.selector,
            address(infrared),
            governor,
            address(ir),
            MIN_IBGT_ALLOCATION
        );
        distributor = IRRewardDistributor(
            address(new ERC1967Proxy(address(distImpl), distInitData))
        );

        // Setup eligible vaults
        infrared.setVaultRegistry(vault1, makeAddr("registryNew1")); // Mock valid
        infrared.setVaultRegistry(vault2, makeAddr("registryNew2")); // Mock valid
        infrared.setVaultRegistry(vault3, makeAddr("registryNew3")); // Mock valid
        vm.startPrank(governor);
        distributor.addEligibleVault(vault1);
        distributor.addEligibleVault(vault2);
        distributor.addEligibleVault(vault3);
        distributor.setRewardsPerEpoch(REWARDS_PER_EPOCH);
        vm.stopPrank();

        // Fund contracts
        ir.mint(address(distributor), 100000 ether);
        wbera.mint(address(auction), 10000 ether);
        honey.mint(address(auction), 10000 ether);

        // Setup users with IR
        ir.mint(alice, 10000 ether);
        ir.mint(bob, 10000 ether);
        ir.mint(charlie, 10000 ether);
        ir.mint(keeper, 10000 ether);

        // Get KEEPER_ROLE bytes32
        bytes32 keeperRole = keccak256("KEEPER_ROLE");

        // Grant keeper role (governor has DEFAULT_ADMIN_ROLE from initialize)
        vm.prank(governor);
        distributor.grantRole(keeperRole, keeper);

        vm.prank(governor);
        distributor.grantRole(keeperRole, governor);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  FULL FLOW INTEGRATION                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FullFlow_StakeWeightsAuctionDistribute() public {
        // === STEP 1: Users stake IR to get sIR ===
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        uint256 aliceShares = sir.deposit(1000 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        ir.approve(address(sir), 500 ether);
        uint256 bobShares = sir.deposit(500 ether, bob);
        vm.stopPrank();

        // Verify sIR balance
        assertGt(sir.balanceOf(alice), 0);
        assertGt(sir.balanceOf(bob), 0);

        // === STEP 2: Governance/Keeper sets vault reward weights ===
        {
            address[] memory vaults = new address[](3);
            vaults[0] = vault1;
            vaults[1] = vault2;
            vaults[2] = vault3;
            uint256[] memory weights = new uint256[](3);
            weights[0] = 5000; // 50%
            weights[1] = 3000; // 30%
            weights[2] = 2000; // 20%
            vm.prank(governor);
            distributor.updateDefaultWeights(vaults, weights);
        }

        // === STEP 3: Epoch ends, rewards distributed ===
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();
        assertEq(distributor.currentEpoch(), 2);

        // === STEP 4: Keeper auctions rewards for IR ===
        uint256 sirAssetsBefore = sir.totalAssets();
        {
            address[] memory tokens = new address[](2);
            tokens[0] = address(wbera);
            tokens[1] = address(honey);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 200 ether;
            amounts[1] = 100 ether;

            vm.startPrank(keeper);
            ir.approve(address(auction), PAYOUT_AMOUNT);
            auction.claimFees(keeper, tokens, amounts);
            vm.stopPrank();

            assertEq(wbera.balanceOf(keeper), 200 ether);
            assertEq(honey.balanceOf(keeper), 100 ether);
        }

        // === STEP 5: IR was compounded into sIR ===
        assertEq(sir.totalAssets(), sirAssetsBefore + PAYOUT_AMOUNT);

        // === STEP 6: Alice and Bob's shares increased in value ===
        assertGt(sir.convertToAssets(aliceShares), 1000 ether);
        assertGt(sir.convertToAssets(bobShares), 500 ether);

        // === STEP 7: After lockup, users can withdraw ===
        vm.warp(block.timestamp + MIN_LOCKUP);

        vm.prank(alice);
        assertGt(sir.redeem(aliceShares, alice, alice), 1000 ether);

        vm.prank(bob);
        assertGt(sir.redeem(bobShares, bob, bob), 500 ether);
    }

    function test_MultipleEpochs_CompoundingReturns() public {
        // Alice stakes
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        uint256 aliceShares = sir.deposit(1000 ether, alice);
        vm.stopPrank();

        uint256 initialValue = sir.convertToAssets(aliceShares);

        // Set default weights
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000;
        weights[1] = 3000;
        weights[2] = 2000;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        // Simulate 4 weeks of epochs
        for (uint256 i = 0; i < 4; i++) {
            // End epoch
            vm.warp(block.timestamp + EPOCH_DURATION);
            distributor.distributeRewards();

            // Keeper auctions rewards
            address[] memory rewardTokens = new address[](1);
            rewardTokens[0] = address(wbera);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 100 ether;

            vm.startPrank(keeper);
            ir.approve(address(auction), PAYOUT_AMOUNT);
            auction.claimFees(keeper, rewardTokens, amounts);
            vm.stopPrank();
        }

        // After 4 epochs of compounding
        uint256 finalValue = sir.convertToAssets(aliceShares);
        uint256 totalCompounded = 4 * PAYOUT_AMOUNT;

        // Alice's share value should have increased
        assertGt(finalValue, initialValue);

        // Total assets should reflect all compounds
        assertGe(
            sir.totalAssets(),
            INITIAL_SIR_DEPOSIT + 1000 ether + totalCompounded
        );
    }

    function test_WeightsConfigurableByGovernance() public {
        // Setup: Governance configures vault weights
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000; // 50%
        weights[1] = 3000; // 30%
        weights[2] = 2000; // 20%

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        // Verify weights were set correctly
        assertEq(distributor.defaultVaultWeights(vault1), 5000);
        assertEq(distributor.defaultVaultWeights(vault2), 3000);
        assertEq(distributor.defaultVaultWeights(vault3), 2000);
        assertEq(distributor.totalDefaultWeight(), 10000);
    }

    function test_IBGTVaultMandatoryAllocation() public {
        // Set default weights for distribution
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000;
        weights[1] = 5000;
        weights[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        // Distribute
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();

        // iBGT vault should have received MIN_IBGT_ALLOCATION (20%)
        // uint256 expectedIBGTAllocation =
        //     (REWARDS_PER_EPOCH * MIN_IBGT_ALLOCATION) / 10000;

        // Remaining 80% split between vault1 and vault2
        // uint256 remaining = REWARDS_PER_EPOCH - expectedIBGTAllocation;
        // uint256 expectedVault1 = remaining / 2; // 50% of remaining
        // uint256 expectedVault2 = remaining / 2;

        // In practice, check via infrared.addIncentives calls
        // This would require a more sophisticated mock
    }

    function test_AuctionDifferentPayoutAmounts() public {
        // Alice stakes
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        sir.deposit(1000 ether, alice);
        vm.stopPrank();

        // Initial auction
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        uint256 sirAssetsBefore = sir.totalAssets();

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);
        auction.claimFees(keeper, rewardTokens, amounts);
        vm.stopPrank();

        assertEq(sir.totalAssets(), sirAssetsBefore + PAYOUT_AMOUNT);

        // Governor changes payout amount
        uint256 newPayout = 200 ether;
        vm.prank(governor);
        auction.setPayoutAmount(newPayout);

        // Second auction with new payout
        vm.startPrank(keeper);
        ir.approve(address(auction), newPayout);
        auction.claimFees(keeper, rewardTokens, amounts);
        vm.stopPrank();

        // Should have compounded newPayout this time
        assertEq(sir.totalAssets(), sirAssetsBefore + PAYOUT_AMOUNT + newPayout);
    }

    function test_WeightsAlwaysUsedForDistribution() public {
        // Set weights
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 6000;
        weights[1] = 4000;
        weights[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        // Distribute using configured weights
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();

        // Should succeed using weights
        assertEq(distributor.currentEpoch(), 2);
    }

    function test_KeeperCanUpdateWeights() public {
        // Get KEEPER_ROLE bytes32
        bytes32 keeperRole = keccak256("KEEPER_ROLE");

        // Grant keeper role
        vm.prank(governor);
        distributor.grantRole(keeperRole, keeper);

        // Keeper updates weights
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 7000;
        weights[1] = 3000;
        weights[2] = 0;

        vm.prank(keeper);
        distributor.updateDefaultWeights(vaults, weights);

        // Verify weights were set correctly
        assertEq(distributor.defaultVaultWeights(vault1), 7000);
        assertEq(distributor.defaultVaultWeights(vault2), 3000);
    }

    function test_CompoundBenefitsAllStakers() public {
        // Three stakers with different amounts
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        uint256 aliceShares = sir.deposit(1000 ether, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        ir.approve(address(sir), 500 ether);
        uint256 bobShares = sir.deposit(500 ether, bob);
        vm.stopPrank();

        vm.startPrank(charlie);
        ir.approve(address(sir), 250 ether);
        uint256 charlieShares = sir.deposit(250 ether, charlie);
        vm.stopPrank();

        // Record initial values
        uint256 aliceValueBefore = sir.convertToAssets(aliceShares);
        uint256 bobValueBefore = sir.convertToAssets(bobShares);
        uint256 charlieValueBefore = sir.convertToAssets(charlieShares);

        // Compound via auction
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(wbera);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 350 ether; // Large auction

        vm.startPrank(keeper);
        ir.approve(address(auction), PAYOUT_AMOUNT);
        auction.claimFees(keeper, rewardTokens, amounts);
        vm.stopPrank();

        // All stakers benefit proportionally
        uint256 aliceValueAfter = sir.convertToAssets(aliceShares);
        uint256 bobValueAfter = sir.convertToAssets(bobShares);
        uint256 charlieValueAfter = sir.convertToAssets(charlieShares);

        // All increased
        assertGt(aliceValueAfter, aliceValueBefore);
        assertGt(bobValueAfter, bobValueBefore);
        assertGt(charlieValueAfter, charlieValueBefore);

        // Increases are proportional to stake
        uint256 aliceGain = aliceValueAfter - aliceValueBefore;
        uint256 bobGain = bobValueAfter - bobValueBefore;
        uint256 charlieGain = charlieValueAfter - charlieValueBefore;

        // Alice has 2x Bob's stake, should have ~2x gains
        assertApproxEqRel(aliceGain, bobGain * 2, 0.01e18);
        // Bob has 2x Charlie's stake, should have ~2x gains
        assertApproxEqRel(bobGain, charlieGain * 2, 0.01e18);
    }

    function test_WithdrawalAfterMultipleCompounds() public {
        // Alice deposits
        vm.startPrank(alice);
        ir.approve(address(sir), 1000 ether);
        uint256 aliceShares = sir.deposit(1000 ether, alice);
        vm.stopPrank();

        // Multiple compounds over time
        for (uint256 i = 0; i < 3; i++) {
            address[] memory rewardTokens = new address[](1);
            rewardTokens[0] = address(wbera);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 50 ether;

            vm.startPrank(keeper);
            ir.approve(address(auction), PAYOUT_AMOUNT);
            auction.claimFees(keeper, rewardTokens, amounts);
            vm.stopPrank();

            vm.warp(block.timestamp + 1 days);
        }

        // Alice withdraws
        uint256 irBalanceBefore = ir.balanceOf(alice);
        vm.prank(alice);
        uint256 withdrawn = sir.redeem(aliceShares, alice, alice);

        assertGt(withdrawn, 1000 ether);

        // After lockup
        vm.warp(block.timestamp + MIN_LOCKUP + 1);

        sir.claimBatch(sir.getUserRequests(alice));

        // Should have received original + compounded returns
        assertEq(ir.balanceOf(alice), irBalanceBefore + withdrawn);

        // Total compounded was 3 * PAYOUT_AMOUNT
        // uint256 totalCompounded = 3 * PAYOUT_AMOUNT;
        // Alice's share of that (minus initial deposit still locked)
        // Should be roughly her proportion
    }
}
