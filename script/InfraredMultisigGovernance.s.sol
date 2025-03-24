// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BatchScript} from "@forge-safe/BatchScript.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {Infrared, ValidatorTypes} from "src/core/Infrared.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {Voter} from "src/voting/Voter.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";

contract InfraredMultisigGovernance is BatchScript {
    // Validator Management

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
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    // Bribe collector management

    function setPayoutAmount(address collector, uint256 _newPayoutAmount)
        external
    {
        bytes memory data = abi.encodeWithSignature(
            "setPayoutAmount(uint256)", _newPayoutAmount
        );
        addToBatch(collector, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    // Vault Management

    function addReward(
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "addReward(address,address,uint256)",
            _stakingToken,
            _rewardsToken,
            _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateWhiteListedRewardTokens(
        address payable infrared,
        address _token,
        bool _whitelisted
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "updateWhiteListedRewardTokens(address,bool)", _token, _whitelisted
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
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
        bytes memory data = abi.encodeWithSignature(
            "updateRewardsDurationForVault(address,address,uint256)",
            _stakingToken,
            _rewardsToken,
            _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
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
        bytes32 role = Infrared(infrared).PAUSER_ROLE();
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
        bytes32 role = Infrared(infrared).PAUSER_ROLE();
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
        bytes32 role = Infrared(infrared).KEEPER_ROLE();
        bytes memory data =
            abi.encodeWithSignature("grantRole(bytes32,address)", role, keeper);
        addToBatch(infrared, 0, data);
        addToBatch(ibera, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    /// @dev revoke keeper role on infrared and ibera
    function revokeKeeperRole(
        address safe,
        address payable infrared,
        address ibera,
        address keeper
    ) external isBatch(safe) {
        bytes32 role = Infrared(infrared).KEEPER_ROLE();
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
        address payable infrared,
        address _to,
        address _token,
        uint256 _amount
    ) external {
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
        address payable infrared,
        uint256 _weight
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "updateInfraredBERABribesWeight(uint256)", _weight
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
        address _token
    ) external isBatch(safe) {
        bytes memory data = abi.encodeWithSignature(
            "claimProtocolFees(address,address)", _to, _token
        );
        addToBatch(infrared, 0, data);
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

    // Voter management

    function setMaxVotingNum(address voter, uint256 _maxVotingNum) external {
        bytes memory data =
            abi.encodeWithSignature("setMaxVotingNum(uint256)", _maxVotingNum);
        addToBatch(voter, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function whitelistNFT(address voter, uint256 _tokenId, bool _bool)
        external
    {
        bytes memory data = abi.encodeWithSignature(
            "whitelistNFT(uint256,bool)", _tokenId, _bool
        );
        addToBatch(voter, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function reviveBribeVault(address voter, address _stakingToken) external {
        bytes memory data =
            abi.encodeWithSignature("reviveBribeVault(address)", _stakingToken);
        addToBatch(voter, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function killBribeVault(address voter, address _stakingToken) external {
        bytes memory data =
            abi.encodeWithSignature("killBribeVault(address)", _stakingToken);
        addToBatch(voter, 0, data);
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
}
