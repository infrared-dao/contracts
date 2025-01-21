// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {IERC20Mintable} from "src/interfaces/IERC20Mintable.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";

/// @dev For testing InfraredVault.sol
contract MockInfrared {
    using EnumerableSet for EnumerableSet.AddressSet;

    IInfraredBGT public immutable ibgt;
    IERC20Mintable public immutable ir;
    IBerachainRewardsVaultFactory public immutable rewardsFactory;

    EnumerableSet.AddressSet internal _infraredValidators;

    mapping(bytes pub => address validator) internal _infraredPubkeyToValidator;
    mapping(address validator => bytes pub) internal _infraredValidatorToPubkey;

    event VaultHarvested(address vault);

    mapping(address => IInfraredVault) public vaultRegistry;

    constructor(address _ibgt, address _ir, address _rewardsFactory) {
        ibgt = IInfraredBGT(_ibgt);
        ir = IERC20Mintable(_ir);
        rewardsFactory = IBerachainRewardsVaultFactory(_rewardsFactory);
    }

    function harvestVault(address vault) external {
        emit VaultHarvested(vault);
    }

    function addValidator(address validator) external {
        _infraredValidators.add(validator);
    }

    // TODO: replace other function checking other tests not affected
    function addValidator(address validator, bytes memory pubkey) external {
        _infraredValidators.add(validator);
        _infraredPubkeyToValidator[pubkey] = validator;
        _infraredValidatorToPubkey[validator] = pubkey;
    }

    // TODO: replace with fn signature more in line with Infrared.sol
    function removeValidator(address validator) external {
        _infraredValidators.remove(validator);
        bytes memory pubkey = _infraredValidatorToPubkey[validator];
        delete _infraredValidatorToPubkey[validator];
        delete _infraredPubkeyToValidator[pubkey];
    }

    function isInfraredValidator(bytes calldata pubkey)
        external
        view
        returns (bool)
    {
        return (_infraredPubkeyToValidator[pubkey] != address(0));
    }

    function numInfraredValidators() external view returns (uint256) {
        return _infraredValidators.length();
    }

    function registerVault(address stakingToken, address[] memory) external {
        vaultRegistry[stakingToken] = IInfraredVault(address(1));
    }
}
