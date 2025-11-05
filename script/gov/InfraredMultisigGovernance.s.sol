// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BatchScript} from "@forge-safe/BatchScript.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {
    IInfraredVault,
    InfraredV1_9,
    ValidatorTypes
} from "src/core/InfraredV1_9.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";
import {BribeCollectorV1_4} from "src/core/BribeCollectorV1_4.sol";
import {HarvestBaseCollectorV1_2} from
    "src/staking/HarvestBaseCollectorV1_2.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";

import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
}

contract InfraredMultisigGovernance is BatchScript {
    // Validator Management

    /// @notice add validator and set deposit signature
    function onboardValidator(
        address safe,
        address payable infrared,
        address ibera,
        address addr,
        bytes calldata pubkey,
        bytes calldata signature
    ) public isBatch(safe) {
        ValidatorTypes.Validator[] memory _validators =
            new ValidatorTypes.Validator[](1);
        _validators[0] = ValidatorTypes.Validator({pubkey: pubkey, addr: addr});

        // add validator to contracts
        bytes memory data = abi.encodeWithSignature(
            "addValidators((bytes,address)[])", _validators
        );
        addToBatch(infrared, 0, data);

        // set init 10k deposit sig
        data = abi.encodeWithSignature(
            "setDepositSignature(bytes,bytes)", pubkey, signature
        );
        addToBatch(ibera, 0, data);

        // not yet operator until 10k deposit
        // set commission 100%
        // uint96 maxCommissionRate = 10000; // 100% = 10000 in BeraChef
        // data = abi.encodeWithSignature(
        //     "queueValCommission(bytes,uint96)", pubkey, maxCommissionRate
        // );
        // addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function addValidator(
        address safe,
        address payable infrared,
        address addr,
        bytes calldata pubkey
    ) public isBatch(safe) {
        ValidatorTypes.Validator[] memory _validators =
            new ValidatorTypes.Validator[](1);
        _validators[0] = ValidatorTypes.Validator({pubkey: pubkey, addr: addr});

        bytes memory data = abi.encodeWithSignature(
            "addValidators((bytes,address)[])", _validators
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function removeValidator(
        address safe,
        address payable infrared,
        bytes calldata pubkey
    ) external isBatch(safe) {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = pubkey;

        bytes memory data =
            abi.encodeWithSignature("removeValidators(bytes[])", pubkeys);
        addToBatch(infrared, 0, data);

        executeBatch(true);
    }

    // Bribe collector management

    function setPayoutAmount(
        address safe,
        address collector,
        uint256 _newPayoutAmount
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "setPayoutAmount(uint256)", _newPayoutAmount
        );
        addToBatch(collector, 0, data);
        executeBatch(true);
    }

    function setPayoutToken(
        address safe,
        address collector,
        address _newPayoutToken
    ) external isBatch(safe) {
        if (
            safe == address(0) || collector == address(0)
                || _newPayoutToken == address(0)
        ) revert();
        bytes memory data =
            abi.encodeWithSignature("setPayoutToken(address)", _newPayoutToken);
        addToBatch(collector, 0, data);
        executeBatch(true);
    }

    // Vault Management

    function addReward(
        address safe,
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external isBatch(safe) {
        if (!InfraredV1_9(infrared).whitelistedRewardTokens(_rewardsToken)) {
            // Infrared(infrared).updateWhiteListedRewardTokens(_rewardsToken, true);
            bytes memory data0 = abi.encodeWithSignature(
                "updateWhiteListedRewardTokens(address,bool)",
                _rewardsToken,
                true
            );
            addToBatch(infrared, 0, data0);
        }
        bytes memory data = abi.encodeWithSignature(
            "addReward(address,address,uint256)",
            _stakingToken,
            _rewardsToken,
            _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        // vm.startBroadcast();
        executeBatch(true);
        // vm.stopBroadcast();
    }

    function removeReward(
        address safe,
        address payable infrared,
        address _stakingToken,
        address _rewardsToken
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "removeReward(address,address)", _stakingToken, _rewardsToken
        );
        addToBatch(infrared, 0, data);
        executeBatch(true);

        // IInfraredVault vault = Infrared(infrared).vaultRegistry(_stakingToken);
        // vault.getAllRewardTokens();
    }

    function multiSendToken(
        address safe,
        address token,
        uint256 totaAmount,
        address[] calldata users,
        uint256[] calldata amounts
    ) external isBatch(safe) {
        uint256 _totalAmount;

        if (users.length != amounts.length) revert();

        for (uint256 i; i < users.length; i++) {
            _totalAmount += amounts[i];
            bytes memory data = abi.encodeWithSignature(
                "transfer(address,uint256)", users[i], amounts[i]
            );
            addToBatch(token, 0, data);
        }

        // safety check
        if (_totalAmount != totaAmount) revert();

        executeBatch(true);
    }

    function updateWhiteListedRewardTokens(
        address safe,
        address payable infrared,
        address _token,
        bool _whitelisted
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "updateWhiteListedRewardTokens(address,bool)", _token, _whitelisted
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateMultipleWhiteListedRewardTokens(
        address safe,
        address payable infrared,
        address ibera,
        address[] calldata _tokens,
        bool _whitelisted
    ) external isBatch(safe) {
        uint256 len = _tokens.length;
        if (len == 0) revert();
        for (uint256 i; i < len; i++) {
            address _token = _tokens[i];
            // check not already whitelisted
            if (InfraredV1_9(infrared).whitelistedRewardTokens(_token)) {
                continue;
            }
            // Test the token before adding it to the batch (ibera proxy exception)
            if (_token == ibera || testToken(_token)) {
                bytes memory data = abi.encodeWithSignature(
                    "updateWhiteListedRewardTokens(address,bool)",
                    _token,
                    _whitelisted
                );
                addToBatch(infrared, 0, data);
            } else {
                // Log failure (requires Foundry's console.sol for scripting)
                console.log(
                    "Token at address %s failed tests and was skipped", _token
                );
            }
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function testToken(address token) internal view returns (bool) {
        IERC20 erc20 = IERC20(token);

        // ERC20 Compliance Checks
        try erc20.totalSupply() returns (uint256) {
            // Success
        } catch {
            console.log("Token %s failed totalSupply check", token);
            return false;
        }

        try erc20.balanceOf(address(0)) returns (uint256) {
            // Success
        } catch {
            console.log("Token %s failed balanceOf check", token);
            return false;
        }

        try erc20.allowance(address(0), address(0)) returns (uint256) {
            // Success
        } catch {
            console.log("Token %s failed allowance check", token);
            return false;
        }

        // Proxy Check
        if (isProxy(token)) {
            console.log("Token %s appears to be a proxy", token);
            return false; // Or handle as needed
        }

        return true; // Token passed all checks
    }

    function isProxy(address token) internal view returns (bool) {
        // EIP-1967 implementation slot
        bytes32 implSlot = bytes32(
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        );
        address impl = address(uint160(uint256(vm.load(token, implSlot))));
        if (impl != address(0)) {
            return true; // Likely a proxy
        }
        return false;
    }

    function updateRewardsDuration(
        address safe,
        address payable infrared,
        uint256 _rewardsDuration
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "updateRewardsDuration(uint256)", _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateRewardsDurationForVault(
        address safe,
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external isBatch(safe) {
        IInfraredVault vault =
            InfraredV1_9(infrared).vaultRegistry(_stakingToken);

        // Get current reward data
        (,, uint256 periodFinish, uint256 rewardRate,,,) =
            IMultiRewards(address(vault)).rewardData(_rewardsToken);

        bytes memory data;

        // Check if we're in a potentially problematic state
        bool isPeriodExpired = block.timestamp >= periodFinish;
        bool hasActiveRate = rewardRate > 0;

        if (isPeriodExpired && hasActiveRate) {
            // 1 wei will set rate to zero (for safety) and renew reward period, also for safety
            uint256 minAmount = 1;

            // Approve infrared to spend the amount
            data = abi.encodeWithSignature(
                "approve(address,uint256)", address(infrared), minAmount
            );
            addToBatch(_rewardsToken, 0, data);

            // Add incentives to reset the period
            // This will set periodFinish = block.timestamp + currentDuration
            data = abi.encodeWithSignature(
                "addIncentives(address,address,uint256)",
                _stakingToken,
                _rewardsToken,
                minAmount
            );
            addToBatch(infrared, 0, data);
        }

        // Update reward cache
        data = abi.encodeWithSignature("getRewardForUser(address)", address(0));
        addToBatch(address(vault), 0, data);

        // Update the reward duration
        data = abi.encodeWithSignature(
            "updateRewardsDurationForVault(address,address,uint256)",
            _stakingToken,
            _rewardsToken,
            _rewardsDuration
        );
        addToBatch(infrared, 0, data);

        executeBatch(true);
    }

    function updateRewardDurationsForAllVaults(
        address safe,
        address payable infrared,
        address[] calldata _stakingTokens,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external isBatch(safe) {
        // update infrared reward duration
        bytes memory data = abi.encodeWithSignature(
            "updateRewardsDuration(uint256)", _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        // update vaults
        for (uint256 i; i < _stakingTokens.length; i++) {
            address _stakingToken = _stakingTokens[i];
            data = abi.encodeWithSignature(
                "updateRewardsDurationForVault(address,address,uint256)",
                _stakingToken,
                _rewardsToken,
                _rewardsDuration
            );
            addToBatch(infrared, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function pauseVaultStaking(address payable infrared, address _asset)
        external
    {
        bytes memory data =
            abi.encodeWithSignature("pauseStaking(address)", _asset);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function pauseMultipleVaultStaking(
        address safe,
        address payable infrared,
        address[] calldata _assets
    ) external isBatch(safe) {
        for (uint256 i; i < _assets.length; i++) {
            address _asset = _assets[i];
            bytes memory data =
                abi.encodeWithSignature("pauseStaking(address)", _asset);
            addToBatch(infrared, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function unpauseVaultStaking(address payable infrared, address _asset)
        external
    {
        bytes memory data =
            abi.encodeWithSignature("unpauseStaking(address)", _asset);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function grantHypernativePauserRole(
        address payable infrared,
        address hypernative
    ) external {
        bytes32 role = InfraredV1_9(infrared).PAUSER_ROLE();
        bytes memory data = abi.encodeWithSignature(
            "grantRole(bytes32,address)", role, hypernative
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function revokeHypernativePauserRole(
        address payable infrared,
        address hypernative
    ) external {
        bytes32 role = InfraredV1_9(infrared).PAUSER_ROLE();
        bytes memory data = abi.encodeWithSignature(
            "revoke(bytes32,address)", role, hypernative
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    /// @dev grant new keeper role on infrared and ibera
    function grantKeeperRole(
        address safe,
        address payable infrared,
        address ibera,
        address keeper
    ) external isBatch(safe) {
        bytes32 role = InfraredV1_9(infrared).KEEPER_ROLE();
        bytes memory data =
            abi.encodeWithSignature("grantRole(bytes32,address)", role, keeper);
        addToBatch(infrared, 0, data);
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function grantKeeperRoleOnlyInfrared(
        address safe,
        address payable infrared,
        address keeper
    ) external isBatch(safe) {
        bytes32 role = InfraredV1_9(infrared).KEEPER_ROLE();
        bytes memory data =
            abi.encodeWithSignature("grantRole(bytes32,address)", role, keeper);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function grantKeeperRoleBaseCollector(
        address safe,
        address baseCollector,
        address keeper
    ) external isBatch(safe) {
        bytes32 role =
            HarvestBaseCollectorV1_2(payable(baseCollector)).KEEPER_ROLE();
        bytes memory data =
            abi.encodeWithSignature("grantRole(bytes32,address)", role, keeper);
        addToBatch(baseCollector, 0, data);

        executeBatch(true);
    }

    /// @dev revoke keeper role on infrared and ibera
    function revokeKeeperRole(
        address safe,
        address payable infrared,
        address ibera,
        address keeper
    ) external isBatch(safe) {
        bytes32 role = InfraredV1_9(infrared).KEEPER_ROLE();
        bytes memory data =
            abi.encodeWithSignature("revoke(bytes32,address)", role, keeper);
        addToBatch(infrared, 0, data);
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function claimLostRewardsOnVault(address payable infrared, address _asset)
        external
    {
        bytes memory data =
            abi.encodeWithSignature("claimLostRewardsOnVault(address)", _asset);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function recoverERC20(
        address safe,
        address payable infrared,
        address _to,
        address _token,
        uint256 _amount
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "recoverERC20(address,address,uint256)", _to, _token, _amount
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function recoverERC20FromVault(
        address payable infrared,
        address _asset,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "recoverERC20FromVault(address,address,address,uint256)",
            _asset,
            _to,
            _token,
            _amount
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function delegateBGT(address payable infrared, address _delegatee)
        external
    {
        bytes memory data =
            abi.encodeWithSignature("delegateBGT(address)", _delegatee);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateInfraredBERABribesWeight(
        address safe,
        address payable infrared,
        uint256 _weight
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "updateInfraredBERABribeSplit(uint256)", _weight
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateFee(
        address safe,
        address payable infrared,
        ConfigTypes.FeeType _t,
        uint256 _fee
    ) external isBatch(safe) {
        bytes memory data =
            abi.encodeWithSignature("updateFee(uint8,uint256)", _t, _fee);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function claimProtocolFees(
        address safe,
        address payable infrared,
        address _to,
        address[] calldata _tokens
    ) external isBatch(safe) {
        uint256 len = _tokens.length;
        for (uint256 i; i < len; i++) {
            bytes memory data = abi.encodeWithSignature(
                "claimProtocolFees(address,address)", _to, _tokens[i]
            );
            addToBatch(infrared, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function setVaultRegistrationPauseStatus(
        address payable infrared,
        bool pause
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "setVaultRegistrationPauseStatus(bool)", pause
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    // iBERA management

    function setWithdrawalsEnabled(address ibera, bool flag) external {
        bytes memory data =
            abi.encodeWithSignature("setWithdrawalsEnabled(bool)", flag);
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function setFeeDivisorShareholders(address ibera, uint16 to) external {
        bytes memory data =
            abi.encodeWithSignature("setFeeDivisorShareholders(uint16)", to);
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function setDepositSignature(
        address safe,
        address ibera,
        bytes calldata pubkey,
        bytes calldata signature
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "setDepositSignature(bytes,bytes)", pubkey, signature
        );
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function setFees(
        address safe,
        address payable infrared,
        address ibera,
        uint16 feeDivisorShareholders,
        uint256 operatorWeight,
        uint256 harvestOperatorFeeRate,
        uint256 harvestVaultFeeRate,
        uint256 harvestBribesFeeRate,
        uint256 harvestBoostFeeRate
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "setFeeDivisorShareholders(uint16)", feeDivisorShareholders
        );
        addToBatch(ibera, 0, data);

        data = abi.encodeWithSignature(
            "updateInfraredBERABribeSplit(uint256)", operatorWeight
        );
        addToBatch(infrared, 0, data);

        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestOperatorProtocolRate,
            1e6
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestVaultProtocolRate,
            1e6
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestBribesProtocolRate,
            1e6
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestBoostProtocolRate,
            1e6
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestOperatorFeeRate,
            harvestOperatorFeeRate
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestVaultFeeRate,
            harvestVaultFeeRate
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestBribesFeeRate,
            harvestBribesFeeRate
        );
        addToBatch(infrared, 0, data);
        data = abi.encodeWithSignature(
            "updateFee(uint8,uint256)",
            ConfigTypes.FeeType.HarvestBoostFeeRate,
            harvestBoostFeeRate
        );
        addToBatch(infrared, 0, data);

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function migrateVault(
        address safe,
        address infrared,
        address _asset,
        uint8 versionToUpgradeTo
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "migrateVault(address,uint8)", _asset, versionToUpgradeTo
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function migrateMultipleVaults(
        address safe,
        address infrared,
        address[] calldata _assets,
        uint8 versionToUpgradeTo
    ) external isBatch(safe) {
        uint256 len = _assets.length;
        if (len == 0) revert();
        for (uint256 i; i < len; i++) {
            bytes memory data = abi.encodeWithSignature(
                "migrateVault(address,uint8)", _assets[i], versionToUpgradeTo
            );
            addToBatch(infrared, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function queueValCommissions(
        address safe,
        address _infraredProxy,
        bytes[] calldata _pubkeys
    ) external isBatch(safe) {
        // input check
        if (safe == address(0) || _infraredProxy == address(0)) {
            revert();
        }

        // queue validator incentive commissions
        uint256 len = _pubkeys.length;
        uint96 maxCommissionRate = 10000; // 100% = 10000 in BeraChef
        for (uint256 i; i < len; i++) {
            bytes memory data = abi.encodeWithSignature(
                "queueValCommission(bytes,uint96)",
                _pubkeys[i],
                maxCommissionRate
            );
            addToBatch(_infraredProxy, 0, data);
        }

        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }
}
