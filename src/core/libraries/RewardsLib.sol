// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewardVault as IBerachainRewardsVault} from
    "@berachain/pol/interfaces/IRewardVault.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {IInfraredDistributor} from "src/interfaces/IInfraredDistributor.sol";
import {IBerachainBGTStaker} from "src/interfaces/IBerachainBGTStaker.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {ConfigTypes} from "src/core/libraries/ConfigTypes.sol";
import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IReward} from "src/voting/interfaces/IReward.sol";
import {IVoter} from "src/voting/interfaces/IVoter.sol";
import {DataTypes} from "src/utils/DataTypes.sol";
import {IWBERA} from "src/interfaces/IWBERA.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {IInfraredGovernanceToken} from
    "src/interfaces/IInfraredGovernanceToken.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";
import {Errors} from "src/utils/Errors.sol";

library RewardsLib {
    using SafeTransferLib for ERC20;

    struct RewardsStorage {
        mapping(address => uint256) protocolFeeAmounts; // Tracks accumulated protocol fees per token
        uint256 irMintRate; // Rate for minting IR tokens
        uint256 collectBribesWeight;
        mapping(uint256 => uint256) fees; // Fee configuration
    }

    /**
     * @notice IR mint rate in hundredths of 1 bip
     * @dev Used as the denominator when calculating IR minting (1e6)
     */
    uint256 internal constant RATE_UNIT = 1e6;

    /**
     * @notice Weight units when partitioning reward amounts in hundredths of 1 bip
     * @dev Used as the denominator when calculating weighted distributions (1e6)
     */
    uint256 internal constant WEIGHT_UNIT = 1e6;

    /**
     * @notice Protocol fee rate in hundredths of 1 bip
     * @dev Used as the denominator when calculating protocol fees (1e6)
     */
    uint256 internal constant FEE_UNIT = 1e6;

    /// @notice Emitted when Red cannot be minted during a harvest because of pause
    event RedNotMinted(uint256 amount);

    /// @notice Calculates how fees are split between protocol, voters, and the recipient.
    /// @notice _amt            The amount of rewards in wei
    /// @notice _feeTotal       The fee rate out of 1e6
    /// @notice _feeProtocol    The protocol fee rate out of 1e6
    function chargedFeesOnRewards(
        uint256 _amt,
        uint256 _feeTotal,
        uint256 _feeProtocol
    )
        external
        pure
        returns (uint256 amtRecipient, uint256 amtVoter, uint256 amtProtocol)
    {
        (amtRecipient, amtVoter, amtProtocol) =
            _chargedFeesOnRewards(_amt, _feeTotal, _feeProtocol);
    }

    /// @notice Internal logic for chargedFeesOnRewards
    /// @notice _amt            The amount of rewards in wei
    /// @notice _feeTotal       The fee rate out of 1e6
    /// @notice _feeProtocol    The protocol fee rate out of 1e6
    ///
    /// @return amtRecipient    The amount of rewards for the recipient
    /// @return amtVoter        The amount of rewards for the voter
    /// @return amtProtocol     The amount of rewards for the protocol
    function _chargedFeesOnRewards(
        uint256 _amt,
        uint256 _feeTotal,
        uint256 _feeProtocol
    )
        internal
        pure
        returns (uint256 amtRecipient, uint256 amtVoter, uint256 amtProtocol)
    {
        amtRecipient = _amt;
        if (_feeTotal == 0) return (amtRecipient, 0, 0);

        uint256 _amtTotal = amtRecipient * _feeTotal / FEE_UNIT; // FEE_UNIT = 1e6
        amtProtocol =
            amtRecipient * _feeTotal * _feeProtocol / (FEE_UNIT * FEE_UNIT); // Protocol's share
        amtVoter = _amtTotal - amtProtocol; // Remainder for voter
        amtRecipient -= (amtProtocol + amtVoter); // Deduct fees from recipient
    }

    /// @notice Distributes fees on rewards to the protocol, voter, and recipient.
    /// @notice _protocolFeeAmounts The accumulator for protocol fees per token
    /// @notice _voter              The address of the voter
    /// @notice _token              The address of the reward token
    /// @notice _amtVoter           The amount of rewards for the voter
    /// @notice _amtProtocol        The amount of rewards for the protocol
    function _distributeFeesOnRewards(
        mapping(address => uint256) storage protocolFeeAmounts,
        address _voter,
        address _token,
        uint256 _amtVoter,
        uint256 _amtProtocol
    ) internal {
        // add protocol fees to accumulator for token
        protocolFeeAmounts[_token] += _amtProtocol;

        // forward voter fees
        if (_amtVoter > 0) {
            address voterFeeVault = IVoter(_voter).feeVault();
            ERC20(_token).safeApprove(voterFeeVault, _amtVoter);
            IReward(voterFeeVault).notifyRewardAmount(_token, _amtVoter);
        }

        emit IInfrared.ProtocolFees(_token, _amtProtocol, _amtVoter);
    }

    /// @notice Harvet's base rewards from the BGT contract, ie rewards from Distributor, given in BGT
    ///     ref - https://github.com/berachain/contracts-monorepo/blob/main/src/pol/rewards/Distributor.sol#L160
    /// @param bgt      The address of the BGT token
    /// @param ibgt     The address of the InfraredBGT token
    /// @param ibera    The address of the InfraredBERA token
    ///
    /// @return bgtAmt  The amount of BGT rewards harvested
    function harvestBase(address bgt, address ibgt, address ibera)
        external
        returns (uint256 bgtAmt)
    {
        uint256 minted = IInfraredBGT(ibgt).totalSupply();
        uint256 bgtBalance = _getBGTBalance(bgt);
        // @dev should never happen but check in case
        if (bgtBalance < minted) revert Errors.UnderFlow();

        bgtAmt = bgtBalance - minted;
        if (bgtAmt == 0) return 0;

        // Redeem BGT for BERA and send to InfraredBERA receivor
        // No fee deduction needed here as fees will be handled by
        // subsequent harvest calls through the InfraredBERA receiver's logic
        IBerachainBGT(bgt).redeem(IInfraredBERA(ibera).receivor(), bgtAmt);
    }

    /// @notice Harvest's ERC20 Rewards from the vault
    /// @notice BGT transferred here directly to the user https://github.com/berachain/contracts-monorepo/blob/c374de32077ede0147985cf2bf6ed89570244a7e/src/pol/rewards/RewardVault.sol#L404
    /// @param vault            The address of the InfraredRewardVault, wrapping an underlying RewardVault
    /// @param bgt              The address of the BGT token
    /// @param ibgt             The address of the InfraredBGT token
    /// @param voter            The address of the voter (0 until IR token is live)
    /// @param ir               The address of the Infrared token
    /// @param rewardsDuration  The duration of the rewards
    /// 
    /// @return bgtAmt The amount of BGT rewards harvested
    function harvestVault(
        RewardsStorage storage $,
        IInfraredVault vault,
        address bgt,
        address ibgt,
        address voter,
        address ir,
        uint256 rewardsDuration
    ) external returns (uint256 bgtAmt) {
        // Ensure the vault is valid
        if (vault == IInfraredVault(address(0))) {
            revert Errors.VaultNotSupported();
        }

        // Record the BGT balance before claiming rewards
        uint256 balanceBefore = _getBGTBalance(bgt);

        // Get the rewards from the vault's reward vault
        IBerachainRewardsVault rewardsVault = vault.rewardsVault();
        rewardsVault.getReward(address(vault), address(this));

        // Calculate the amount of BGT rewards received
        bgtAmt = _getBGTBalance(bgt) - balanceBefore;

        // If no BGT rewards were received, exit early
        if (bgtAmt == 0) return bgtAmt;

        // Mint InfraredBGT tokens equivalent to the BGT rewards
        IInfraredBGT(ibgt).mint(address(this), bgtAmt);

        // Calculate and distribute fees on the BGT rewards
        (uint256 _amt, uint256 _amtVoter, uint256 _amtProtocol) =
        _chargedFeesOnRewards(
            bgtAmt,
            $.fees[uint256(ConfigTypes.FeeType.HarvestVaultFeeRate)],
            $.fees[uint256(ConfigTypes.FeeType.HarvestVaultProtocolRate)]
        );
        _distributeFeesOnRewards(
            $.protocolFeeAmounts, voter, ibgt, _amtVoter, _amtProtocol
        );

        // Send the remaining InfraredBGT rewards to the vault
        if (_amt > 0) {
            ERC20(ibgt).safeApprove(address(vault), _amt);
            vault.notifyRewardAmount(ibgt, _amt);
        }

        uint256 mintRate = $.irMintRate;

        // If IR token is set and mint rate is greater than zero, handle IR rewards
        if (ir != address(0) && mintRate > 0) {
            // Calculate the amount of IR tokens to mint
            uint256 irAmt = bgtAmt * mintRate / RATE_UNIT;
            try IInfraredGovernanceToken(ir).mint(address(this), irAmt) {
                {
                    // Check if IR is already a reward token in the vault
                    (, uint256 IRRewardsDuration,,,,,) = vault.rewardData(ir);
                    if (IRRewardsDuration == 0) {
                        // Add IR as a reward token if not already added
                        vault.addReward(ir, rewardsDuration);
                    }
                }

                // Send the remaining IR rewards to the vault
                if (irAmt > 0) {
                    ERC20(ir).safeApprove(address(vault), irAmt);
                    vault.notifyRewardAmount(ir, irAmt);
                }
            } catch {
                emit RedNotMinted(irAmt);
            }
        }
    }

    /// @notice Harvest Bribes in tokens from RewardVault, sent to us via processIncentive
    /// ref - https://github.com/berachain/contracts-monorepo/blob/c374de32077ede0147985cf2bf6ed89570244a7e/src/pol/rewards/RewardVault.sol#L421 
    /// @param $            The storage pointer for all rewards accumulators
    /// @param wbera        The address of the WBERA token
    /// @param collector    The address of the bribe collector, which will auction off fees for WBERA
    /// @param _tokens      The array of token addresses to harvest
    /// @param whitelisted  The array of booleans indicating if the token is whitelisted, and should be collected
    function harvestBribes(
        RewardsStorage storage $,
        address wbera,
        address collector,
        address[] memory _tokens,
        bool[] memory whitelisted
    ) external returns (address[] memory tokens, uint256[] memory _amounts) {
        uint256 len = _tokens.length;
        _amounts = new uint256[](len);
        tokens = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            if (!whitelisted[i]) continue;
            address _token = _tokens[i];
            if (_token == DataTypes.NATIVE_ASSET) {
                IWBERA(wbera).deposit{value: address(this).balance}();
                _token = wbera;
            }
            // amount to forward is balance of this address less existing protocol fees
            uint256 _amount = ERC20(_token).balanceOf(address(this))
                - $.protocolFeeAmounts[_token];
            _amounts[i] = _amount;
            tokens[i] = _token;
            _handleTokenBribesForReceiver($, collector, _token, _amount);
        }
    }

    /// @notice Callback from the BribeCollector to payout the WBERA bribes were auctioned off for
    ///     ref - https://github.com/infrared-dao/infrared-contracts/blob/develop/src/core/BribeCollector.sol#L87
    /// @param $        Storage pointer for reward accumulators
    /// @param _amount          The amount of WBERA our bribes were auctioned off for
    /// @param wbera            The address of the WBERA token
    /// @param ibera            The address of the InfraredBERA token
    /// @param ibgtVault        The address of the InfraredBGT vault
    /// @param voter            The address of the voter (address(0) if IR token is not live)
    /// @param rewardsDuration  The duration of the rewards
    ///
    /// @notice WBERA is split between the iBERA product (where it is redeemed for BERA) and the rest is sent to the IBGT vault.
    /// @return amtInfraredBERA The amount of WBERA sent to the iBERA product
    /// @return amtIbgtVault    The amount of WBERA sent to the IBGT vault
    function collectBribesInWBERA(
        RewardsStorage storage $,
        uint256 _amount,
        address wbera,
        address ibera,
        address ibgtVault,
        address voter,
        uint256 rewardsDuration
    ) external returns (uint256 amtInfraredBERA, uint256 amtIbgtVault) {
        // transfer WBERA from bribe collector
        ERC20(wbera).safeTransferFrom(msg.sender, address(this), _amount);

        // determine amount to send to iBERA and IBGT vault
        amtInfraredBERA = _amount * $.collectBribesWeight / WEIGHT_UNIT;
        amtIbgtVault = _amount - amtInfraredBERA;

        // Redeem WBERA for BERA and send to IBERA receivor for compounding
        IWBERA(wbera).withdraw(amtInfraredBERA);
        SafeTransferLib.safeTransferETH(IInfraredBERA(ibera).receivor(), amtInfraredBERA);

        // Get Fee totals (voter + protocol)
        uint256 feeTotal =
            $.fees[uint256(ConfigTypes.FeeType.HarvestBribesFeeRate)];
        uint256 feeProtocol =
            $.fees[uint256(ConfigTypes.FeeType.HarvestBribesProtocolRate)];

        // Charge fees and notify rewards
        _handleTokenRewardsForVault(
            $,
            IInfraredVault(ibgtVault),
            wbera,
            voter,
            amtIbgtVault,
            feeTotal,
            feeProtocol,
            rewardsDuration
        );
    }

    /// @notice Harvest boost rewards from the BGT staker (in HONEY -- likely -- inshAllah)
    /// @param $                The storage pointer for all rewards accumulators
    /// @param bgt              The address of the BGT token
    /// @param ibgtVault        The address of the InfraredBGT vault
    /// @param voter            The address of the voter (address(0) if IR token is not live)
    /// @param rewardsDuration  The duration of the rewards
    ///
    /// @return _token           The rewards token harvested (likely hunny)
    /// @return _amount          The amount of rewards harvested
    function harvestBoostRewards(
        RewardsStorage storage $,
        address bgt,
        address ibgtVault,
        address voter,
        uint256 rewardsDuration
    ) external returns (address _token, uint256 _amount) {
        IBerachainBGTStaker _bgtStaker =
            IBerachainBGTStaker(IBerachainBGT(bgt).staker());
        _token = address(_bgtStaker.rewardToken());

        // claim boost reward
        // @dev not trusting return from bgt staker in case transfer fees
        uint256 balanceBefore = ERC20(_token).balanceOf(address(this));
        _bgtStaker.getReward();
        _amount = ERC20(_token).balanceOf(address(this)) - balanceBefore;

        // get total and protocol fee rates
        uint256 feeTotal =
            $.fees[uint256(ConfigTypes.FeeType.HarvestBoostFeeRate)];
        uint256 feeProtocol =
            $.fees[uint256(ConfigTypes.FeeType.HarvestBoostProtocolRate)];

        _handleTokenRewardsForVault(
            $,
            IInfraredVault(ibgtVault),
            _token,
            voter,
            _amount,
            feeTotal,
            feeProtocol,
            rewardsDuration
        );
    }

    /// @notice Harvest rewards given to our operators for setting their cuttingboard weights
    /// ref - https://github.com/infrared-dao/infrared-contracts/blob/develop/src/staking/InfraredBERAFeeReceivor.sol#L83
    /// @param $                The storage pointer for all rewards accumulators
    /// @param ibera            The address of the InfraredBERA token
    /// @param voter            The address of the voter (address(0) if IR token is not live)
    /// @param distributor      The address of the distributor
    ///
    /// @param _amt             The amount of rewards harvested
    function harvestOperatorRewards(
        RewardsStorage storage $,
        address ibera,
        address voter,
        address distributor
    ) external returns (uint256 _amt) {
        IInfraredBERA(ibera).compound();
        uint256 iBERAShares = IInfraredBERA(ibera).collect();

        if (iBERAShares == 0) return 0;

        uint256 feeTotal =
            $.fees[uint256(ConfigTypes.FeeType.HarvestOperatorFeeRate)];
        uint256 feeProtocol =
            $.fees[uint256(ConfigTypes.FeeType.HarvestOperatorProtocolRate)];

        _amt = _handleRewardsForOperators(
            $, ibera, voter, distributor, iBERAShares, feeTotal, feeProtocol
        );
    }

    /**
     * @notice Handles non-InfraredBGT token rewards to the vault.
     * @param _vault       IInfraredVault   The address of the vault.
     * @param _token       address          The reward token.
     * @param _amount      uint256          The amount of reward token to send to vault.
     * @param _feeTotal    uint256          The rate to charge for total fees on `_amount`.
     * @param _feeProtocol uint256          The rate to charge for protocol treasury on total fees.
     */
    function _handleTokenRewardsForVault(
        RewardsStorage storage $,
        IInfraredVault _vault,
        address _token,
        address voter,
        uint256 _amount,
        uint256 _feeTotal,
        uint256 _feeProtocol,
        uint256 rewardsDuration
    ) internal {
        if (_amount == 0) return;

        // add reward if not already added
        (, uint256 _vaultRewardsDuration,,,,,) = _vault.rewardData(_token);
        if (_vaultRewardsDuration == 0) {
            _vault.addReward(_token, rewardsDuration);
        }

        uint256 _amtVoter;
        uint256 _amtProtocol;

        // calculate and distribute fees on rewards
        (_amount, _amtVoter, _amtProtocol) =
            _chargedFeesOnRewards(_amount, _feeTotal, _feeProtocol);
        _distributeFeesOnRewards(
            $.protocolFeeAmounts, voter, _token, _amtVoter, _amtProtocol
        );

        // increase allowance then notify vault of new rewards
        if (_amount > 0) {
            ERC20(_token).safeApprove(address(_vault), _amount);
            _vault.notifyRewardAmount(_token, _amount);
        }
    }

    /**
     * @notice Handles non-InfraredBGT token bribe rewards to a non-vault receiver address.
     * @dev Does *not* take protocol fee on bribe coin, as taken on bribe collector payout token in eventual callback.
     * @param _recipient address  The address of the recipient.
     * @param _token     address  The address of the token to forward to recipient.
     */
    function _handleTokenBribesForReceiver(
        RewardsStorage storage,
        address _recipient,
        address _token,
        uint256 _amount
    ) internal {
        if (_amount == 0) return;

        // transfer rewards to recipient
        ERC20(_token).safeTransfer(_recipient, _amount);
    }

    /**
     * @notice Handles BGT base rewards supplied to validator distributor.
     * @param _iBERAShares      uint256         The BGT reward amount.
     * @param _feeTotal    uint256         The rate to charge for total fees on `_iBERAShares`.
     * @param _feeProtocol uint256         The rate to charge for protocol treasury on total fees.
     */
    function _handleRewardsForOperators(
        RewardsStorage storage $,
        address ibera,
        address voter,
        address distributor,
        uint256 _iBERAShares,
        uint256 _feeTotal,
        uint256 _feeProtocol
    ) internal returns (uint256 _amt) {
        // pass if no bgt rewards
        if (_iBERAShares == 0) return 0;

        address _token = ibera;

        uint256 _amtVoter;
        uint256 _amtProtocol;

        // calculate and distribute fees on rewards
        (_amt, _amtVoter, _amtProtocol) =
            _chargedFeesOnRewards(_iBERAShares, _feeTotal, _feeProtocol);
        _distributeFeesOnRewards(
            $.protocolFeeAmounts, voter, _token, _amtVoter, _amtProtocol
        );

        // send token rewards less fee to vault
        if (_amt > 0) {
            ERC20(_token).safeApprove(distributor, _amt);
            IInfraredDistributor(distributor).notifyRewardAmount(_amt);
        }
    }

    function delegateBGT(
        RewardsStorage storage,
        address _delegatee,
        address bgt
    ) external {
        if (_delegatee == address(0)) revert Errors.ZeroAddress();
        if (_delegatee == address(this)) revert Errors.InvalidDelegatee();
        IBerachainBGT(bgt).delegate(_delegatee);
    }

    function updateInfraredBERABribesWeight(
        RewardsStorage storage $,
        uint256 _weight
    ) external {
        if (_weight > WEIGHT_UNIT) revert Errors.InvalidWeight();
        $.collectBribesWeight = _weight;
    }

    function updateFee(
        RewardsStorage storage $,
        ConfigTypes.FeeType _t,
        uint256 _fee
    ) external {
        if (_fee > FEE_UNIT) revert Errors.InvalidFee();
        $.fees[uint256(_t)] = _fee;
    }

    function claimProtocolFees(
        RewardsStorage storage $,
        address _to,
        address _token,
        uint256 _amount
    ) external {
        if (_amount > $.protocolFeeAmounts[_token]) {
            revert Errors.MaxProtocolFeeAmount();
        }
        $.protocolFeeAmounts[_token] -= _amount;
        ERC20(_token).safeTransfer(_to, _amount);
    }

    function getBGTBalance(RewardsStorage storage, address bgt)
        external
        view
        returns (uint256)
    {
        return _getBGTBalance(bgt);
    }

    function _getBGTBalance(address bgt) internal view returns (uint256) {
        return IBerachainBGT(bgt).balanceOf(address(this));
    }

    function updateIRMintRate(RewardsStorage storage $, uint256 _irMintRate)
        external
    {
        // Update the IR minting rate
        // This rate determines how many IR tokens are minted per IBGT

        // @note The rate can be greater than RATE_UNIT (1e6)
        // This allows for minting multiple IR tokens per IBGT if desired

        // For example:
        // - If _irMintRate = 500,000 (0.5 * RATE_UNIT), 0.5 IR is minted per IBGT
        // - If _irMintRate = 2,000,000 (2 * RATE_UNIT), 2 IR are minted per IBGT

        // The actual calculation is done in harvestVault
        // uint256 _redAmt = Math.mulDiv(_bgtAmt, $.redMintRate, RATE_UNIT);

        $.irMintRate = _irMintRate;
    }
}
