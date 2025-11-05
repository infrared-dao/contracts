// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRewardVault} from "@berachain/pol/interfaces/IRewardVault.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

import {InfraredForkTest} from "../InfraredForkTest.t.sol";
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20PresetMinterPauser} from "src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/depreciated/core/Infrared.sol";

contract RegisterVaultForkTest is InfraredForkTest {
    function testRegisterVaultWithoutRewardsVault() public {
        deployIR();
        vm.startPrank(infraredGovernance);

        // priors checked
        assertEq(address(infrared.vaultRegistry(address(ir))), address(0));
        assertEq(factory.getVault(address(ir)), address(0));

        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(ir);

        IInfraredVault _newVault = infrared.registerVault(address(ir));

        // check vault stored in registry
        assertTrue(address(infrared.vaultRegistry(address(ir))) != address(0));
        assertEq(
            address(infrared.vaultRegistry(address(ir))), address(_newVault)
        );

        // check berachain rewards vault created
        IRewardVault _newRewardsVault = _newVault.rewardsVault();
        assertEq(address(_newRewardsVault), factory.getVault(address(ir)));

        // check infrared rewards vault sets infrared as operator
        assertEq(
            _newRewardsVault.operator(address(_newVault)), address(infrared)
        );

        infrared.updateWhiteListedRewardTokens(address(ir), true);

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

    function deployIR() internal {
        ir = new InfraredGovernanceToken(
            address(infrared),
            infraredGovernance,
            infraredGovernance,
            infraredGovernance,
            address(0)
        );

        // gov only (i.e. this needs to be run by gov)
        vm.startPrank(infraredGovernance);
        infrared.setIR(address(ir));
        vm.stopPrank();
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
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
