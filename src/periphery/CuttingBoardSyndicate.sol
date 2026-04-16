// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IBeraChefVaultCheck} from "src/interfaces/IBeraChefVaultCheck.sol";
import {CuttingBoardDutchAuctionV1_2 as CuttingBoardDutchAuction} from
    "src/periphery/CuttingBoardDutchAuctionV1_2.sol";
import {CuttingBoardManagerV1_1 as CuttingBoardManager} from
    "./CuttingBoardManagerV1_1.sol";
import {CuttingBoardNFT} from "./CuttingBoardNFT.sol";
import {CuttingBoardSlotNFT} from "./CuttingBoardSlotNFT.sol";
import {CuttingBoardSyndicateLib} from
    "./libraries/CuttingBoardSyndicateLib.sol";
import {Upgradeable} from "src/utils/Upgradeable.sol";

/**
 * @title CuttingBoardSyndicate
 * @notice Enables multiple partners to collectively win a cutting board Dutch auction
 *         through a priority-based bidding system. Partners bid on weight slices of
 *         the 10 000 bps validator board; fill order is determined by bid value
 *         (weight × maxPricePerBps), and the current Dutch auction price gates
 *         eligibility per partner.
 *
 * @dev The syndicate owns the minted CuttingBoardNFT after a successful claim and
 *      submits proposals to CuttingBoardManager on behalf of partners.
 *
 *      Each round is identified by its auctionId. Rounds for different auctions
 *      (including concurrent auctions for different validators, or a new auction
 *      that opens before the previous allocation period has expired) are fully
 *      independent. There is no global state shared between rounds.
 *
 *      External parties are welcome to bid directly on the underlying Dutch auction.
 *      Rounds that fail to trigger before the auction window closes are expected and
 *      handled cleanly via expireRound().
 *
 * Round lifecycle
 * ───────────────
 *  (new auctionId)
 *       │
 *  Idle ──openRound()──► Open ──triggerClaim()──► Active (terminal)
 *                          │   (conditions met)     NFT held until allocation expires
 *                    expireRound()
 *                   (auction lapsed)
 *                          │
 *                        Expired (terminal; all deposits refunded)
 *
 * Bidding model
 * ─────────────
 *  Each partner registers (vault, weight, maxPricePerBps). weight must be a
 *  positive multiple of minSlotWeight and at most maxWeightPerVault. A deposit
 *  of maxPricePerBps × weight is collected upfront.
 *
 *  At trigger time:
 *   1. Eligible partners (maxPricePerBps × 10 000 ≥ currentPrice) are sorted by
 *      bid value (weight × maxPricePerBps) descending; ties break on registration order.
 *   2. Weight is allocated greedily to 10 000 bps. The last included partner may
 *      receive a partial fill (fewer bps than requested).
 *   3. Any remaining bps go to the buffer vault, funded from bufferDeposit.
 *
 *  Each partner's cost = floor(currentPrice × allocatedWeight / 10 000).
 *  The buffer vault's bps share plus arithmetic rounding dust are both deducted
 *  from bufferDeposit, keeping per-partner costs strictly proportional.
 *
 * Buffer vault
 * ────────────
 *  A protocol-owned vault that absorbs small remainders when partners nearly (but
 *  not exactly) fill the board. It is not intended to force a close — a round may
 *  legitimately expire without triggering. The buffer is sized to bridge gaps of
 *  roughly 5–10 % of the board; it is subject to BeraChef's per-vault weight cap.
 *  bufferDeposit rolls over between rounds and is never refunded on expiry.
 *
 *  Even when the buffer vault receives zero bps (partners fill all 10 000 bps
 *  exactly), bufferDeposit must cover up to (partnerCount − 1) wei of rounding
 *  dust arising from floor-dividing the auction price across allocations. Governance
 *  should maintain a minimum deposit of at least maxNumWeightsPerRewardAllocation
 *  wei to guarantee this is always satisfied.
 *
 * Access control
 * ──────────────
 *  GOVERNANCE_ROLE: setBufferVault, withdrawBuffer, setMinSlotWeight, setSlotNFT, recoverERC20, unpause
 *  PAUSER_ROLE:     pause
 *  All other operations are permissionless.
 */
