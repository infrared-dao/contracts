// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Owned} from "@solmate/auth/Owned.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "@solmate/utils/MerkleProofLib.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";

/**
 * @title MerkleDistributor
 * @notice Distributes ERC20 tokens to eligible addresses using Merkle proofs
 * @dev Implements a custom claiming window with admin pause functionality
 */
contract MerkleDistributor is Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    // ============ State Variables ============

    /// @notice Internal variable to track pause status
    bool private _paused;

    /// @notice The ERC20 token being distributed
    ERC20 public immutable token;

    /// @notice The Merkle root of the distribution tree
    bytes32 public immutable merkleRoot;

    /// @notice Timestamp when the claiming period ends (90 days from deployment)
    uint256 public immutable claimDeadline;

    /// @notice Tracks claimed amounts for each address
    mapping(address => uint256) public claimed;

    /// @notice Total amount of tokens claimed so far
    uint256 public totalClaimed;

    /// @notice Total amount of tokens allocated for distribution
    uint256 public totalAllocated;

    // ============ Events ============

    event Claimed(address indexed account, uint256 amount);
    event EmergencyWithdraw(
        address indexed token, address indexed to, uint256 amount
    );
    event Paused(address account);
    event Unpaused(address account);

    // ============ Errors ============

    error InvalidProof();
    error ClaimingPeriodEnded();
    error AlreadyClaimed();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidMerkleRoot();
    error DeadlineNotReached();
    error EnforcedPause();

    // ============ Constructor ============

    /**
     * @notice Initializes the distributor with token and merkle root
     * @param _token The ERC20 token to distribute
     * @param _merkleRoot The merkle root of the distribution tree
     * @param _owner The owner address for admin functions
     * @param window Time window to allow claims for in seconds
     * @param _totalAllocated Total token allocation for merkle drop
     */
    constructor(
        address _token,
        bytes32 _merkleRoot,
        address _owner,
        uint256 window,
        uint256 _totalAllocated
    ) Owned(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        if (_merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        if (_owner == address(0)) revert ZeroAddress();
        if (_totalAllocated == 0) revert ZeroAmount();
        if (window == 0) revert ZeroAmount();

        token = ERC20(_token);
        merkleRoot = _merkleRoot;
        claimDeadline = block.timestamp + window;
        totalAllocated = _totalAllocated;
    }

    // ============ Modifiers ===============

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        if (paused()) {
            revert EnforcedPause();
        }
        _;
    }

    // ============ External Functions ============

    /**
     * @notice Claims tokens for the caller
     * @param amount The amount of tokens to claim
     * @param merkleProof The merkle proof for the claim
     */
    function claim(uint256 amount, bytes32[] calldata merkleProof)
        external
        nonReentrant
        whenNotPaused
    {
        _claim(msg.sender, amount, merkleProof);
    }

    /**
     * @notice Claims tokens on behalf of an account
     * @param account The account to claim for
     * @param amount The amount of tokens to claim
     * @param merkleProof The merkle proof for the claim
     */
    function claimFor(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        _claim(account, amount, merkleProof);
    }

    /**
     * @notice Checks if an address can claim tokens
     * @param account The address to check
     * @param amount The amount to check
     * @param merkleProof The merkle proof
     * @return _canClaim Whether the address can claim
     * @return claimableAmount The amount that can be claimed
     */
    function canClaim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool _canClaim, uint256 claimableAmount) {
        if (paused()) {
            return (false, 0);
        }
        if (block.timestamp > claimDeadline) {
            return (false, 0);
        }

        if (claimed[account] >= amount) {
            return (false, 0);
        }

        bytes32 leaf = keccak256(abi.encode(account, amount));
        bool validProof = MerkleProofLib.verify(merkleProof, merkleRoot, leaf);

        if (!validProof) {
            return (false, 0);
        }

        claimableAmount = amount - claimed[account];
        _canClaim = true;
    }

    // ============ Admin Functions ============

    /**
     * @notice Pauses claiming functionality
     * @dev Only callable by owner
     */
    function pause() external whenNotPaused onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses claiming functionality
     * @dev Only callable by owner
     */
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Recovers ERC20 tokens sent to this contract
     * @dev Can only recover non-distribution tokens before deadline, or any token after deadline
     * @param tokenAddress The token to recover
     * @param to The address to send recovered tokens to
     */
    function recoverERC20(address tokenAddress, address to)
        external
        onlyOwner
    {
        if (to == address(0)) revert ZeroAddress();

        ERC20 recoveryToken = ERC20(tokenAddress);
        uint256 balance = recoveryToken.balanceOf(address(this));

        if (balance == 0) revert ZeroAmount();

        // Prevent recovering distribution tokens before deadline unless it's excess
        if (tokenAddress == address(token) && block.timestamp <= claimDeadline)
        {
            // Only allow recovering excess tokens (tokens beyond what's allocated)
            uint256 requiredBalance = totalAllocated - totalClaimed;
            if (balance <= requiredBalance) {
                revert DeadlineNotReached();
            }
            // Recover only the excess
            balance = balance - requiredBalance;
        }

        recoveryToken.safeTransfer(to, balance);
        emit EmergencyWithdraw(tokenAddress, to, balance);
    }

    /**
     * @notice Withdraws unclaimed tokens after the deadline
     * @dev Only callable by owner after claim deadline
     * @param to The address to send unclaimed tokens to
     */
    function withdrawUnclaimed(address to) external onlyOwner {
        if (block.timestamp <= claimDeadline) revert DeadlineNotReached();
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) revert ZeroAmount();

        token.safeTransfer(to, amount);
        emit EmergencyWithdraw(address(token), to, amount);
    }

    /**
     * @notice Sets the total allocated amount for tracking
     * @dev Should be called after funding the contract
     * @param _totalAllocated The total amount allocated for distribution
     */
    function setTotalAllocated(uint256 _totalAllocated) external onlyOwner {
        totalAllocated = _totalAllocated;
        if (totalAllocated < totalClaimed) revert();
        uint256 balance = token.balanceOf(address(this));
        if (balance < totalAllocated - totalClaimed) revert();
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal claim logic
     * @param account The account claiming tokens
     * @param amount The total amount allocated to the account
     * @param merkleProof The merkle proof for verification
     */
    function _claim(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) internal {
        if (block.timestamp > claimDeadline) revert ClaimingPeriodEnded();
        if (amount == 0) revert ZeroAmount();
        if (claimed[account] >= amount) revert AlreadyClaimed();

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encode(account, amount));
        if (!MerkleProofLib.verify(merkleProof, merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // Calculate claimable amount
        uint256 claimableAmount = amount - claimed[account];

        // Update state before transfer
        claimed[account] = amount;
        totalClaimed += claimableAmount;

        // Transfer tokens
        token.safeTransfer(account, claimableAmount);

        emit Claimed(account, claimableAmount);
    }

    // ============ View Functions ============

    /**
     * @notice Returns the amount already claimed by an account
     * @param account The account to check
     * @return The amount already claimed
     */
    function getClaimedAmount(address account)
        external
        view
        returns (uint256)
    {
        return claimed[account];
    }

    /**
     * @notice Returns the remaining time until claim deadline
     * @return The remaining time in seconds (0 if deadline passed)
     */
    function getRemainingTime() external view returns (uint256) {
        if (block.timestamp >= claimDeadline) {
            return 0;
        }
        return claimDeadline - block.timestamp;
    }

    /**
     * @notice Checks if the claiming period is still active
     * @return Whether claiming is still possible
     */
    function isClaimingActive() external view returns (bool) {
        return block.timestamp <= claimDeadline && !paused();
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }
}
