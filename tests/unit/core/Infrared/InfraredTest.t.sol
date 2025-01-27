// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    Helper,
    IInfrared,
    InfraredVault,
    InfraredGovernanceToken
} from "./Helper.sol";
import "tests/unit/mocks/MockERC20.sol";
import {BGTStaker} from "@berachain/pol/BGTStaker.sol";
import "@berachain/pol/rewards/RewardVaultFactory.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "@berachain/pol/interfaces/IRewardVault.sol";
import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {ValidatorTypes} from "src/core/libraries/ValidatorTypes.sol";
import {Errors} from "src/utils/Errors.sol";
import {DataTypes} from "src/utils/DataTypes.sol";

contract InfraredTest is Helper {
    // using stdStorage for StdStorage;

    // MockBerachainRewardsVaultFactory public factory
    /*//////////////////////////////////////////////////////////////
               END TO END TESTS, FULL LIFE CYCLE
    //////////////////////////////////////////////////////////////*/

    function testStorage() public view {
        assertEq(
            infrared.VALIDATOR_STORAGE_LOCATION(),
            keccak256(
                abi.encode(
                    uint256(keccak256(bytes("infrared.validatorStorage"))) - 1
                )
            ) & ~bytes32(uint256(0xff))
        );
        assertEq(
            infrared.VAULT_STORAGE_LOCATION(),
            keccak256(
                abi.encode(
                    uint256(keccak256(bytes("infrared.vaultStorage"))) - 1
                )
            ) & ~bytes32(uint256(0xff))
        );
        assertEq(
            infrared.REWARDS_STORAGE_LOCATION(),
            keccak256(
                abi.encode(
                    uint256(keccak256(bytes("infrared.rewardsStorage"))) - 1
                )
            ) & ~bytes32(uint256(0xff))
        );
    }

    function testEndToEndFlow() public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(ibgt);
        rewardTokens[1] = address(ir);

        // Step 1: Vault Registration
        // InfraredVault vault = InfraredVault(
        //     address(infrared.registerVault(address(wbera), rewardTokens))
        // );

        InfraredVault vault = infraredVault;

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        vm.stopPrank();

        // Step 2: User Interaction - Staking Tokens
        address user = address(10);
        vm.deal(address(user), 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();

        // Step 3: Reward Accrual via Rewards Factory (Simulate Reward Increase)
        // Assuming factory and infrared contracts have been set up to interact correctly
        address vaultWbera = factory.getVault(address(wbera));

        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Step 4: Passage of Time for Rewards Distribution
        vm.warp(block.timestamp + 100 days); // Simulating 10 days for reward accrual

        // Step 5: Harvest Vault - Distributing Rewards
        uint256 vaultBalanceBefore = ibgt.balanceOf(address(vault));

        vm.startPrank(address(vault));
        vault.rewardsVault().setOperator(address(infrared));
        vm.stopPrank();
        vm.startPrank(keeper);
        vm.expectEmit();
        emit IInfrared.VaultHarvested(
            keeper, address(wbera), address(vault), 99999999999999999000
        );
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        uint256 vaultBalanceAfter = ibgt.balanceOf(address(vault));
        assertTrue(
            vaultBalanceAfter > vaultBalanceBefore,
            "Vault should have more InfraredBGT after harvest"
        );

        // Step 6: Claiming Rewards
        vm.startPrank(user);
        vm.warp(block.timestamp + 10 days); //
        vault.getReward();
        vm.stopPrank();
        uint256 rewardBalance = ibgt.balanceOf(user);
        assertTrue(rewardBalance > 0, "User should have rewards");

        // Step 7: Users Withdraw Tokens
        vm.startPrank(user);
        vault.withdraw(stakeAmount);
        uint256 finalBalance = wbera.balanceOf(user);
        vm.stopPrank();

        assertEq(
            finalBalance,
            stakeAmount,
            "User should have withdrawn all staked tokens"
        );

        // Step 8: Assertions
        assertEq(
            vault.totalSupply() - 1, // infared holds a balance of 1 wei in every vault
            0,
            "Vault total supply should be zero after withdrawal"
        );
        assertEq(
            vault.balanceOf(user),
            0,
            "User balance in vault should be zero after withdrawal"
        );
    }

    function testCollectBribesSuccess() public {
        // Step 0. Update the weight of `uint256(WeightType.CollectBribesWiberaVault)`.
        // vm.startPrank(infraredGovernance);
        // infrared.updateWeight(
        //     ConfigTypes.WeightType.CollectBribesWiberaVault, 1e6 / 2
        // );
        // vm.stopPrank();

        // 1. Mint some native tokens to the collector.
        vm.deal(address(collector), 100 ether);
        vm.startPrank(address(collector));

        // 2. Wrap these as wbera tokens.
        wbera.deposit{value: 100 ether}();
        // Check that the collector balance of wbera is 100 ether.
        assertEq(
            wbera.balanceOf(address(collector)),
            100 ether,
            "Collector balance should be 100 ether"
        );
        vm.stopPrank();

        address ibgtVault = address(infrared.ibgtVault());

        // Step 4. approve 3 ether to infrared.
        vm.startPrank(address(collector));
        wbera.approve(address(infrared), 3 ether);

        // Step 5. Call `collectBribes` with the reward token.
        infrared.collectBribes(address(wbera), 3 ether);

        // Step 7. Assure that the vaults received the collected bribes.
        assertTrue(
            wbera.balanceOf(address(ibgtVault)) == 3 ether,
            "InfraredBGTVault should have 1.5 ether"
        );
        assertTrue(
            wbera.balanceOf(address(infrared)) == 0 ether,
            "Infrared should have 0 ether"
        );
    }

    function testcollectBribesNotWhitelistedToken() public {
        // 1. Mint some native tokens to the collector, then wrap it as wbera.
        vm.deal(address(collector), 100 ether);
        vm.startPrank(address(collector));
        wbera.deposit{value: 100 ether}();
        wbera.approve(address(infrared), 1 ether);

        // Step 4. Call `collectBribes` with the reward token. Should revert.
        vm.expectRevert(abi.encodeWithSignature("RewardTokenNotSupported()"));
        infrared.collectBribes(address(15), 1 ether);
    }

    function testcollectBribesNotCollector() public {
        // 1. Mint some native tokens to the collector, then wrap it as wbera.
        vm.deal(address(collector), 100 ether);
        vm.startPrank(address(collector));
        wbera.deposit{value: 100 ether}();
        wbera.approve(address(infrared), 1 ether);
        vm.stopPrank();

        // Step 2. Call `updateWhitelistedRewardTokens` to add the reward token.
        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        vm.stopPrank();

        vm.startPrank(address(keeper));
        // Step 3. Call `collectBribes` with the reward token. Should revert.
        vm.expectRevert(
            abi.encodeWithSignature("Unauthorized(address)", address(keeper))
        );
        infrared.collectBribes(address(wbera), 1 ether);
    }

    function testharvestBaseNotEnoughBacking() public {
        // 1. Mint some BGT to the Infrared contract, simulating base rewards.
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        vm.stopPrank();

        // 2. Deal only 99 ether to the BGT contract.
        vm.deal(address(bgt), 99 ether);

        // 3. HarvestBase should have the BGT balance constant.
        uint256 balanceBefore = bgt.balanceOf(address(infrared));
        infrared.harvestBase();
        uint256 balanceAfter = bgt.balanceOf(address(infrared));
        assertEq(balanceBefore, balanceAfter);
    }

    function testharvestBaseSuccess() public {
        // 1. Add a validator to the validator set
        vm.startPrank(infraredGovernance);
        ValidatorTypes.Validator memory validator_str = ValidatorTypes.Validator({
            pubkey: "0x1234567890abcdef",
            addr: address(validator)
        });
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = validator_str;
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validator_str.pubkey;
        infrared.addValidators(validators);
        vm.stopPrank();

        // 2. Mint ibgt to some random address, such that total supply of ibgt is 10000 ether
        vm.prank(address(infrared));
        ibgt.mint(address(12), 10000 ether);
        vm.startPrank(address(blockRewardController));
        // 3. Mint bgt to the Infrared, to simulate the rewards.
        bgt.mint(address(infrared), 11000 ether);
        vm.stopPrank();
        deal(address(bgt), 11000 ether);

        assertTrue(
            bgt.balanceOf(address(infrared)) > ibgt.totalSupply(),
            "Infrared should have more BGT than total supply of InfraredBGT"
        );

        // Store initial balances
        uint256 receivorBalanceBefore = ibera.receivor().balance;

        // 4. Call harvestBase to distribute the rewards
        vm.expectEmit();
        emit IInfrared.BaseHarvested(admin, 1000 ether);
        infrared.harvestBase();

        // Check that ETH was sent to InfraredBERA receivor
        uint256 receivorBalanceAfter = ibera.receivor().balance;
        assertTrue(
            receivorBalanceAfter > receivorBalanceBefore,
            "InfraredBERA receivor should have received ETH"
        );

        // 5. Call harvestOperatorRewards to distribute the rewards
        // 5.1 mint some ibera shares to randrom contract
        deal(address(this), 20000 ether);
        ibera.mint{value: 11000 ether}(address(this));

        // 5.2 call harvestOperatorRewards to distribute the rewards
        infrared.harvestOperatorRewards();
        assertTrue(
            ibera.balanceOf(address(infrared.distributor())) > 0,
            "Infrared should have received operator rewards"
        );

        // 6. Claim rewards as validator (if needed in new system)
        vm.startPrank(validator);
        infrared.distributor().claim(validator_str.pubkey, validator_str.addr);
        vm.stopPrank();

        // Verify validator received expected rewards
        assertTrue(
            ibera.balanceOf(address(validator)) > 0,
            "Validator should have received rewards"
        );
    }

    function testharvestBribesSuccess() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(mockAsset), true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockAsset);

        uint256 mintMockAssetAmount = 10000000;
        uint256 mintNativeAssetAmount = 100 ether;
        mockAsset.mint(address(infrared), mintMockAssetAmount);
        vm.deal(address(infrared), mintNativeAssetAmount);

        address collectAddress = address(collector);

        uint256 mockAssetFeeAmount =
            infrared.protocolFeeAmounts(address(mockAsset));

        vm.expectEmit(true, true, true, true);
        emit IInfrared.BribeSupplied(
            collectAddress,
            address(mockAsset),
            mintMockAssetAmount - mockAssetFeeAmount
        );

        address user = address(10);
        vm.startPrank(user);
        infrared.harvestBribes(tokens);

        assertEq(
            mockAsset.balanceOf(address(collector)),
            mintMockAssetAmount - mockAssetFeeAmount,
            "Collector should receive the mockAsset bribe"
        );
    }

    function testharvestBribesNotWhitelistedToken() public {
        MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockAsset);

        vm.expectEmit(true, false, false, true);
        emit IInfrared.RewardTokenNotSupported(address(mockAsset));

        address user = address(10);
        vm.startPrank(user);
        infrared.harvestBribes(tokens);
    }

    function testharvestBoostRewards() public {
        // 1. Add a validator to the validator set
        vm.startPrank(infraredGovernance);
        ValidatorTypes.Validator memory validator_str = ValidatorTypes.Validator({
            pubkey: "0x1234567890abcdef",
            addr: address(validator)
        });
        ValidatorTypes.Validator[] memory validators =
            new ValidatorTypes.Validator[](1);
        validators[0] = validator_str;

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validator_str.pubkey;

        infrared.addValidators(validators);
        vm.stopPrank();

        // Step 2: Vault Registration

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(ibgt);
        rewardTokens[1] = address(ir);
        // InfraredVault vault = InfraredVault(
        //     address(infrared.registerVault(address(wbera), rewardTokens))
        // );
        InfraredVault vault = infraredVault;

        vm.prank(address(infrared));
        ibgt.mint(address(infraredGovernance), 100 ether);
        vm.startPrank(address(blockRewardController));

        bgt.mint(address(infrared), 101 ether);

        vm.stopPrank();

        address ibgtVault = address(infrared.ibgtVault());

        infrared.harvestBase();

        // ========================================================
        // HARVEST BASE PART
        // ========================================================

        // Assumed that there are some boost rewards in the contract.
        // MockERC20 mockAsset = new MockERC20("MockAsset", "MCK", 18);
        // factory.createRewardsVault(address(mockAsset));
        // Step 1: Vault Registration
        // InfraredVault vault = InfraredVault(
        //     address(infrared.registerVault(address(wbera), rewardTokens))
        // );

        vm.startPrank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(address(wbera), true);
        vm.stopPrank();

        // Step 2: User Interaction - Staking Tokens
        address user = address(10);
        vm.deal(address(user), 1000 ether);
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        wbera.deposit{value: stakeAmount}();
        wbera.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();

        // Step 3: Reward Accrual via Rewards Factory (Simulate Reward Increase)
        // Assuming factory and infrared contracts have been set up to interact correctly
        address vaultWbera = factory.getVault(address(wbera));

        vm.startPrank(address(blockRewardController));
        bgt.mint(address(distributor), 100 ether);
        vm.stopPrank();

        vm.startPrank(address(distributor));
        bgt.approve(address(vaultWbera), 100 ether);
        IBerachainRewardsVault(vaultWbera).notifyRewardAmount(
            abi.encodePacked(bytes32("v0"), bytes16("")), 100 ether
        );
        vm.stopPrank();

        // Step 4: Passage of Time for Rewards Distribution
        vm.warp(block.timestamp + 10 days); // Simulating 10 days for reward accrual

        // Step 5: Harvest Vault - Distributing Rewards

        vm.startPrank(address(vault));
        vault.rewardsVault().setOperator(address(infrared));

        vm.startPrank(keeper);
        infrared.harvestVault(address(wbera));
        vm.stopPrank();

        // Step 6: Calculate the amounts to queue.
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = uint128(bgt.balanceOf(address(infrared)))
            - bgt.queuedBoost(address(infrared)) - bgt.boosts(address(infrared));

        // Step 7: Queue the boosts.
        vm.startPrank(address(keeper));
        infrared.queueBoosts(pubkeys, amounts);
        vm.stopPrank();

        // move forward beyond buffer length so enough time passed through buffer
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1);

        // activate boost
        infrared.activateBoosts(pubkeys);

        // uint256 earned = bgtStaker.earned(address(infrared));

        uint256 ibgtVaultWberaBalanceBefore =
            wbera.balanceOf(address(ibgtVault));

        vm.startPrank(address(feeCollector));
        vm.deal(address(feeCollector), 100 ether);
        wbera.deposit{value: 100 ether}();
        wbera.transfer(address(bgt.staker()), 100 ether);
        BGTStaker(bgt.staker()).notifyRewardAmount(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days); // Simulate passage of time for reward distribution

        infrared.harvestBoostRewards();

        uint256 ibgtVaultWberaBalanceAfter = wbera.balanceOf(address(ibgtVault));
        assertTrue(
            ibgtVaultWberaBalanceAfter > ibgtVaultWberaBalanceBefore,
            "Vault should have more wBera after harvest"
        );
    }

    function testRegisterVault() public {
        // pause staking
        vm.prank(infraredGovernance);
        infrared.setVaultRegistrationPauseStatus(true);

        // assert revert during pause
        vm.expectRevert(Errors.RegistrationPaused.selector);
        InfraredVault(address(infrared.registerVault(address(honey))));

        // un-pause staking
        vm.prank(infraredGovernance);
        infrared.setVaultRegistrationPauseStatus(false);

        // assert anyone can register a new vault
        InfraredVault(address(infrared.registerVault(address(honey))));
    }

    function testSetRedSuccess() public {
        // Create new IR token mock
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        // Grant MINTER_ROLE to infrared contract
        // newIR.grantRole(newIR.MINTER_ROLE(), address(infrared));

        // Start recording storage access
        vm.record();

        // Set IR token
        vm.prank(infraredGovernance);
        infrared.setIR(address(newIR));

        assertEq(address(infrared.ir()), address(newIR));

        assertTrue(
            infrared.whitelistedRewardTokens(address(newIR)),
            "IR token not whitelisted"
        );
    }

    function testSetRedFailsZeroAddress() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAddress.selector);
        infrared.setIR(address(0));
    }

    function testSetRedFailsAlreadySet() public {
        // First set
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );
        // newIR.grantRole(newIR.MINTER_ROLE(), address(infrared));
        vm.prank(infraredGovernance);
        infrared.setIR(address(newIR));

        // Try to set again
        InfraredGovernanceToken anotherIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );
        // anotherIR.grantRole(anotherIR.MINTER_ROLE(), address(infrared));
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.AlreadySet.selector);
        infrared.setIR(address(anotherIR));
    }

    function testSetRedFailsAccessControll() public {
        // Create IR token without granting MINTER_ROLE
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(12),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        vm.startPrank(address(123));
        vm.expectRevert();
        infrared.setIR(address(newIR));
    }

    function testSetRedFailsMinterUnauthorized() public {
        // Create IR token without granting MINTER_ROLE
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(12),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );
        vm.prank(infraredGovernance);
        vm.expectRevert(
            abi.encodeWithSignature("Unauthorized(address)", address(infrared))
        );
        infrared.setIR(address(newIR));
    }

    function testUpdateirMintRateSuccess() public {
        // Setup: First set IR token
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );
        // newIR.grantRole(newIR.MINTER_ROLE(), address(infrared));
        vm.prank(infraredGovernance);
        infrared.setIR(address(newIR));

        // Get the base slot from the public constant
        bytes32 baseSlot = infrared.REWARDS_STORAGE_LOCATION();

        // IRMintRate is after 9 addresses and 1 mapping in the struct
        bytes32 irMintRateSlot = bytes32(uint256(baseSlot) + 1);

        // Start recording storage access for debugging
        vm.record();

        // Test case 1: Set rate to 0.5 IR per InfraredBGT
        uint256 halfRate = 500_000; // 0.5 * 1e6
        vm.prank(infraredGovernance);
        infrared.updateIRMintRate(halfRate);

        // Verify irMintRate in internal storage
        bytes32 storedValue = vm.load(address(infrared), irMintRateSlot);
        uint256 irMintRate = uint256(storedValue);

        assertEq(
            irMintRate, halfRate, "Internal storage mismatch for half rate"
        );

        // Test case 2: Set rate to 2 IR per InfraredBGT
        uint256 doubleRate = 2_000_000; // 2 * 1e6
        vm.prank(infraredGovernance);
        infrared.updateIRMintRate(doubleRate);

        // Verify irMintRate in internal storage again
        storedValue = vm.load(address(infrared), irMintRateSlot);
        irMintRate = uint256(storedValue);

        assertEq(
            irMintRate, doubleRate, "Internal storage mismatch for double rate"
        );
    }

    function testRedMintingRatioHalf() public {
        // Setup: Set IR token and mint rate to 0.5
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        vm.startPrank(infraredGovernance);
        infrared.setIR(address(newIR));
        infrared.updateIRMintRate(500_000); // 0.5 * 1e6
        vm.stopPrank();

        // Setup vault and rewards
        address user = address(10);
        uint256 stakeAmount = 1000 ether;
        stakeInVault(address(ibgtVault), address(ibgt), user, stakeAmount);

        // Simulate BGT rewards
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        vm.stopPrank();

        // Harvest rewards
        vm.prank(keeper);
        infrared.harvestVault(address(wbera));

        // Verify IR minting ratio (0.5 IR per InfraredBGT)
        uint256 redBalance = newIR.balanceOf(address(ibgtVault));
        uint256 ibgtBalance = ibgt.balanceOf(address(ibgtVault));
        assertApproxEqRel(redBalance, ibgtBalance / 2, 1e16); // 1% tolerance
    }

    function testRedMintingRatioDouble() public {
        // Setup: Set IR token and mint rate to 2.0
        InfraredGovernanceToken newIR = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        vm.startPrank(infraredGovernance);
        infrared.setIR(address(newIR));
        infrared.updateIRMintRate(2_000_000); // 2 * 1e6
        vm.stopPrank();

        // Setup vault and rewards
        address user = address(10);
        uint256 stakeAmount = 1000 ether;
        stakeInVault(address(ibgtVault), address(ibgt), user, stakeAmount);

        // Simulate BGT rewards
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        vm.stopPrank();

        // Harvest rewards
        vm.prank(keeper);
        infrared.harvestVault(address(wbera));

        // Verify IR minting ratio (2 IR per InfraredBGT)
        uint256 redBalance = newIR.balanceOf(address(ibgtVault));
        uint256 ibgtBalance = ibgt.balanceOf(address(ibgtVault));
        assertApproxEqRel(redBalance, ibgtBalance * 2, 1e16); // 1% tolerance
    }

    /* TODO: fix
    function testEndToEndHarvestValidator() public {
        // Staking by User in InfraredBGT Vault
        address user = address(10);
        uint256 stakeAmount = 1000 * 1e18;
        ibgt.mint(user, stakeAmount);
        vm.startPrank(user);
        ibgt.approve(address(ibgtVault), stakeAmount);
        ibgtVault.stake(stakeAmount);
        vm.stopPrank();

        // Simulate Rewards from Validators
        // TODO: For Validator 1 with token rewards

        // Harvesting Rewards from Validators
        vm.prank(keeper);
        // TODO: infrared.harvestValidator(validator);

        // TODO: For Validator 2 with token rewards

        vm.prank(keeper);
        // TODO: fix infrared.harvestValidator(validator2);

        // Time Skip for Reward Distribution
        vm.warp(block.timestamp + 30 days); // Simulate passage of time for reward distribution

        // Claiming Rewards and Checking Balances
        vm.startPrank(user);
        ibgtVault.getReward();
        uint256 rewardBalanceBGT = ibgt.balanceOf(user);
        uint256 rewardBalanceBERA = mockWbera.balanceOf(user);
        vm.stopPrank();
        assertTrue(rewardBalanceBGT > 0, "User should have BGT rewards");
        assertTrue(rewardBalanceBERA > 0, "User should have BERA rewards");

        // Withdrawal by User
        vm.startPrank(user);
        ibgtVault.withdraw(stakeAmount);
        uint256 finalBalance = ibgt.balanceOf(user);
        vm.stopPrank();
        // Final balance expected is the sum of initially staked amount and rewards received
        uint256 expectedFinalBalance = stakeAmount + rewardBalanceBGT;
        assertEq(
            finalBalance,
            expectedFinalBalance,
            "User final balance should be sum of staked amount and BGT rewards"
        );

        // Final Assertions
        assertEq(
            ibgtVault.totalSupply(),
            0,
            "InfraredBGT Vault total supply should be zero after withdrawals"
        );
        assertEq(
            ibgtVault.balanceOf(user),
            0,
            "User balance in InfraredBGT Vault should be zero after withdrawal"
        );
    }

    ?*/
}