contract CuttingBoardSyndicate is Upgradeable {
    using SafeTransferLib for ERC20;
    using
    CuttingBoardSyndicateLib
    for CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage;

    // keccak256(abi.encode(uint256(keccak256("infrared.storage.CuttingBoardSyndicate")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUTTING_BOARD_SYNDICATE_STORAGE_LOCATION =
        0xfc0b30dd43c7ca556e4ca78929e2b1fe291ff15419dda9ea9db08f129f339e00;

    function _getStorage()
        private
        pure
        returns (
            CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $
        )
    {
        assembly {
            $.slot := CUTTING_BOARD_SYNDICATE_STORAGE_LOCATION
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event BufferVaultSet(address indexed vault);
    event RoundBufferVaultUpdated(
        uint256 indexed auctionId, address indexed newVault
    );
    event BufferDeposited(address indexed depositor, uint256 amount);
    event BufferWithdrawn(address indexed recipient, uint256 amount);
    event MinSlotWeightSet(uint96 minWeight);

    event RoundOpened(uint256 indexed auctionId, bytes32 indexed validatorHash);
    event SlotRegistered(
        uint256 indexed auctionId,
        address indexed partner,
        address indexed vault,
        uint96 weight,
        uint128 maxPricePerBps,
        uint128 deposit
    );
    event SlotVaultUpdated(
        uint256 indexed auctionId,
        address indexed partner,
        address indexed newVault
    );
    event MaxPriceIncreased(
        uint256 indexed auctionId,
        address indexed partner,
        uint128 newMax,
        uint128 additionalDeposit
    );
    event SlotExited(
        uint256 indexed auctionId, address indexed partner, uint128 refund
    );

    /// @notice Emitted for each partner included in the winning allocation
    event SlotFilled(
        uint256 indexed auctionId,
        address indexed partner,
        uint96 requested,
        uint96 allocated,
        uint256 cost
    );
    /// @notice Emitted for each partner whose price ceiling was below the trigger price
    event SlotExcluded(
        uint256 indexed auctionId, address indexed partner, uint256 refund
    );
    /// @notice Emitted when the buffer vault absorbs unallocated bps
    event BufferUsed(
        uint256 indexed auctionId,
        address indexed vault,
        uint96 weight,
        uint256 cost
    );

    event RoundTriggered(
        uint256 indexed auctionId, uint128 claimPrice, uint256 tokenId
    );
    event RoundExpired(uint256 indexed auctionId);
    event RefundClaimed(address indexed partner, uint256 amount);
    event RoundCompleted(uint256 indexed auctionId);
    event SlotNFTSet(address indexed slotNFT);
    event ERC20Recovered(
        address indexed token, address indexed to, uint256 amount
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error NotOpen();
    error NotActive();
    error RoundAlreadyExists();
    error SlotAlreadyExists();
    error NoSlot();
    /// @notice Weight is zero, not a multiple of minSlotWeight, or exceeds the per-vault cap
    error InvalidWeight();
    /// @notice maxPricePerBps must be ≥ minimumPricePerBps()
    error InsufficientMaxPrice();
    /// @notice Included partners (+ buffer) exceed BeraChef's maxNumWeightsPerRewardAllocation
    error TooManyPartners();
    error VaultNotWhitelisted();
    /// @notice Vault is already registered by another partner or equals bufferVault
    error DuplicateVaultEntry(address vault);
    error AuctionNotActive();
    error AuctionStillLive();
    error NFTExpiredOrInvalid();
    error MaxPriceMustIncrease();
    error NothingToRefund();
    error ZeroAddress();
    /// @notice minSlotWeight must be a positive divisor of 10 000
    error InvalidMinSlotWeight();
    /// @notice bufferVault must be set before triggerClaim can allocate remaining bps to it
    error NoBufferVault();
    /// @notice bufferDeposit is too small to cover the buffer vault's share plus rounding dust
    error InsufficientBuffer();
    /// @notice No eligible partner has maxPricePerBps × 10 000 ≥ currentPrice
    error NoBidders();
    /// @notice Buffer vault would receive more than BeraChef's per-vault cap;
    ///         more partner coverage is needed to reduce the buffer's share
    error BufferWeightExceedsMax();
    /// @notice Cannot recover paymentToken via recoverERC20; use withdrawBuffer or claimRefund
    error CannotRecoverPaymentToken();
    /// @notice maxPricePerBps × weight exceeds uint128; use a lower maxPricePerBps
    error DepositOverflow();
    /// @notice slotNFT must be set before calling updateSlotVault
    error SlotNFTNotSet();
    /// @notice Caller does not own the SlotNFT for the requested tokenId
    error NotSlotNFTHolder();
    /// @notice SlotNFT address is not a compatible contract
    error InvalidSlotNFT();
    /// @notice SlotNFT address can only be set once
    error SlotNFTAlreadySet();
    /// @notice Buffer vault is no longer whitelisted in BeraChef
    error BufferVaultNotWhitelisted();
    error NFTStillValid();

    // ──────────────────────────────────────────────────────────────────────────
    // Initialisation
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Parameters for initialize() — grouped to avoid stack-too-deep
    struct InitParams {
        address dutchAuction;
        address controlManager;
        address controlNFT;
        address chef;
        address governance;
        address keeper; // optional; address(0) skips granting KEEPER_ROLE
        uint96 minSlotWeight; // 0 defaults to 100 (1 %)
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialise the syndicate.
     * @param params Configuration parameters.
     */
    function initialize(InitParams calldata params) external initializer {
        if (params.dutchAuction == address(0)) revert ZeroAddress();
        if (params.controlManager == address(0)) revert ZeroAddress();
        if (params.controlNFT == address(0)) revert ZeroAddress();
        if (params.chef == address(0)) revert ZeroAddress();
        if (params.governance == address(0)) revert ZeroAddress();
        if (params.keeper == address(0)) revert ZeroAddress();

        uint96 msw = params.minSlotWeight == 0 ? 100 : params.minSlotWeight;
        if (10000 % msw != 0) revert InvalidMinSlotWeight();

        __Upgradeable_init();

        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        $.dutchAuction = CuttingBoardDutchAuction(params.dutchAuction);
        $.controlManager = CuttingBoardManager(params.controlManager);
        $.controlNFT = CuttingBoardNFT(params.controlNFT);
        $.paymentToken =
            CuttingBoardDutchAuction(params.dutchAuction).paymentToken();
        $.chef = IBeraChefVaultCheck(params.chef);
        $.minSlotWeight = msw;

        _grantRole(DEFAULT_ADMIN_ROLE, params.governance);
        _grantRole(GOVERNANCE_ROLE, params.governance);
        _grantRole(KEEPER_ROLE, params.keeper);

        emit MinSlotWeightSet(msw);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Public getters
    // ──────────────────────────────────────────────────────────────────────────

    function dutchAuction()
        public
        view
        virtual
        returns (CuttingBoardDutchAuction)
    {
        return _getStorage().dutchAuction;
    }

    function controlManager()
        public
        view
        virtual
        returns (CuttingBoardManager)
    {
        return _getStorage().controlManager;
    }

    function controlNFT() public view virtual returns (CuttingBoardNFT) {
        return _getStorage().controlNFT;
    }

    function paymentToken() public view virtual returns (ERC20) {
        return _getStorage().paymentToken;
    }

    function chef() public view virtual returns (IBeraChefVaultCheck) {
        return _getStorage().chef;
    }

    function minSlotWeight() public view virtual returns (uint96) {
        return _getStorage().minSlotWeight;
    }

    function bufferVault() public view virtual returns (address) {
        return _getStorage().bufferVault;
    }

    function bufferDeposit() public view virtual returns (uint256) {
        return _getStorage().bufferDeposit;
    }

    function slotNFT() public view virtual returns (CuttingBoardSlotNFT) {
        return _getStorage().slotNFT;
    }

    /// @notice Minimum acceptable maxPricePerBps derived from the auction's minimumPrice.
    /// @dev Returns dutchAuction.minimumPrice() / 10 000 — the floor per-bps price.
    function minimumPricePerBps() public view virtual returns (uint256) {
        return _getStorage().dutchAuction.minimumPrice() / 10000;
    }

    /// @notice Pending refund balance for a single user across all rounds
    function getPendingRefund(address user)
        public
        view
        virtual
        returns (uint256)
    {
        return _getStorage().pendingRefunds[user];
    }

    /**
     * @notice All addresses with a non-zero pending refund and their balances.
     * @dev Enumerates the refundees tracking array. Claimed users are removed
     *      on claim, so every entry has a non-zero balance.
     */
    function getPendingRefunds()
        external
        view
        virtual
        returns (address[] memory users, uint256[] memory amounts)
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        address[] storage all = $.refundees;
        uint256 n = all.length;

        users = new address[](n);
        amounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            users[i] = all[i];
            amounts[i] = $.pendingRefunds[all[i]];
        }
    }

    /// @notice Buffer vault's allocated weight for a given Active round (0 otherwise)
    function getRoundBufferAllocated(uint256 auctionId)
        public
        view
        virtual
        returns (uint96)
    {
        return _getStorage().roundBufferAllocated[auctionId];
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Governance — buffer and slot configuration
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Set the fallback vault that absorbs unallocated bps.
     * @dev Only callable by governance. Intended for bridging small gaps (~5–10 % of the
     *      board) when partners nearly but not exactly fill 10 000 bps.
     *      Subject to BeraChef's per-vault weight cap — set the buffer deposit to
     *      cover at most maxWeightPerVault bps per round.
     *      Set to address(0) to disable.
     *
     *      WARNING: Do not set to a vault that is currently registered by any
     *      partner in an Open round. If the same vault appears twice in the weight
     *      assembly, BeraChef will reject the claim and the round will be stuck
     *      until the conflict is resolved (partner updates their vault or governance
     *      changes bufferVault) or the auction window expires.
     */
    function setBufferVault(address vault) external virtual onlyGovernor {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        $.validateSetBufferVault(vault);
        $.bufferVault = vault;
        emit BufferVaultSet(vault);
    }

    /**
     * @notice Replace the buffer vault for a specific Active round.
     * @dev Governance-only. Use when BeraChef de-whitelists the buffer vault
     *      that was snapshotted at trigger time, which would otherwise block
     *      all proposals for that round.
     *
     *      The new vault must be whitelisted and must not duplicate any
     *      included partner's vault in the round.
     *
     *      Only meaningful when `roundBufferAllocated[auctionId] > 0` — if
     *      the buffer has no allocation the vault is not included in proposals.
     *
     * @param auctionId The Active round to update.
     * @param newVault  The replacement buffer vault address.
     */
    function updateRoundBufferVault(uint256 auctionId, address newVault)
        external
        virtual
        onlyGovernor
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Active
        ) revert NotActive();
        $.validateBufferVaultUpdate(auctionId, newVault);
        $.rounds[auctionId].bufferVault = newVault;
        emit RoundBufferVaultUpdated(auctionId, newVault);
    }

    /**
     * @notice Withdraw tokens from the buffer reserve.
     * @dev Only callable by governance. Reverts on underflow.
     */
    function withdrawBuffer(address to, uint256 amount)
        external
        virtual
        onlyGovernor
    {
        if (to == address(0)) revert ZeroAddress();
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        $.bufferDeposit -= amount; // reverts on underflow
        $.paymentToken.safeTransfer(to, amount);
        emit BufferWithdrawn(to, amount);
    }

    /**
     * @notice Update the minimum weight (and allocation step size) for partner slots.
     * @dev Must evenly divide 10 000 so partial fills are always valid multiples.
     *      For example 100 (1 %), 200 (2 %), 500 (5 %) are valid; 300 is not.
     */
    function setMinSlotWeight(uint96 minWeight) external virtual onlyGovernor {
        if (minWeight == 0 || 10000 % minWeight != 0) {
            revert InvalidMinSlotWeight();
        }
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (minWeight > $.chef.maxWeightPerVault()) {
            revert InvalidMinSlotWeight();
        }
        _getStorage().minSlotWeight = minWeight;
        emit MinSlotWeightSet(minWeight);
    }

    /**
     * @notice Set the per-winner slot NFT contract.
     * @dev Only callable by governance.
     *      Deploy CuttingBoardSlotNFT with this syndicate's address as the authorised
     *      minter, then call this function to activate the feature.
     * @param _slotNFT Address of the CuttingBoardSlotNFT contract.
     */
    function setSlotNFT(address _slotNFT) external virtual onlyGovernor {
        // check contract is compatible
        if (CuttingBoardSlotNFT(_slotNFT).syndicate() != address(this)) {
            revert InvalidSlotNFT();
        }
        // can only set once
        if (address(_getStorage().slotNFT) != address(0)) {
            revert SlotNFTAlreadySet();
        }
        _getStorage().slotNFT = CuttingBoardSlotNFT(_slotNFT);
        emit SlotNFTSet(_slotNFT);
    }

    /**
     * @notice Recover accidentally sent ERC-20 tokens.
     * @dev Only callable by governance. Reverts if `token` is the payment token
     *      to prevent draining user deposits and buffer funds.
     * @param token  ERC-20 token to recover.
     * @param to     Recipient address.
     * @param amount Amount to transfer.
     */
    function recoverERC20(address token, address to, uint256 amount)
        external
        virtual
        onlyGovernor
    {
        if (to == address(0)) revert ZeroAddress();
        if (token == address(_getStorage().paymentToken)) {
            revert CannotRecoverPaymentToken();
        }
        ERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Buffer management (permissionless deposit)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposit payment tokens into the buffer reserve.
     * @dev Permissionless. The reserve persists across rounds and is consumed only
     *      at claim time (proportional to the buffer's bps allocation, plus any
     *      rounding dust from floor-dividing the price across partner allocations).
     */
    function depositBuffer(uint256 amount) external virtual {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        $.bufferDeposit += amount; // effect before interaction (CEI)
        $.paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        emit BufferDeposited(msg.sender, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Round management
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Open partner registration for a specific auction.
     * @param auctionId The auction ID in CuttingBoardDutchAuction to target.
     * @dev Permissionless. Each auctionId can only be opened once. Rounds for
     *      different auctions — including concurrent auctions across validators
     *      or overlapping allocation periods for the same validator — are fully
     *      independent and do not block each other.
     *
     *      validatorHash is derived on-chain from the auction contract so there
     *      is no risk of mismatch between auctionId and validator.
     */
    function openRound(uint256 auctionId) external virtual whenNotPaused {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Idle
        ) {
            revert RoundAlreadyExists();
        }
        if (!$.dutchAuction.isAuctionActive(auctionId)) {
            revert AuctionNotActive();
        }

        bytes32 validatorHash =
            keccak256($.dutchAuction.getAuctionValidator(auctionId));

        $.rounds[auctionId] = CuttingBoardSyndicateLib.Round({
            validatorHash: validatorHash,
            claimPrice: 0,
            tokenId: 0,
            state: CuttingBoardSyndicateLib.RoundState.Open,
            bufferVault: address(0)
        });

        emit RoundOpened(auctionId, validatorHash);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Slot management (Open state)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a slot in an Open round.
     * @param auctionId       Round to register in.
     * @param vault           Whitelisted BeraChef receiver vault. Must not equal
     *                        bufferVault. Multiple partners may bid on the same
     *                        vault; at trigger time only the top bid per vault wins.
     * @param weight          Bps to bid for. Must be a positive multiple of
     *                        minSlotWeight and at most maxWeightPerVault.
     *                        Partners may collectively request more than 10 000 bps;
     *                        actual allocation is resolved at trigger time.
     * @param maxPricePerBps  Maximum price per basis point this partner will accept.
     *                        Must be ≥ minimumPricePerBps(). Deposit = maxPricePerBps ×
     *                        weight is collected now.
     */
    function registerSlot(
        uint256 auctionId,
        address vault,
        uint96 weight,
        uint128 maxPricePerBps
    ) external virtual whenNotPaused {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) revert NotOpen();
        if (!$.dutchAuction.isAuctionActive(auctionId)) {
            revert AuctionNotActive();
        }
        if ($.slots[auctionId][msg.sender].weight != 0) {
            revert SlotAlreadyExists();
        }
        if (maxPricePerBps < $.dutchAuction.minimumPrice() / 10000) {
            revert InsufficientMaxPrice();
        }
        if (weight == 0 || weight % $.minSlotWeight != 0) {
            revert InvalidWeight();
        }
        if (weight > $.chef.maxWeightPerVault()) revert InvalidWeight();
        if (!$.chef.isWhitelistedVault(vault)) revert VaultNotWhitelisted();
        if (vault == $.bufferVault) revert DuplicateVaultEntry(vault);
        if (
            $.roundPartners[auctionId].length + 1
                > 5 * $.chef.maxNumWeightsPerRewardAllocation()
        ) revert TooManyPartners();

        uint256 depositRaw = uint256(maxPricePerBps) * weight;
        if (depositRaw > type(uint128).max) revert DepositOverflow();
        uint128 deposit = uint128(depositRaw);

        $.slots[auctionId][msg.sender] = CuttingBoardSyndicateLib.Slot({
            weight: weight,
            maxPricePerBps: maxPricePerBps,
            vault: vault,
            allocatedWeight: 0,
            deposit: deposit
        });
        $.roundPartners[auctionId].push(msg.sender);

        $.paymentToken.safeTransferFrom(msg.sender, address(this), deposit);

        emit SlotRegistered(
            auctionId, msg.sender, vault, weight, maxPricePerBps, deposit
        );
    }

    /**
     * @notice Change the vault for a slot (Open state convenience overload).
     * @dev In Open state, msg.sender is the partner key. Reverts if the round
     *      is not Open; callers in Active state must use the three-argument
     *      overload so they can specify which slot they hold the SlotNFT for.
     */
    function updateSlotVault(uint256 auctionId, address newVault)
        external
        virtual
        whenNotPaused
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) revert NotOpen();
        if (!$.dutchAuction.isAuctionActive(auctionId)) {
            revert AuctionNotActive();
        }
        CuttingBoardSyndicateLib.Slot storage slot =
            $.slots[auctionId][msg.sender];
        if (slot.weight == 0) revert NoSlot();
        $.validateVaultUpdate(auctionId, msg.sender, newVault);
        slot.vault = newVault;
        emit SlotVaultUpdated(auctionId, msg.sender, newVault);
    }

    /**
     * @notice Change the vault for a slot in Active state via SlotNFT ownership,
     *         then automatically submit an updated cutting board proposal.
     * @dev The caller must hold the SlotNFT for (auctionId, originalPartner).
     *      This explicit parameter avoids an O(n) scan and supports callers who
     *      hold multiple SlotNFTs in the same round (acquired on secondary market).
     *      The SlotNFT metadata is kept in sync with the slot storage.
     *
     *      After updating the vault, the function assembles the current weight
     *      allocation and submits a proposal to CuttingBoardManager. The
     *      manager's keeper must still call approveCuttingBoard() to execute
     *      the update on-chain via Infrared.
     *
     *      The new vault must be whitelisted, must not equal bufferVault, and must
     *      not duplicate any other partner's current vault choice.
     * @param auctionId        The round to update.
     * @param originalPartner  The original partner who registered the slot.
     * @param newVault         The new BeraChef receiver vault.
     */
    function updateSlotVault(
        uint256 auctionId,
        address originalPartner,
        address newVault
    ) external virtual whenNotPaused {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Active
        ) revert NotActive();

        CuttingBoardSlotNFT _slotNFT = $.slotNFT;
        if (address(_slotNFT) == address(0)) revert SlotNFTNotSet();

        uint256 slotTokenId = _slotNFT.getTokenId(auctionId, originalPartner);
        if (slotTokenId == 0 || _slotNFT.ownerOf(slotTokenId) != msg.sender) {
            revert NotSlotNFTHolder();
        }

        $.validateVaultUpdate(auctionId, originalPartner, newVault);
        $.slots[auctionId][originalPartner].vault = newVault;
        _slotNFT.updateVault(slotTokenId, newVault);
        emit SlotVaultUpdated(auctionId, originalPartner, newVault);

        $.proposeCurrentWeights(auctionId);
    }

    /**
     * @notice Raise your maximum acceptable price, topping up deposit accordingly.
     * @dev Only upward adjustment is permitted. Downward adjustment would allow a
     *      free-rider exploit: register at a high ceiling to gain fill priority,
     *      then lower to extract an oversized refund at other partners' expense.
     */
    function increaseMaxPrice(uint256 auctionId, uint128 newMaxPricePerBps)
        external
        virtual
        whenNotPaused
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) revert NotOpen();
        if (!$.dutchAuction.isAuctionActive(auctionId)) {
            revert AuctionNotActive();
        }
        CuttingBoardSyndicateLib.Slot storage slot =
            $.slots[auctionId][msg.sender];
        if (slot.weight == 0) revert NoSlot();
        if (newMaxPricePerBps <= slot.maxPricePerBps) {
            revert MaxPriceMustIncrease();
        }

        uint256 newDepositRaw = uint256(newMaxPricePerBps) * slot.weight;
        if (newDepositRaw > type(uint128).max) revert DepositOverflow();
        uint128 newDeposit = uint128(newDepositRaw);
        uint128 additional = newDeposit - slot.deposit;

        slot.maxPricePerBps = newMaxPricePerBps;
        slot.deposit = newDeposit;

        $.paymentToken.safeTransferFrom(msg.sender, address(this), additional);
        emit MaxPriceIncreased(
            auctionId, msg.sender, newMaxPricePerBps, additional
        );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Claim
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Trigger the auction claim once fill conditions are satisfied.
     *
     * Conditions at currentPrice:
     *   1. At least one partner is eligible (maxPricePerBps × 10 000 ≥ currentPrice).
     *   2. The buffer vault's share (10 000 − partnerFill) does not exceed
     *      BeraChef's per-vault weight cap.
     *   3. bufferDeposit covers bufferRequired (buffer vault's bps cost plus
     *      rounding dust from floor-dividing price across allocations). This
     *      applies even when the buffer vault receives zero bps.
     *
     * On success:
     *   - Syndicate pays the auction and receives the CuttingBoardNFT.
     *   - Each included partner's excess deposit is credited to pendingRefunds.
     *   - Each excluded partner's full deposit is credited to pendingRefunds.
     *   - Round state transitions to Active.
     *
     * @dev Permissionless. External parties may also bid directly on the underlying
     *      auction. If they claim first the round can no longer be triggered and
     *      expireRound() should be called to refund partners.
     */
    function triggerClaim(uint256 auctionId) external virtual whenNotPaused {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) revert NotOpen();

        uint256 currentPrice = $.dutchAuction.getCurrentPrice(auctionId);
        CuttingBoardSyndicateLib.FillResult memory fill =
            $.computeFill(auctionId, currentPrice);

        $.validateFill(fill);

        // ── Effects — all state changes before external interactions ──────────
        // Setting state to Active first acts as a reentrancy guard: any reentrant
        // call to triggerClaim or registerSlot will fail the Open check.
        $.rounds[auctionId].state = CuttingBoardSyndicateLib.RoundState.Active;
        $.rounds[auctionId].claimPrice = uint128(currentPrice);
        // Snapshot the buffer vault so submitProposal is unaffected by future
        // governance changes to $.bufferVault.
        $.rounds[auctionId].bufferVault = $.bufferVault;
        $.bufferDeposit -= fill.bufferRequired;

        // Mark included partners via allocatedWeight sentinel, credit refunds.
        // cost ≤ deposit is guaranteed: currentPrice/10000 ≤ maxPricePerBps (eligibility)
        // and alloc ≤ weight (greedy fill), so cost = currentPrice*alloc/10000
        // ≤ maxPricePerBps*weight = deposit. The subtraction cannot underflow.
        for (uint256 i = 0; i < fill.count; i++) {
            address p = fill.included[i];
            uint96 alloc = fill.allocs[i];
            uint96 reqWeight = $.slots[auctionId][p].weight;
            $.slots[auctionId][p].allocatedWeight = alloc;

            uint256 cost = currentPrice * alloc / 10000;
            uint256 refund;
            unchecked {
                refund = $.slots[auctionId][p].deposit - cost;
            }
            if (refund > 0) _creditRefund(p, refund);

            emit SlotFilled(auctionId, p, reqWeight, alloc, cost);
        }

        // Full refund for excluded partners (allocatedWeight still 0).
        // Zero the deposit field so getSlot() is not misleading for excluded partners.
        address[] storage _partners = $.roundPartners[auctionId];
        for (uint256 i = 0; i < _partners.length;) {
            address p = _partners[i];
            if ($.slots[auctionId][p].allocatedWeight == 0) {
                uint256 dep = $.slots[auctionId][p].deposit;
                if (dep > 0) {
                    $.slots[auctionId][p].deposit = 0;
                    _creditRefund(p, dep);
                }
                emit SlotExcluded(auctionId, p, dep);
                // remove excluded partners from round list (swap and pop from array)
                _partners[i] = _partners[_partners.length - 1];
                _partners.pop();
                // don't increment i (new element swapped in and len decreased)
            } else {
                unchecked {
                    ++i;
                }
            }
        }

        $.roundBufferAllocated[auctionId] = fill.bfWeight;
        if (fill.bfWeight > 0) {
            emit BufferUsed(
                auctionId, $.bufferVault, fill.bfWeight, fill.bufferRequired
            );
        }

        // ── Interactions ──────────────────────────────────────────────────────
        IBeraChef.Weight[] memory weights = $.weightsFromFill(
            auctionId, fill.included, fill.allocs, fill.count, fill.bfWeight
        );
        $.paymentToken.safeApprove(address($.dutchAuction), currentPrice);
        $.dutchAuction.claimCuttingBoardControl(auctionId, weights);
        $.paymentToken.safeApprove(address($.dutchAuction), 0);

        // tokenId is only available after the claim; it is purely informational
        // and does not gate any state transitions.
        (CuttingBoardDutchAuction.Auction memory auctionData,) =
            $.dutchAuction.getAuction(auctionId);
        uint96 controlTokenId = uint96(auctionData.controlTokenId);
        $.rounds[auctionId].tokenId = controlTokenId;

        emit RoundTriggered(auctionId, uint128(currentPrice), controlTokenId);

        // Mint per-winner SlotNFTs. slotNFT must be configured before calling triggerClaim.
        // Extracted to a private helper to keep triggerClaim within the stack-variable limit.
        CuttingBoardSlotNFT _slotNFT = $.slotNFT;
        if (address(_slotNFT) == address(0)) revert SlotNFTNotSet();
        _mintSlotNFTs(
            $, _slotNFT, auctionId, currentPrice, controlTokenId, fill
        );
    }

    /// @dev Mint a SlotNFT for each included partner. Extracted from triggerClaim() to
    ///      avoid stack-too-deep; operates in its own stack frame.
    function _mintSlotNFTs(
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $,
        CuttingBoardSlotNFT _slotNFT,
        uint256 auctionId,
        uint256 currentPrice,
        uint96 controlTokenId,
        CuttingBoardSyndicateLib.FillResult memory fill
    ) private {
        // Retrieve expiry from the just-minted control NFT.
        (, uint256 expiry,,) = $.controlNFT.getControlRights(controlTokenId);

        for (uint256 i = 0; i < fill.count; i++) {
            address partner = fill.included[i];
            CuttingBoardSyndicateLib.Slot storage s =
                $.slots[auctionId][partner];
            _slotNFT.mint(
                partner,
                auctionId,
                partner, // originalPartner = partner (first-hand mint)
                s.allocatedWeight,
                s.weight, // requestedWeight
                uint128(currentPrice),
                s.vault,
                expiry,
                s.allocatedWeight < s.weight // isPartialFill
            );
        }
    }

    /**
     * @notice Mark the round as Expired when the auction lapsed without a claim.
     * @dev All partner deposits are moved to pendingRefunds atomically.
     *      This also handles the case where an external party claimed the auction
     *      first — isAuctionActive() returns false in both cases.
     *      bufferDeposit rolls over; it is not refunded on expiry.
     *      Not gated by whenNotPaused so partners can always recover their funds.
     */
    function expireRound(uint256 auctionId) external virtual {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) revert NotOpen();
        if ($.dutchAuction.isAuctionActive(auctionId)) {
            revert AuctionStillLive();
        }

        address[] memory _partners = $.roundPartners[auctionId];
        for (uint256 i = 0; i < _partners.length; i++) {
            address partner = _partners[i];
            uint128 deposit = $.slots[auctionId][partner].deposit;
            if (deposit > 0) _creditRefund(partner, deposit);
        }

        _clearSlots(auctionId);
        $.rounds[auctionId].state = CuttingBoardSyndicateLib.RoundState.Expired;

        emit RoundExpired(auctionId);
    }

    /**
     * @notice Transition an Active round to Complete once its control NFT has expired.
     * @dev Permissionless — anyone can call once the NFT is no longer valid.
     * @param auctionId The round to complete.
     */
    function completeRound(uint256 auctionId) external virtual {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Active
        ) revert NotActive();
        uint256 tokenId = $.rounds[auctionId].tokenId;
        if ($.controlNFT.isValid(tokenId)) revert NFTStillValid();

        $.rounds[auctionId].state = CuttingBoardSyndicateLib.RoundState.Complete;
        emit RoundCompleted(auctionId);
    }

    /**
     * @notice Governance override to replace a partner's vault when the SlotNFT
     *         holder is unresponsive and the vault has been de-whitelisted.
     * @dev Bypasses SlotNFT ownership check. Updates slot storage and SlotNFT
     *      metadata, then auto-submits an updated proposal to CuttingBoardManager.
     *      Use only when the holder cannot or will not call updateSlotVault themselves.
     * @param auctionId        The Active round to update.
     * @param originalPartner  The partner whose vault is being replaced.
     * @param newVault         The replacement BeraChef receiver vault.
     */
    function forceUpdateSlotVault(
        uint256 auctionId,
        address originalPartner,
        address newVault
    ) external virtual onlyGovernor {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Active
        ) revert NotActive();
        $.forceVaultUpdate(auctionId, originalPartner, newVault);
        emit SlotVaultUpdated(auctionId, originalPartner, newVault);
        $.proposeCurrentWeights(auctionId);
    }

    /**
     * @notice Re-submit the current allocation as a proposal to prevent
     *         staleness from BeraChef's inactivity span.
     * @dev Permissionless. Calls proposeCuttingBoard on the Manager using
     *      weightsFromStorage — does not change any weights. The Manager's
     *      keeper must still approve for the refresh to take effect on-chain.
     *      Only callable when the round is Active and the control NFT is valid.
     * @param auctionId The Active round to refresh.
     */
    function refreshProposal(uint256 auctionId)
        external
        virtual
        whenNotPaused
        onlyKeeper
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Active
        ) revert NotActive();
        $.proposeCurrentWeights(auctionId);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Post-claim operations
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Withdraw accumulated refunds for `user`.
     * @dev Funds are sent to `user`, not msg.sender. Permissionless — anyone
     *      can push refunds to inactive partners (or pass their own address).
     *      Not gated by whenNotPaused — partners can always withdraw their funds.
     */
    function claimRefund(address user) external virtual {
        _claimRefund(user);
    }

    /**
     * @notice Push pending refunds to every address that has a non-zero balance.
     * @dev Permissionless — useful for keepers to sweep the full ledger in one tx
     *      so partners do not need to call claimRefund() individually.
     *      Not gated by whenNotPaused — partners can always withdraw their funds.
     *
     *      Iterates backwards and pops each entry so the array is empty when done.
     */
    function claimAllRefunds() external virtual {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        address[] storage all = $.refundees;
        for (uint256 i = all.length; i > 0;) {
            unchecked {
                --i;
            }
            address user = all[i];
            uint256 amount = $.pendingRefunds[user];
            $.refundeeIndex[user] = 0;
            all.pop();
            if (amount > 0) {
                $.pendingRefunds[user] = 0;
                $.paymentToken.safeTransfer(user, amount);
                emit RefundClaimed(user, amount);
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Views
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check whether an Active round's stored allocation still satisfies
     *         current BeraChef rules (whitelist, maxWeightPerVault,
     *         maxNumWeightsPerRewardAllocation).
     * @dev Use for monitoring: if valid is false, the allocation may have been
     *      silently displaced by BeraChef's default allocation.
     * @return valid  True if the allocation would pass BeraChef validation.
     */
    function isRoundAllocationValid(uint256 auctionId)
        external
        view
        virtual
        returns (bool valid)
    {
        return _getStorage().checkRoundAllocationValid(auctionId);
    }

    /// @notice Round metadata for a given auction
    function getRound(uint256 auctionId)
        external
        view
        virtual
        returns (CuttingBoardSyndicateLib.Round memory)
    {
        return _getStorage().rounds[auctionId];
    }

    /// @notice Ordered partner list for a given round
    function getPartners(uint256 auctionId)
        external
        view
        virtual
        returns (address[] memory)
    {
        return _getStorage().roundPartners[auctionId];
    }

    /// @notice Slot details for a specific partner in a given round
    function getSlot(uint256 auctionId, address partner)
        external
        view
        virtual
        returns (CuttingBoardSyndicateLib.Slot memory)
    {
        return _getStorage().slots[auctionId][partner];
    }

    /**
     * @notice Returns true if triggerClaim(auctionId) would currently succeed.
     * @dev Uses the same computeFill DELEGATECALL and validation predicates as
     *      triggerClaim itself, so the two functions are always aligned on
     *      feasibility — including live BeraChef policy (vault whitelist,
     *      maxWeightPerVault, maxNumWeightsPerRewardAllocation).
     */
    function canTrigger(uint256 auctionId)
        external
        view
        virtual
        returns (bool)
    {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if (
            $.rounds[auctionId].state
                != CuttingBoardSyndicateLib.RoundState.Open
        ) return false;
        if (!$.dutchAuction.isAuctionActive(auctionId)) return false;

        uint256 currentPrice;
        try $.dutchAuction.getCurrentPrice(auctionId) returns (uint256 p) {
            currentPrice = p;
        } catch {
            return false;
        }

        CuttingBoardSyndicateLib.FillResult memory fill =
            $.computeFill(auctionId, currentPrice);

        if (fill.bfWeight > $.chef.maxWeightPerVault()) return false;
        if (fill.count == 0) return false;
        uint256 totalEntries = fill.count + (fill.bfWeight > 0 ? 1 : 0);
        if (totalEntries > $.chef.maxNumWeightsPerRewardAllocation()) {
            return false;
        }
        if (fill.bfWeight > 0 && $.bufferVault == address(0)) return false;
        if (fill.bfWeight > 0 && !$.chef.isWhitelistedVault($.bufferVault)) {
            return false;
        }
        return $.bufferDeposit >= fill.bufferRequired;
    }

    /**
     * @notice Preview the fill outcome at a given auction price.
     * @param auctionId    Round to preview.
     * @param price        Hypothetical auction price.
     * @return included    Partners in fill order, trimmed to fill count.
     * @return allocations Allocated bps per partner, trimmed to fill count.
     * @return count       Number of included partners.
     * @return bfWeight    Bps assigned to the buffer vault.
     * @return bufferRequired Payment tokens the buffer must supply (bps cost + rounding dust).
     */
    function previewFillAt(uint256 auctionId, uint256 price)
        external
        view
        virtual
        returns (
            address[] memory included,
            uint96[] memory allocations,
            uint256 count,
            uint96 bfWeight,
            uint256 bufferRequired
        )
    {
        CuttingBoardSyndicateLib.FillResult memory fill =
            _getStorage().computeFill(auctionId, price);

        // Trim arrays to the actual fill count so callers receive clean slices.
        included = new address[](fill.count);
        allocations = new uint96[](fill.count);
        for (uint256 i = 0; i < fill.count; i++) {
            included[i] = fill.included[i];
            allocations[i] = fill.allocs[i];
        }

        return (
            included,
            allocations,
            fill.count,
            fill.bfWeight,
            fill.bufferRequired
        );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Credit a refund to a user and register them in the enumeration set.
    function _creditRefund(address user, uint256 amount) internal {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        if ($.refundeeIndex[user] == 0) {
            $.refundees.push(user);
            $.refundeeIndex[user] = $.refundees.length; // 1-based
        }
        $.pendingRefunds[user] += amount;
    }

    /// @notice Zero balance, remove from set, transfer, and emit.
    function _claimRefund(address user) internal {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        uint256 amount = $.pendingRefunds[user];
        if (amount == 0) revert NothingToRefund();
        $.pendingRefunds[user] = 0;
        _removeRefundee($, user);
        $.paymentToken.safeTransfer(user, amount);
        emit RefundClaimed(user, amount);
    }

    /// @notice Remove a user from the refundees enumeration set (swap-and-pop).
    function _removeRefundee(
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $,
        address user
    ) internal {
        uint256 idx = $.refundeeIndex[user]; // 1-based
        if (idx == 0) return;
        uint256 lastIdx = $.refundees.length;
        if (idx != lastIdx) {
            address last = $.refundees[lastIdx - 1];
            $.refundees[idx - 1] = last;
            $.refundeeIndex[last] = idx;
        }
        $.refundees.pop();
        $.refundeeIndex[user] = 0;
    }

    function _clearSlots(uint256 auctionId) internal {
        CuttingBoardSyndicateLib.CuttingBoardSyndicateStorage storage $ =
            _getStorage();
        address[] memory _partners = $.roundPartners[auctionId];
        for (uint256 i = 0; i < _partners.length; i++) {
            delete $.slots[auctionId][_partners[i]];
        }
        delete $.roundPartners[auctionId];
    }
}
