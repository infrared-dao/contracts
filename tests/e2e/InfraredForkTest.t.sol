// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20PresetMinterPauser} from
    "../../src/vendors/ERC20PresetMinterPauser.sol";

import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Infrared} from "src/depreciated/core/Infrared.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/depreciated/core/BribeCollector.sol";

import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {IMultiRewards} from "src/interfaces/IMultiRewards.sol";

import "./HelperForkTest.t.sol";

contract InfraredForkTest is HelperForkTest {
    ERC20PresetMinterPauser public stakingToken;

    IInfraredVault public lpVault;

    uint256 internal constant FEE_UNIT = 1e6;

    function setUp() public virtual override {
        super.setUp();

        uint256 _rewardsDuration = 30 days;
        uint256 _bribeCollectorPayoutAmount = 10 ether;

        // deploy
        deployer = new InfraredDeployer();
        deployer.run(
            infraredGovernance,
            keeper,
            address(bgt),
            address(factory),
            address(beraChef),
            address(beaconDepositContract),
            address(wbera),
            address(honey),
            _rewardsDuration,
            _bribeCollectorPayoutAmount
        );

        // retreive addersses
        infrared = deployer.infrared();
        collector = deployer.collector();
        infraredDistributor = deployer.distributor();
        ibgt = deployer.ibgt();
        ibera = deployer.ibera();
        depositor = deployer.depositor();
        receivor = deployer.receivor();

        uint16 feeShareholders = 4; // 25% of fees
        vm.prank(infraredGovernance);
        ibera.setFeeDivisorShareholders(feeShareholders);

        stakingToken = new ERC20PresetMinterPauser(
            "Staking Token",
            "STAKE",
            address(this),
            address(this),
            address(this),
            address(this)
        );

        // mint and deal staking tokens
        stakingToken.mint(address(this), 1000 ether);

        lpVault = infrared.registerVault(address(stakingToken));
    }

    function testSetUp() public virtual {
        assertEq(address(infrared.ibgt()), address(ibgt));

        assertEq(address(infrared.collector()), address(collector));
        assertEq(address(infrared.distributor()), address(infraredDistributor));

        IInfraredVault _ibgtVault = infrared.vaultRegistry(address(ibgt));
        assertTrue(address(_ibgtVault) != address(0));
        assertEq(address(_ibgtVault), address(infrared.ibgtVault()));
        assertEq(address(_ibgtVault.infrared()), address(infrared));

        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(ibgt);

        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address rewardToken = _rewardTokens[i];
            assertTrue(infrared.whitelistedRewardTokens(rewardToken));

            (, uint256 rewardDurationIbgt,,,,,) =
                IMultiRewards(address(_ibgtVault)).rewardData(rewardToken);
            assertTrue(rewardDurationIbgt > 0);
        }

        assertTrue(
            infrared.hasRole(infrared.DEFAULT_ADMIN_ROLE(), infraredGovernance)
        );
        assertTrue(infrared.hasRole(infrared.KEEPER_ROLE(), keeper));
        assertTrue(
            infrared.hasRole(infrared.GOVERNANCE_ROLE(), infraredGovernance)
        );

        assertEq(stakingToken.balanceOf(address(this)), 1000 ether);

        assertEq(
            address(lpVault.rewardsVault()),
            factory.getVault(address(stakingToken))
        );

        // test implementations disabled
        address collectorImplementation = collector.currentImplementation();
        vm.expectRevert();
        BribeCollector(collectorImplementation).initialize(
            address(infrared), infraredGovernance, address(wbera), 10 ether
        );

        address distributorImplementation =
            infraredDistributor.currentImplementation();
        vm.expectRevert();
        InfraredDistributor(distributorImplementation).initialize(
            address(infrared), infraredGovernance, address(ibera)
        );
    }
}
