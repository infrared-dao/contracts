// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Testing Libraries.
import "forge-std/Test.sol";

// external
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {BeaconDeposit} from "@berachain/pol/BeaconDeposit.sol";

import {WrappedRewardToken} from "src/periphery/WrappedRewardToken.sol";

import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAV2} from "src/staking/InfraredBERAV2.sol";
import {InfraredBERADepositorV2} from "src/staking/InfraredBERADepositorV2.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAWithdraworLite} from
    "src/depreciated/staking/InfraredBERAWithdraworLite.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/depreciated/core/BribeCollector.sol";
import {BribeCollectorV1_2} from "src/depreciated/core/BribeCollectorV1_2.sol";
import {BribeCollectorV1_3} from "src/depreciated/core/BribeCollectorV1_3.sol";
import {BribeCollectorV1_4} from "src/core/BribeCollectorV1_4.sol";

// internal
import {ERC20, Infrared} from "src/depreciated/core/Infrared.sol";
import {InfraredV1_2} from "src/depreciated/core/InfraredV1_2.sol";
import {InfraredV1_3} from "src/depreciated/core/InfraredV1_3.sol";
import {InfraredV1_4} from "src/depreciated/core/InfraredV1_4.sol";
import {InfraredV1_5} from "src/depreciated/core/InfraredV1_5.sol";
import {InfraredV1_7} from "src/depreciated/core/InfraredV1_7.sol";
import {InfraredV1_8} from "src/depreciated/core/InfraredV1_8.sol";
import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";
import {DataTypes} from "src/utils/DataTypes.sol";
import {HarvestBaseCollector} from
    "src/depreciated/staking/HarvestBaseCollector.sol";

import {IInfrared} from "src/depreciated/interfaces/IInfrared.sol";
// mocks
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {RewardVaultFactory} from "@berachain/pol/rewards/RewardVaultFactory.sol";
import {BeaconDepositMock, POLTest} from "@berachain/../test/pol/POL.t.sol";

