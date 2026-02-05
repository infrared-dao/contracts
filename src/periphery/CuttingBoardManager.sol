// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Upgradeable} from "src/utils/Upgradeable.sol";
import {CuttingBoardNFT} from "./CuttingBoardNFT.sol";
import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IBeraChefVaultCheck} from "src/interfaces/IBeraChefVaultCheck.sol";

interface IInfrared {
    function queueNewCuttingBoard(
        bytes calldata _pubkey,
        uint64 _startBlock,
        IBeraChef.Weight[] calldata _weights
    ) external;
}

/**
 * @title CuttingBoardManager
 * @notice Manages validator cutting board updates for NFT holders with 2-step proposal/approval process
 * @dev Acts as a KEEPER_ROLE intermediary between NFT holders and the Infrared contract.
 *      NFT holders propose cutting board updates, keepers approve them.
 *      This contract must be granted KEEPER_ROLE on the Infrared contract.
 * @dev Uses ERC-7201 namespaced storage pattern for upgradeability
 */
contract CuttingBoardManager is Upgradeable {
    /// @custom:storage-location erc7201:infrared.storage.CuttingBoardManager
    struct CuttingBoardManagerStorage {
        /// @notice Reference to the Infrared core contract
        IInfrared infrared;
        /// @notice Reference to the CuttingBoardNFT contract
        CuttingBoardNFT controlNFT;
        /// @notice Reference to BeraChef for vault whitelist validation
        IBeraChefVaultCheck chef;
        /// @notice Duration in seconds for which a proposal remains valid
        uint256 proposalValidityDuration;
        /// @notice Last block number an NFT updated its cutting board
        mapping(uint256 => uint256) lastUpdateBlock;
        /// @notice Active proposals by tokenId
        mapping(uint256 => Proposal) proposals;
    }

    // keccak256(abi.encode(uint256(keccak256("infrared.storage.CuttingBoardManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUTTING_BOARD_MANAGER_STORAGE_LOCATION =
        0x9fd5aaf305ec5d9d4acf2d4a2d8f6d67e82cf32b8c76929329ec5790707b7d00;

    /// @notice Represents a cutting board update proposal
    struct Proposal {
        address proposer;
        uint64 startBlock;
        uint64 proposedAt;
        bool exists;
        IBeraChef.Weight[] weights;
    }

    function _getCuttingBoardManagerStorage()
        private
        pure
        returns (CuttingBoardManagerStorage storage $)
    {
        assembly {
            $.slot := CUTTING_BOARD_MANAGER_STORAGE_LOCATION
        }
    }

    // Public getters for storage variables
    function infrared() public view returns (IInfrared) {
        return _getCuttingBoardManagerStorage().infrared;
    }

    function controlNFT() public view returns (CuttingBoardNFT) {
        return _getCuttingBoardManagerStorage().controlNFT;
    }

    function chef() public view returns (IBeraChefVaultCheck) {
        return _getCuttingBoardManagerStorage().chef;
    }

    function proposalValidityDuration() public view returns (uint256) {
        return _getCuttingBoardManagerStorage().proposalValidityDuration;
    }

    // Reserve storage space for upgrades
    uint256[20] private __gap;

    /// @notice Emitted when a cutting board proposal is created
    /// @param tokenId The NFT token ID used for authorization
    /// @param proposer The address that created the proposal
    /// @param validatorPubkey The validator whose cutting board will be updated
    /// @param weights The proposed cutting board weights
    event CuttingBoardProposed(
        uint256 indexed tokenId,
        address indexed proposer,
        bytes validatorPubkey,
        IBeraChef.Weight[] weights
    );

    /// @notice Emitted when a cutting board proposal is approved
    /// @param tokenId The NFT token ID used for authorization
    /// @param approver The keeper who approved the proposal
    /// @param validatorPubkey The validator whose cutting board was updated
    /// @param startBlock The block when the new allocation activates
    /// @param weights The new cutting board weights
    event CuttingBoardApproved(
        uint256 indexed tokenId,
        address indexed approver,
        bytes validatorPubkey,
        uint64 startBlock,
        IBeraChef.Weight[] weights
    );

    /// @notice Emitted when a cutting board proposal is cancelled
    /// @param tokenId The NFT token ID
    /// @param canceller The address that cancelled the proposal
    event ProposalCancelled(uint256 indexed tokenId, address indexed canceller);

    /// @notice Emitted when the proposal validity duration is changed
    /// @param oldDuration The previous duration in seconds
    /// @param newDuration The new duration in seconds
    event ProposalValidityDurationUpdated(
        uint256 oldDuration, uint256 newDuration
    );

    /// @notice Thrown when caller is not the NFT owner
    error NotNFTOwner();

    /// @notice Thrown when NFT has expired
    error NFTExpired();

    /// @notice Thrown when NFT is inactive
    error NFTInactive();

    /// @notice Thrown when trying to update too soon after last update
    error UpdateTooSoon();

    /// @notice Thrown when weights don't sum to exactly 10000 (100%)
    error InvalidWeightSum();

    /// @notice Thrown when a vault in weights is not whitelisted
    error VaultNotWhitelisted();

    /// @notice Thrown when weights array is empty
    error EmptyWeights();

    /// @notice Thrown when invalid address provided in initializer
    error InvalidAddress();

    /// @notice Thrown when ownership changes and old proposer is no longer valid
    error InvalidProposer();

    /// @notice Thrown when no proposal exists for the given tokenId
    error NoProposalExists();

    /// @notice Thrown when a proposal already exists for the tokenId
    error ProposalAlreadyExists();

    /// @notice Thrown when a proposal has expired
    error ProposalExpired();

    /// @notice Thrown when caller is not the proposer
    error NotProposer();

    /// @notice Thrown when cutting board allocation has too many vaults
    error TooManyWeights();

    /// @notice Thrown when cutting board vault has either 0 or a percentage greater than max defined by berachain
    error InvalidWeight();

    /// @notice Thrown when outstanding cutting board queue for validator prevents new update
    error AlreadyQueue();

    /// @notice Thrown when duplicate vaults provided in cutting board
    error DuplicateReceiver();

    /// @notice Thrown when proposalValidityDuration is zero
    error InvalidDuration();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the CuttingBoardManager
     * @param _infrared Address of the Infrared contract
     * @param _controlNFT Address of the CuttingBoardNFT contract
     * @param _chef Address of the BeraChef contract
     * @param _governance Address of governance (receives GOVERNANCE_ROLE and DEFAULT_ADMIN_ROLE)
     * @param _keeper Address of the keeper (receives KEEPER_ROLE)
     * @param _proposalValidityDuration Duration in seconds for which proposals are valid
     */
    function initialize(
        address _infrared,
        address _controlNFT,
        address _chef,
        address _governance,
        address _keeper,
        uint256 _proposalValidityDuration
    ) external initializer {
        if (_infrared == address(0)) revert InvalidAddress();
        if (_controlNFT == address(0)) revert InvalidAddress();
        if (_chef == address(0)) revert InvalidAddress();
        if (_governance == address(0)) revert InvalidAddress();
        if (_proposalValidityDuration == 0) revert InvalidDuration();

        __Upgradeable_init();

        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();
        $.infrared = IInfrared(_infrared);
        $.controlNFT = CuttingBoardNFT(_controlNFT);
        $.chef = IBeraChefVaultCheck(_chef);
        $.proposalValidityDuration = _proposalValidityDuration;

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(GOVERNANCE_ROLE, _governance);
        if (_keeper != address(0)) {
            _grantRole(KEEPER_ROLE, _keeper);
        }
    }

    /**
     * @notice Propose a cutting board update for a validator controlled by NFT
     * @param tokenId NFT token ID proving control rights
     * @param weights New cutting board distribution
     */
    function proposeCuttingBoard(
        uint256 tokenId,
        IBeraChef.Weight[] calldata weights
    ) external virtual whenNotPaused {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();

        // cache sender
        address sender = msg.sender;
        // adjust for special case of initial proposal
        // sender is effectively the owner in this case
        if (sender == address($.controlNFT.auction())) {
            sender = $.controlNFT.ownerOf(tokenId);
        }

        // Verify NFT ownership
        if ($.controlNFT.ownerOf(tokenId) != sender) revert NotNFTOwner();

        // Verify NFT is still valid (active and not expired)
        if (!$.controlNFT.isValid(tokenId)) {
            // Check specific reason for better error message
            (, uint256 expiry,, bool active) =
                $.controlNFT.getControlRights(tokenId);
            if (!active) revert NFTInactive();
            if (block.timestamp > expiry) revert NFTExpired();
        }

        // Check if a proposal already exists
        if ($.proposals[tokenId].exists) {
            // If proposal is expired, auto-clear it
            if (
                block.timestamp
                    > $.proposals[tokenId].proposedAt + $.proposalValidityDuration
            ) {
                delete $.proposals[tokenId];
                emit ProposalCancelled(tokenId, address(0));
            } else {
                revert ProposalAlreadyExists();
            }
        }

        // Enforce minimum delay between updates (skip check for first update)
        if (
            $.lastUpdateBlock[tokenId] != 0
                && block.number
                    < $.lastUpdateBlock[tokenId] + $.chef.rewardAllocationBlockDelay()
        ) {
            revert UpdateTooSoon();
        }

        // Get validator pubkey from NFT
        bytes memory pubkey = $.controlNFT.getValidator(tokenId);

        // Validate weights
        _validateWeights(weights);

        // Create proposal
        // note startBlock is defined on acceptance
        Proposal storage proposal = $.proposals[tokenId];
        proposal.proposer = sender;
        proposal.proposedAt = uint64(block.timestamp);
        proposal.exists = true;

        // Store weights
        for (uint256 i = 0; i < weights.length; i++) {
            proposal.weights.push(weights[i]);
        }

        emit CuttingBoardProposed(tokenId, sender, pubkey, weights);
    }

    /**
     * @notice Approve a cutting board proposal (keeper only)
     * @param tokenId NFT token ID of the proposal to approve
     */
    function approveCuttingBoard(uint256 tokenId)
        external
        virtual
        whenNotPaused
        onlyKeeper
    {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();

        // Check proposal exists
        if (!$.proposals[tokenId].exists) revert NoProposalExists();

        Proposal storage proposal = $.proposals[tokenId];

        // check proposer is current owner
        if (proposal.proposer != $.controlNFT.ownerOf(tokenId)) {
            revert InvalidProposer();
        }

        // Check proposal hasn't expired
        if (block.timestamp > proposal.proposedAt + $.proposalValidityDuration)
        {
            revert ProposalExpired();
        }

        // Verify NFT is still valid
        uint64 beraBlockDelay = $.chef.rewardAllocationBlockDelay();
        (, uint256 expiry,, bool active) =
            $.controlNFT.getControlRights(tokenId);
        if (!active) revert NFTInactive();
        // check bera delay updates before expiry
        if (block.timestamp + (2 * uint256(beraBlockDelay)) > expiry) {
            revert NFTExpired();
        }

        // Get validator pubkey from NFT
        bytes memory pubkey = $.controlNFT.getValidator(tokenId);

        // check there is no current queue
        {
            IBeraChef.RewardAllocation memory ra =
                $.chef.getQueuedRewardAllocation(pubkey);
            if (ra.startBlock > 0) revert AlreadyQueue();
        }

        // Update last update block
        $.lastUpdateBlock[tokenId] = block.number;

        // define startBlock now as min time delay
        uint64 startBlock = uint64(block.number) + beraBlockDelay + 1;

        // Queue the cutting board to Infrared
        $.infrared.queueNewCuttingBoard(pubkey, startBlock, proposal.weights);

        emit CuttingBoardApproved(
            tokenId, msg.sender, pubkey, startBlock, proposal.weights
        );

        // Clean up proposal
        delete $.proposals[tokenId];
    }

    /**
     * @notice Cancel a pending proposal
     * @param tokenId NFT token ID of the proposal to cancel
     */
    function cancelProposal(uint256 tokenId) external virtual {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();

        if (!$.proposals[tokenId].exists) revert NoProposalExists();

        // Only keeper, NFT owner, or governance can cancel
        if (
            !hasRole(KEEPER_ROLE, msg.sender)
                && msg.sender != $.controlNFT.ownerOf(tokenId)
                && !hasRole(GOVERNANCE_ROLE, msg.sender)
        ) {
            revert NotProposer();
        }

        delete $.proposals[tokenId];
        emit ProposalCancelled(tokenId, msg.sender);
    }

    /**
     * @notice Get the last update block for an NFT
     * @param tokenId The NFT token ID
     * @return The block number of the last update
     */
    function getLastUpdateBlock(uint256 tokenId)
        external
        view
        virtual
        returns (uint256)
    {
        return _getCuttingBoardManagerStorage().lastUpdateBlock[tokenId];
    }

    /**
     * @notice Get all token IDs that have valid pending proposals awaiting keeper approval
     * @dev Iterates through all minted NFTs to find those with non-expired proposals.
     *      Uses a two-pass approach: first counts valid proposals, then fills the array.
     *      Useful for keepers to discover which proposals need review.
     * @return tokenIds Array of token IDs with pending proposals (may be empty)
     */
    function getPendingProposalTokenIds()
        external
        view
        virtual
        returns (uint256[] memory tokenIds)
    {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();
        uint256 numNFTs = $.controlNFT.totalSupply();

        // First pass: count pending proposals
        uint256 count = 0;
        for (uint256 i = 1; i <= numNFTs; i++) {
            if (_isPendingProposal($, i)) {
                count++;
            }
        }

        // Allocate array with exact size needed
        tokenIds = new uint256[](count);

        // Second pass: fill array
        uint256 index = 0;
        for (uint256 i = 1; i <= numNFTs; i++) {
            if (_isPendingProposal($, i)) {
                tokenIds[index++] = i;
            }
        }
    }

    /**
     * @notice Check if a token ID has a valid pending proposal
     * @param $ Storage reference
     * @param tokenId The token ID to check
     * @return True if there is a valid pending proposal for this token
     */
    function _isPendingProposal(
        CuttingBoardManagerStorage storage $,
        uint256 tokenId
    ) internal view virtual returns (bool) {
        Proposal storage proposal = $.proposals[tokenId];

        // Must have an existing proposal
        if (!proposal.exists) return false;

        // Proposal must not be expired
        if (block.timestamp > proposal.proposedAt + $.proposalValidityDuration)
        {
            return false;
        }

        // NFT must still be valid
        if (!$.controlNFT.isValid(tokenId)) return false;

        return true;
    }

    /// @dev Duplicate vault check in proposed cutting board
    function _checkForDuplicateReceivers(IBeraChef.Weight[] calldata weights)
        internal
        pure
    {
        address[] memory receivers = new address[](weights.length);

        for (uint256 i; i < weights.length; ++i) {
            address r = weights[i].receiver;

            for (uint256 j; j < i; ++j) {
                if (receivers[j] == r) revert DuplicateReceiver();
            }

            receivers[i] = r;
        }
    }

    /**
     * @notice Get proposal details for a token ID
     * @param tokenId The NFT token ID
     * @return proposer Address of the proposer
     * @return startBlock Block when allocation activates
     * @return proposedAt Timestamp when proposed
     * @return exists Whether the proposal exists
     * @return weights The proposed weights
     */
    function getProposal(uint256 tokenId)
        external
        view
        virtual
        returns (
            address proposer,
            uint64 startBlock,
            uint64 proposedAt,
            bool exists,
            IBeraChef.Weight[] memory weights
        )
    {
        Proposal memory proposal =
            _getCuttingBoardManagerStorage().proposals[tokenId];
        return (
            proposal.proposer,
            proposal.startBlock,
            proposal.proposedAt,
            proposal.exists,
            proposal.weights
        );
    }

    /**
     * @notice Check if a proposal has expired
     * @param tokenId The NFT token ID
     * @return True if the proposal exists and has expired
     */
    function isProposalExpired(uint256 tokenId)
        external
        view
        virtual
        returns (bool)
    {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();
        if (!$.proposals[tokenId].exists) return false;
        return block.timestamp
            > $.proposals[tokenId].proposedAt + $.proposalValidityDuration;
    }

    /**
     * @notice Check if an NFT can propose now
     * @param tokenId The NFT token ID
     * @return True if the NFT can propose a cutting board update
     */
    function canProposeNow(uint256 tokenId)
        external
        view
        virtual
        returns (bool)
    {
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();
        if (paused()) return false;
        if (!$.controlNFT.isValid(tokenId)) return false;
        // Check if an ACTIVE (non-expired) proposal exists
        if ($.proposals[tokenId].exists) {
            // Expired proposals don't block new proposals
            if (
                block.timestamp
                    <= $.proposals[tokenId].proposedAt + $.proposalValidityDuration
            ) {
                return false; // Active proposal exists
            }
        }
        // First update is always allowed
        if ($.lastUpdateBlock[tokenId] == 0) return true;
        return block.number
            >= $.lastUpdateBlock[tokenId] + $.chef.rewardAllocationBlockDelay();
    }

    /**
     * @notice Update proposal validity duration
     * @param _proposalValidityDuration New duration in seconds
     * @dev proposal duration should be less than allocation duration, though not enforced
     */
    function setProposalValidityDuration(uint256 _proposalValidityDuration)
        external
        virtual
        onlyGovernor
    {
        if (_proposalValidityDuration == 0) revert InvalidDuration();
        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();
        uint256 oldDuration = $.proposalValidityDuration;
        $.proposalValidityDuration = _proposalValidityDuration;
        emit ProposalValidityDurationUpdated(
            oldDuration, _proposalValidityDuration
        );
    }

    /**
     * @notice Emergency: Invalidate an NFT's control rights
     * @param tokenId The NFT token ID to invalidate
     */
    function revokeControl(uint256 tokenId) external virtual onlyGovernor {
        _getCuttingBoardManagerStorage().controlNFT.invalidate(tokenId);
    }

    /**
     * @notice Validate cutting board weights
     * @param weights The weights to validate
     */
    function _validateWeights(IBeraChef.Weight[] calldata weights)
        internal
        virtual
    {
        if (weights.length == 0) revert EmptyWeights();

        _checkForDuplicateReceivers(weights);

        CuttingBoardManagerStorage storage $ = _getCuttingBoardManagerStorage();

        if (weights.length > $.chef.maxNumWeightsPerRewardAllocation()) {
            revert TooManyWeights();
        }

        uint256 totalWeight = 0;

        for (uint256 i = 0; i < weights.length; i++) {
            IBeraChef.Weight calldata weight = weights[i];
            if (
                weight.percentageNumerator == 0
                    || weight.percentageNumerator > $.chef.maxWeightPerVault()
            ) {
                revert InvalidWeight();
            }

            // Verify vault is whitelisted in BeraChef
            if (!$.chef.isWhitelistedVault(weight.receiver)) {
                revert VaultNotWhitelisted();
            }

            totalWeight += weight.percentageNumerator;
        }

        // Total must equal exactly 10000 (100%)
        if (totalWeight != 10000) revert InvalidWeightSum();
    }
}
