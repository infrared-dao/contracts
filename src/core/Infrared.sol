// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// External dependencies.
import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IRewardVault as IBerachainRewardsVault} from
    "@berachain/pol/interfaces/IRewardVault.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";
import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";

// Internal dependencies.
import {DataTypes} from "src/utils/DataTypes.sol";
import {Errors} from "src/utils/Errors.sol";

import {InfraredVaultDeployer} from "src/utils/InfraredVaultDeployer.sol";

import {IVoter} from "src/voting/interfaces/IVoter.sol";

import {IWBERA} from "src/interfaces/IWBERA.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";

import {IRED} from "src/interfaces/IRED.sol";
import {IBribeCollector} from "src/interfaces/IBribeCollector.sol";
import {IInfraredDistributor} from "src/interfaces/IInfraredDistributor.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {ConfigTypes, IInfrared} from "src/interfaces/IInfrared.sol";

import {InfraredUpgradeable} from "src/core/InfraredUpgradeable.sol";
import {InfraredVault} from "src/core/InfraredVault.sol";
import {IInfraredBERA} from "src/interfaces/IInfraredBERA.sol";

import {ValidatorManagerLib} from "./libraries/ValidatorManagerLib.sol";
import {ValidatorTypes} from "./libraries/ValidatorTypes.sol";
import {VaultManagerLib} from "./libraries/VaultManagerLib.sol";
import {RewardsLib} from "./libraries/RewardsLib.sol";

/**
 * @title Infrared Protocol Core Contract
 * @notice Provides core functionalities for managing validators, vaults, and reward distribution in the Infrared protocol.
 * @dev Serves as the main entry point for interacting with the Infrared protocol
 * @dev The contract is upgradeable, ensuring flexibility for governance-led upgrades and chain compatibility.
 */
