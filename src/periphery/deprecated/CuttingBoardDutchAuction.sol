// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Upgradeable} from "src/utils/Upgradeable.sol";
import {CuttingBoardNFT} from "src/periphery/CuttingBoardNFT.sol";
import {CuttingBoardManager} from "src/periphery/CuttingBoardManager.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IBeraChefVaultCheck} from "src/interfaces/IBeraChefVaultCheck.sol";

/**
 * @notice Minimal interface for Infrared protocol validator validation
 * @dev Used to verify validator pubkeys are registered with Infrared
 */
interface IInfrared {
    /**
     * @notice Check if a validator is registered with Infrared protocol
     * @param _pubkey The validator public key to check
     * @return True if the validator is registered, false otherwise
     */
    function isInfraredValidator(bytes memory _pubkey)
        external
        view
        returns (bool);
}

/**
 * @title CuttingBoardDutchAuction
 * @notice Dutch auction for temporary control rights over validator cutting boards
 * @dev Extends the cutting board auction model to grant full manual control of validator
 *      reward allocations. Winners receive an NFT that allows them to update the cutting
 *      board multiple times during the allocation period, enabling dynamic yield optimization.
 *
 * Key features:
 * - Auctions specific validators (identified by pubkey)
 * - Winner must provide initial cutting board on claim
 * - Mints NFT representing control rights
 * - NFT holder can update cutting board via CuttingBoardManager
 * - Linear price decay (Dutch auction model)
 * - Control expires after allocationDuration
 * - Configurable auction parameters (duration, portion size, max auctions).
 * - Starting price: Configurable multiplier of previous closing price.
 * - Base price (floor): Configurable divisor of previous closing price.
 * - Payment in specified payment token.
 * - Single winner claims the full portion per auction.
 * - On-chain claim: Anyone can claim by paying exactly the current price.
 * @dev Uses ERC-7201 namespaced storage pattern for upgradeability
 */
