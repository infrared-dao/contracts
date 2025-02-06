// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {Errors} from "src/utils/Errors.sol";
import {Infrared} from "src/core/Infrared.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";

/**
 * @title Infrared WrappedVault
 * @notice A wrapper vault built on ERC4626 to facilitate staking operations and reward distribution
 *         through the Infrared protocol. Each staking token has a corresponding wrapped vault.
 * @dev deploy 1 wrapped vault per staking token
 */
contract WrappedVault is ERC4626 {
    using SafeTransferLib for ERC20;

    /// @notice Address of the reward distributor, typically a multisig.
    address public immutable rewardDistributor;

    /// @notice Instance of the associated InfraredVault for staking.
    InfraredVault public immutable iVault;

    /// @dev Inflation attack prevention
    uint256 internal constant deadShares = 1e3;

    /// @notice Event emitted when reward tokens claimed
    event RewardClaimed(address indexed token, uint256 amount);

    /**
     * @notice Initializes a new WrappedVault contract for a specific staking token.
     * @param _rewardDistributor Address of the reward distributor (e.g., multisig).
     * @param _infrared Address of the Infrared protocol.
     * @param _stakingToken Address of the ERC20 staking token.
     * @param _name Name of the wrapped vault token (ERC4626).
     * @param _symbol Symbol of the wrapped vault token (ERC4626).
     */
    constructor(
        address _rewardDistributor,
        address _infrared,
        address _stakingToken,
        string memory _name,
        string memory _symbol
    ) ERC4626(ERC20(_stakingToken), _name, _symbol) {
        if (
            _rewardDistributor == address(0) || _infrared == address(0)
                || _stakingToken == address(0)
        ) revert Errors.ZeroAddress();
        Infrared infrared = Infrared(payable(_infrared));
        // register vault if necessary
        address _vaultAddress = address(infrared.vaultRegistry(_stakingToken));
        if (_vaultAddress == address(0)) {
            iVault =
                InfraredVault(address(infrared.registerVault(_stakingToken)));
        } else {
            iVault = InfraredVault(_vaultAddress);
        }
        rewardDistributor = _rewardDistributor;

        // Mint dead shares to prevent inflation attacks
        _mint(address(0), deadShares);
    }

    // ERC4626 overrides

    /**
     * @notice Returns the total assets managed by the wrapped vault.
     * @dev Overrides the ERC4626 `totalAssets` function to integrate with the InfraredVault balance.
     * @return The total amount of staking tokens held by the InfraredVault.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return iVault.balanceOf(address(this)) + deadShares;
    }

    /**
     * @notice Hook called before withdrawal operations.
     * @dev This function ensures that the requested amount of staking tokens is withdrawn
     *      from the InfraredVault before being transferred to the user.
     * @param assets The amount of assets to withdraw.
     */
    function beforeWithdraw(uint256 assets, uint256)
        internal
        virtual
        override
    {
        iVault.withdraw(assets);
    }

    /**
     * @notice Hook called after deposit operations.
     * @dev This function stakes the deposited tokens into the InfraredVault.
     * @param assets The amount of assets being deposited.
     */
    function afterDeposit(uint256 assets, uint256) internal virtual override {
        asset.safeApprove(address(iVault), assets);
        iVault.stake(assets);
    }

    /**
     * @notice Claims rewards from the InfraredVault and transfers them to the reward distributor.
     * @dev Only rewards other than the staking token itself are transferred.
     */
    function claimRewards() external {
        // Claim rewards from the InfraredVault
        iVault.getReward();
        // Retrieve all reward tokens
        address[] memory _tokens = iVault.getAllRewardTokens();
        uint256 len = _tokens.length;
        // Loop through reward tokens and transfer them to the reward distributor
        for (uint256 i; i < len; ++i) {
            ERC20 _token = ERC20(_tokens[i]);
            uint256 bal = _token.balanceOf(address(this));
            if (bal == 0) continue;
            (bool success, bytes memory data) = address(_token).call(
                abi.encodeWithSelector(
                    ERC20.transfer.selector, rewardDistributor, bal
                )
            );
            if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                emit RewardClaimed(address(_token), bal);
            } else {
                continue;
            }
        }
    }
}
