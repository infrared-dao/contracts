// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";

/**
 * @notice Minimal BeraChef interface for vault whitelist and allocation checking
 * @dev Used by CuttingBoardManager, CuttingBoardSyndicate and CuttingBoardDutchAuction
 */
interface IBeraChefVaultCheck {
    function isWhitelistedVault(address vault) external view returns (bool);
    function rewardAllocationBlockDelay() external view returns (uint64);
    function maxNumWeightsPerRewardAllocation() external view returns (uint8);
    function maxWeightPerVault() external view returns (uint96);
    function getQueuedRewardAllocation(bytes calldata valPubkey)
        external
        view
        returns (IBeraChef.RewardAllocation memory);
    function getActiveRewardAllocation(bytes calldata valPubkey)
        external
        view
        returns (IBeraChef.RewardAllocation memory);
    function getSetActiveRewardAllocation(bytes calldata valPubkey)
        external
        view
        returns (IBeraChef.RewardAllocation memory);
    function rewardAllocationInactivityBlockSpan()
        external
        view
        returns (uint256);
}