contract CuttingBoardDutchAuction is Upgradeable {
    using SafeTransferLib for ERC20;

    /// @custom:storage-location erc7201:infrared.storage.CuttingBoardDutchAuction
    struct CuttingBoardDutchAuctionStorage {
        /// @notice Infrared address
        IInfrared infrared;
        /// @notice Payment token for auction bids (must be a plain ERC20 i.e. not fee on transfer or blacklist)
        ERC20 paymentToken;
        /// @notice Treasury address receiving auction payments
        address treasury;
        /// @notice BeraChef contract for vault whitelist validation
        IBeraChefVaultCheck chef;
        /// @notice CuttingBoardNFT contract for minting control rights
        CuttingBoardNFT controlNFT;
        /// @notice CuttingBoardManager for queueing initial cutting boards
        CuttingBoardManager controlManager;
        /// @notice Auction duration in seconds (price decay period)
        uint256 auctionDuration;
        /// @notice Allocation duration in seconds (how long winner controls validator)
        uint256 allocationDuration;
        /// @notice Maximum number of auctions
        uint256 maxAuctions;
        /// @notice Starting price multiplier (e.g., 2e18 = 2x previous price)
        uint256 startingPriceMultiplier;
        /// @notice Base price divisor (e.g., 2e18 = 0.5x previous price)
        uint256 basePriceDivisor;
        /// @notice Minimum price floor
        uint256 minimumPrice;
        /// @notice Reference to last closing price for next auction
        uint256 lastClosingPrice;
        /// @notice Array of all auctions
        Auction[] auctions;
        /// @notice Mapping from auction ID to validator pubkey
        mapping(uint256 => bytes) auctionValidators;
        /// @notice Mapping from validator pubkey hash to active auction ID (0 = none)
        mapping(bytes32 => uint256) activeValidatorAuctions;
        /// @notice Mapping from validator pubkey hash to control token id
        mapping(bytes32 => uint256) validatorControlTokenId;
    }

    // keccak256(abi.encode(uint256(keccak256("infrared.storage.CuttingBoardDutchAuction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUTTING_BOARD_DUTCH_AUCTION_STORAGE_LOCATION =
        0x67c283459ab08c5e5e83c645bebd5b8d5f91d5b9fb7d2a34ff4694a99438fd00;

    function _getCuttingBoardDutchAuctionStorage()
        internal
        pure
        returns (CuttingBoardDutchAuctionStorage storage $)
    {
        assembly {
            $.slot := CUTTING_BOARD_DUTCH_AUCTION_STORAGE_LOCATION
        }
    }

    // Public getters for storage variables
    function infrared() public view returns (IInfrared) {
        return _getCuttingBoardDutchAuctionStorage().infrared;
    }

    function paymentToken() public view returns (ERC20) {
        return _getCuttingBoardDutchAuctionStorage().paymentToken;
    }

    function treasury() public view returns (address) {
        return _getCuttingBoardDutchAuctionStorage().treasury;
    }

    function chef() public view returns (IBeraChefVaultCheck) {
        return _getCuttingBoardDutchAuctionStorage().chef;
    }

    function controlNFT() public view returns (CuttingBoardNFT) {
        return _getCuttingBoardDutchAuctionStorage().controlNFT;
    }

    function controlManager() public view returns (CuttingBoardManager) {
        return _getCuttingBoardDutchAuctionStorage().controlManager;
    }

    function auctionDuration() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().auctionDuration;
    }

    function allocationDuration() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().allocationDuration;
    }

    function maxAuctions() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().maxAuctions;
    }

    function startingPriceMultiplier() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().startingPriceMultiplier;
    }

    function basePriceDivisor() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().basePriceDivisor;
    }

    function minimumPrice() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().minimumPrice;
    }

    function lastClosingPrice() public view returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().lastClosingPrice;
    }

    // Reserve storage space for upgrades
    uint256[20] private __gap;

    /// @notice Auction data structure (optimized for storage)
    /// @dev Packed to minimize storage slots
    struct Auction {
        /// @dev Timestamp when the auction started (uint128 to save gas)
        uint128 startTime;
        /// @dev Initial auction price at start time
        uint128 startingPrice;
        /// @dev Floor price after full auction duration
        uint128 basePrice;
        /// @dev Actual price paid when claimed (0 if not claimed)
        uint128 claimPrice;
        /// @dev Address of the auction winner (address(0) if not claimed)
        address winner;
        /// @dev Whether the auction has been claimed
        bool claimed;
        /// @dev Duration in seconds the winner controls the validator
        uint32 allocationDuration;
        /// @dev Token ID of the minted control NFT (0 if not claimed)
        uint256 controlTokenId;
    }

    /// @notice Emitted when a new auction is started
    /// @param auctionId The unique identifier for the auction
    /// @param validatorHash Hash of validator pubkey for cutting board auction
    /// @param startingPrice The initial price at auction start
    /// @param basePrice The floor price after auction duration
    /// @param startTime The timestamp when the auction started
    /// @param allocationDuration The duration in seconds the winner controls the allocation
    event AuctionStarted(
        uint256 indexed auctionId,
        bytes32 indexed validatorHash,
        uint256 startingPrice,
        uint256 basePrice,
        uint256 startTime,
        uint256 allocationDuration
    );

    /// @notice Emitted when an auction is claimed
    /// @param auctionId The unique identifier for the auction
    /// @param winner The address that won the auction
    /// @param validatorHash Hash of validator pubkey for cutting board auction
    /// @param pricePaid The final price paid to claim the auction
    /// @param controlTokenId The NFT id with cutting board control
    /// @param allocationDuration The duration in seconds the winner controls the allocation
    event AuctionClaimed(
        uint256 indexed auctionId,
        address indexed winner,
        bytes32 indexed validatorHash,
        uint256 pricePaid,
        uint256 controlTokenId,
        uint256 allocationDuration
    );

    /// @notice Emitted when auction duration is updated
    /// @param newDuration The new auction duration in seconds
    event AuctionDurationUpdated(uint256 newDuration);

    /// @notice Emitted when allocation duration is updated
    /// @param newDuration The new allocation duration in seconds
    event AllocationDurationUpdated(uint256 newDuration);

    /// @notice Emitted when max auctions is updated
    /// @param newMaxAuctions The new maximum number of auctions
    event MaxAuctionsUpdated(uint256 newMaxAuctions);

    /// @notice Emitted when minimum price is updated
    /// @param newPrice The new minimum price
    event MinimumPriceUpdated(uint256 newPrice);

    /// @notice Emitted when base price divisor is updated
    /// @param newDivisor The new base price divisor
    event BasePriceDivisorUpdated(uint256 newDivisor);

    /// @notice Emitted when starting price multiplier is updated
    /// @param newMultiplier The new starting price multiplier
    event StartingPriceMultiplierUpdated(uint256 newMultiplier);

    /// @notice Emitted when initial price is set
    /// @param price The initial closing price reference
    event InitialPriceSet(uint256 price);

    /// @notice Initialization parameters struct to avoid stack too deep
    struct InitParams {
        address infrared;
        address paymentToken;
        address treasury;
        address chef;
        address controlNFT;
        address controlManager;
        address governance;
        address keeper;
        uint256 auctionDuration;
        uint256 allocationDuration;
        uint256 maxAuctions;
        uint256 startingPriceMultiplier;
        uint256 basePriceDivisor;
        uint256 minimumPrice;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the CuttingBoardDutchAuction contract
     * @param params Initialization parameters struct containing all configuration values
     * @dev Validates all parameters and sets contract references
     *      Requires all addresses to be non-zero and numeric parameters to be within valid ranges
     */
    function initialize(InitParams calldata params) external initializer {
        // Validate addresses
        if (params.infrared == address(0)) revert ZeroAddress();
        if (params.paymentToken == address(0)) revert InvalidPaymentToken();
        if (params.treasury == address(0)) revert InvalidTreasury();
        if (params.chef == address(0)) revert InvalidChef();
        if (params.controlNFT == address(0)) revert InvalidNFT();
        if (params.controlManager == address(0)) revert InvalidManager();
        if (params.governance == address(0)) revert ZeroAddress();

        // Validate parameters
        if (params.auctionDuration == 0) revert InvalidDuration();
        if (params.allocationDuration == 0) revert InvalidAllocationDuration();
        if (params.maxAuctions == 0) revert InvalidMaxAuctions();
        if (params.startingPriceMultiplier <= 1e18) revert InvalidMultiplier();
        if (params.basePriceDivisor <= 1e18) revert InvalidDivisor();
        if (params.minimumPrice == 0) revert InvalidMinimumPrice();

        __Upgradeable_init();

        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        $.infrared = IInfrared(params.infrared);
        $.paymentToken = ERC20(params.paymentToken);
        $.treasury = params.treasury;
        $.chef = IBeraChefVaultCheck(params.chef);
        $.controlNFT = CuttingBoardNFT(params.controlNFT);
        $.controlManager = CuttingBoardManager(params.controlManager);
        $.auctionDuration = params.auctionDuration;
        $.allocationDuration = params.allocationDuration;
        $.maxAuctions = params.maxAuctions;
        $.startingPriceMultiplier = params.startingPriceMultiplier;
        $.basePriceDivisor = params.basePriceDivisor;
        $.minimumPrice = params.minimumPrice;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, params.governance);
        _grantRole(GOVERNANCE_ROLE, params.governance);
        if (params.keeper != address(0)) {
            _grantRole(KEEPER_ROLE, params.keeper);
        }
    }

    /**
     * @notice Start auction for a specific validator
     * @param validatorPubkey The validator pubkey to auction control rights for
     * @dev Callable by keeper.
     * Price params derived from lastClosingPrice.
     * Prevents starting a new auction if the previous one hasn't been claimed.
     * If previous auction was unclaimed, uses its base price as the closing price.
     */
    function startCuttingBoardAuction(bytes calldata validatorPubkey)
        external
        virtual
        onlyKeeper
        whenNotPaused
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if ($.auctions.length >= $.maxAuctions) revert AllAuctionsCompleted();
        if (validatorPubkey.length != 48) revert InvalidValidatorPubkey();
        if (!$.infrared.isInfraredValidator(validatorPubkey)) {
            revert InvalidValidatorPubkey();
        }

        // Prevent simultaneous auctions - previous must be claimed first
        if ($.auctions.length > 0) {
            Auction memory prevAuction = $.auctions[$.auctions.length - 1];
            if (!prevAuction.claimed) {
                // Allow starting new auction if previous expired
                uint256 auctionEndTime =
                    prevAuction.startTime + $.auctionDuration;
                if (block.timestamp < auctionEndTime) {
                    revert PreviousAuctionNotClaimed();
                }
                // Update lastClosingPrice to expired auction's base price
                $.lastClosingPrice = prevAuction.basePrice;
                // Previous auction expired - clear active validator auction mapping
                bytes32 prevValidatorHash =
                    keccak256($.auctionValidators[$.auctions.length - 1]);
                $.activeValidatorAuctions[prevValidatorHash] = 0;
            }
        }

        // Check validator is available (not currently controlled)
        bytes32 validatorHash = keccak256(validatorPubkey);
        if (!_isValidatorAvailable(validatorHash)) {
            revert ValidatorNotAvailable();
        }

        // For first auction, require initial price
        if ($.auctions.length == 0) {
            if ($.lastClosingPrice == 0) revert SetInitialPriceFirst();
        }

        // Calculate prices
        if ($.lastClosingPrice > type(uint256).max / $.startingPriceMultiplier)
        {
            revert PriceOverflow();
        }
        uint256 starting =
            ($.lastClosingPrice * $.startingPriceMultiplier) / 1e18;
        uint256 base = ($.lastClosingPrice * 1e18) / $.basePriceDivisor;

        if (base < $.minimumPrice) {
            base = $.minimumPrice;
        }

        if (starting <= base) revert InvalidPriceRange();
        if (starting > type(uint128).max) revert PriceOverflow();
        if (base > type(uint128).max) revert PriceOverflow();
        if (block.timestamp > type(uint128).max) revert PriceOverflow();
        if ($.allocationDuration > type(uint32).max) revert PriceOverflow();

        uint256 auctionId = $.auctions.length;

        $.auctions.push(
            Auction({
                startTime: uint128(block.timestamp),
                startingPrice: uint128(starting),
                basePrice: uint128(base),
                claimPrice: 0,
                winner: address(0),
                claimed: false,
                allocationDuration: uint32($.allocationDuration),
                controlTokenId: 0
            })
        );

        $.auctionValidators[auctionId] = validatorPubkey;
        $.activeValidatorAuctions[validatorHash] = auctionId + 1; // +1 to distinguish from 0

        emit AuctionStarted(
            auctionId,
            validatorHash,
            starting,
            base,
            block.timestamp,
            $.allocationDuration
        );
    }

    /**
     * @notice Claim validator control by paying current price
     * @param auctionId The auction ID to claim
     * @param initialWeights Initial cutting board configuration
     */
    function claimCuttingBoardControl(
        uint256 auctionId,
        IBeraChef.Weight[] calldata initialWeights
    ) external virtual whenNotPaused {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if (auctionId >= $.auctions.length) revert InvalidAuctionId();
        if (initialWeights.length == 0) revert InvalidWeights();

        Auction storage auction = $.auctions[auctionId];
        if (auction.claimed) revert AlreadyClaimed();
        if (block.timestamp < auction.startTime) revert AuctionNotStarted();

        // Check if auction has expired
        uint256 auctionEndTime = auction.startTime + $.auctionDuration;
        if (block.timestamp >= auctionEndTime) revert AuctionExpired();

        uint256 currentPrice = getCurrentPrice(auctionId);
        if (currentPrice == 0) revert InvalidPrice();
        if (currentPrice > type(uint128).max) revert PriceOverflow();

        // Process claim with scoped variables
        bytes memory validatorPubkey = $.auctionValidators[auctionId];
        // re-check validity of infrared validator for safety
        if (!$.infrared.isInfraredValidator(validatorPubkey)) {
            revert InvalidValidatorPubkey();
        }
        uint256 tokenId = _processClaim(
            auctionId, auction, currentPrice, validatorPubkey, initialWeights
        );

        emit AuctionClaimed(
            auctionId,
            msg.sender,
            keccak256(validatorPubkey),
            currentPrice,
            tokenId,
            auction.allocationDuration
        );
    }

    /**
     * @notice Internal function to process claim and reduce stack depth
     * @param auctionId The auction ID
     * @param auction Storage reference to auction
     * @param currentPrice The current auction price
     * @param validatorPubkey The validator pubkey
     * @param initialWeights Initial cutting board weights
     * @return tokenId The minted NFT token ID
     */
    function _processClaim(
        uint256 auctionId,
        Auction storage auction,
        uint256 currentPrice,
        bytes memory validatorPubkey,
        IBeraChef.Weight[] calldata initialWeights
    ) internal virtual returns (uint256 tokenId) {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        bytes32 validatorHash = keccak256(validatorPubkey);
        uint256 expiryTimestamp = block.timestamp + auction.allocationDuration;

        // Effects: Update state before external calls
        auction.winner = msg.sender;
        auction.claimed = true;
        auction.claimPrice = uint128(currentPrice);
        $.lastClosingPrice = currentPrice;

        // Clear active auction for this validator
        $.activeValidatorAuctions[validatorHash] = 0;

        // Mint control NFT
        tokenId = $.controlNFT.mint(
            msg.sender, validatorPubkey, expiryTimestamp, auctionId
        );

        // Set control token id
        $.validatorControlTokenId[validatorHash] = tokenId;

        auction.controlTokenId = tokenId;

        // Transfer payment to treasury
        $.paymentToken.safeTransferFrom(msg.sender, $.treasury, currentPrice);

        // Queue initial cutting board via manager
        $.controlManager.proposeCuttingBoard(tokenId, initialWeights);
    }

    /**
     * @notice Get current auction price
     * @param auctionId The auction ID
     * @return Current price (decays linearly)
     * @dev Reverts if auction has expired (past auctionDuration)
     */
    function getCurrentPrice(uint256 auctionId)
        public
        view
        virtual
        returns (uint256)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if (auctionId >= $.auctions.length) revert InvalidAuctionId();
        Auction storage auction = $.auctions[auctionId];
        if (block.timestamp < auction.startTime) revert AuctionNotStarted();
        if (auction.claimed) revert AlreadyClaimed();

        uint256 elapsed = block.timestamp - auction.startTime;
        if (elapsed >= $.auctionDuration) {
            revert AuctionExpired();
        }

        if (elapsed == 0) return auction.startingPrice;

        uint256 priceRange = auction.startingPrice - auction.basePrice;
        if (priceRange > type(uint256).max / elapsed) revert PriceOverflow();
        uint256 priceDrop = (priceRange * elapsed) / $.auctionDuration;
        return auction.startingPrice - priceDrop;
    }

    /**
     * @notice Check if a validator is available for auction
     * @param validatorPubkey The validator pubkey to check
     * @return True if validator can be auctioned
     */
    function isValidatorAvailable(bytes calldata validatorPubkey)
        external
        view
        virtual
        returns (bool)
    {
        return _isValidatorAvailable(keccak256(validatorPubkey));
    }

    /**
     * @notice Check if a validator is currently allocated to NFT holder
     * @param validatorPubkey The validator pubkey to check
     * @return True if validator is currently allocated to NFT holder
     */
    function isValidatorAllocated(bytes calldata validatorPubkey)
        external
        view
        virtual
        returns (bool)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        return $.controlNFT.isValid(
            $.validatorControlTokenId[keccak256(validatorPubkey)]
        );
    }

    /**
     * @notice Get validator pubkey for an auction
     * @param auctionId The auction ID
     * @return The validator pubkey
     */
    function getAuctionValidator(uint256 auctionId)
        external
        view
        virtual
        returns (bytes memory)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (auctionId >= $.auctions.length) revert InvalidAuctionId();
        return $.auctionValidators[auctionId];
    }

    /**
     * @notice Get complete auction details
     * @param auctionId The auction ID
     * @return auction_ The auction struct data
     * @return validatorPubkey The validator pubkey for this auction
     */
    function getAuction(uint256 auctionId)
        external
        view
        virtual
        returns (Auction memory auction_, bytes memory validatorPubkey)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (auctionId >= $.auctions.length) revert InvalidAuctionId();
        auction_ = $.auctions[auctionId];
        validatorPubkey = $.auctionValidators[auctionId];
    }

    /**
     * @notice Get total number of auctions
     * @return The total number of auctions created
     */
    function getAuctionCount() external view virtual returns (uint256) {
        return _getCuttingBoardDutchAuctionStorage().auctions.length;
    }

    /**
     * @notice Check if an auction is active
     * @param auctionId The auction ID
     * @return True if auction is active (started and not claimed), false otherwise
     */
    function isAuctionActive(uint256 auctionId)
        external
        view
        virtual
        returns (bool)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (auctionId >= $.auctions.length) return false;
        Auction storage auction = $.auctions[auctionId];
        return block.timestamp >= auction.startTime && !auction.claimed
            && block.timestamp < auction.startTime + $.auctionDuration;
    }

    /**
     * @notice Get the current active auction
     * @return auctionId The ID of the active auction (0 if none active)
     * @return isActive True if there is an active auction, false otherwise
     */
    function getActiveAuction()
        external
        view
        virtual
        returns (uint256 auctionId, bool isActive)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if ($.auctions.length == 0) return (0, false);

        uint256 latestId = $.auctions.length - 1;
        Auction storage auction = $.auctions[latestId];

        if (
            block.timestamp >= auction.startTime && !auction.claimed
                && block.timestamp < auction.startTime + $.auctionDuration
        ) {
            return (latestId, true);
        }

        return (0, false);
    }

    /**
     * @notice Get the most recent auction regardless of validator
     * @dev Useful for keepers to check the current auction state
     * @return auctionId The ID of the last auction (0 if none exist)
     * @return auction_ The auction struct data
     * @return validatorPubkey The validator pubkey for this auction
     * @return exists True if at least one auction exists, false otherwise
     */
    function getLastAuction()
        external
        view
        virtual
        returns (
            uint256 auctionId,
            Auction memory auction_,
            bytes memory validatorPubkey,
            bool exists
        )
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if ($.auctions.length == 0) {
            return (auctionId, auction_, validatorPubkey, exists);
        }

        auctionId = $.auctions.length - 1;
        auction_ = $.auctions[auctionId];
        validatorPubkey = $.auctionValidators[auctionId];
        exists = true;
    }

    /**
     * @notice Get the most recent auction for a specific validator
     * @dev Iterates backwards through auctions to find the last one for the given validator.
     *      Useful for keepers to check if a validator has been auctioned before and its history.
     * @param validatorPubkey The validator pubkey to search for (must be 48 bytes)
     * @return auctionId The ID of the last auction for this validator (0 if not found)
     * @return auction_ The auction struct data (empty if not found)
     * @return exists True if an auction was found for this validator, false otherwise
     */
    function getLastValidatorAuction(bytes calldata validatorPubkey)
        external
        view
        virtual
        returns (uint256 auctionId, Auction memory auction_, bool exists)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        if ($.auctions.length == 0) {
            return (auctionId, auction_, exists);
        }

        // Iterate backwards to find the most recent auction for this validator
        // Use unchecked decrement pattern to properly handle index 0
        bytes32 targetHash = keccak256(validatorPubkey);
        for (uint256 i = $.auctions.length; i > 0;) {
            unchecked {
                --i;
            }
            if (keccak256($.auctionValidators[i]) == targetHash) {
                auctionId = i;
                auction_ = $.auctions[i];
                exists = true;
                break;
            }
        }
    }

    // Admin functions

    /**
     * @notice Set the initial price reference for the first auction
     * @param price The initial closing price (must be > 0)
     * @dev Can only be called before any auctions are started
     */
    function setInitialPrice(uint256 price) external virtual onlyGovernor {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if ($.auctions.length > 0) revert AuctionsAlreadyStarted();
        if (price == 0) revert InvalidPrice();
        $.lastClosingPrice = price;
        emit InitialPriceSet(price);
    }

    /**
     * @notice Update the auction duration (price decay period)
     * @param _auctionDuration New auction duration in seconds
     * @dev Can only be called before any auctions are started
     */
    function setAuctionDuration(uint256 _auctionDuration)
        external
        virtual
        onlyGovernor
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if ($.auctions.length > 0) revert AuctionsAlreadyStarted();
        if (_auctionDuration == 0) revert InvalidDuration();
        $.auctionDuration = _auctionDuration;
        emit AuctionDurationUpdated(_auctionDuration);
    }

    /**
     * @notice Update the allocation duration (control period length)
     * @param _allocationDuration New allocation duration in seconds
     * @dev Can only be called before any auctions are started
     */
    function setAllocationDuration(uint256 _allocationDuration)
        external
        virtual
        onlyGovernor
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if ($.auctions.length > 0) revert AuctionsAlreadyStarted();
        if (_allocationDuration == 0) revert InvalidAllocationDuration();
        $.allocationDuration = _allocationDuration;
        emit AllocationDurationUpdated(_allocationDuration);
    }

    /**
     * @notice Update the maximum number of auctions
     * @param _maxAuctions New maximum auction count
     */
    function setMaxAuctions(uint256 _maxAuctions)
        external
        virtual
        onlyGovernor
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_maxAuctions == 0) revert InvalidMaxAuctions();
        $.maxAuctions = _maxAuctions;
        emit MaxAuctionsUpdated(_maxAuctions);
    }

    /**
     * @notice Update the minimum price floor
     * @param _minimumPrice New minimum price in payment token decimals
     * @dev Can be updated at any time by keeper
     */
    function setMinimumPrice(uint256 _minimumPrice)
        external
        virtual
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_minimumPrice == 0) revert InvalidMinimumPrice();
        $.minimumPrice = _minimumPrice;
        if (_minimumPrice > $.lastClosingPrice) {
            // Update lastClosingPrice to new min
            $.lastClosingPrice = _minimumPrice;
            emit InitialPriceSet(_minimumPrice);
        }
        emit MinimumPriceUpdated(_minimumPrice);
    }

    function setClosingPriceReference(uint256 price)
        external
        virtual
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (price == 0) revert InvalidPrice();
        $.lastClosingPrice = price;
        emit InitialPriceSet(price);
    }

    /**
     * @notice Update the base price divisor (controls price floor)
     * @param _basePriceDivisor New divisor (e.g., 2e18 = 0.5x previous price)
     * @dev Can be updated at any time by keeper, must be > 1e18
     */
    function setBasePriceDivisor(uint256 _basePriceDivisor)
        external
        virtual
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_basePriceDivisor <= 1e18) revert InvalidDivisor();
        $.basePriceDivisor = _basePriceDivisor;
        emit BasePriceDivisorUpdated(_basePriceDivisor);
    }

    /**
     * @notice Update the starting price multiplier (controls auction start price)
     * @param _startingPriceMultiplier New multiplier (e.g., 2e18 = 2x previous price)
     * @dev Can be updated at any time by keeper, must be > 1e18
     */
    function setStartingPriceMultiplier(uint256 _startingPriceMultiplier)
        external
        virtual
        onlyKeeper
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();
        if (_startingPriceMultiplier <= 1e18) revert InvalidMultiplier();
        $.startingPriceMultiplier = _startingPriceMultiplier;
        emit StartingPriceMultiplierUpdated(_startingPriceMultiplier);
    }

    // Internal functions

    /**
     * @notice Check if a validator is available for a new auction
     * @param validatorHash Keccak256 hash of the validator pubkey
     * @return True if validator can be auctioned, false otherwise
     * @dev A validator is available if:
     *      1. No active auction exists for this validator
     *      2. Control period has expired (if previously controlled)
     */
    function _isValidatorAvailable(bytes32 validatorHash)
        internal
        view
        virtual
        returns (bool)
    {
        CuttingBoardDutchAuctionStorage storage $ =
            _getCuttingBoardDutchAuctionStorage();

        // Check if there's an active auction for this validator
        if ($.activeValidatorAuctions[validatorHash] != 0) {
            return false;
        }

        // Check if control period has expired
        uint256 tokenId = $.validatorControlTokenId[validatorHash];
        if ($.controlNFT.isValid(tokenId)) {
            return false;
        }

        return true;
    }

    // Custom errors

    /// @notice Thrown when an invalid payment token address is provided
    error InvalidPaymentToken();

    /// @notice Thrown when an invalid auction duration is provided (zero)
    error InvalidDuration();

    /// @notice Thrown when an invalid max auctions value is provided (zero)
    error InvalidMaxAuctions();

    /// @notice Thrown when an invalid starting price multiplier is provided (<= 1e18)
    error InvalidMultiplier();

    /// @notice Thrown when an invalid base price divisor is provided (<= 1e18)
    error InvalidDivisor();

    /// @notice Thrown when an invalid treasury address is provided
    error InvalidTreasury();

    /// @notice Thrown when an invalid minimum price is provided (zero)
    error InvalidMinimumPrice();

    /// @notice Thrown when an invalid allocation duration is provided (zero)
    error InvalidAllocationDuration();

    /// @notice Thrown when attempting to start an auction after max auctions reached
    error AllAuctionsCompleted();

    /// @notice Thrown when attempting to start the first auction without setting initial price
    error SetInitialPriceFirst();

    /// @notice Thrown when starting price is not greater than base price
    error InvalidPriceRange();

    /// @notice Thrown when an invalid auction ID is provided
    error InvalidAuctionId();

    /// @notice Thrown when attempting to interact with an auction that hasn't started
    error AuctionNotStarted();

    /// @notice Thrown when attempting to claim or get price for an expired auction
    error AuctionExpired();

    /// @notice Thrown when attempting to claim an already claimed auction
    error AlreadyClaimed();

    /// @notice Thrown when an invalid price is provided (zero or invalid calculation)
    error InvalidPrice();

    /// @notice Thrown when attempting to update parameters after auctions have started
    error AuctionsAlreadyStarted();

    /// @notice Thrown when attempting to start a new auction before the previous one is claimed
    error PreviousAuctionNotClaimed();

    /// @notice Thrown when a price calculation would overflow
    error PriceOverflow();

    /// @notice Thrown when an invalid NFT contract address is provided (zero address)
    error InvalidNFT();

    /// @notice Thrown when an invalid manager contract address is provided (zero address)
    error InvalidManager();

    /// @notice Thrown when an invalid BeraChef contract address is provided (zero address)
    error InvalidChef();

    /// @notice Thrown when an invalid validator pubkey is provided (wrong length or not registered)
    error InvalidValidatorPubkey();

    /// @notice Thrown when cutting board weights are invalid (not whitelisted vaults or total != 10000)
    error InvalidWeights();

    /// @notice Thrown when attempting to auction a validator that is not currently available
    error ValidatorNotAvailable();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();
}
