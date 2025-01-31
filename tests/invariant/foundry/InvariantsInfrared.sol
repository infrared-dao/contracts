// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

// external
import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";

import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";

// internal
import "src/core/Infrared.sol";
import "src/core/InfraredBGT.sol";
import "src/core/InfraredVault.sol";
import "src/utils/DataTypes.sol";

// mocks
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import "tests/unit/mocks/MockWbera.sol";
import "@berachain/pol/rewards/RewardVaultFactory.sol";

import "./handlers/Keeper.sol";
import "./handlers/User.sol";

import "src/core/MultiRewards.sol";

contract InvariantsInfrared is Test {
    Infrared public infrared;
    InfraredBGT public ibgt;

    BribeCollector public collector;
    InfraredDistributor public distributor;

    Voter public voter;
    VotingEscrow public sIR;

    address public admin;
    address public keeper;
    address public governance;

    Keeper public keeperHandler;
    User public userHandler;

    MockERC20 public bgt;
    MockERC20 public ir;
    MockERC20 public ibera;
    MockERC20 public honey;
    MockWbera public mockWbera;

    MockERC20 public mockPool;
    RewardVaultFactory public rewardsFactory;
    address public chef = makeAddr("chef"); // TODO: fix with mock chef

    string vaultName;
    string vaultSymbol;
    address[] rewardTokens;
    address stakingAsset;
    address poolAddress;

    // New declaration for mock pools
    MockERC20[] public mockPools;

    function setUp() public {
        // Mock non transferable token BGT token
        bgt = new MockERC20("BGT", "BGT", 18);
        // Mock contract instantiations
        ir = new MockERC20("IRED", "IRED", 18);
        ibera = new MockERC20("WInfraredBERA", "WInfraredBERA", 18);
        honey = new MockERC20("HONEY", "HONEY", 18);
        mockWbera = new MockWbera();

        // Set up addresses for roles
        admin = address(this);
        keeper = address(1);
        governance = address(2);

        // TODO: mock contracts
        mockPool = new MockERC20("Mock Asset", "MAS", 18);
        stakingAsset = address(mockPool);

        // deploy a rewards vault for InfraredBGT
        rewardsFactory = new RewardVaultFactory();

        // initialize Infrared contracts;
        infrared = Infrared(payable(setupProxy(address(new Infrared()))));
        collector = BribeCollector(setupProxy(address(new BribeCollector())));
        distributor =
            InfraredDistributor(setupProxy(address(new InfraredDistributor())));

        // IRED voting
        voter = Voter(setupProxy(address(new Voter())));
        sIR = new VotingEscrow(
            address(this), address(ir), address(voter), address(infrared)
        );

        collector.initialize(
            address(infrared), address(this), address(mockWbera), 10 ether
        );
        distributor.initialize(address(infrared), address(this), address(ibera));
        Infrared.InitializationData memory data = Infrared.InitializationData(
            governance,
            keeper,
            address(bgt),
            address(rewardsFactory),
            address(chef),
            payable(address(mockWbera)),
            address(honey),
            address(collector),
            address(distributor),
            address(voter),
            address(ibera),
            1 days
        );
        infrared.initialize(data); // make helper contract the admin
        ibgt = new InfraredBGT(
            data._gov, address(infrared), data._gov, address(infrared)
        );

        infrared.setIBGT(address(ibgt));

        // @dev must initialize after infrared so address(this) has keeper role
        voter.initialize(address(infrared), address(sIR), governance, keeper);
        /* Handler Setup */

        // deploy the handler contracts
        keeperHandler = new Keeper(infrared, keeper, rewardsFactory);

        userHandler = new User(infrared, keeperHandler);

        bytes4[] memory keeperSelectors = new bytes4[](2);
        keeperSelectors[0] = keeperHandler.registerVault.selector;
        keeperSelectors[1] = keeperHandler.harvestVault.selector;

        bytes4[] memory userSelectors = new bytes4[](3);
        userSelectors[0] = userHandler.deposit.selector;
        userSelectors[1] = userHandler.withdraw.selector;
        userSelectors[2] = userHandler.claim.selector;

        excludeArtifact("InfraredVault");
        // excludeArtifact("MockBerachainRewardsVault");
        excludeArtifact("tests/unit/mocks/MockERC20.sol:MockERC20");

        targetSelector(
            FuzzSelector({
                addr: address(keeperHandler),
                selectors: keeperSelectors
            })
        );
        targetContract(address(keeperHandler));

        targetSelector(
            FuzzSelector({addr: address(userHandler), selectors: userSelectors})
        );
        targetContract(address(userHandler));
    }

    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_ibgt_minted_equal_to_bgt_rewards() public view {
        // assert that the total minted ibgt is equal to the total bgt rewards
        assertEq(
            ibgt.totalSupply(),
            bgt.balanceOf(address(infrared)),
            "Invariant: Minted InfraredBGT should be equal to total BGT rewards"
        );
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }

    /*//////////////////////////////////////////////////////////////
                    User Invariants
    //////////////////////////////////////////////////////////////*/
    function invariant_user_earned_ibgt_rewards() public view {
        // assert that the user earned ibgt rewards
        address[] memory users = userHandler.getUsers();
        uint256 userRewards;

        for (uint256 i = 0; i < users.length; i++) {
            userRewards += ibgt.balanceOf(users[i]);
        }

        assertTrue(
            userRewards <= ibgt.totalSupply(),
            "Invariant: Users should earn InfraredBGT rewards"
        );
    }
}
