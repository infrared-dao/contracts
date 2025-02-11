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

        vm.startBroadcast();

        if (_checkEnoughTimePassed(blockNumberLast)) {
            infrared.activateBoosts(_pubkeys);

            uint256 maxBoost = ibgt.totalSupply()
                - (
                    bgt.boosts(address(infrared))
                        + bgt.queuedBoost(address(infrared))
                );

            uint256 len = _pubkeys.length;
            uint128[] memory amts = new uint128[](len);
            for (uint256 i; i < len; i++) {
                amts[i] = uint128(maxBoost / len);
            }

            infrared.queueBoosts(_pubkeys, amts);
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
