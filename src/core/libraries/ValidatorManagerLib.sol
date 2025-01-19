// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {Errors} from "src/utils/Errors.sol";
import {ValidatorTypes} from "./ValidatorTypes.sol";
import {IInfraredDistributor} from "src/interfaces/IInfraredDistributor.sol";
import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library ValidatorManagerLib {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct ValidatorStorage {
        EnumerableSet.Bytes32Set validatorIds; // Set of validator IDs
        mapping(bytes32 => bytes) validatorPubkeys; // Maps validator ID to public key
    }

    // Public function to check if a validator exists, accessible to any external contract or account
    function isValidator(ValidatorStorage storage $, bytes memory pubkey)
        external
        view
        returns (bool)
    {
        return $.validatorIds.contains(keccak256(pubkey));
    }

    /// @notice Gets the validator ID for associated CL pubkey
    /// @param pubkey The CL pubkey of validator
    function _getValidatorId(bytes memory pubkey)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(pubkey);
    }

    function addValidators(
        ValidatorStorage storage $,
        address distributor,
        ValidatorTypes.Validator[] memory _validators
    ) external {
        for (uint256 i = 0; i < _validators.length; i++) {
            ValidatorTypes.Validator memory v = _validators[i];
            if (v.addr == address(0)) revert Errors.ZeroAddress();
            bytes32 id = _getValidatorId(v.pubkey);
            if ($.validatorIds.contains(id)) {
                revert Errors.InvalidValidator();
            }
            $.validatorIds.add(id);
            $.validatorPubkeys[id] = v.pubkey;

            // add pubkey to those elligible for iBGT rewards
            IInfraredDistributor(distributor).add(v.pubkey, v.addr);
        }
    }

    function removeValidators(
        ValidatorStorage storage $,
        address distributor,
        bytes[] memory _pubkeys
    ) external {
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            bytes memory pubkey = _pubkeys[i];
            bytes32 id = keccak256(pubkey);
            if (!$.validatorIds.contains(id)) {
                revert Errors.InvalidValidator();
            }
            $.validatorIds.remove(id);
            delete $.validatorPubkeys[id];

            // remove pubkey from those elligible for iBGT rewards
            IInfraredDistributor(distributor).remove(pubkey);
        }
    }

    function replaceValidator(
        ValidatorStorage storage $,
        address distributor,
        bytes calldata _current,
        bytes calldata _new
    ) external {
        bytes32 id = keccak256(_current);
        if (!$.validatorIds.contains(id)) {
            revert Errors.InvalidValidator();
        }
        address _addr = _getValidatorAddress($, distributor, _current);

        // remove current from set
        $.validatorIds.remove(id);
        delete $.validatorPubkeys[id];
        IInfraredDistributor(distributor).remove(_current);

        // add new to set
        id = _getValidatorId(_new);
        if ($.validatorIds.contains(id)) {
            revert Errors.InvalidValidator();
        }
        $.validatorIds.add(id);
        $.validatorPubkeys[id] = _new;

        IInfraredDistributor(distributor).add(_new, _addr);
    }

    function queueBoosts(
        ValidatorStorage storage $,
        address bgt,
        address ibgt,
        bytes[] memory _pubkeys,
        uint128[] memory _amts
    ) external {
        if (_pubkeys.length != _amts.length) {
            revert Errors.InvalidArrayLength();
        }
        // check if sum of boosts is less than or equal to totalSpupply of iBGT
        uint256 _totalBoosts = 0;
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            if (!$.validatorIds.contains(keccak256(_pubkeys[i]))) {
                revert Errors.InvalidValidator();
            }
            if (_amts[i] == 0) revert Errors.ZeroAmount();
            _totalBoosts += _amts[i];
        }

        // make that new boost plus the existing boosts and queued boosts
        // are less than or equal to the total supply of iBGT
        if (
            _totalBoosts
                > IInfraredBGT(ibgt).totalSupply()
                    - (
                        IBerachainBGT(bgt).boosts(address(this))
                            + IBerachainBGT(bgt).queuedBoost(address(this))
                    )
        ) {
            revert Errors.BoostExceedsSupply();
        }
        // check if all pubkeys are valid
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            IBerachainBGT(bgt).queueBoost(_pubkeys[i], _amts[i]);
        }
    }

    function cancelBoosts(
        ValidatorStorage storage $,
        address bgt,
        bytes[] memory _pubkeys,
        uint128[] memory _amts
    ) external {
        if (_pubkeys.length != _amts.length) {
            revert Errors.InvalidArrayLength();
        }
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            bytes memory pubkey = _pubkeys[i];
            bytes32 id = keccak256(pubkey);
            if (!$.validatorIds.contains(id)) {
                revert Errors.InvalidValidator();
            }
            if (_amts[i] == 0) revert Errors.ZeroAmount();
            IBerachainBGT(bgt).cancelBoost(pubkey, _amts[i]);
        }
    }

    function activateBoosts(
        ValidatorStorage storage $,
        address bgt,
        bytes[] memory _pubkeys
    ) external {
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            if (!$.validatorIds.contains(keccak256(_pubkeys[i]))) {
                revert Errors.InvalidValidator();
            }
            IBerachainBGT(bgt).activateBoost(address(this), _pubkeys[i]);
        }
    }

    function queueDropBoosts(
        ValidatorStorage storage $,
        address bgt,
        bytes[] memory _pubkeys,
        uint128[] memory _amts
    ) external {
        if (_pubkeys.length != _amts.length) {
            revert Errors.InvalidArrayLength();
        }
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            if (!$.validatorIds.contains(keccak256(_pubkeys[i]))) {
                revert Errors.InvalidValidator();
            }
            if (_amts[i] == 0) revert Errors.ZeroAmount();
            IBerachainBGT(bgt).queueDropBoost(_pubkeys[i], _amts[i]);
        }
    }

    function cancelDropBoosts(
        ValidatorStorage storage $,
        address bgt,
        bytes[] memory _pubkeys,
        uint128[] memory _amts
    ) external {
        if (_pubkeys.length != _amts.length) {
            revert Errors.InvalidArrayLength();
        }
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            bytes memory pubkey = _pubkeys[i];
            bytes32 id = keccak256(pubkey);
            if (!$.validatorIds.contains(id)) {
                revert Errors.InvalidValidator();
            }
            if (_amts[i] == 0) revert Errors.ZeroAmount();
            IBerachainBGT(bgt).cancelDropBoost(_pubkeys[i], _amts[i]);
        }
    }

    function dropBoosts(
        ValidatorStorage storage $,
        address bgt,
        bytes[] memory _pubkeys
    ) external {
        for (uint256 i = 0; i < _pubkeys.length; i++) {
            if (!$.validatorIds.contains(keccak256(_pubkeys[i]))) {
                revert Errors.InvalidValidator();
            }
            IBerachainBGT(bgt).dropBoost(address(this), _pubkeys[i]);
        }
    }

    function infraredValidators(ValidatorStorage storage $, address distributor)
        external
        view
        returns (ValidatorTypes.Validator[] memory validators)
    {
        bytes32[] memory ids = $.validatorIds.values();
        uint256 len = ids.length;
        validators = new ValidatorTypes.Validator[](len);

        for (uint256 i = 0; i < len; i++) {
            bytes memory pubkey = $.validatorPubkeys[ids[i]];
            validators[i] = ValidatorTypes.Validator({
                pubkey: pubkey,
                addr: _getValidatorAddress($, distributor, pubkey)
            });
        }
    }

    // Public function to return the number of validators
    function numInfraredValidators(ValidatorStorage storage $)
        external
        view
        returns (uint256)
    {
        return $.validatorIds.length();
    }

    // Helper function to retrieve validator address from distributor
    function _getValidatorAddress(
        ValidatorStorage storage,
        address distributor,
        bytes memory pubkey
    ) internal view returns (address) {
        return IInfraredDistributor(distributor).getValidator(pubkey);
    }
}
