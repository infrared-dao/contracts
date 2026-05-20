// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@solmate/tokens/ERC721.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/**
 * @title CuttingBoardSlotNFT
 * @notice ERC-721 token representing a won slot in a CuttingBoardSyndicate round.
 * @dev Minted at triggerClaim() for each included partner. Transferable — the current
 *      holder can redirect the slot allocation to a different vault via the Syndicate's
 *      updateSlotVaultByNFT(). Expiry matches the control NFT (same allocationDuration).
 *
 *      Deployment order:
 *        1. Deploy Syndicate proxy (address known).
 *        2. Deploy CuttingBoardSlotNFT(syndicate=proxyAddr, owner=governance, baseURI="").
 *        3. Syndicate governance calls setSlotNFT(slotNFTAddr).
 *
 *      No circular dependency — the syndicate address is immutable in this contract,
 *      and the syndicate stores the SlotNFT address in its own upgradeable storage.
 */
contract CuttingBoardSlotNFT is ERC721, Owned {
    /// @notice Represents the slot rights associated with an NFT
    struct SlotRights {
        uint256 auctionId;
        address originalPartner; // original auction winner (for reverse lookup in Syndicate)
        uint96 allocatedWeight; // actual bps allocated at triggerClaim
        uint96 requestedWeight; // bps bid by the partner
        uint128 clearingPrice; // total auction price paid at triggerClaim
        address vault; // current BeraChef receiver vault (updatable via Syndicate)
        uint256 expiryTimestamp; // matches control NFT expiry (allocationDuration end)
        bool isPartialFill; // true when allocatedWeight < requestedWeight
    }

    /// @notice Address of the CuttingBoardSyndicate — sole authorised minter/updater
    address public immutable syndicate;

    /// @notice Mapping from token ID to slot rights
    mapping(uint256 => SlotRights) private _tokenRights;

    /// @notice Current token ID counter; starts at 1
    uint256 private _nextTokenId;

    /// @notice Reverse lookup: auctionId → originalPartner → tokenId (0 = not minted)
    mapping(uint256 => mapping(address => uint256)) private _auctionPartnerToken;

    /// @notice Metadata base URI
    string private _baseTokenURI;

    // ── Events ────────────────────────────────────────────────────────────────

    /// @notice Emitted when a new slot NFT is minted
    event SlotNFTMinted(
        uint256 indexed tokenId,
        uint256 indexed auctionId,
        address indexed originalPartner,
        address vault,
        uint96 allocatedWeight,
        uint96 requestedWeight,
        uint128 clearingPrice,
        uint256 expiryTimestamp,
        bool isPartialFill
    );

    /// @notice Emitted when the vault recorded in a slot NFT is updated
    event SlotVaultUpdated(uint256 indexed tokenId, address indexed newVault);

    // ── Errors ────────────────────────────────────────────────────────────────

    /// @notice Caller is not the syndicate contract
    error NotSyndicate();

    /// @notice Token ID does not exist
    error InvalidTokenId();

    // ── Modifier ──────────────────────────────────────────────────────────────

    modifier onlySyndicate() {
        if (msg.sender != syndicate) revert NotSyndicate();
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @notice Deploy the CuttingBoardSlotNFT contract.
     * @param _syndicate Address of the CuttingBoardSyndicate proxy (authorised minter).
     * @param _owner     Address of the contract owner (can update baseURI).
     * @param baseURI    Initial metadata base URI (may be empty).
     */
    constructor(address _syndicate, address _owner, string memory baseURI)
        ERC721("Infrared Slot", "iSLOT")
        Owned(_owner)
    {
        if (_syndicate == address(0)) revert NotSyndicate();
        syndicate = _syndicate;
        _baseTokenURI = baseURI;
        _nextTokenId = 1;
    }

    // ── Syndicate-only write functions ────────────────────────────────────────

    /**
     * @notice Mint a new slot NFT to a winner.
     * @dev Only callable by the syndicate. Records all auction metadata at the time
     *      of triggerClaim. The reverse lookup (_auctionPartnerToken) maps
     *      (auctionId, originalPartner) → tokenId for the lifetime of the token.
     * @param to               Recipient of the NFT (the winning partner).
     * @param auctionId        Syndicate round / auction identifier.
     * @param originalPartner  The original winning partner (for reverse lookup).
     * @param allocatedWeight  Actual bps allocated.
     * @param requestedWeight  Bps bid by the partner.
     * @param clearingPrice    Total auction price paid at triggerClaim.
     * @param vault            Initial BeraChef receiver vault.
     * @param expiryTimestamp  When slot rights expire (matches control NFT expiry).
     * @param isPartialFill    True when allocatedWeight < requestedWeight.
     * @return tokenId         The newly minted token ID.
     */
    function mint(
        address to,
        uint256 auctionId,
        address originalPartner,
        uint96 allocatedWeight,
        uint96 requestedWeight,
        uint128 clearingPrice,
        address vault,
        uint256 expiryTimestamp,
        bool isPartialFill
    ) external virtual onlySyndicate returns (uint256 tokenId) {
        tokenId = _nextTokenId++;

        _tokenRights[tokenId] = SlotRights({
            auctionId: auctionId,
            originalPartner: originalPartner,
            allocatedWeight: allocatedWeight,
            requestedWeight: requestedWeight,
            clearingPrice: clearingPrice,
            vault: vault,
            expiryTimestamp: expiryTimestamp,
            isPartialFill: isPartialFill
        });

        _auctionPartnerToken[auctionId][originalPartner] = tokenId;

        _mint(to, tokenId);

        emit SlotNFTMinted(
            tokenId,
            auctionId,
            originalPartner,
            vault,
            allocatedWeight,
            requestedWeight,
            clearingPrice,
            expiryTimestamp,
            isPartialFill
        );
    }

    /**
     * @notice Update the vault recorded in a slot NFT.
     * @dev Only callable by the syndicate (after it validates the new vault). This
     *      keeps the NFT metadata in sync with the Syndicate's slot storage.
     * @param tokenId  The token whose vault is being updated.
     * @param newVault The new BeraChef receiver vault address.
     */
    function updateVault(uint256 tokenId, address newVault)
        external
        virtual
        onlySyndicate
    {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert InvalidTokenId();
        _tokenRights[tokenId].vault = newVault;
        emit SlotVaultUpdated(tokenId, newVault);
    }

    // ── View functions ────────────────────────────────────────────────────────

    /**
     * @notice Check whether a slot NFT is still valid (exists and not expired).
     * @param tokenId The token ID to check.
     * @return True if the token exists and block.timestamp ≤ expiryTimestamp.
     */
    function isValid(uint256 tokenId) external view virtual returns (bool) {
        if (tokenId == 0 || tokenId >= _nextTokenId) return false;
        if (_ownerOf[tokenId] == address(0)) return false;
        return block.timestamp <= _tokenRights[tokenId].expiryTimestamp;
    }

    /**
     * @notice Return the full slot rights for a token.
     * @param tokenId The token ID.
     * @return The SlotRights struct.
     */
    function getSlotRights(uint256 tokenId)
        external
        view
        virtual
        returns (SlotRights memory)
    {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert InvalidTokenId();
        return _tokenRights[tokenId];
    }

    /**
     * @notice Reverse lookup: return the token ID for a given (auctionId, originalPartner) pair.
     * @param auctionId       The syndicate round ID.
     * @param originalPartner The original winning partner address.
     * @return The token ID, or 0 if no token has been minted for this pair.
     */
    function getTokenId(uint256 auctionId, address originalPartner)
        external
        view
        virtual
        returns (uint256)
    {
        return _auctionPartnerToken[auctionId][originalPartner];
    }

    /**
     * @notice Return the total number of slot NFTs minted.
     */
    function totalSupply() external view virtual returns (uint256) {
        return _nextTokenId - 1;
    }

    // ── Owner functions ───────────────────────────────────────────────────────

    /**
     * @notice Update the metadata base URI.
     * @param newBaseURI The new base URI string.
     */
    function setBaseURI(string calldata newBaseURI)
        external
        virtual
        onlyOwner
    {
        _baseTokenURI = newBaseURI;
    }

    // ── ERC-721 overrides ─────────────────────────────────────────────────────

    /**
     * @notice Return the token URI.
     * @param tokenId The token ID.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (_ownerOf[tokenId] == address(0)) revert InvalidTokenId();
        return _baseTokenURI;
    }
}
