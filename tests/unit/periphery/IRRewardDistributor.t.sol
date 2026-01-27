// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IRRewardDistributor} from "src/periphery/IRRewardDistributor.sol";
import {StakedIR} from "src/core/StakedIR.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";

contract IRRewardDistributorTest is Test {
    IRRewardDistributor public distributor;
    // StakedIR public sir;
    MockERC20 public ir;
    MockInfrared public infrared;
    InfraredBGT public ibgt;

    address public governor = makeAddr("governor");
    address public keeper = makeAddr("keeper");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    address public vault1 = makeAddr("vault1");
    address public vault2 = makeAddr("vault2");
    address public vault3 = makeAddr("vault3");

    uint256 constant EPOCH_DURATION = 7 days;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant MIN_IBGT_ALLOCATION = 2000; // 20%
    uint256 constant REWARDS_PER_EPOCH = 1000 ether;
    uint256 constant INITIAL_SIR_DEPOSIT = 10 ether;

    event RewardsDistributed(address indexed stakingToken, uint256 amount);
    event VaultExcluded(address indexed stakingToken);
    event VaultIncluded(address indexed stakingToken);
    event EligibleVaultAdded(address indexed stakingToken);
    event EligibleVaultRemoved(address indexed stakingToken);
    event EpochStarted(
        uint256 indexed epoch, uint256 timestamp, uint256 totalRewards
    );
    event EpochFinalized(uint256 indexed epoch);
    event WeightsUpdated(address indexed stakingToken, uint256 weight);

    function setUp() public {
        // Deploy tokens
        ir = new MockERC20("Infrared", "IR", 18);

        // Deploy StakedIR
        // ir.mint(address(this), INITIAL_SIR_DEPOSIT);
        // address sirAddress =
        //     vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        // ir.approve(sirAddress, INITIAL_SIR_DEPOSIT);
        // sir = new StakedIR(ERC20(address(ir)), address(this));

        // Deploy mock Infrared with iBGT
        address admin = address(this);
        address minter = address(this);
        address pauser = address(this);
        address burner = address(this);
        ibgt = new InfraredBGT(admin, minter, pauser, burner);
        address red = makeAddr("red");
        address rewardsFactory = makeAddr("rewardsFactory");
        infrared = new MockInfrared(address(ibgt), red, rewardsFactory);

        // Deploy IRRewardDistributor via proxy
        IRRewardDistributor implementation = new IRRewardDistributor();
        bytes memory initData = abi.encodeWithSelector(
            IRRewardDistributor.initialize.selector,
            address(infrared),
            governor,
            address(ir),
            MIN_IBGT_ALLOCATION
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        distributor = IRRewardDistributor(address(proxy));

        // Setup eligible vaults
        infrared.setVaultRegistry(vault1, makeAddr("registryNew1")); // Mock valid
        infrared.setVaultRegistry(vault2, makeAddr("registryNew2")); // Mock valid
        infrared.setVaultRegistry(vault3, makeAddr("registryNew3")); // Mock valid
        vm.startPrank(governor);
        distributor.addEligibleVault(vault1);
        distributor.addEligibleVault(vault2);
        distributor.addEligibleVault(vault3);
        vm.stopPrank();

        // Setup users with sIR
        ir.mint(alice, 1000 ether);
        ir.mint(bob, 1000 ether);
        ir.mint(charlie, 1000 ether);

        // Fund distributor with rewards
        ir.mint(address(distributor), 10000 ether);

        // Set rewards per epoch
        vm.prank(governor);
        distributor.setRewardsPerEpoch(REWARDS_PER_EPOCH);

        // Get KEEPER_ROLE bytes32
        bytes32 keeperRole = keccak256("KEEPER_ROLE");

        // Grant keeper role (governor has DEFAULT_ADMIN_ROLE from initialize)
        vm.prank(governor);
        distributor.grantRole(keeperRole, keeper);

        vm.prank(governor);
        distributor.grantRole(keeperRole, governor);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public view {
        assertEq(distributor.IR_TOKEN(), address(ir));
        assertEq(distributor.minIBGTAllocation(), MIN_IBGT_ALLOCATION);
        assertEq(distributor.currentEpoch(), 1);
        assertEq(distributor.totalRewardsPerEpoch(), REWARDS_PER_EPOCH);
        assertEq(distributor.epochDuration(), EPOCH_DURATION);
    }

    function test_RevertInitialize_InvalidAllocation() public {
        IRRewardDistributor implementation = new IRRewardDistributor();

        vm.expectRevert();
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                IRRewardDistributor.initialize.selector,
                address(infrared),
                governor,
                address(ir),
                6000 // > MAX_IBGT_ALLOCATION (50%)
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    VAULT MANAGEMENT TESTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ExcludeVault() public {
        vm.expectEmit(true, false, false, false);
        emit VaultExcluded(vault1);

        vm.prank(governor);
        distributor.excludeVault(vault1);

        assertTrue(distributor.isVaultExcluded(vault1));

        address[] memory eligible = distributor.getEligibleVaults();
        assertEq(eligible.length, 2); // vault2 and vault3
    }

    function test_RevertExcludeVault_IBGTVault() public {
        vm.prank(governor);
        vm.expectRevert();
        distributor.excludeVault(address(ibgt));
    }

    function test_IncludeVault() public {
        // First exclude
        vm.prank(governor);
        distributor.excludeVault(vault1);

        // Then include
        vm.expectEmit(true, false, false, false);
        emit VaultIncluded(vault1);

        vm.prank(governor);
        distributor.includeVault(vault1);

        assertFalse(distributor.isVaultExcluded(vault1));
    }

    function test_AddEligibleVault() public {
        address newVault = makeAddr("newVault");
        infrared.setVaultRegistry(newVault, makeAddr("registryNew")); // Mock valid

        vm.expectEmit(true, false, false, false);
        emit EligibleVaultAdded(newVault);

        vm.prank(governor);
        distributor.addEligibleVault(newVault);

        address[] memory eligible = distributor.getEligibleVaults();
        assertEq(eligible.length, 4);
    }

    function test_RevertAddEligibleVault_InvalidRegistry() public {
        address invalidVault = makeAddr("invalidVault");
        // No registry set, so address(0)

        vm.prank(governor);
        vm.expectRevert(IRRewardDistributor.InvalidVault.selector);
        distributor.addEligibleVault(invalidVault);
    }

    function test_RevertAddEligibleVault_Excluded() public {
        address newVault = makeAddr("newVault");
        infrared.setVaultRegistry(newVault, makeAddr("registryNew"));

        vm.startPrank(governor);
        distributor.excludeVault(newVault);

        vm.expectRevert();
        distributor.addEligibleVault(newVault);
        vm.stopPrank();
    }

    function test_RemoveEligibleVault() public {
        vm.expectEmit(true, false, false, false);
        emit EligibleVaultRemoved(vault1);

        vm.prank(governor);
        distributor.removeEligibleVault(vault1);

        address[] memory eligible = distributor.getEligibleVaults();
        assertEq(eligible.length, 2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      DISTRIBUTION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_DistributeRewards_WithWeights() public {
        // Set weights
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

        // Fast forward to end of epoch
        vm.warp(block.timestamp + EPOCH_DURATION);

        // Distribute with weights
        vm.expectEmit(false, false, false, false);
        emit EpochFinalized(1);

        distributor.distributeRewards();

        // New epoch should have started
        assertEq(distributor.currentEpoch(), 2);
    }

    function test_RevertDistributeRewards_EpochNotEnded() public {
        vm.expectRevert();
        distributor.distributeRewards();
    }

    function test_RevertDistributeRewards_NoRewards() public {
        // Set rewards to 0
        vm.prank(governor);
        distributor.setRewardsPerEpoch(0);

        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.expectRevert();
        distributor.distributeRewards();
    }

    function test_RevertDistributeRewards_InsufficientBalance() public {
        uint256 bal = ir.balanceOf(address(distributor));
        // Drain distributor
        vm.prank(address(distributor));
        ir.transfer(governor, bal);

        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.expectRevert();
        distributor.distributeRewards();
    }

    function test_RevertDistributeRewards_NoWeights() public {
        // No weights set
        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.expectRevert();
        distributor.distributeRewards();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetRewardsPerEpoch() public {
        uint256 newAmount = 2000 ether;

        vm.prank(governor);
        distributor.setRewardsPerEpoch(newAmount);

        assertEq(distributor.totalRewardsPerEpoch(), newAmount);
    }

    function test_SetEpochDuration() public {
        uint256 newDuration = 1 days;

        // Set weights
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

        vm.expectEmit(false, false, false, true);
        emit IRRewardDistributor.EpochDurationUpdated(
            EPOCH_DURATION, newDuration
        );

        vm.prank(governor);
        distributor.setEpochDuration(newDuration);

        assertEq(distributor.epochDuration(), newDuration);

        // Test effect on epoch
        vm.warp(block.timestamp + newDuration);
        distributor.distributeRewards(); // Should succeed after new duration
    }

    function test_RevertSetEpochDuration_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.setEpochDuration(1 days);
    }

    function test_SetMinIBGTAllocation() public {
        uint256 newAllocation = 3000; // 30%

        vm.prank(governor);
        distributor.setMinIBGTAllocation(newAllocation);

        assertEq(distributor.minIBGTAllocation(), newAllocation);
    }

    function test_RevertSetMinIBGTAllocation_TooHigh() public {
        vm.prank(governor);
        vm.expectRevert();
        distributor.setMinIBGTAllocation(6000); // > 50%
    }

    function test_UpdateDefaultWeights() public {
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 7000;
        weights[1] = 3000;
        weights[2] = 0;

        vm.expectEmit(true, false, false, true);
        emit WeightsUpdated(vault1, 7000);

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        assertEq(distributor.defaultVaultWeights(vault1), 7000);
        assertEq(distributor.defaultVaultWeights(vault2), 3000);
        assertEq(distributor.totalDefaultWeight(), 10000);
    }

    function test_UpdateDefaultWeights_ByKeeper() public {
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 6000;
        weights[1] = 4000;
        weights[2] = 0;

        vm.prank(keeper);
        distributor.updateDefaultWeights(vaults, weights);

        assertEq(distributor.defaultVaultWeights(vault1), 6000);
        assertEq(distributor.defaultVaultWeights(vault2), 4000);
    }

    function test_RevertUpdateDefaultWeights_Unauthorized() public {
        address[] memory vaults = new address[](2);
        vaults[0] = vault1;
        vaults[1] = vault2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 7000;
        weights[1] = 3000;

        vm.prank(alice);
        vm.expectRevert();
        distributor.updateDefaultWeights(vaults, weights);
    }

    function test_RevertUpdateDefaultWeights_NotBasisPoints() public {
        address[] memory vaults = new address[](2);
        vaults[0] = vault1;
        vaults[1] = vault2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 7000;
        weights[1] = 2000; // Total = 9000

        vm.prank(governor);
        vm.expectRevert();
        distributor.updateDefaultWeights(vaults, weights);
    }

    function test_RevertUpdateDefaultWeights_IBGTVault() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(ibgt);

        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        vm.prank(governor);
        vm.expectRevert();
        distributor.updateDefaultWeights(vaults, weights);
    }

    function test_RecoverERC20() public {
        // Send extra IR to distributor
        uint256 extra = 500 ether;
        ir.mint(address(distributor), extra);

        uint256 initialBal = ir.balanceOf(governor);

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.TokensRecovered(address(ir), extra);

        vm.prank(governor);
        distributor.recoverERC20(address(ir), extra);

        assertEq(ir.balanceOf(governor), initialBal + extra);
        assertEq(ir.balanceOf(address(distributor)), 10000 ether); // Original funding preserved
    }

    function test_RecoverERC20_FullBalanceIfZero() public {
        // Deploy another token
        MockERC20 otherToken = new MockERC20("Other", "OTH", 18);
        uint256 amount = 100 ether;
        otherToken.mint(address(distributor), amount);

        vm.prank(governor);
        distributor.recoverERC20(address(otherToken), 0); // 0 means full

        assertEq(otherToken.balanceOf(governor), amount);
        assertEq(otherToken.balanceOf(address(distributor)), 0);
    }

    function test_RevertRecoverERC20_InvalidAmount() public {
        vm.prank(governor);
        vm.expectRevert(IRRewardDistributor.InvalidAmount.selector);
        distributor.recoverERC20(address(ir), type(uint256).max); // More than balance
    }

    function test_RevertRecoverERC20_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.recoverERC20(address(ir), 100 ether);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW TESTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TimeUntilNextEpoch() public {
        uint256 timeRemaining = distributor.timeUntilNextEpoch();
        assertEq(timeRemaining, EPOCH_DURATION);

        vm.warp(block.timestamp + EPOCH_DURATION / 2);
        timeRemaining = distributor.timeUntilNextEpoch();
        assertApproxEqAbs(timeRemaining, EPOCH_DURATION / 2, 1);

        vm.warp(block.timestamp + EPOCH_DURATION);
        timeRemaining = distributor.timeUntilNextEpoch();
        assertEq(timeRemaining, 0);
    }

    function test_GetEligibleVaults() public view {
        address[] memory eligible = distributor.getEligibleVaults();
        assertEq(eligible.length, 3);
        assertEq(eligible[0], vault1);
        assertEq(eligible[1], vault2);
        assertEq(eligible[2], vault3);
    }

    function test_GetVaultAllocation() public {
        // Set weights
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

        // iBGT allocation: 20% of 1000 ether = 200 ether
        assertEq(distributor.getVaultAllocation(address(ibgt)), 200 ether);

        // Remaining 800 ether split by weights
        // vault1: 50% of 800 = 400 ether
        assertEq(distributor.getVaultAllocation(vault1), 400 ether);
        // vault2: 30% of 800 = 240 ether
        assertEq(distributor.getVaultAllocation(vault2), 240 ether);
        // vault3: 20% of 800 = 160 ether
        assertEq(distributor.getVaultAllocation(vault3), 160 ether);

        // Invalid vault: 0
        assertEq(distributor.getVaultAllocation(makeAddr("invalid")), 0);
    }

    function test_GetNextEpochRewards() public {
        assertEq(distributor.getNextEpochRewards(), REWARDS_PER_EPOCH);

        uint256 newRewards = 2000 ether;
        vm.prank(governor);
        distributor.setRewardsPerEpoch(newRewards);
        assertEq(distributor.getNextEpochRewards(), newRewards);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTEGRATION TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FullEpochCycle() public {
        // Setup weights
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

        // Epoch 1 distribution
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();

        assertEq(distributor.currentEpoch(), 2);

        // Can distribute again in new epoch after waiting
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();

        assertEq(distributor.currentEpoch(), 3);
    }

    function test_MultipleEpochsWithWeightUpdates() public {
        // Initial weights
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;

        uint256[] memory weights1 = new uint256[](3);
        weights1[0] = 5000;
        weights1[1] = 5000;
        weights1[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights1);

        // Distribute epoch 1
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();
        assertEq(distributor.currentEpoch(), 2);

        // Update weights for epoch 2
        uint256[] memory weights2 = new uint256[](3);
        weights2[0] = 7000;
        weights2[1] = 3000;
        weights2[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights2);

        assertEq(distributor.defaultVaultWeights(vault1), 7000);
        assertEq(distributor.defaultVaultWeights(vault2), 3000);

        // Distribute epoch 2 with new weights
        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();
        assertEq(distributor.currentEpoch(), 3);
    }

    function test_DistributeRewards_PartialFailure() public {
        // Setup weights
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

        // Simulate failure for vault2 and iBGT
        infrared.setShouldRevertForVault(vault2, true);
        infrared.setShouldRevertForVault(address(ibgt), true);

        // Fast forward to epoch end
        vm.warp(block.timestamp + EPOCH_DURATION);

        // // Expect events for successes and failures
        // vm.expectEmit(true, true, false, true);
        // emit RewardsDistributed(vault1, 400 ether); // 50% of remaining 800 ether
        // vm.expectEmit(true, true, false, true);
        // emit RewardsDistributed(vault3, 160 ether); // 20% of 800
        // vm.expectEmit(true, true, false, true);
        // emit IRRewardDistributor.DistributionFailed(vault2, 240 ether, abi.encodeWithSignature("Simulated failure"));
        // vm.expectEmit(true, true, false, true);
        // emit IRRewardDistributor.DistributionFailed(address(ibgt), 200 ether, abi.encodeWithSignature("Simulated failure"));
        // Expect events in contract order: Failed iBGT, Success vault1, Failed vault2, Success vault3
        bytes memory expectedErrorData =
            abi.encodeWithSelector(0x08c379a0, "Simulated failure");

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.DistributionFailed(
            address(ibgt), 200 ether, expectedErrorData
        );

        vm.expectEmit(true, false, false, true);
        emit RewardsDistributed(vault1, 400 ether);

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.DistributionFailed(
            vault2, 240 ether, expectedErrorData
        );

        vm.expectEmit(true, false, false, true);
        emit RewardsDistributed(vault3, 160 ether);

        distributor.distributeRewards();

        // Verify carryOvers accumulated for failed vaults
        assertEq(distributor.carryOverRewards(vault2), 240 ether);
        assertEq(distributor.carryOverRewards(address(ibgt)), 200 ether);
        assertEq(distributor.carryOverRewards(vault1), 0);
        assertEq(distributor.carryOverRewards(vault3), 0);

        // Epoch advanced
        assertEq(distributor.currentEpoch(), 2);
    }

    function test_DistributeRewards_WithCarryOverInNextEpoch() public {
        // First epoch: Force failure for vault1 and iBGT
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

        infrared.setShouldRevertForVault(vault1, true);
        infrared.setShouldRevertForVault(address(ibgt), true);

        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards();

        // CarryOvers set
        assertEq(distributor.carryOverRewards(vault1), 400 ether);
        assertEq(distributor.carryOverRewards(address(ibgt)), 200 ether);

        // Fix failures for next epoch
        infrared.setShouldRevertForVault(vault1, false);
        infrared.setShouldRevertForVault(address(ibgt), false);

        // Second epoch: Expect distributions including carryOvers
        vm.warp(block.timestamp + EPOCH_DURATION);

        // iBGT: base 200 + carry 200 = 400
        vm.expectEmit(true, true, false, true);
        emit RewardsDistributed(address(ibgt), 400 ether);
        // vault1: base 400 + carry 400 = 800
        vm.expectEmit(true, true, false, true);
        emit RewardsDistributed(vault1, 800 ether);

        distributor.distributeRewards();

        // CarryOvers reset
        assertEq(distributor.carryOverRewards(vault1), 0);
        assertEq(distributor.carryOverRewards(address(ibgt)), 0);
        assertEq(distributor.currentEpoch(), 3);
    }

    function test_DistributeRewards_AllFailures() public {
        // Setup weights
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

        // Simulate failures for all
        infrared.setShouldRevertForVault(vault1, true);
        infrared.setShouldRevertForVault(vault2, true);
        infrared.setShouldRevertForVault(address(ibgt), true);

        vm.warp(block.timestamp + EPOCH_DURATION);

        // Expect all failures, epoch still advances
        // vm.expectEmit(true, true, false, true);
        // emit IRRewardDistributor.DistributionFailed(address(ibgt), 200 ether, abi.encodeWithSignature("Simulated failure"));
        // vm.expectEmit(true, true, false, true);
        // emit IRRewardDistributor.DistributionFailed(vault1, 400 ether, abi.encodeWithSignature("Simulated failure"));
        // vm.expectEmit(true, true, false, true);
        // emit IRRewardDistributor.DistributionFailed(vault2, 400 ether, abi.encodeWithSignature("Simulated failure"));
        // Expect events in order: Failed iBGT, Failed vault1, Failed vault2
        bytes memory expectedErrorData =
            abi.encodeWithSelector(0x08c379a0, "Simulated failure");

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.DistributionFailed(
            address(ibgt), 200 ether, expectedErrorData
        );

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.DistributionFailed(
            vault1, 400 ether, expectedErrorData
        );

        vm.expectEmit(true, false, false, true);
        emit IRRewardDistributor.DistributionFailed(
            vault2, 400 ether, expectedErrorData
        );

        distributor.distributeRewards();

        // All carried over
        assertEq(distributor.carryOverRewards(address(ibgt)), 200 ether);
        assertEq(distributor.carryOverRewards(vault1), 400 ether);
        assertEq(distributor.carryOverRewards(vault2), 400 ether);
        assertEq(distributor.currentEpoch(), 2);
    }

    function test_RevertDistributeRewards_InsufficientBalanceWithCarryOver()
        public
    {
        // Force a carryOver by failing one vault
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 10000;
        weights[1] = 0;
        weights[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        infrared.setShouldRevertForVault(vault1, true);

        vm.warp(block.timestamp + EPOCH_DURATION);
        distributor.distributeRewards(); // Creates carryOver for vault1 (800 ether remaining + 200 iBGT if failed, but adjust)

        // Drain some IR to cause insufficient
        uint256 bal = ir.balanceOf(address(distributor));
        vm.startPrank(address(distributor));
        ir.transfer(governor, bal - distributor.totalRewardsPerEpoch() + 1); // Leave just under needed with carryOver
        vm.stopPrank();

        vm.warp(block.timestamp + EPOCH_DURATION);

        vm.expectRevert();
        distributor.distributeRewards();
    }

    function test_GetVaultAllocation_WithCarryOver() public {
        // Manually set carryOvers (or simulate via failure)
        // vm.prank(address(distributor)); // Cheat to set
        // distributor.carryOverRewards(vault1) = 100 ether;
        vm.store(
            address(distributor),
            bytes32(keccak256(abi.encode(vault1, 43))),
            bytes32(uint256(100 ether))
        );

        // distributor.carryOverRewards(address(ibgt)) = 50 ether;
        vm.store(
            address(distributor),
            bytes32(keccak256(abi.encode(address(ibgt), 43))),
            bytes32(uint256(50 ether))
        );

        // Setup weights for base calc
        address[] memory vaults = new address[](3);
        vaults[0] = vault1;
        vaults[1] = vault2;
        vaults[2] = vault3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 10000;
        weights[1] = 0;
        weights[2] = 0;

        vm.prank(governor);
        distributor.updateDefaultWeights(vaults, weights);

        // iBGT: base 200 + carry 50 = 250
        assertEq(distributor.getVaultAllocation(address(ibgt)), 250 ether);

        // vault1: base 800 + carry 100 = 900
        assertEq(distributor.getVaultAllocation(vault1), 900 ether);

        // Invalid: 0
        assertEq(distributor.getVaultAllocation(vault2), 0);
    }

    function test_GetNextEpochRewards_WithCarryOver() public {
        // Set carryOvers
        // vm.prank(address(distributor)); // Cheat
        // distributor.carryOverRewards(vault1) = 100 ether;
        vm.store(
            address(distributor),
            bytes32(keccak256(abi.encode(vault1, 43))),
            bytes32(uint256(100 ether))
        );
        // distributor.carryOverRewards(vault2) = 200 ether;
        vm.store(
            address(distributor),
            bytes32(keccak256(abi.encode(vault2, 43))),
            bytes32(uint256(200 ether))
        );
        // distributor.carryOverRewards(address(ibgt)) = 50 ether;
        vm.store(
            address(distributor),
            bytes32(keccak256(abi.encode(address(ibgt), 43))),
            bytes32(uint256(50 ether))
        );

        // Total: 1000 base + 350 carry = 1350
        assertEq(distributor.getNextEpochRewards(), 1350 ether);
    }
}
