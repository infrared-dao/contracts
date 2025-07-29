// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

import {Errors} from "src/utils/Errors.sol";
import {Infrared} from "src/core/Infrared.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";

/**
 * @title Infrared WrappedRewardToken
 * @notice A wrapper vault built on ERC4626 to facilitate reward tokens that have low decimals eg 6 like USDC
 */
contract WrappedRewardToken is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable asset;

    /// @notice The scaling factor to adjust for decimal differences (10^18 / 10^asset.decimals()).
    uint256 public immutable scaling;

    constructor(ERC20 _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol, 18)
    {
        asset = _asset;
        uint8 assetDecimals = _asset.decimals();
        require(assetDecimals <= 18, "Asset decimals must be <= 18");
        scaling = 10 ** (18 - assetDecimals); // e.g., 10^12 for 6-decimal asset
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        public
        virtual
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting to prevent ERC777 reentrancy.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        virtual
        returns (uint256 assets)
    {
        assets = previewMint(shares); // Rounds up to ensure sufficient assets.

        // Need to transfer before minting to prevent ERC777 reentrancy.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets); // Rounds up to ensure sufficient shares.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        returns (uint256 assets)
    {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return assets * scaling;
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return shares / scaling;
    }

    function previewDeposit(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return (shares + scaling - 1) / scaling; // Ceiling to ensure enough assets.
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return assets * scaling; // Exact shares required.
    }

    function previewRedeem(uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

    function afterDeposit(uint256 assets, uint256 shares) internal virtual {}
}
