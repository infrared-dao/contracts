// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ICuttingBoardSlotNFT
 * @notice Interface for the CuttingBoardSlotNFT ERC-721 contract that represents
 *         per-winner slot ownership in a CuttingBoardSyndicate round.
 */
interface ICuttingBoardSlotNFT {
    /// @notice Represents the slot rights associated with an NFT
    struct SlotRights {
        uint256 auctionId;
        address originalPartner; // original auction winner
        uint96 allocatedWeight; // actual bps allocated at triggerClaim
        uint96 requestedWeight; // bps bid by the partner
        uint128 clearingPrice; // total auction price paid at triggerClaim
        address vault; // current BeraChef receiver vault (updatable via Syndicate)
        uint256 expiryTimestamp; // matches control NFT expiry
        bool isPartialFill; // true when allocatedWeight < requestedWeight
    }

    // ── Events ────────────────────────────────────────────────────────────────

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

    event SlotVaultUpdated(uint256 indexed tokenId, address indexed newVault);

    // ── Errors ────────────────────────────────────────────────────────────────

    error NotSyndicate();
    error InvalidTokenId();

    // ── State variables ───────────────────────────────────────────────────────

    /// @notice Address of the CuttingBoardSyndicate — sole authorised minter/updater
    function syndicate() external view returns (address);

    // ── Syndicate-only write functions ────────────────────────────────────────

    /**
     * @notice Mint a new slot NFT to a winner.
     * @param to               Recipient of the NFT.
     * @param auctionId        Syndicate round / auction identifier.
     * @param originalPartner  The original winning partner.
     * @param allocatedWeight  Actual bps allocated.
     * @param requestedWeight  Bps bid by the partner.
     * @param clearingPrice    Total auction price paid at triggerClaim.
     * @param vault            Initial BeraChef receiver vault.
     * @param expiryTimestamp  When slot rights expire.
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
    ) external returns (uint256 tokenId);

    /**
     * @notice Update the vault recorded in a slot NFT.
     * @param tokenId  The token whose vault is being updated.
     * @param newVault The new BeraChef receiver vault address.
     */
    function updateVault(uint256 tokenId, address newVault) external;

    // ── View functions ────────────────────────────────────────────────────────

    /**
     * @notice Check whether a slot NFT is still valid (exists and not expired).
     * @param tokenId The token ID to check.
     * @return True if the token exists and block.timestamp ≤ expiryTimestamp.
     */
    function isValid(uint256 tokenId) external view returns (bool);

    /**
     * @notice Return the full slot rights for a token.
     * @param tokenId The token ID.
     */
    function getSlotRights(uint256 tokenId)
        external
        view
        returns (SlotRights memory);

    /**
     * @notice Reverse lookup: return the token ID for a given (auctionId, originalPartner) pair.
     * @return The token ID, or 0 if no token has been minted for this pair.
     */
    function getTokenId(uint256 auctionId, address originalPartner)
        external
        view
        returns (uint256);

    /**
     * @notice Return the total number of slot NFTs minted.
     */
    function totalSupply() external view returns (uint256);

    // ── Owner functions ───────────────────────────────────────────────────────

    /**
     * @notice Update the metadata base URI.
     */
    function setBaseURI(string calldata newBaseURI) external;

    // ── ERC-721 ───────────────────────────────────────────────────────────────

    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
