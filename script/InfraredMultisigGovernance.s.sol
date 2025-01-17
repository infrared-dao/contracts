// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {BatchScript} from "forge-safe/BatchScript.sol";

import {Infrared, ValidatorTypes} from "src/core/Infrared.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {Voter} from "src/voting/Voter.sol";

contract InfraredGovernance is BatchScript {
    // Validator Management

    function addValidator(
        address payable infrared,
        address addr,
        bytes calldata pubkey
    ) public {
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

    function removeValidator(address payable infrared, bytes calldata pubkey)
        external
    {
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
        address payable infrared,
        uint256 _rewardsDuration
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "updateRewardsDuration(uint256)", _rewardsDuration
        );
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function updateRewardsDurationForVault(
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
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

    function toggleVault(address payable infrared, address _asset) external {
        bytes memory data =
            abi.encodeWithSignature("toggleVault(address)", _asset);
        addToBatch(infrared, 0, data);
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
        address payable infrared,
        ConfigTypes.FeeType _t,
        uint256 _fee
    ) external {
        bytes memory data =
            abi.encodeWithSignature("updateFee(uint8,uint256)", _t, _fee);
        addToBatch(infrared, 0, data);
        vm.startBroadcast();
        executeBatch(true);
        vm.stopBroadcast();
    }

    function claimProtocolFees(
        address payable infrared,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        bytes memory data = abi.encodeWithSignature(
            "claimProtocolFees(address,address,uint256)", _to, _token, _amount
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
        address ibera,
        bytes calldata pubkey,
        bytes calldata signature
    ) external {
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
}
