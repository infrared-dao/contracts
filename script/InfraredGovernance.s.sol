// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {Infrared, ValidatorTypes} from "src/core/Infrared.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {Voter} from "src/voting/Voter.sol";

contract InfraredGovernance is Script {
    // Validator Management

    function addValidator(
        address payable infrared,
        address addr,
        bytes calldata pubkey
    ) public {
        ValidatorTypes.Validator[] memory _validators =
            new ValidatorTypes.Validator[](1);
        _validators[0] = ValidatorTypes.Validator({pubkey: pubkey, addr: addr});
        vm.startBroadcast();
        Infrared(infrared).addValidators(_validators);
        vm.stopBroadcast();
    }

    function removeValidator(address payable infrared, bytes calldata pubkey)
        external
    {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = pubkey;

        vm.startBroadcast();
        Infrared(infrared).removeValidators(pubkeys);
        vm.stopBroadcast();
    }

    // Bribe collector management

    function setPayoutAmount(address collector, uint256 _newPayoutAmount)
        external
    {
        vm.startBroadcast();
        BribeCollector(collector).setPayoutAmount(_newPayoutAmount);
        vm.stopBroadcast();
    }

    // Vault Management

    function addReward(
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        vm.startBroadcast();
        Infrared(infrared).addReward(
            _stakingToken, _rewardsToken, _rewardsDuration
        );
        vm.stopBroadcast();
    }

    function updateWhiteListedRewardTokens(
        address payable infrared,
        address _token,
        bool _whitelisted
    ) external {
        vm.startBroadcast();
        Infrared(infrared).updateWhiteListedRewardTokens(_token, _whitelisted);
        vm.stopBroadcast();
    }

    function updateRewardsDuration(
        address payable infrared,
        uint256 _rewardsDuration
    ) external {
        vm.startBroadcast();
        Infrared(infrared).updateRewardsDuration(_rewardsDuration);
        vm.stopBroadcast();
    }

    function updateRewardsDurationForVault(
        address payable infrared,
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        vm.startBroadcast();
        Infrared(infrared).updateRewardsDurationForVault(
            _stakingToken, _rewardsToken, _rewardsDuration
        );
        vm.stopBroadcast();
    }

    function toggleVault(address payable infrared, address _asset) external {
        vm.startBroadcast();
        Infrared(infrared).toggleVault(_asset);
        vm.stopBroadcast();
    }

    function claimLostRewardsOnVault(address payable infrared, address _asset)
        external
    {
        vm.startBroadcast();
        Infrared(infrared).claimLostRewardsOnVault(_asset);
        vm.stopBroadcast();
    }

    function recoverERC20(
        address payable infrared,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        vm.startBroadcast();
        Infrared(infrared).recoverERC20(_to, _token, _amount);
        vm.stopBroadcast();
    }

    function recoverERC20FromVault(
        address payable infrared,
        address _asset,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        vm.startBroadcast();
        Infrared(infrared).recoverERC20FromVault(_asset, _to, _token, _amount);
        vm.stopBroadcast();
    }

    function delegateBGT(address payable infrared, address _delegatee)
        external
    {
        vm.startBroadcast();
        Infrared(infrared).delegateBGT(_delegatee);
        vm.stopBroadcast();
    }

    function updateInfraredBERABribesWeight(
        address payable infrared,
        uint256 _weight
    ) external {
        vm.startBroadcast();
        Infrared(infrared).updateInfraredBERABribesWeight(_weight);
        vm.stopBroadcast();
    }

    function updateFee(
        address payable infrared,
        ConfigTypes.FeeType _t,
        uint256 _fee
    ) external {
        vm.startBroadcast();
        Infrared(infrared).updateFee(_t, _fee);
        vm.stopBroadcast();
    }

    function claimProtocolFees(
        address payable infrared,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        vm.startBroadcast();
        Infrared(infrared).claimProtocolFees(_to, _token, _amount);
        vm.stopBroadcast();
    }

    function setVaultRegistrationPauseStatus(
        address payable infrared,
        bool pause
    ) external {
        vm.startBroadcast();
        Infrared(infrared).setVaultRegistrationPauseStatus(pause);
        vm.stopBroadcast();
    }

    // iBERA management

    function setWithdrawalsEnabled(address ibera, bool flag) external {
        vm.startBroadcast();
        InfraredBERA(ibera).setWithdrawalsEnabled(flag);
        vm.stopBroadcast();
    }

    function setFeeDivisorShareholders(address ibera, uint16 to) external {
        vm.startBroadcast();
        InfraredBERA(ibera).setFeeDivisorShareholders(to);
        vm.stopBroadcast();
    }

    function setDepositSignature(
        address ibera,
        bytes calldata pubkey,
        bytes calldata signature
    ) external {
        vm.startBroadcast();
        InfraredBERA(ibera).setDepositSignature(pubkey, signature);
        vm.stopBroadcast();
    }

    // Voter management

    function setMaxVotingNum(address voter, uint256 _maxVotingNum) external {
        vm.startBroadcast();
        Voter(voter).setMaxVotingNum(_maxVotingNum);
        vm.stopBroadcast();
    }

    function whitelistNFT(address voter, uint256 _tokenId, bool _bool)
        external
    {
        vm.startBroadcast();
        Voter(voter).whitelistNFT(_tokenId, _bool);
        vm.stopBroadcast();
    }

    function reviveBribeVault(address voter, address _stakingToken) external {
        vm.startBroadcast();
        Voter(voter).reviveBribeVault(_stakingToken);
        vm.stopBroadcast();
    }

    function killBribeVault(address voter, address _stakingToken) external {
        vm.startBroadcast();
        Voter(voter).killBribeVault(_stakingToken);
        vm.stopBroadcast();
    }
}
