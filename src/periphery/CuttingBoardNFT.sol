// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@solmate/tokens/ERC721.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title CuttingBoardNFT
 * @notice NFT representing temporary control rights over a validator's cutting board
 * @dev Each NFT grants the holder the ability to update the reward allocation (cutting board)
 *      for a specific validator until the expiry timestamp. NFTs are tradeable and can be
 *      used in DeFi protocols as collateral or for yield optimization strategies.
 */
contract CuttingBoardNFT is ERC721, Owned {
    using Strings for uint256;

    /// @notice Represents the control rights associated with an NFT
    struct ControlRights {
        bytes validatorPubkey;
        uint256 expiryTimestamp;
        uint256 auctionId;
        bool active;
    }

    /// @notice Address of the auction contract authorized to mint NFTs
    address public immutable auction;

    /// @notice Address of the control manager authorized to invalidate NFTs
    address public manager;

    /// @notice Mapping from token ID to control rights
    mapping(uint256 => ControlRights) private _tokenRights;

    /// @notice Current token ID counter
    uint256 private _nextTokenId;

    /// @notice Metadata uri
    string private _baseTokenURI;

    /// @notice Emitted when a new control NFT is minted
    /// @param tokenId The ID of the newly minted token
    /// @param owner The address receiving the NFT
    /// @param validatorPubkey The validator pubkey being controlled
    /// @param expiryTimestamp When control rights expire
    /// @param auctionId The auction ID that granted these rights
    event ControlNFTMinted(
        uint256 indexed tokenId,
        address indexed owner,
        bytes validatorPubkey,
        uint256 expiryTimestamp,
        uint256 indexed auctionId
    );

    /// @notice Emitted when an NFT is invalidated
    /// @param tokenId The ID of the invalidated token
    event ControlNFTInvalidated(uint256 indexed tokenId);

    /// @notice Emitted when the manager address is updated
    /// @param oldManager The previous manager address
    /// @param newManager The new manager address
    event ManagerUpdated(
        address indexed oldManager, address indexed newManager
    );

    /// @notice Thrown when caller is not the auction contract
    error NotAuction();

    /// @notice Thrown when caller is not the manager contract
    error NotManager();

    /// @notice Thrown when attempting to interact with an invalid token ID
    error InvalidTokenId();

    /// @notice Thrown when attempting to interact with an inactive NFT
    error TokenInactive();

    /// @notice Thrown when attempting to interact with an expired NFT
    error TokenExpired();

    /// @notice Thrown when providing an invalid manager address
    error InvalidManager();

    modifier onlyAuction() {
        if (msg.sender != auction) revert NotAuction();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /**
     * @notice Initialize the CuttingBoardNFT contract
     * @param _auction Address of the auction contract
     * @param _owner Address of the contract owner
     * @param _manager Address of contract manager for invalidating NFT's
     * @param _baseURI Metadata uri
     */
    constructor(
        address _auction,
        address _owner,
        address _manager,
        string memory _baseURI
    ) ERC721("Cutting Board NFT", "CBNFT") Owned(_owner) {
        if (_auction == address(0)) revert NotAuction();
        if (_manager == address(0)) revert InvalidManager();
        auction = _auction;
        manager = _manager;
        _baseTokenURI = _baseURI;
        _nextTokenId = 1; // Start token IDs at 1
    }

    /**
     * @notice Set the manager contract address
     * @param _manager Address of the ValidatorControlManager contract
     */
    function setManager(address _manager) external virtual onlyOwner {
        if (_manager == address(0)) revert InvalidManager();
        address oldManager = manager;
        manager = _manager;
        emit ManagerUpdated(oldManager, _manager);
    }

    /**
     * @notice Mint a new control NFT
     * @param to Address to receive the NFT
     * @param validatorPubkey Validator pubkey being controlled
     * @param expiryTimestamp When control rights expire
     * @param auctionId The auction ID that granted these rights
     * @return tokenId The ID of the newly minted token
     */
    function mint(
        address to,
        bytes calldata validatorPubkey,
        uint256 expiryTimestamp,
        uint256 auctionId
    ) external virtual onlyAuction returns (uint256 tokenId) {
        tokenId = _nextTokenId++;

        _tokenRights[tokenId] = ControlRights({
            validatorPubkey: validatorPubkey,
            expiryTimestamp: expiryTimestamp,
            auctionId: auctionId,
            active: true
        });

        _mint(to, tokenId);

        emit ControlNFTMinted(
            tokenId, to, validatorPubkey, expiryTimestamp, auctionId
        );
    }

    /**
     * @notice Check if an NFT is still valid (active and not expired)
     * @param tokenId The token ID to check
     * @return True if the NFT is valid and grants control rights
     */
    function isValid(uint256 tokenId) external view virtual returns (bool) {
        if (tokenId == 0 || tokenId >= _nextTokenId) return false;

        ControlRights storage rights = _tokenRights[tokenId];
        return rights.active && block.timestamp <= rights.expiryTimestamp;
    }

    /**
     * @notice Get the validator pubkey associated with a token
     * @param tokenId The token ID
     * @return The validator pubkey
     */
    function getValidator(uint256 tokenId)
        external
        view
        virtual
        returns (bytes memory)
    {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert InvalidTokenId();
        return _tokenRights[tokenId].validatorPubkey;
    }

    /**
     * @notice Get complete control rights information for a token
     * @param tokenId The token ID
     * @return validatorPubkey The validator pubkey
     * @return expiryTimestamp When control expires
     * @return auctionId The auction that granted these rights
     * @return active Whether the NFT is still active
     */
    function getControlRights(uint256 tokenId)
        external
        view
        virtual
        returns (
            bytes memory validatorPubkey,
            uint256 expiryTimestamp,
            uint256 auctionId,
            bool active
        )
    {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert InvalidTokenId();

        ControlRights memory rights = _tokenRights[tokenId];
        return (
            rights.validatorPubkey,
            rights.expiryTimestamp,
            rights.auctionId,
            rights.active
        );
    }

    /**
     * @notice Invalidate an NFT (emergency or on expiry)
     * @param tokenId The token ID to invalidate
     */
    function invalidate(uint256 tokenId) external virtual onlyManager {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert InvalidTokenId();

        _tokenRights[tokenId].active = false;

        emit ControlNFTInvalidated(tokenId);
    }

    /**
     * @notice Get the token URI for metadata
     * @param tokenId The token ID
     * @return The token URI (empty string for now, can be extended)
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

    /**
     * @notice Set metadata uri
     * @param newBaseURI new uri
     * @dev Only owner can call
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    /**
     * @notice Get the total number of NFTs minted
     * @return The total supply of NFTs
     */
    function totalSupply() external view virtual returns (uint256) {
        return _nextTokenId - 1;
    }
}
