// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base, BribeVotingReward, ERC20, MockERC20} from "./Base.t.sol";
import {IVoter} from "src/voting/interfaces/IVoter.sol";
// import {assertApproxEq} from "forge-std/StdAssertions.sol";

contract VoterTest is Base {
    event WhitelistToken(
        address indexed whitelister, address indexed token, bool indexed _bool
    );
    event WhitelistNFT(
        address indexed whitelister, uint256 indexed tokenId, bool indexed _bool
    );
    event Voted(
        address indexed voter,
        address indexed stakingToken,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event Abstained(
        address indexed voter,
        address indexed stakingToken,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event NotifyReward(
        address indexed sender, address indexed reward, uint256 amount
    );
    event NoLongerWhitelistedTokenRemoved(address indexed token);

    // Note: _vote are not included in one-vote-per-epoch
    // Only vote() should be constrained as they must be called by the owner
    // Reset is not constrained as epochs are accrue and are distributed once per epoch
    // poke() can be called by anyone anytime to "refresh" an outdated vote state
    function testCannotChangeVoteInSameEpoch() public {
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];

        // create a lock for user1
        createLock(user1);

        // vote
        skipToNextEpoch(1 hours + 1);

        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        vm.startPrank(user1);
        voter.vote(1, _stakingTokens, weights);
        vm.stopPrank();

        // fwd half epoch
        skip(1 weeks / 2);

        // try voting again and fail
        _stakingTokens[0] = stakingTokens[1];
        vm.expectRevert(IVoter.AlreadyVotedOrDeposited.selector);
        voter.vote(1, _stakingTokens, weights);
    }

    function testCannotResetUntilAfterDistributeWindow() public {
        // create a lock for user1
        createLock(user1);

        vm.startPrank(user1);
        // vote
        skipToNextEpoch(1 hours + 1);
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];

        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, _stakingTokens, weights);

        skipToNextEpoch(0);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.reset(1);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.reset(1);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.reset(1);

        skip(1);
        voter.reset(1);

        vm.stopPrank();
    }

    function testCannotResetInSameEpoch() public {
        // create a lock for user1
        createLock(user1);

        vm.startPrank(user1);
        // vote
        skipToNextEpoch(1 hours + 1);
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(1, _stakingTokens, weights);

        // fwd half epoch
        skip(1 weeks / 2);

        // try resetting and fail
        vm.expectRevert(IVoter.AlreadyVotedOrDeposited.selector);
        voter.reset(1);

        vm.stopPrank();
    }

    function testCannotPokeUntilAfterDistributeWindow() public {
        // create a lock for user1
        uint256 tokenId = createLock(user1);

        vm.startPrank(user1);

        // vote
        skipToNextEpoch(1 hours + 1);
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        voter.vote(tokenId, _stakingTokens, weights);

        skipToNextEpoch(0);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.poke(tokenId);

        // successful poke one hour before epoch start
        skip(1);
        voter.poke(tokenId);
        vm.stopPrank();
    }

    function testPoke() public {
        // create a lock for user1
        uint256 tokenId = createLock(user1);

        vm.startPrank(user1);

        skipAndRoll(1 hours);

        voter.poke(tokenId);

        vm.stopPrank();

        assertFalse(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), 0);
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.usedWeights(tokenId), 0);
    }

    function testPokeAfterVote() public {
        skip(1 hours + 1);
        // create a lock for user1
        uint256 tokenId = createLock(user1);

        vm.startPrank(user1);

        // vote
        address[] memory _stakingTokens = new address[](2);
        _stakingTokens[0] = stakingTokens[0];
        _stakingTokens[1] = stakingTokens[1];
        address stakingToken = stakingTokens[0];
        address stakingToken2 = stakingTokens[1];
        uint256[] memory weights = new uint256[](2);
        weights[0] = 100;
        weights[1] = 200;

        /// balance: 997231719186530010
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken),
            1,
            332410573062176670,
            332410573062176670,
            block.timestamp
        );
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken2),
            1,
            664821146124353340,
            664821146124353340,
            block.timestamp
        );
        voter.vote(tokenId, _stakingTokens, weights);

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), block.timestamp);
        assertApproxEqAbs(voter.totalWeight(), TOKEN_1, 0.01e18);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertApproxEqAbs(
            voter.weights(address(stakingToken)), TOKEN_1 / 3, 0.01e18
        );
        assertEq(voter.weights(address(stakingToken)), 332410573062176670);
        assertApproxEqAbs(
            voter.weights(address(stakingToken2)), (TOKEN_1 / 3) * 2, 0.01e18
        );
        assertEq(voter.weights(address(stakingToken2)), 664821146124353340);
        assertEq(
            voter.votes(tokenId, address(stakingToken)), 332410573062176670
        );
        assertEq(
            voter.votes(tokenId, address(stakingToken2)), 664821146124353340
        );
        assertEq(voter.stakingTokenVote(tokenId, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId, 1), address(stakingToken2));

        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken),
            1,
            332410573062176670,
            332410573062176670,
            block.timestamp
        );
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken2),
            1,
            664821146124353340,
            664821146124353340,
            block.timestamp
        );
        voter.poke(1);

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), 608402);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(stakingToken)), 332410573062176670);
        assertEq(voter.weights(address(stakingToken2)), 664821146124353340);
        assertEq(
            voter.votes(tokenId, address(stakingToken)), 332410573062176670
        );
        assertEq(
            voter.votes(tokenId, address(stakingToken2)), 664821146124353340
        );
        assertEq(voter.stakingTokenVote(tokenId, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId, 1), address(stakingToken2));

        // balance: 996546787679762010
        skipAndRoll(1 days);
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken),
            1,
            332182262559920670,
            332182262559920670,
            block.timestamp
        );
        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken2),
            1,
            664364525119841340,
            664364525119841340,
            block.timestamp
        );
        voter.poke(1);

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), 608402);
        assertEq(voter.totalWeight(), 996546787679762010);
        assertEq(voter.usedWeights(tokenId), 996546787679762010);
        assertEq(voter.weights(address(stakingToken)), 332182262559920670);
        assertEq(voter.weights(address(stakingToken2)), 664364525119841340);
        assertEq(
            voter.votes(tokenId, address(stakingToken)), 332182262559920670
        );
        assertEq(
            voter.votes(tokenId, address(stakingToken2)), 664364525119841340
        );
        assertEq(voter.stakingTokenVote(tokenId, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId, 1), address(stakingToken2));

        vm.stopPrank();
    }

    function testPokeAfterVoteWithKilledBribe() public {
        testPokeAfterVote();

        skipAndRoll(1 days);

        voter.killBribeVault(stakingTokens[0]);

        vm.expectEmit(true, false, false, true, address(voter));
        emit IVoter.SkipKilledBribeVault(stakingTokens[0], 1);

        vm.expectEmit(true, false, false, true, address(voter));
        emit Voted(
            address(this), // third party is poking on behalf of user1
            stakingTokens[1],
            1, // tokenId1
            663907904115329340,
            663907904115329340,
            block.timestamp
        );
        voter.poke(1);
    }

    function testVoteAfterResetInSameEpoch() public {
        skip(1 weeks / 2);

        // create a lock for user1
        uint256 tokenId = createLock(user1);

        // point to bribeVault (gauge)
        address bribeVault = voter.bribeVaults(stakingTokens[0]);
        // add rewards for stakingToken
        ERC20(stakingTokens[0]).approve(bribeVault, TOKEN_1);
        BribeVotingReward(bribeVault).notifyRewardAmount(
            stakingTokens[0], TOKEN_1
        );

        vm.startPrank(user1);
        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        voter.vote(1, _stakingTokens, weights);

        skipToNextEpoch(1 hours + 1);

        // assert reward tokens are fully distributed
        assertEq(
            BribeVotingReward(bribeVault).earned(_stakingTokens[0], tokenId),
            TOKEN_1
        );

        voter.reset(tokenId);

        vm.stopPrank();

        skip(1 days);

        // add rewards for stakingToken2
        address bribeVault2 = voter.bribeVaults(stakingTokens[1]);

        ERC20(stakingTokens[1]).approve(bribeVault2, TOKEN_1);
        BribeVotingReward(bribeVault2).notifyRewardAmount(
            stakingTokens[1], TOKEN_1
        );

        // vote again after reset
        vm.startPrank(user1);

        _stakingTokens[0] = stakingTokens[1];
        voter.vote(1, _stakingTokens, weights);

        skipToNextEpoch(1);

        // rewards only occur for stakingToken2, not stakingToken
        assertEq(
            BribeVotingReward(bribeVault).earned(stakingTokens[0], tokenId),
            TOKEN_1
        );
        assertEq(
            BribeVotingReward(bribeVault2).earned(stakingTokens[1], tokenId),
            TOKEN_1
        );
    }

    function testVote() public {
        skip(1 hours + 1);

        uint256 tokenId = createLock(user1);

        // vote
        // vote
        address[] memory _stakingTokens = new address[](2);
        _stakingTokens[0] = stakingTokens[0];
        _stakingTokens[1] = stakingTokens[1];
        address stakingToken = stakingTokens[0];
        address stakingToken2 = stakingTokens[1];
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 2;

        vm.startPrank(user1);
        /// balance: 997231719186530010
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken),
            1,
            332410573062176670,
            332410573062176670,
            block.timestamp
        );
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken2),
            1,
            664821146124353340,
            664821146124353340,
            block.timestamp
        );
        voter.vote(tokenId, _stakingTokens, weights);

        vm.stopPrank();

        assertTrue(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), block.timestamp);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(stakingToken)), 332410573062176670);
        assertEq(voter.weights(address(stakingToken2)), 664821146124353340);
        assertEq(
            voter.votes(tokenId, address(stakingToken)), 332410573062176670
        );
        assertEq(
            voter.votes(tokenId, address(stakingToken2)), 664821146124353340
        );
        assertEq(voter.stakingTokenVote(tokenId, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId, 1), address(stakingToken2));

        // create lock for user2
        uint256 tokenId2 = createLock(user2);

        vm.startPrank(user2);
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user2,
            address(stakingToken),
            tokenId2,
            332410573062176670,
            664821146124353340,
            block.timestamp
        );
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user2,
            address(stakingToken2),
            tokenId2,
            664821146124353340,
            1329642292248706680,
            block.timestamp
        );
        voter.vote(tokenId2, _stakingTokens, weights);
        vm.stopPrank();

        assertTrue(escrow.voted(tokenId2));
        assertEq(voter.lastVoted(tokenId2), block.timestamp);
        assertEq(voter.totalWeight(), 1994463438373060020);
        assertEq(voter.usedWeights(tokenId2), 997231719186530010);
        assertEq(voter.weights(address(stakingToken)), 664821146124353340);
        assertEq(voter.weights(address(stakingToken2)), 1329642292248706680);
        assertEq(
            voter.votes(tokenId2, address(stakingToken)), 332410573062176670
        );
        assertEq(
            voter.votes(tokenId2, address(stakingToken2)), 664821146124353340
        );
        assertEq(voter.stakingTokenVote(tokenId2, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId2, 1), address(stakingToken2));
    }

    function testRewardsAccuralForMultipleEpochsWithoutPoke() public {
        skip(1 weeks / 2);

        // create a lock for user1
        uint256 tokenId = createLock(user1);

        // point to bribeVault (gauge)
        address bribeVault = voter.bribeVaults(stakingTokens[0]);
        // add rewards for stakingToken
        ERC20(stakingTokens[0]).approve(bribeVault, TOKEN_1);
        BribeVotingReward(bribeVault).notifyRewardAmount(
            stakingTokens[0], TOKEN_1
        );

        vm.startPrank(user1);
        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        voter.vote(1, _stakingTokens, weights);

        vm.stopPrank();

        skipToNextEpoch(1 hours + 1);

        skip(1 days);

        // add rewards for stakingToken2
        ERC20(stakingTokens[0]).approve(bribeVault, TOKEN_1);
        BribeVotingReward(bribeVault).notifyRewardAmount(
            stakingTokens[0], TOKEN_1
        );

        skipToNextEpoch(1);

        // rewards only occur for stakingToken2, not stakingToken
        assertEq(
            BribeVotingReward(bribeVault).earned(stakingTokens[0], tokenId),
            TOKEN_1 * 2
        );

        voter.getStakingTokenWeights();
    }

    function testRedistributeRewardsFromNonDepositedVaults() public {
        skip(1 weeks / 2);

        // create a lock for user1
        uint256 tokenId = createLock(user1);
        // Add rewards to two stakingTokens

        address bribeVault = voter.bribeVaults(stakingTokens[0]);
        // add rewards for stakingToken
        ERC20(stakingTokens[0]).approve(bribeVault, TOKEN_1);
        BribeVotingReward(bribeVault).notifyRewardAmount(
            stakingTokens[0], TOKEN_1
        );

        address bribeVault2 = voter.bribeVaults(stakingTokens[1]);
        // add rewards for stakingToken
        ERC20(stakingTokens[1]).approve(bribeVault2, TOKEN_1);
        BribeVotingReward(bribeVault2).notifyRewardAmount(
            stakingTokens[1], TOKEN_1
        );

        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[1];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        // change vote to not vote for  stakingTokens[1] instead of stakingTokens[0]
        vm.prank(user1);
        voter.vote(1, _stakingTokens, weights);

        skipToNextEpoch(1 hours + 1);

        // rewards only occur for stakingToken2, not stakingToken
        assertEq(
            BribeVotingReward(bribeVault).earned(stakingTokens[0], tokenId), 0
        );
        assertEq(
            BribeVotingReward(bribeVault2).earned(stakingTokens[1], tokenId),
            TOKEN_1
        );

        // redistribute rewards
        BribeVotingReward(bribeVault).renotifyRewardAmount(
            block.timestamp - (1 weeks + 1 hours), stakingTokens[0]
        );

        // change user vote back to stakingTokens[0]
        _stakingTokens[0] = stakingTokens[0];

        vm.prank(user1);
        voter.vote(1, _stakingTokens, weights);

        skipToNextEpoch(1 hours + 1);

        // rewards from previous epoch should be redistributed
        assertEq(
            BribeVotingReward(bribeVault).earned(stakingTokens[0], tokenId),
            TOKEN_1
        );
        assertEq(
            BribeVotingReward(bribeVault2).earned(stakingTokens[1], tokenId),
            TOKEN_1
        );
    }

    function testReset() public {
        uint256 tokenId = createLock(user1);
        skipAndRoll(1 hours + 1);

        vm.startPrank(user1);

        voter.reset(tokenId);

        assertFalse(escrow.voted(tokenId));
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.usedWeights(tokenId), 0);
        vm.expectRevert();
        voter.stakingTokenVote(tokenId, 0);
    }

    function testResetAfterVote() public {
        skipAndRoll(1 hours + 1);
        uint256 tokenId = createLock(user1);

        uint256 tokenId2 = createLock(user2);

        // vote

        // vote
        address[] memory _stakingTokens = new address[](2);
        _stakingTokens[0] = stakingTokens[0];
        _stakingTokens[1] = stakingTokens[1];
        address stakingToken = stakingTokens[0];
        address stakingToken2 = stakingTokens[1];
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 2;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken),
            1,
            332410573062176670,
            332410573062176670,
            block.timestamp
        );
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user1,
            address(stakingToken2),
            1,
            664821146124353340,
            664821146124353340,
            block.timestamp
        );
        voter.vote(tokenId, _stakingTokens, weights);
        vm.prank(user2);
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user2,
            address(stakingToken),
            2,
            332410573062176670,
            664821146124353340,
            block.timestamp
        );
        vm.expectEmit(true, true, false, true, address(voter));
        emit Voted(
            user2,
            address(stakingToken2),
            2,
            664821146124353340,
            1329642292248706680,
            block.timestamp
        );
        voter.vote(tokenId2, _stakingTokens, weights);

        assertEq(voter.totalWeight(), 1994463438373060020);
        assertEq(voter.usedWeights(tokenId), 997231719186530010);
        assertEq(voter.weights(address(stakingToken)), 664821146124353340);
        assertEq(voter.weights(address(stakingToken2)), 1329642292248706680);
        assertEq(
            voter.votes(tokenId, address(stakingToken)), 332410573062176670
        );
        assertEq(
            voter.votes(tokenId, address(stakingToken2)), 664821146124353340
        );
        assertEq(voter.stakingTokenVote(tokenId, 0), address(stakingToken));
        assertEq(voter.stakingTokenVote(tokenId, 1), address(stakingToken2));

        uint256 lastVoted = voter.lastVoted(tokenId);
        skipToNextEpoch(1 hours + 1);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(voter));
        emit Abstained(
            user1,
            address(stakingToken),
            1,
            332410573062176670,
            332410573062176670,
            block.timestamp
        );
        vm.expectEmit(true, true, false, true, address(voter));
        emit Abstained(
            user1,
            address(stakingToken2),
            1,
            664821146124353340,
            664821146124353340,
            block.timestamp
        );
        voter.reset(tokenId);

        assertFalse(escrow.voted(tokenId));
        assertEq(voter.lastVoted(tokenId), lastVoted);
        assertEq(voter.totalWeight(), 997231719186530010);
        assertEq(voter.usedWeights(tokenId), 0);
        assertEq(voter.weights(address(stakingToken)), 332410573062176670);
        assertEq(voter.weights(address(stakingToken2)), 664821146124353340);
        assertEq(voter.votes(tokenId, address(stakingToken)), 0);
        assertEq(voter.votes(tokenId, address(stakingToken2)), 0);
        vm.expectRevert();
        voter.stakingTokenVote(tokenId, 0);
    }

    function testResetAfterVoteOnKilledBribeVault() public {
        skipAndRoll(1 hours + 1);
        uint256 tokenId = createLock(user1);

        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        vm.prank(user1);
        voter.vote(tokenId, _stakingTokens, weights);

        // kill the bribeVault voted for (address this == governor)
        voter.killBribeVault(_stakingTokens[0]);

        // skip to the next epoch to be able to reset - no revert
        skipToNextEpoch(1 hours + 1);
        vm.prank(user1);
        voter.reset(tokenId);
    }

    function testCannotVoteWithInactiveManagedNFT() public {
        // address this == governor
        uint256 mTokenId = escrow.createManagedLockFor(address(this));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        skipAndRoll(1 hours);

        vm.expectRevert(IVoter.InactiveManagedNFT.selector);
        voter.vote(mTokenId, _stakingTokens, weights);
    }

    function testCannotVoteUntilAnHourAfterEpochFlips() public {
        createLock(user1);

        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        vm.startPrank(user1);
        skipToNextEpoch(0);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.vote(1, _stakingTokens, weights);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.vote(1, _stakingTokens, weights);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.vote(1, _stakingTokens, weights);

        skip(1);
        voter.vote(1, _stakingTokens, weights);
        vm.stopPrank();
    }

    function testCannotVoteAnHourBeforeEpochFlips() public {
        skipToNextEpoch(0);

        uint256 tokenId = createLock(user1);

        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        vm.prank(user1);
        skip(7 days - 1 hours);
        uint256 sid = vm.snapshot();
        voter.vote(tokenId, _stakingTokens, weights);

        vm.prank(user1);
        vm.revertTo(sid);
        skip(1);
        vm.expectRevert(IVoter.NotWhitelistedNFT.selector);
        voter.vote(tokenId, _stakingTokens, weights);

        vm.prank(user1);
        skip(1 hours - 2);
        /// one second prior to epoch flip
        vm.expectRevert(IVoter.NotWhitelistedNFT.selector);
        voter.vote(tokenId, _stakingTokens, weights);

        // address this == governor
        voter.whitelistNFT(tokenId, true);
        vm.prank(user1);
        voter.vote(tokenId, _stakingTokens, weights);

        vm.prank(user1);
        skipToNextEpoch(1 hours + 1);
        /// new epoch
        voter.vote(tokenId, _stakingTokens, weights);
    }

    function testCannotVoteForKilledBribeVault() public {
        skipToNextEpoch(60 minutes + 1);

        uint256 tokenId = createLock(user1);
        // vote
        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        // kill the gauge voted for
        // address this == governor
        voter.killBribeVault(_stakingTokens[0]);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVoter.BribeVaultNotAlive.selector,
                voter.bribeVaults(_stakingTokens[0])
            )
        );
        vm.prank(user1);
        voter.vote(tokenId, _stakingTokens, weights);
    }

    function testCannotCreateBribeVaultIfStakingTokenNotRegisteredOnInfrared()
        public
    {
        vm.expectRevert(IVoter.VaultNotRegistered.selector);
        vm.prank(keeper);
        voter.createBribeVault(address(0), stakingTokens);
    }

    function testCannotCreateBribeVaultIfBribeVaultAlreadyExists() public {
        vm.expectRevert(IVoter.BribeVaultExists.selector);
        vm.prank(keeper);
        voter.createBribeVault(stakingTokens[0], stakingTokens);
    }

    function testCannotCreateBribeVaultIfRewardTokenNotWhiteListed() public {
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = stakingTokens[0];
        _rewardTokens[1] = address(1);

        // register new infrared Vault that has not have bribe market created yet
        address bribeRewardToken3 =
            address(new MockERC20("BribeRewardToken3", "BRT3", 18));

        vm.startPrank(keeper);
        infrared.registerVault(bribeRewardToken3);

        vm.expectRevert(IVoter.NotWhitelistedToken.selector);
        voter.createBribeVault(bribeRewardToken3, _rewardTokens);
        vm.stopPrank();
    }

    function testCannotVoteForBribeVaultThatDoesNotExist() public {
        skipToNextEpoch(60 minutes + 1);

        uint256 tokenId = createLock(user1);

        // vote
        address[] memory _stakingTokens = new address[](1);
        address fakeStakingToken = address(123456);
        _stakingTokens[0] = fakeStakingToken;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVoter.BribeVaultDoesNotExist.selector, fakeStakingToken
            )
        );
        vm.prank(user1);
        voter.vote(tokenId, _stakingTokens, weights);
    }

    function testCannotSetMaxVotingNumIfNotGovernor() public {
        vm.prank(user2);
        vm.expectRevert();
        voter.setMaxVotingNum(42);
    }

    function testCannotSetMaxVotingNumToSameNum() public {
        uint256 maxVotingNum = voter.maxVotingNum();
        // address this == governor
        vm.expectRevert(IVoter.SameValue.selector);
        voter.setMaxVotingNum(maxVotingNum);
    }

    function testCannotSetMaxVotingNumBelow10() public {
        // address this == governor
        vm.expectRevert(IVoter.MaximumVotingNumberTooLow.selector);
        voter.setMaxVotingNum(0);
    }

    function testSetMaxVotingNum() public {
        assertEq(voter.maxVotingNum(), 30);
        // address this == governor
        voter.setMaxVotingNum(10);
        assertEq(voter.maxVotingNum(), 10);
    }

    function testSetGovernor() public {
        voter.grantRole(voter.GOVERNANCE_ROLE(), user2);

        vm.prank(user2);
        voter.setMaxVotingNum(10);
    }

    function testCannotwhitelistNFTIfNotGovernor() public {
        vm.prank(user2);
        vm.expectRevert();
        voter.whitelistNFT(1, true);
    }

    function testwhitelistNFTWithTrueExpectWhitelisted() public {
        assertFalse(voter.isWhitelistedNFT(1));

        // address this == governor
        vm.expectEmit(true, true, true, true, address(voter));
        emit WhitelistNFT(address(this), 1, true);
        voter.whitelistNFT(1, true);

        assertTrue(voter.isWhitelistedNFT(1));
    }

    function testwhitelistNFTWithFalseExpectUnwhitelisted() public {
        assertFalse(voter.isWhitelistedNFT(1));

        // address this == governor
        voter.whitelistNFT(1, true);

        assertTrue(voter.isWhitelistedNFT(1));

        vm.expectEmit(true, true, true, true, address(voter));
        emit WhitelistNFT(address(this), 1, false);
        voter.whitelistNFT(1, false);

        assertFalse(voter.isWhitelistedNFT(1));
    }

    function testKillBribeVault() public {
        // address this == governor
        voter.killBribeVault(stakingTokens[0]);
        assertFalse(voter.isAlive(stakingTokens[0]));
    }

    function testRemoveNoLongerWhitelistedTokensFromBribeVault() public {
        infrared.updateWhiteListedRewardTokens(stakingTokens[0], false);

        address[] memory noLongerWhitelistedTokens = new address[](1);
        noLongerWhitelistedTokens[0] = stakingTokens[0];

        BribeVotingReward bribeVault1 =
            BribeVotingReward(voter.bribeVaults(stakingTokens[0]));
        BribeVotingReward bribeVault2 =
            BribeVotingReward(voter.bribeVaults(stakingTokens[1]));

        assertTrue(bribeVault1.isReward(stakingTokens[0]));
        uint256 rl1 = bribeVault1.rewardsListLength();
        assertEq(rl1, 2);

        assertTrue(bribeVault2.isReward(stakingTokens[0]));
        uint256 rl2 = bribeVault2.rewardsListLength();
        assertEq(rl2, 2);

        vm.expectEmit();
        emit NoLongerWhitelistedTokenRemoved(noLongerWhitelistedTokens[0]);

        bribeVault1.removeNoLongerWhitelistedTokens(noLongerWhitelistedTokens);

        vm.expectEmit();
        emit NoLongerWhitelistedTokenRemoved(noLongerWhitelistedTokens[0]);

        bribeVault2.removeNoLongerWhitelistedTokens(noLongerWhitelistedTokens);

        assertFalse(bribeVault1.isReward(stakingTokens[0]));
        rl1 = bribeVault1.rewardsListLength();
        assertEq(rl1, 1);

        assertFalse(bribeVault2.isReward(stakingTokens[0]));
        rl2 = bribeVault2.rewardsListLength();
        assertEq(rl2, 1);
    }

    function testCannotKillBribeVaultIfAlreadyKilled() public {
        // address this == governor
        voter.killBribeVault(stakingTokens[0]);
        assertFalse(voter.isAlive(stakingTokens[0]));

        vm.expectRevert(IVoter.BribeVaultAlreadyKilled.selector);
        voter.killBribeVault(stakingTokens[0]);
    }

    function testReviveBribeVault() public {
        voter.killBribeVault(stakingTokens[0]);
        assertFalse(voter.isAlive(stakingTokens[0]));

        voter.reviveBribeVault(stakingTokens[0]);
        assertTrue(voter.isAlive(stakingTokens[0]));
    }

    function testCannotReviveBribeVaultIfAlreadyAlive() public {
        assertTrue(voter.isAlive(stakingTokens[0]));

        vm.expectRevert(IVoter.BribeVaultAlreadyRevived.selector);
        voter.reviveBribeVault(stakingTokens[0]);
    }

    function testCannotKillNonExistentBribeVault() public {
        vm.expectRevert(IVoter.BribeVaultAlreadyKilled.selector);
        voter.killBribeVault(address(0xDEAD));
    }

    function testCannotKillBribeVaultIfNotGovernor() public {
        vm.expectRevert();
        vm.prank(user2);
        voter.killBribeVault(stakingTokens[0]);
    }
}