contract Infrared is InfraredUpgradeable, IInfrared {
    using SafeTransferLib for ERC20;

    using EnumerableSet for EnumerableSet.Bytes32Set;

    using ValidatorManagerLib for ValidatorManagerLib.ValidatorStorage;
    using VaultManagerLib for VaultManagerLib.VaultStorage;
    using RewardsLib for RewardsLib.RewardsStorage;

    /*//////////////////////////////////////////////////////////////
                           STORAGE/EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The BGT token contract reference
     * @dev Immutable IBerachainBGT instance of the BGT token
     */
    IBerachainBGT internal immutable _bgt;

    /// @inheritdoc IInfrared
    IInfraredBGT public immutable ibgt;

    /// @inheritdoc IInfrared
    IBerachainRewardsVaultFactory public immutable rewardsFactory;

    /// @inheritdoc IInfrared
    IBeraChef public immutable chef;

    /// @inheritdoc IInfrared
    IWBERA public immutable wbera;

    /// @inheritdoc IInfrared
    ERC20 public immutable honey;

    /// @inheritdoc IInfrared
    IBribeCollector public collector;

    /// @inheritdoc IInfrared
    IInfraredDistributor public distributor;

    /// @inheritdoc IInfrared
    IVoter public voter;

    /// @inheritdoc IInfrared
    IInfraredBERA public ibera;

    /// @inheritdoc IInfrared
    IRED public red;

    /// @inheritdoc IInfrared
    IInfraredVault public ibgtVault;

    /**
     * @notice Upgradeable ERC-7201 storage for Validator lib
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("infrared.validatorStorage"))) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 public constant VALIDATOR_STORAGE_LOCATION =
        0x8ea5a3cc3b9a6be40b16189aeb1b6e6e61492e06efbfbe10619870b5bc1cc500;

    /**
     * @notice Upgradeable ERC-7201 storage for Vault lib
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("infrared.vaultStorage"))) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 public constant VAULT_STORAGE_LOCATION =
        0x1bb2f1339407e6d63b93b8b490a9d43c5651f6fc4327c66addd5939450742a00;

    /**
     * @notice Upgradeable ERC-7201 storage for Rewards lib
     * @dev keccak256(abi.encode(uint256(keccak256(bytes("infrared.rewardsStorage"))) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 public constant REWARDS_STORAGE_LOCATION =
        0xad12e6d08cc0150709acd6eed0bf697c60a83227922ab1d254d1ca4d3072ca00;

    // Helper functions to access the storage
    function _validatorStorage()
        internal
        pure
        returns (ValidatorManagerLib.ValidatorStorage storage vs)
    {
        bytes32 position = VALIDATOR_STORAGE_LOCATION;
        assembly {
            vs.slot := position
        }
    }

    function _vaultStorage()
        internal
        pure
        returns (VaultManagerLib.VaultStorage storage vs)
    {
        bytes32 position = VAULT_STORAGE_LOCATION;
        assembly {
            vs.slot := position
        }
    }

    function _rewardsStorage()
        internal
        pure
        returns (RewardsLib.RewardsStorage storage rs)
    {
        bytes32 position = REWARDS_STORAGE_LOCATION;
        assembly {
            rs.slot := position
        }
    }

    /**
     * @dev Ensures that only the collector contract can call the function
     * Reverts if the caller is not the collector
     */
    modifier onlyCollector() {
        if (msg.sender != address(collector)) {
            revert Errors.Unauthorized(msg.sender);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                INITIALIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _ibgt,
        address _rewardsFactory,
        address _chef,
        address payable _wbera,
        address _honey
    ) InfraredUpgradeable(address(0)) {
        wbera = IWBERA(_wbera);
        honey = ERC20(_honey);
        rewardsFactory = IBerachainRewardsVaultFactory(_rewardsFactory);
        chef = IBeraChef(_chef);

        ibgt = IInfraredBGT(_ibgt);
        _bgt = IBerachainBGT(ibgt.bgt());
    }

    function initialize(
        address _admin,
        address _collector,
        address _distributor,
        address _voter,
        address _iBERA,
        uint256 _rewardsDuration
    ) external initializer {
        // whitelist immutable tokens for rewards
        if (
            _admin == address(0) || _collector == address(0)
                || _distributor == address(0) || _voter == address(0)
                || _iBERA == address(0)
        ) revert Errors.ZeroAddress();
        if (_rewardsDuration == 0) revert Errors.ZeroAmount();

        _vaultStorage().rewardsDuration = _rewardsDuration;

        // grant admin access roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
        _grantRole(GOVERNANCE_ROLE, _admin);

        _vaultStorage().updateWhitelistedRewardTokens(address(wbera), true);
        _vaultStorage().updateWhitelistedRewardTokens(address(ibgt), true);
        _vaultStorage().updateWhitelistedRewardTokens(address(honey), true);

        // set collector, validator distributor, and veIRED voter fee vault
        collector = IBribeCollector(_collector);
        distributor = IInfraredDistributor(_distributor);
        voter = IVoter(_voter);
        ibera = IInfraredBERA(_iBERA);

        if (collector.payoutToken() != address(wbera)) {
            revert Errors.RewardTokenNotSupported();
        }
        if (address(distributor.token()) != address(ibera)) {
            revert Errors.RewardTokenNotSupported();
        }

        ibgtVault = IInfraredVault(_vaultStorage().registerVault(address(ibgt)));

        // init upgradeable components
        __InfraredUpgradeable_init();
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInfrared
    function registerVault(address _asset)
        external
        whenInitialized
        returns (IInfraredVault vault)
    {
        vault = IInfraredVault(_vaultStorage().registerVault(_asset));
        emit NewVault(msg.sender, _asset, address(vault));
    }

    /// @inheritdoc IInfrared
    function addReward(
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external onlyGovernor whenInitialized {
        _vaultStorage().addReward(
            _stakingToken, _rewardsToken, _rewardsDuration
        );
    }

    /// @inheritdoc IInfrared
    function addIncentives(
        address _stakingToken,
        address _rewardsToken,
        uint256 _amount
    ) external whenInitialized {
        _vaultStorage().addIncentives(_stakingToken, _rewardsToken, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInfrared
    function updateWhiteListedRewardTokens(address _token, bool _whitelisted)
        external
        onlyGovernor
        whenInitialized
    {
        bool previousStatus = whitelistedRewardTokens(_token);
        _vaultStorage().updateWhitelistedRewardTokens(_token, _whitelisted);
        emit WhiteListedRewardTokensUpdated(
            msg.sender, _token, previousStatus, _whitelisted
        );
    }

    /// @inheritdoc IInfrared
    function updateRewardsDuration(uint256 _rewardsDuration)
        external
        onlyGovernor
        whenInitialized
    {
        uint256 oldRewardsDuration = rewardsDuration();
        _vaultStorage().updateRewardsDuration(_rewardsDuration);
        emit RewardsDurationUpdated(
            msg.sender, oldRewardsDuration, _rewardsDuration
        );
    }

    /// @inheritdoc IInfrared
    function updateRewardsDurationForVault(
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external onlyGovernor whenInitialized {
        _vaultStorage().updateRewardsDurationForVault(
            _stakingToken, _rewardsToken, _rewardsDuration
        );
    }

    /// @inheritdoc IInfrared
    function pauseVault(address _asset) external onlyGovernor whenInitialized {
        _vaultStorage().pauseVault(_asset);
    }

    /// @inheritdoc IInfrared
    function claimLostRewardsOnVault(address _asset)
        external
        onlyGovernor
        whenInitialized
    {
        _vaultStorage().claimLostRewardsOnVault(_asset);
    }

    /// @inheritdoc IInfrared
    function recoverERC20(address _to, address _token, uint256 _amount)
        external
        onlyGovernor
        whenInitialized
    {
        if (_to == address(0) || _token == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_amount == 0) revert Errors.ZeroAmount();
        ERC20(_token).safeTransfer(_to, _amount);
        emit Recovered(msg.sender, _token, _amount);
    }

    /// @inheritdoc IInfrared
    function recoverERC20FromVault(
        address _asset,
        address _to,
        address _token,
        uint256 _amount
    ) external onlyGovernor whenInitialized {
        _vaultStorage().recoverERC20FromVault(_asset, _to, _token, _amount);
    }

    /// @inheritdoc IInfrared
    function delegateBGT(address _delegatee)
        external
        onlyGovernor
        whenInitialized
    {
        _rewardsStorage().delegateBGT(_delegatee, address(_bgt));
    }

    /// @inheritdoc IInfrared
    function updateInfraredBERABribesWeight(uint256 _weight)
        external
        onlyGovernor
        whenInitialized
    {
        uint256 prevWeight = _rewardsStorage().collectBribesWeight;
        _rewardsStorage().updateInfraredBERABribesWeight(_weight);
        emit InfraredBERABribesWeightUpdated(msg.sender, prevWeight, _weight);
    }

    /// @inheritdoc IInfrared
    function updateFee(ConfigTypes.FeeType _t, uint256 _fee)
        external
        onlyGovernor
        whenInitialized
    {
        uint256 prevFee = fees(uint256(_t));
        _rewardsStorage().updateFee(_t, _fee);
        emit FeeUpdated(msg.sender, _t, prevFee, _fee);
    }

    /// @inheritdoc IInfrared
    function claimProtocolFees(address _to, address _token, uint256 _amount)
        external
        onlyGovernor
        whenInitialized
    {
        _rewardsStorage().claimProtocolFees(_to, _token, _amount);
        emit ProtocolFeesClaimed(msg.sender, _to, _token, _amount);
    }

    /// @inheritdoc IInfrared
    function setRed(address _red) external onlyGovernor whenInitialized {
        if (_red == address(0)) revert Errors.ZeroAddress();
        if (address(red) != address(0)) revert Errors.AlreadySet();
        if (!IRED(_red).hasRole(IRED(_red).MINTER_ROLE(), address(this))) {
            revert Errors.Unauthorized(address(this));
        }
        red = IRED(_red);
        emit RedSet(msg.sender, _red);
    }

    /// @inheritdoc IInfrared
    function updateRedMintRate(uint256 _redMintRate)
        external
        onlyGovernor
        whenInitialized
    {
        _rewardsStorage().updateRedMintRate(_redMintRate);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS
    //////////////////////////////////////////////////////////////*/

    function chargedFeesOnRewards(
        uint256 _amt,
        uint256 _feeTotal,
        uint256 _feeProtocol
    )
        public
        view
        returns (uint256 amtRecipient, uint256 amtVoter, uint256 amtProtocol)
    {
        return _rewardsStorage().chargedFeesOnRewards(
            _amt, _feeTotal, _feeProtocol
        );
    }

    /// @inheritdoc IInfrared
    function harvestBase() public whenInitialized {
        uint256 bgtAmt = _rewardsStorage().harvestBase(
            address(_bgt), address(ibgt), address(ibera)
        );
        emit BaseHarvested(msg.sender, bgtAmt);
    }

    /// @inheritdoc IInfrared
    function harvestVault(address _asset) external whenInitialized {
        IInfraredVault vault = vaultRegistry(_asset);
        uint256 bgtAmt = _rewardsStorage().harvestVault(
            vault,
            address(_bgt),
            address(ibgt),
            address(voter),
            address(red),
            rewardsDuration()
        );
        emit VaultHarvested(msg.sender, _asset, address(vault), bgtAmt);
    }

    /// @inheritdoc IInfrared
    function harvestBribes(address[] calldata _tokens)
        external
        whenInitialized
    {
        uint256 len = _tokens.length;
        bool[] memory whitelisted = new bool[](len);
        for (uint256 i; i < len; ++i) {
            if (
                whitelistedRewardTokens(_tokens[i])
                    || _tokens[i] == DataTypes.NATIVE_ASSET
            ) {
                whitelisted[i] = true;
            }
        }
        (address[] memory tokens, uint256[] memory _amounts) = _rewardsStorage()
            .harvestBribes(address(wbera), address(collector), _tokens, whitelisted);
        for (uint256 i; i < len; ++i) {
            if (whitelisted[i]) {
                emit BribeSupplied(address(collector), tokens[i], _amounts[i]);
            } else {
                emit RewardTokenNotSupported(_tokens[i]);
            }
        }
    }

    /// @inheritdoc IInfrared
    function collectBribes(address _token, uint256 _amount)
        external
        onlyCollector
        whenInitialized
    {
        if (_token != address(wbera)) {
            revert Errors.RewardTokenNotSupported();
        }

        (uint256 amtInfraredBERA, uint256 amtIbgtVault) = _rewardsStorage()
            .collectBribesInWBERA(
            _amount,
            address(wbera),
            address(ibera),
            address(ibgtVault),
            address(voter),
            rewardsDuration()
        );

        emit BribesCollected(msg.sender, _token, amtInfraredBERA, amtIbgtVault);
    }

    function harvestOperatorRewards() public whenInitialized {
        uint256 _amt = _rewardsStorage().harvestOperatorRewards(
            address(ibera), address(voter), address(distributor)
        );
        emit OperatorRewardsDistributed(
            address(ibera), address(distributor), _amt
        );
    }

    /// @inheritdoc IInfrared
    function harvestBoostRewards() external whenInitialized {
        (address _vault, address _token, uint256 _amount) = _rewardsStorage()
            .harvestBoostRewards(
            address(_bgt), address(ibgtVault), address(voter), rewardsDuration()
        );
        emit RewardSupplied(address(_vault), _token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATORS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInfrared
    function addValidators(ValidatorTypes.Validator[] calldata _validators)
        external
        onlyGovernor
        whenInitialized
    {
        harvestBase();
        harvestOperatorRewards();
        _validatorStorage().addValidators(address(distributor), _validators);
        emit ValidatorsAdded(msg.sender, _validators);
    }

    /// @inheritdoc IInfrared
    function removeValidators(bytes[] calldata _pubkeys)
        external
        onlyGovernor
        whenInitialized
    {
        harvestBase();
        harvestOperatorRewards();
        _validatorStorage().removeValidators(address(distributor), _pubkeys);
        emit ValidatorsRemoved(msg.sender, _pubkeys);
    }

    /// @inheritdoc IInfrared
    function replaceValidator(bytes calldata _current, bytes calldata _new)
        external
        onlyGovernor
        whenInitialized
    {
        harvestBase();
        harvestOperatorRewards();
        _validatorStorage().replaceValidator(
            address(distributor), _current, _new
        );
        emit ValidatorReplaced(msg.sender, _current, _new);
    }

    /// @inheritdoc IInfrared
    function queueNewCuttingBoard(
        bytes calldata _pubkey,
        uint64 _startBlock,
        IBeraChef.Weight[] calldata _weights
    ) external onlyKeeper whenInitialized {
        if (!isInfraredValidator(_pubkey)) revert Errors.InvalidValidator();
        chef.queueNewRewardAllocation(_pubkey, _startBlock, _weights);
    }

    /*//////////////////////////////////////////////////////////////
                            BOOSTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInfrared
    function queueBoosts(bytes[] calldata _pubkeys, uint128[] calldata _amts)
        external
        onlyKeeper
        whenInitialized
    {
        _validatorStorage().queueBoosts(
            address(_bgt), address(ibgt), _pubkeys, _amts
        );
        emit QueuedBoosts(msg.sender, _pubkeys, _amts);
    }

    /// @inheritdoc IInfrared
    function cancelBoosts(bytes[] calldata _pubkeys, uint128[] calldata _amts)
        external
        onlyKeeper
        whenInitialized
    {
        _validatorStorage().cancelBoosts(address(_bgt), _pubkeys, _amts);
        emit CancelledBoosts(msg.sender, _pubkeys, _amts);
    }

    /// @inheritdoc IInfrared
    function activateBoosts(bytes[] calldata _pubkeys)
        external
        whenInitialized
    {
        _validatorStorage().activateBoosts(address(_bgt), _pubkeys);
        emit ActivatedBoosts(msg.sender, _pubkeys);
    }

    /// @inheritdoc IInfrared
    function queueDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts
    ) external onlyKeeper whenInitialized {
        _validatorStorage().queueDropBoosts(address(_bgt), _pubkeys, _amts);
        emit QueueDropBoosts(msg.sender, _pubkeys, _amts);
    }

    /// @inheritdoc IInfrared
    function cancelDropBoosts(
        bytes[] calldata _pubkeys,
        uint128[] calldata _amts
    ) external onlyKeeper whenInitialized {
        _validatorStorage().cancelDropBoosts(address(_bgt), _pubkeys, _amts);
        emit CancelDropBoosts(msg.sender, _pubkeys, _amts);
    }

    /// @inheritdoc IInfrared
    function dropBoosts(bytes[] calldata _pubkeys) external whenInitialized {
        _validatorStorage().dropBoosts(address(_bgt), _pubkeys);
        emit DroppedBoosts(msg.sender, _pubkeys);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInfrared
    function infraredValidators()
        public
        view
        virtual
        returns (ValidatorTypes.Validator[] memory validators)
    {
        return _validatorStorage().infraredValidators(address(distributor));
    }

    /// @inheritdoc IInfrared
    function numInfraredValidators() external view returns (uint256) {
        return _validatorStorage().numInfraredValidators();
    }

    /// @inheritdoc IInfrared
    function isInfraredValidator(bytes calldata _validator)
        public
        view
        returns (bool)
    {
        return _validatorStorage().isValidator(_validator);
    }

    /// @inheritdoc IInfrared
    function getBGTBalance() public view returns (uint256) {
        return _bgt.balanceOf(address(this));
    }

    /**
     * @notice Mapping of tokens that are whitelisted to be used as rewards or accepted as bribes
     * @dev serves as central source of truth for whitelisted reward tokens for all Infrared contracts
     */
    function whitelistedRewardTokens(address token)
        public
        view
        returns (bool)
    {
        return _vaultStorage().isWhitelisted(token);
    }

    /**
     * @notice Mapping of staking token addresses to their corresponding InfraredVault
     * @dev Each staking token can only have one vault
     */
    function vaultRegistry(address _stakingToken)
        public
        view
        returns (IInfraredVault vault)
    {
        vault = _vaultStorage().vaultRegistry[_stakingToken];
    }

    /**
     * @notice Sets new vault registration paused or not
     * @param pause True to pause, False to un pause
     */
    function setVaultRegistrationPauseStatus(bool pause)
        external
        onlyGovernor
    {
        _vaultStorage().setVaultRegistrationPauseStatus(pause);
        emit VaultRegistrationPauseStatus(pause);
    }

    /// @inheritdoc IInfrared
    function rewardsDuration() public view returns (uint256 duration) {
        return _vaultStorage().rewardsDuration;
    }

    /// @inheritdoc IInfrared
    function fees(uint256 t) public view override returns (uint256) {
        return _rewardsStorage().fees[t];
    }

    /// @inheritdoc IInfrared
    function protocolFeeAmounts(address _token)
        external
        view
        returns (uint256)
    {
        return _rewardsStorage().protocolFeeAmounts[_token];
    }

    receive() external payable {}
}
