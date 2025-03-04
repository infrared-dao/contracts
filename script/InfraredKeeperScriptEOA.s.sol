// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";
import {IInfraredBGT} from "src/interfaces/IInfraredBGT.sol";
import {Infrared} from "src/core/Infrared.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {IBGT as IBerachainBGT} from "@berachain/pol/interfaces/IBGT.sol";

contract InfraredKeeperScriptEOA is Script {
    /// @dev The length of the history buffer in the EIP-4788 Beacon Roots contract.
    uint64 private constant HISTORY_BUFFER_LENGTH = 8191;

    Infrared infrared =
        Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
    IBerachainBGT bgt =
        IBerachainBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IInfraredBGT ibgt = IInfraredBGT(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    InfraredBERAWithdrawor iberaWithdrawer = InfraredBERAWithdrawor(
        payable(0x8c0E122960dc2E97dc0059c07d6901Dce72818E1)
    );
    InfraredBERAFeeReceivor rec = InfraredBERAFeeReceivor(
        payable(0xf6a4A6aCECd5311327AE3866624486b6179fEF97)
    );
    InfraredBERADepositor depositor = InfraredBERADepositor(
        payable(0x04CddC538ea65908106416986aDaeCeFD4CAB7D7)
    );

    function harvest(address[] calldata _stakingTokens) external {
        vm.startBroadcast();

        // Harvest each vault
        for (uint256 i = 0; i < _stakingTokens.length; i++) {
            address _stakingToken = _stakingTokens[i];
            IInfraredVault _vault = infrared.vaultRegistry(_stakingToken);
            if (_vault.totalSupply() > 1) {
                infrared.harvestVault(_stakingToken);
            }
        }

        // Harvest base rewards
        infrared.harvestBase();

        (uint256 amount,) = rec.distribution();
        if (amount > 0) {
            // Harvest operator rewards
            infrared.harvestOperatorRewards();
        }

        // Harvest boost rewards
        infrared.harvestBoostRewards();

        vm.stopBroadcast();
    }

    function activateAndMaxBoost(bytes[] calldata _pubkeys) external {
        (uint32 blockNumberLast,) =
            bgt.boostedQueue(address(infrared), _pubkeys[0]);

        uint256 len = _pubkeys.length;
        if (len == 0) return; // Avoid errors with empty input

        // queue boost strategy is to bring all boosts up to max then equally distribute
        uint256 maxBoost = ibgt.totalSupply()
            - (bgt.boosts(address(infrared)) + bgt.queuedBoost(address(infrared)));

        vm.startBroadcast();

        if (_checkEnoughTimePassed(blockNumberLast)) {
            infrared.activateBoosts(_pubkeys);

            // find max boostedValidator
            uint256 highestBoost;
            uint256[] memory currentBoosts = new uint256[](len);
            for (uint256 i; i < len; i++) {
                currentBoosts[i] = bgt.boosted(address(infrared), _pubkeys[i]);
                if (currentBoosts[i] > highestBoost) {
                    highestBoost = currentBoosts[i];
                }
            }

            // assign amounts
            uint256 cumulativeBoost;
            uint128[] memory amts = new uint128[](len);
            // first iteration for levelling amounts
            for (uint256 i; i < len; i++) {
                uint256 amt = highestBoost - currentBoosts[i];
                if (amt == 0) continue;
                if (amt + cumulativeBoost > maxBoost) {
                    amt = maxBoost - cumulativeBoost;
                }
                cumulativeBoost += amt;
                amts[i] = uint128(amt);
                if (cumulativeBoost == maxBoost) break;
            }
            if (cumulativeBoost < maxBoost) {
                maxBoost -= cumulativeBoost;
                // second iteration for equal distribution
                for (uint256 i; i < len; i++) {
                    amts[i] += uint128(maxBoost / len);
                }
            }

            // Filter out zero amounts before queuing boosts
            uint256 count = 0;
            // Count non-zero amounts
            for (uint256 i; i < len; i++) {
                if (amts[i] != 0) {
                    count++;
                }
            }

            // Only proceed if there are non-zero amounts
            if (count > 0) {
                // Create filtered arrays
                bytes[] memory filteredPubkeys = new bytes[](count);
                uint128[] memory filteredAmts = new uint128[](count);

                // Populate filtered arrays with non-zero entries
                uint256 index = 0;
                for (uint256 i; i < len; i++) {
                    if (amts[i] != 0) {
                        filteredPubkeys[index] = _pubkeys[i];
                        filteredAmts[index] = amts[i];
                        index++;
                    }
                }

                // Queue boosts with filtered arrays
                infrared.queueBoosts(filteredPubkeys, filteredAmts);
            }
        }
        vm.stopBroadcast();
    }

    function activateBoost(bytes[] calldata _pubkeys) external {
        (uint32 blockNumberLast,) =
            bgt.boostedQueue(address(infrared), _pubkeys[0]);

        vm.startBroadcast();

        if (_checkEnoughTimePassed(blockNumberLast)) {
            infrared.activateBoosts(_pubkeys);
        }
        vm.stopBroadcast();
    }

    function _checkEnoughTimePassed(uint32 blockNumberLast)
        private
        view
        returns (bool)
    {
        unchecked {
            uint32 delta = uint32(block.number) - blockNumberLast;
            // roughly 5 hours with a 2 second block time
            if (delta <= HISTORY_BUFFER_LENGTH) {
                return false;
            } else {
                return true;
            }
        }
    }
}
