// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRewardVault} from "@berachain/pol/interfaces/IRewardVault.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

import {InfraredForkTest} from "../InfraredForkTest.t.sol";

contract RegisterVaultForkTest is InfraredForkTest {
    function testRegisterVaultWithoutRewardsVault() public {
        vm.startPrank(infraredGovernance);

        // priors checked
        assertEq(address(infrared.vaultRegistry(address(red))), address(0));
        assertEq(factory.getVault(address(red)), address(0));

        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(ired);

        IInfraredVault _newVault = infrared.registerVault(address(red));

        // check vault stored in registry
        assertTrue(address(infrared.vaultRegistry(address(red))) != address(0));
        assertEq(
            address(infrared.vaultRegistry(address(red))), address(_newVault)
        );

        // check berachain rewards vault created
        IRewardVault _newRewardsVault = _newVault.rewardsVault();
        assertEq(address(_newRewardsVault), factory.getVault(address(red)));

        // check infrared rewards vault sets infrared as operator
        assertEq(
            _newRewardsVault.operator(address(_newVault)), address(infrared)
        );

        infrared.updateWhiteListedRewardTokens(address(ired), true);

        infrared.addReward(address(stakingToken), _rewardTokens[0], 10 days);

        // check reward added to multirewards in infrared vault
        (
            address _distributor,
            uint256 _duration,
            uint256 _periodFin,
            uint256 _rate,
            uint256 _last,
            uint256 _stored,
            uint256 _residual
        ) = IMultiRewards(address(_newVault)).rewardData(address(ibgt));
        assertEq(_distributor, address(infrared));
        assertEq(_duration, 30 days);
        assertEq(_periodFin, 0);
        assertEq(_rate, 0);
        assertEq(_last, 0);
        assertEq(_stored, 0);
        assertEq(_residual, 0);

        vm.stopPrank();
    }

    // function testRegisterVaultWithRewardsVault() public {
    //     vm.startPrank(admin);

    //     // priors checked
    //     assertEq(
    //         address(infrared.vaultRegistry(address(vdHoneyToken))), address(0)
    //     );

    //     address rewardsVaultAddress =
    //         factory.getVault(address(vdHoneyToken));
    //     assertTrue(rewardsVaultAddress != address(0));

    //     address[] memory _rewardTokens = new address[](1);
    //     _rewardTokens[0] = address(ibgt);

    //     IInfraredVault _newVault =
    //         infrared.registerVault(address(vdHoneyToken), _rewardTokens);

    //     // check vault stored in registry
    //     assertTrue(
    //         address(infrared.vaultRegistry(address(vdHoneyToken))) != address(0)
    //     );
    //     assertEq(
    //         address(infrared.vaultRegistry(address(vdHoneyToken))),
    //         address(_newVault)
    //     );

    //     // check berachain rewards vault created
    //     IRewardVault _newRewardsVault = _newVault.rewardsVault();
    //     assertEq(address(_newRewardsVault), rewardsVaultAddress);

    //     // check infrared rewards vault sets infrared as operator
    //     assertEq(
    //         _newRewardsVault.operator(address(_newVault)), address(infrared)
    //     );

    //     // check reward added to multirewards in infrared vault
    //     (
    //         address _distributor,
    //         uint256 _duration,
    //         uint256 _periodFin,
    //         uint256 _rate,
    //         uint256 _last,
    //         uint256 _stored
    //     ) = IMultiRewards(address(_newVault)).rewardData(address(ibgt));
    //     assertEq(_distributor, address(infrared));
    //     assertEq(_duration, 10 days);
    //     assertEq(_periodFin, 0);
    //     assertEq(_rate, 0);
    //     assertEq(_last, 0);
    //     assertEq(_stored, 0);

    //     vm.stopPrank();
    // }
}
