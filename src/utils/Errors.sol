// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library Errors {
    // General errors.
    error ZeroAddress();
    error ZeroAmount();
    error UnderFlow();
    error InvalidArrayLength();
    error AlreadySet();

    // ValidatorSet errors.
    error ValidatorAlreadyExists();
    error FailedToAddValidator();
    error ValidatorDoesNotExist();

    // InfraredVault errors.
    error MaxNumberOfRewards();
    error Unauthorized(address sender);
    error IBGTNotRewardToken();
    error IREDNotRewardToken();
    error IBGTNotStakingToken();
    error StakedInRewardsVault();
    error NoRewardsVault();
    error RegistrationPaused();
    error RewardTokenNotWhitelisted();

    // InfraredValidators errors.
    error InvalidValidator();
    error InvalidOperator();
    error InvalidDepositAmount();
    error ValidatorAlreadyRemoved();

    // Infrared errors.
    error VaultNotSupported();
    error InvalidNonce();
    error VaultNotStaked();
    error ClaimDistrRewardsFailed();
    error ClaimableRewardsExist();
    error DuplicateAssetAddress();
    error VaultDeploymentFailed();
    error RewardTokenNotSupported();
    error BGTBalanceMismatch();
    error NotInfrared();
    error NotInitialized();
    error InvalidFee();
    error InvalidCommissionRate();
    error InvalidDelegatee();
    error InvalidWeight();
    error MaxProtocolFeeAmount();
    error BoostExceedsSupply();
    error ETHTransferFailed();
    error TokensReservedForProtocolFees();
    error NoRewardsToClaim();

    // iBERA erros
    error InvalidAmount();
    error InvalidShares();
    error WithdrawalsNotEnabled();
    error InvalidSignature();
    error InvalidReceiver();
    error CallFailed();
    error InvalidReserves();
    error UnauthorizedOperator();
    error ValidatorForceExited();
    error CanNotCompoundAccumuldatedBERA();
}
