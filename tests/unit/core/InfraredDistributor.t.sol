// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "forge-std/Test.sol";

import {BribeCollector} from "src/core/BribeCollector.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";

import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {MockInfrared} from "tests/unit/mocks/MockInfrared.sol";
import {Errors} from "src/utils/Errors.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract InfraredDistributorTest is Test {
    MockERC20 public token;
    MockInfrared public infrared;

    InfraredDistributor public distributor;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    bytes public pubkey1 = abi.encodePacked(validator1);
    bytes public pubkey2 = abi.encodePacked(validator2);
    address public red = makeAddr("iRED");
    address public rewardsFactory = makeAddr("rewardsFactory");

    function setUp() public {
        // Initialize mock contracts
        token = new MockERC20("iBERA", "iBERA", 18);
        infrared = new MockInfrared(address(token), red, rewardsFactory);

        distributor = InfraredDistributor(
            setupProxy(address(new InfraredDistributor(address(infrared))))
        );
        distributor.initialize(address(this), address(token));

        // Set up initial state for tests
        deal(address(token), user, 1000 ether);

        vm.prank(user);
        require(token.approve(address(distributor), 1000 ether));
        assertEq(token.allowance(user, address(distributor)), 1000 ether);
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }

    function testInitialize() public view {
        assertEq(address(distributor.infrared()), address(infrared));
        assertEq(address(distributor.token()), address(token));
        assertEq(distributor.amountsCumulative(), 1);
    }

    event Notified(uint256 amount, uint256 num);

    function testNotifyRewardAmount(uint256 amount) public {
        vm.assume(amount <= token.balanceOf(user));
        vm.assume(amount > 0);

        uint256 amountsCumulativeBefore = distributor.amountsCumulative();
        uint256 balanceDistributorBefore = token.balanceOf(address(distributor));
        uint256 balanceUserBefore = token.balanceOf(address(user));

        // add 2 validators
        infrared.addValidator(validator1);
        infrared.addValidator(validator2);

        // notify reward amount
        vm.expectEmit();
        emit Notified(amount, 2);

        vm.prank(user);
        distributor.notifyRewardAmount(amount);

        // check amounts cumulative state changed
        assertEq(
            distributor.amountsCumulative(),
            amountsCumulativeBefore + amount / 2
        );

        // check token transferred in to distributor from user
        assertEq(
            token.balanceOf(address(distributor)),
            balanceDistributorBefore + amount
        );
        assertEq(token.balanceOf(user), balanceUserBefore - amount);
    }

    event Added(bytes pubkey, address validator, uint256 amountCumulative);

    function testAdd() public {
        vm.expectEmit();
        emit Added(pubkey1, validator1, 1);

        vm.prank(address(infrared));
        distributor.add(pubkey1, validator1);

        (uint256 last1, uint256 fin1) = distributor.snapshots(pubkey1);
        assertEq(last1, 1);
        assertEq(fin1, 0);

        // now notify reward amount for next validator
        infrared.addValidator(validator1);
        vm.prank(user);
        distributor.notifyRewardAmount(10 ether);

        // add second validator and check cumulative last set to accumulator
        assertEq(distributor.amountsCumulative(), 10 ether + 1);

        vm.expectEmit();
        emit Added(pubkey2, validator2, 10 ether + 1);

        vm.prank(address(infrared));
        distributor.add(pubkey2, validator2);

        // @dev need this for infrared.numInfraredValidators to be correct
        infrared.addValidator(validator2);

        (uint256 last2, uint256 fin2) = distributor.snapshots(pubkey2);
        assertEq(last2, 10 ether + 1);
        assertEq(fin2, 0);
    }

    event Removed(bytes pubkey, address validator, uint256 amountCumulative);

    function testRemove() public {
        testAdd();

        // notify again for second round of rewards shared equally
        assertEq(infrared.numInfraredValidators(), 2);

        vm.prank(user);
        distributor.notifyRewardAmount(20 ether);

        assertEq(distributor.amountsCumulative(), 20 ether + 1); // 10 / 1 + 20 / 2

        vm.expectEmit();
        emit Removed(pubkey1, validator1, 20 ether + 1);

        vm.prank(address(infrared));
        distributor.remove(pubkey1);

        // @dev need this for infrared.numInfraredValidators to be correct
        infrared.removeValidator(validator1);

        (uint256 last1, uint256 fin1) = distributor.snapshots(pubkey1);
        assertEq(last1, 1);
        assertEq(fin1, 20 ether + 1);
    }

    function testCannotRemoveValidatorTwice() public {
        // First add validator1
        vm.prank(address(infrared));
        distributor.add(pubkey1, validator1);
        infrared.addValidator(validator1);

        // Add some rewards
        vm.prank(user);
        distributor.notifyRewardAmount(10 ether);

        // First removal should succeed
        vm.prank(address(infrared));
        distributor.remove(pubkey1);
        infrared.removeValidator(validator1);

        // Get snapshot after first removal
        (uint256 lastAfterRemoval, uint256 finalAfterRemoval) =
            distributor.snapshots(pubkey1);

        // Attempt to remove again - should revert
        vm.expectRevert(Errors.ValidatorAlreadyRemoved.selector);
        vm.prank(address(infrared));
        distributor.remove(pubkey1);

        // Verify snapshot hasn't changed
        (uint256 lastAfterAttempt, uint256 finalAfterAttempt) =
            distributor.snapshots(pubkey1);
        assertEq(
            lastAfterAttempt, lastAfterRemoval, "Last amount should not change"
        );
        assertEq(
            finalAfterAttempt,
            finalAfterRemoval,
            "Final amount should not change"
        );
    }

    function testDoubleRemovalWithMultipleValidators() public {
        // Add two validators
        vm.prank(address(infrared));
        distributor.add(pubkey1, validator1);
        infrared.addValidator(validator1);

        vm.prank(address(infrared));
        distributor.add(pubkey2, validator2);
        infrared.addValidator(validator2);

        // Add initial rewards
        vm.prank(user);
        distributor.notifyRewardAmount(20 ether); // 10 ether each

        // Remove first validator
        vm.prank(address(infrared));
        distributor.remove(pubkey1);
        infrared.removeValidator(validator1);

        // Add more rewards (should only go to validator2)
        vm.prank(user);
        distributor.notifyRewardAmount(10 ether);

        // Try to remove validator1 again
        vm.expectRevert(Errors.ValidatorAlreadyRemoved.selector);
        vm.prank(address(infrared));
        distributor.remove(pubkey1);

        // Verify validator1 can still claim their original share
        vm.prank(validator1);
        distributor.claim(pubkey1, validator1);

        // Final balance for validator1 should be 10 ether (their share of initial rewards)
        assertEq(
            token.balanceOf(validator1),
            10 ether,
            "Validator1 should only receive initial share"
        );
    }

    // TODO: test purge

    event Claimed(
        bytes pubkey, address validator, address recipient, uint256 amount
    );

    function testClaim() public {
        testRemove();

        // notify again for third round of rewards to only validator 2
        assertEq(infrared.numInfraredValidators(), 1);

        vm.prank(user);
        distributor.notifyRewardAmount(30 ether);

        assertEq(distributor.amountsCumulative(), 50 ether + 1); // 10 / 1 + 20 / 2 + 30 / 1
        assertEq(token.balanceOf(address(distributor)), 60 ether);

        // claim for validator 1
        vm.expectEmit();
        emit Claimed(pubkey1, validator1, validator1, 20 ether); // 10 / 1 + 20 / 2

        vm.prank(validator1);
        distributor.claim(pubkey1, validator1);

        (uint256 last1, uint256 fin1) = distributor.snapshots(pubkey1);
        assertEq(last1, 20 ether + 1);
        assertEq(fin1, 20 ether + 1);

        assertEq(token.balanceOf(validator1), 20 ether);
        assertEq(token.balanceOf(address(distributor)), 40 ether);

        // claim for validator 2
        vm.expectEmit();
        emit Claimed(pubkey2, validator2, validator2, 40 ether); // 20 / 2 + 30 / 1

        vm.prank(validator2);
        distributor.claim(pubkey2, validator2);

        (uint256 last2, uint256 fin2) = distributor.snapshots(pubkey2);
        assertEq(last2, 50 ether + 1);
        assertEq(fin2, 0);

        assertEq(token.balanceOf(validator2), 40 ether);
        assertEq(token.balanceOf(address(distributor)), 0);
    }

    function testClaimRevertsWhenNoRewardsToClaim() public {
        // Setup initial state
        vm.prank(address(infrared));
        distributor.add(pubkey1, validator1);
        infrared.addValidator(validator1);

        // Initial state - validator was just added, no rewards yet distributed
        (uint256 last1,) = distributor.snapshots(pubkey1);
        assertEq(last1, distributor.amountsCumulative());

        // Should revert since no new rewards to claim (amountCumulativeLast == fin)
        vm.prank(validator1);
        vm.expectRevert(Errors.NoRewardsToClaim.selector);
        distributor.claim(pubkey1, validator1);

        // Add some rewards and claim them
        vm.prank(user);
        distributor.notifyRewardAmount(10 ether);

        // Claim rewards first time - should succeed
        vm.prank(validator1);
        distributor.claim(pubkey1, validator1);

        // Try to claim again immediately - should revert
        vm.prank(validator1);
        vm.expectRevert(Errors.NoRewardsToClaim.selector);
        distributor.claim(pubkey1, validator1);

        // Add more rewards before removal
        vm.prank(user);
        distributor.notifyRewardAmount(10 ether);

        // Remove validator
        vm.prank(address(infrared));
        distributor.remove(pubkey1);

        // Can claim one last time after removal
        vm.prank(validator1);
        distributor.claim(pubkey1, validator1);

        // Should revert after claiming all final rewards
        vm.prank(validator1);
        vm.expectRevert(Errors.NoRewardsToClaim.selector);
        distributor.claim(pubkey1, validator1);
    }
}
