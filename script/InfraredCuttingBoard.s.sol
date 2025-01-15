// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {IBeraChef} from "@berachain/pol/interfaces/IBeraChef.sol";
import {IInfrared} from "src/interfaces/IInfrared.sol";

contract InfraredCuttingBoard is Script {
    function run(
        address infrared,
        bytes calldata validator,
        uint64 blocksUntilStart,
        address[] memory receivers,
        uint96[] memory percentageNumerators
    ) external {
        vm.startBroadcast();

        uint64 startBlock = uint64(block.number) + blocksUntilStart;

        require(
            receivers.length == percentageNumerators.length,
            "len(receivers) != len(percents)"
        );
        require(receivers.length > 0, "len(receivers) == 0");

        // assemble berachef weights
        uint256 len = receivers.length;
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](len);
        for (uint256 i = 0; i < len; i++) {
            weights[i] = IBeraChef.Weight({
                receiver: receivers[i],
                percentageNumerator: percentageNumerators[i]
            });
        }

        IInfrared(infrared).queueNewCuttingBoard(validator, startBlock, weights);

        vm.stopBroadcast();
    }
}