abstract contract Helper is POLTest {
    Infrared public infrared;
    InfraredBGT public ibgt;
    InfraredGovernanceToken public ir;

    InfraredBERAV2 public ibera;
    InfraredBERADepositorV2 public depositor;
    InfraredBERA public iberaV0;
    InfraredBERADepositor public depositorV0;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAWithdraworLite public withdraworLite;
    InfraredBERAFeeReceivor public receivor;

    BribeCollector internal collector0;
    BribeCollectorV1_2 internal collector;
    InfraredDistributor internal infraredDistributor;

    // Standard test addresses
    address internal admin;
    address internal keeper;
    address internal infraredGovernance;
    address internal testUser;
    address constant SEARCHER = address(777);

    // MockERC20 internal bgt;ibger
    MockERC20 internal honey;
    address internal beraVault;

    MockERC20 internal mockPool;
    // address internal chef = makeAddr("chef");

    string vaultName;
    string vaultSymbol;
    // address[] rewardTokens;
    address stakingAsset;
    address poolAddress;

    IInfraredVault internal ibgtVault;
    InfraredVault internal infraredVault;

    address validator = address(888);
    address validator2 = address(999);

    address wiBGT;

    function setUp() public virtual override {
        super.setUp();

        address depositContract = address(new BeaconDeposit());

        honey = new MockERC20("HONEY", "HONEY", 18);

        // Set up addresses for roles
        admin = address(this);
        keeper = address(1);
        infraredGovernance = address(2);
        testUser = address(3);

        stakingAsset = address(wbera);

        // Set up bera bgt distribution for mockPool
        beraVault = factory.createRewardVault(stakingAsset);

        // initialize Infrared contracts
        infrared = Infrared(payable(setupProxy(address(new Infrared()))));

        // ibera = new InfraredBERA(address(infrared));
        // InfraredBERA
        iberaV0 = InfraredBERA(setupProxy(address(new InfraredBERA())));

        depositorV0 = InfraredBERADepositor(
            setupProxy(address(new InfraredBERADepositor()))
        );
        withdraworLite = InfraredBERAWithdraworLite(
            payable(setupProxy(address(new InfraredBERAWithdraworLite())))
        );

        receivor = InfraredBERAFeeReceivor(
            payable(setupProxy(address(new InfraredBERAFeeReceivor())))
        );

        collector0 = BribeCollector(setupProxy(address(new BribeCollector())));
        infraredDistributor =
            InfraredDistributor(setupProxy(address(new InfraredDistributor())));

        collector0.initialize(
            address(infrared), infraredGovernance, address(wbera), 10 ether
        );
        infraredDistributor.initialize(
            address(infrared), infraredGovernance, address(iberaV0)
        );

        // voter = Voter(setupProxy(address(new Voter(address(infrared)))));

        Infrared.InitializationData memory data = Infrared.InitializationData(
            infraredGovernance,
            keeper,
            address(bgt),
            address(factory),
            address(beraChef),
            payable(address(wbera)),
            address(honey),
            address(collector0),
            address(infraredDistributor),
            address(0),
            address(iberaV0),
            1 days
        );
        infrared.initialize(data);
        ibgt = new InfraredBGT(
            data._gov, address(infrared), data._gov, address(infrared)
        );

        infrared.setIBGT(address(ibgt));

        // initialize ibera proxies
        depositorV0.initialize(
            infraredGovernance, keeper, address(iberaV0), depositContract
        );
        withdraworLite.initialize(infraredGovernance, keeper, address(iberaV0));

        receivor.initialize(
            infraredGovernance, keeper, address(iberaV0), address(infrared)
        );

        // init deposit to avoid inflation attack
        iberaV0.initialize{value: 10 ether}(
            infraredGovernance,
            keeper,
            address(infrared),
            address(depositorV0),
            address(withdraworLite),
            address(receivor)
        );

        uint16 feeShareholders = 4; // 25% of fees

        vm.prank(infraredGovernance);
        iberaV0.setFeeDivisorShareholders(feeShareholders);

        vm.startPrank(governance);
        bgt.whitelistSender(address(factory), true);
        vm.stopPrank();

        infraredVault =
            InfraredVault(address(infrared.registerVault(stakingAsset)));

        ibgtVault = infrared.ibgtVault();

        labelContracts();

        // upgrade infrared
        address infraredV1_2Implementation = address(new InfraredV1_2());

        // upgrade proxy
        vm.prank(infraredGovernance);
        infrared.upgradeToAndCall(infraredV1_2Implementation, "");

        // upgrade bribe collector to v1.2
        collector = new BribeCollectorV1_2();

        // perform proxy upgrade
        vm.prank(infraredGovernance);
        (bool success,) = address(collector0).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(collector), ""
            )
        );
        require(success, "Upgrade failed");
        collector = BribeCollectorV1_2(address(collector0));

        // upgrade bribe collector to v1.3
        BribeCollectorV1_3 bribeCollectorV1_3 = new BribeCollectorV1_3();

        // perform proxy upgrade
        vm.prank(infraredGovernance);
        (success,) = address(collector0).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(bribeCollectorV1_3),
                ""
            )
        );
        require(success, "Upgrade to BribeCollectorV1_3 failed");

        // Grant KEEPER_ROLE to addresses that need to call claimFees
        vm.startPrank(infraredGovernance);
        collector.grantRole(collector.KEEPER_ROLE(), SEARCHER);
        collector.grantRole(collector.KEEPER_ROLE(), address(this));
        collector.grantRole(collector.KEEPER_ROLE(), keeper);
        vm.stopPrank();

        // upgrade infrared again
        address infraredV1_3Implementation = address(new InfraredV1_3());

        // upgrade proxy again
        vm.prank(infraredGovernance);
        infrared.upgradeToAndCall(infraredV1_3Implementation, "");

        // upgrade infrared again
        address infraredV1_4Implementation = address(new InfraredV1_4());

        // upgrade proxy again
        vm.prank(infraredGovernance);
        infrared.upgradeToAndCall(infraredV1_4Implementation, "");

        // upgrade infrared again
        address infraredV1_5Implementation = address(new InfraredV1_5());

        // upgrade proxy again
        vm.prank(infraredGovernance);
        infrared.upgradeToAndCall(infraredV1_5Implementation, "");

        // iber v2
        _upgradeIBeraToV2();

        // upgrade infrared v1.7
        vm.startPrank(infraredGovernance);
        infrared.upgradeToAndCall(
            address(new InfraredV1_7()),
            abi.encodeWithSignature(
                "initializeV1_7(address)",
                setupProxy(
                    address(new HarvestBaseCollector()),
                    abi.encodeWithSignature(
                        "initialize(address,address,address,address,address,address,uint256)",
                        address(infrared),
                        infraredGovernance,
                        keeper,
                        address(ibgt),
                        address(wbera),
                        address(receivor),
                        10 ether
                    )
                )
            )
        );
        vm.stopPrank();

        // set auctionBase flag to false for legacy tests
        vm.prank(keeper);
        InfraredV1_7(payable(address(infrared))).toggleAuctionBase();

        // v1.8 upgrade
        vm.startPrank(infraredGovernance);
        // upgrade bribe collector to v1.4 (set initial payout token to wbera for legacy tests)
        BribeCollectorV1_4 bribeCollectorV1_4 = new BribeCollectorV1_4();
        (success,) = address(collector0).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(bribeCollectorV1_4),
                ""
            )
        );
        require(success, "Upgrade to BribeCollectorV1_4 failed");
        // infrared v1.8
        infrared.upgradeToAndCall(address(new InfraredV1_8()), "");
        vm.stopPrank();
        // infrared v1.9
        wiBGT = address(
            new WrappedRewardToken(
                ERC20(address(ibgt)), "Wrapped Infrared BGT", "wiBGT"
            )
        );
        vm.startPrank(infraredGovernance);
        infrared.upgradeToAndCall(
            address(new InfraredV1_9()),
            abi.encodeWithSelector(InfraredV1_9.initializeV1_9.selector, wiBGT)
        );
        vm.stopPrank();
    }

    function _upgradeIBeraToV2() internal {
        // Deploy V2 implementations
        address depositorV2Impl = address(new InfraredBERADepositorV2());
        address iberaV2Impl = address(new InfraredBERAV2());

        vm.startPrank(infraredGovernance);
        // Upgrade depositor to V2
        depositorV0.upgradeToAndCall(depositorV2Impl, "");
        depositor = InfraredBERADepositorV2(address(depositorV0));

        // Upgrade ibera to V2
        iberaV0.upgradeToAndCall(iberaV2Impl, "");
        ibera = InfraredBERAV2(address(iberaV0));

        depositor.initializeV2();
        ibera.initializeV2();
        vm.stopPrank();
    }

    function labelContracts() public {
        // labeling contracts
        vm.label(address(infrared), "infrared");
        vm.label(address(ibgt), "ibgt");
        vm.label(address(bgt), "bgt");
        vm.label(address(wbera), "wbera");
        vm.label(admin, "admin");
        vm.label(keeper, "keeper");
        vm.label(stakingAsset, "stakingAsset");
        vm.label(infraredGovernance, "infraredGovernance");
        vm.label(address(factory), "rewardsFactory");
        vm.label(address(beraChef), "chef");
        vm.label(address(ibgtVault), "ibgtVault");
        vm.label(address(collector), "collector");
    }

    function stakeInVault(
        address iVault,
        address asset,
        address user,
        uint256 amount
    ) internal {
        deal(asset, user, amount);
        vm.startPrank(user);
        ERC20(asset).approve(iVault, amount);
        InfraredVault(iVault).stake(amount);
        vm.stopPrank();
    }

    function isStringSame(string memory _a, string memory _b)
        internal
        pure
        returns (bool _isSame)
    {
        bytes memory a = bytes(_a);
        bytes memory b = bytes(_b);

        if (a.length != b.length) {
            return false;
        }

        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }

        return true;
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }

    function setupProxy(address implementation, bytes memory data)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, data));
    }

    function _credential(address addr) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), addr);
    }

    function _create96Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes32("32"), bytes32("32"));
    }

    function _create48Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes16("16"));
    }
}
