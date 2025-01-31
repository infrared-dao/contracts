// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Base.t.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {
    IERC721,
    IERC721Metadata
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract VotingEscrowTest is Base {
    event DelegateChanged(
        address indexed delegator,
        uint256 indexed fromDelegate,
        uint256 indexed toDelegate
    );
    event LockPermanent(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 amount,
        uint256 _ts
    );
    event UnlockPermanent(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 amount,
        uint256 _ts
    );
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );
    event MetadataUpdate(uint256 _tokenId);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 indexed epoch,
        uint256 amount
    );
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );

    function testInitialState() public view {
        assertEq(escrow.allowedManager(), address(keeper));
        // voter should already have been setup
        assertEq(escrow.voter(), address(voter));
    }

    function testSupportInterfaces() public view {
        assertTrue(escrow.supportsInterface(type(IERC165).interfaceId));
        assertTrue(escrow.supportsInterface(type(IERC721).interfaceId));
        assertTrue(escrow.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(escrow.supportsInterface(0x49064906)); // 4906 is events only, so uses a custom interface id
        assertTrue(escrow.supportsInterface(type(IERC6372).interfaceId));
    }

    function testCreateLock() public {
        vm.startPrank(user1);
        ir.mint(user1, 1e25);
        ir.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(user1), 0);
        uint256 tokenId = escrow.createLock(1e25, lockDuration);
        assertEq(escrow.ownerOf(tokenId), user1);
        assertEq(escrow.balanceOf(user1), 1);
        assertEq(
            uint256(escrow.escrowType(tokenId)),
            uint256(IVotingEscrow.EscrowType.NORMAL)
        );
        assertEq(escrow.numCheckpoints(tokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user1, tokenId, block.timestamp),
            47945126204972095225334
        );
        assertEq(escrow.balanceOfNFT(tokenId), 47945126204972095225334);
        vm.stopPrank();
    }

    function testCreateLockOutsideAllowedZones() public {
        ir.approve(address(escrow), 1e25);
        vm.expectRevert(IVotingEscrow.LockDurationTooLong.selector);
        escrow.createLock(1e25, MAXTIME + 1 weeks);
    }

    function testIncreaseAmount() public {
        uint256 tokenId = createLock(user1);

        vm.startPrank(user1);
        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        ir.mint(user1, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.increaseAmount(tokenId, TOKEN_1);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        assertEq(
            uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end))
        );
        assertEq(
            uint256(uint128(postLocked.amount))
                - uint256(uint128(preLocked.amount)),
            TOKEN_1
        );
    }

    function testIncreaseUnlockTime() public {
        vm.startPrank(user1);
        ir.mint(user1, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 weeks);

        skip((1 weeks) / 2);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        uint256 expectedLockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        assertEq(uint256(uint128(postLocked.end)), expectedLockTime);
        assertEq(
            uint256(uint128(postLocked.amount)),
            uint256(uint128(preLocked.amount))
        );
    }

    function testIncreaseAmountWithNormalLock() public {
        // timestamp: 604801
        uint256 tokenId = createLock(user1);

        skipAndRoll(1);

        vm.startPrank(user1);
        ir.mint(user1, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 1994520516124422418); // (TOKEN_1 * 2 / MAXTIME) * (126403200 - 604802)
        assertEq(convert(userPoint.slope), 15854895991); // TOKEN_1 * 2 / MAXTIME
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 1994520516124422418);
        assertEq(convert(globalPoint.slope), 15854895991);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.supply(), TOKEN_1 * 2);
        assertEq(escrow.slopeChanges(126403200), -15854895991);
    }

    function testDepositFor() public {
        uint256 tokenId = createLock(user1);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        // address (this) will deposit for user1 (add balance to NFT)
        ir.approve(address(escrow), TOKEN_1);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.depositFor(tokenId, TOKEN_1);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        assertEq(
            uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end))
        );
        assertEq(
            uint256(uint128(postLocked.amount))
                - uint256(uint128(preLocked.amount)),
            TOKEN_1
        );
    }

    function testIncreaseAmountWithPermanentLock() public {
        uint256 tokenId = createLock(user1);

        vm.startPrank(user1);
        escrow.lockPermanent(tokenId);

        skipAndRoll(1);

        ir.mint(user1, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);
        assertEq(escrow.supply(), TOKEN_1 * 2);

        // no delegation checkpoint created
        assertEq(escrow.numCheckpoints(tokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(user1, tokenId, 604802), TOKEN_1 * 2);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 2);
        assertEq(escrow.totalSupply(), TOKEN_1 * 2);
    }

    function testIncreaseAmountWithDelegatedPermanentLock() public {
        uint256 tokenId = createLock(user1);
        vm.prank(user1);
        escrow.lockPermanent(tokenId);
        vm.startPrank(user2);
        ir.mint(user2, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        skipAndRoll(1);
        // delegate user1's locked NFT to user2
        vm.prank(user1);
        escrow.delegate(tokenId, tokenId2);

        // check delegation checkpoint created for delegator
        assertEq(escrow.delegates(tokenId), tokenId2);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);
        assertEq(escrow.getPastVotes(user1, tokenId, 604802), 0);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 1);

        skipAndRoll(1);
        vm.startPrank(user1);
        ir.mint(user1, TOKEN_1);
        ir.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);
        vm.stopPrank();

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(globalPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);

        // no new checkpoints for delegator as nothing changes delegation-wise
        assertEq(escrow.delegates(tokenId), tokenId2);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        checkpoint = escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);
        assertEq(escrow.getPastVotes(user1, tokenId, 604803), 0);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 2);

        // delegatee balance updates
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 2);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604803),
            TOKEN_1 * 2 + 997260250071864015
        );
        assertEq(escrow.balanceOfNFT(tokenId2), 997260250071864015);
        assertEq(escrow.totalSupply(), TOKEN_1 * 2 + 997260250071864015);
        assertEq(escrow.supply(), TOKEN_1 * 3);
    }

    function testCannotIncreaseUnlockTimeWithPermanentLock() public {
        uint256 tokenId = createLock(user1);
        vm.startPrank(user1);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
    }

    function testCannotDepositForWithLockedNFT() public {
        skipAndRoll(1 hours);
        // address governor == address(this);
        uint256 mTokenId = escrow.createManagedLockFor(user2);

        uint256 tokenId = createLock(user1);

        vm.prank(user1);
        voter.depositManaged(tokenId, mTokenId);
        assertEq(
            uint256(escrow.escrowType(tokenId)),
            uint256(IVotingEscrow.EscrowType.LOCKED)
        );

        vm.expectRevert(IVotingEscrow.NotManagedOrNormalNFT.selector);
        escrow.depositFor(tokenId, TOKEN_1);
    }

    // function testCannotDepositForWithManagedNFTIfNotDistributor() public {
    //     skipAndRoll(1);
    //     // call from governor == address(this)
    //     uint256 mTokenId = escrow.createManagedLockFor(manager);

    //     vm.startPrank(manager);
    //     uint256 tokenId = createLock(user1);
    //     voter.depositManaged(tokenId, mTokenId);

    //     vm.expectRevert(IVotingEscrow.NotDistributor.selector);
    //     escrow.depositFor(mTokenId, TOKEN_1);
    // }

    // function testDepositForWithManagedNFT() public {
    //     skipAndRoll(1 hours);
    //     uint256 reward = TOKEN_1;
    //     uint256 mTokenId = escrow.createManagedLockFor(user2);
    //     LockedManagedReward lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
    //     assertEq(VELO.allowance(address(escrow), address(lockedManagedReward)), 0);

    //     VELO.approve(address(escrow), TOKEN_1);
    //     uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
    //     voter.depositManaged(tokenId, mTokenId);
    //     deal(address(VELO), address(distributor), TOKEN_1);

    //     uint256 pre = VELO.balanceOf(address(lockedManagedReward));
    //     IVotingEscrow.LockedBalance memory preLocked = escrow.locked(mTokenId);
    //     vm.prank(address(distributor));
    //     vm.expectEmit(true, true, true, true, address(lockedManagedReward));
    //     emit NotifyReward(address(escrow), address(VELO), 604800, reward);
    //     vm.expectEmit(false, false, false, true, address(escrow));
    //     emit MetadataUpdate(mTokenId);
    //     escrow.depositFor(mTokenId, reward);
    //     uint256 post = VELO.balanceOf(address(lockedManagedReward));
    //     IVotingEscrow.LockedBalance memory postLocked = escrow.locked(mTokenId);

    //     assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
    //     assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), reward);
    //     assertEq(post - pre, reward);
    //     assertEq(VELO.allowance(address(escrow), address(lockedManagedReward)), 0);
    // }

    // function testCannotIncreaseUnlockTimeWithManagedNFT() public {
    //     skip(1 hours);
    //     uint256 mTokenId = escrow.createManagedLockFor(user2);

    //     VELO.approve(address(escrow), TOKEN_1);
    //     uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

    //     voter.depositManaged(tokenId, mTokenId);
    //     skipAndRoll(1);

    //     vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
    //     escrow.increaseUnlockTime(tokenId, MAXTIME);
    // }

    function testTransferFrom() public {
        uint256 tokenId = createLock(user1);
        skipAndRoll(1);

        // check tokenId checkpoint
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        vm.prank(user1);
        escrow.transferFrom(user1, user2, tokenId);

        assertEq(escrow.balanceOf(user1), 0);
        // assertEq(escrow.ownerToNFTokenIdList(user1, 0), 0);
        assertEq(escrow.ownerOf(tokenId), user2);
        assertEq(escrow.balanceOf(user2), 1);
        // assertEq(escrow.ownerToNFTokenIdList(user2, 0), tokenId);

        // check new checkpoint created for tokenId with updated owner
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        checkpoint = escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // flash protection
        assertEq(escrow.balanceOfNFT(tokenId), 0);
    }

    function testWithdraw() public {
        deal(address(ir), user1, TOKEN_1);
        vm.startPrank(user1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        ir.approve(address(escrow), TOKEN_1);

        uint256 tokenId = escrow.createLock(TOKEN_1, lockDuration);
        uint256 preBalance = ir.balanceOf(user1);
        skipAndRoll(lockDuration);

        escrow.withdraw(tokenId);
        vm.stopPrank();

        uint256 postBalance = ir.balanceOf(user1);
        assertEq(postBalance - preBalance, TOKEN_1);
        assertEq(escrow.ownerOf(tokenId), address(0));
        assertEq(escrow.balanceOf(user1), 0);
        // assertEq(escrow.ownerToNFTokenIdList(user1, 0), 0);

        // check voting checkpoint created on burn updating owner
        assertEq(escrow.delegates(tokenId), 0);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 1209601);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(user1, tokenId, block.timestamp), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
    }

    function testCannotWithdrawBeforeLockExpired() public {
        deal(address(ir), user1, TOKEN_1);
        vm.startPrank(user1);
        ir.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        uint256 tokenId = escrow.createLock(TOKEN_1, lockDuration);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.LockNotExpired.selector);
        escrow.withdraw(tokenId);
    }

    function testCannotWithdrawPermanentLock() public {
        deal(address(ir), user1, TOKEN_1);
        vm.startPrank(user1);
        ir.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.withdraw(tokenId);
    }

    function testLockPermanent() public {
        // timestamp: 604801
        uint256 tokenId = createLock(user1);
        assertEq(escrow.locked(tokenId).end, 126403200);
        assertEq(escrow.slopeChanges(0), 0);
        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope is negative after lock creation

        skipAndRoll(1);

        vm.startPrank(user1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit LockPermanent(user1, tokenId, TOKEN_1, 604802);
        escrow.lockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        assertEq(escrow.slopeChanges(0), 0);
        assertEq(escrow.slopeChanges(126403200), 0); // no contribution to global slope
        assertEq(escrow.permanentLockBalance(), TOKEN_1);
    }

    function testCannotUnlockPermanentIfNotApprovedOrOwner() public {
        uint256 tokenId = createLock(user1);
        vm.startPrank(user1);
        escrow.lockPermanent(tokenId);
        vm.stopPrank();
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        vm.prank(user2);
        escrow.unlockPermanent(tokenId);
    }

    function testCannotUnlockPermanentIfNotPermanentlyLocked() public {
        uint256 tokenId = createLock(user1);
        skipAndRoll(1);
        vm.startPrank(user1);
        vm.expectRevert(IVotingEscrow.NotPermanentLock.selector);
        escrow.unlockPermanent(tokenId);
    }

    function testCannotUnlockPermanentIfManagedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(user1);
        skipAndRoll(1);

        vm.startPrank(user1);
        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.unlockPermanent(mTokenId);
    }

    function testCannotUnlockPermanentIfLockedNFT() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(user1);

        uint256 tokenId = createLock(user1);
        vm.startPrank(user1);
        voter.depositManaged(tokenId, mTokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.unlockPermanent(mTokenId);
    }

    function testCannotUnlockPermanentIfVoted() public {
        uint256 tokenId = createLock(user1);
        vm.startPrank(user1);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1 hours);

        address[] memory _stakingTokens = new address[](1);
        _stakingTokens[0] = stakingTokens[0];
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, _stakingTokens, weights);

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.AlreadyVoted.selector);
        escrow.unlockPermanent(tokenId);
    }

    function testUnlockPermanent() public {
        // timestamp: 604801
        uint256 tokenId = createLock(user1);
        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope is negative after lock creation
        assertEq(escrow.numCheckpoints(tokenId), 1);

        skipAndRoll(1);

        vm.startPrank(user1);

        escrow.lockPermanent(tokenId);
        assertEq(escrow.slopeChanges(126403200), 0); // slope zero on permanent lock

        skipAndRoll(1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit UnlockPermanent(user1, tokenId, TOKEN_1, 604803);
        escrow.unlockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 3);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 3);
        assertEq(convert(userPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 997260250071864015);
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope restored
        assertEq(escrow.permanentLockBalance(), 0);
        assertEq(escrow.numCheckpoints(tokenId), 1);
    }

    function testUnlockPermanentWithDelegate() public {
        // timestamp: 604801
        uint256 tokenId = createLock(user1);
        uint256 tokenId2 = createLock(user2);
        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2); // slope is negative after lock creation

        skipAndRoll(1);

        vm.startPrank(user1);
        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, tokenId2);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        skipAndRoll(1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit UnlockPermanent(user1, tokenId, TOKEN_1, 604803);
        escrow.unlockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 3);
        IVotingEscrow.UserPoint memory userPoint =
            escrow.userPointHistory(tokenId, 3);
        assertEq(convert(userPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 997260250071864015 * 2); // contribution from tokenId and tokenId2
        assertEq(convert(globalPoint.slope), 7927447995 * 2);
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2);
        assertEq(escrow.permanentLockBalance(), 0);

        // check tokenId dedelegates from tokenId2
        assertEq(escrow.delegates(tokenId), 0);
        assertEq(escrow.numCheckpoints(tokenId), 3);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check tokenId2 delegated balance is updated
        assertEq(escrow.delegates(tokenId2), 0);
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
    }

    function testDelegate() public {
        // timestamp: 604801
        uint256 tokenId1 = createLock(user1);
        uint256 tokenId2 = createLock(user2);
        uint256 tokenId3 = createLock(user3);
        skipAndRoll(1);

        vm.startPrank(user1);

        escrow.lockPermanent(tokenId1);

        // delegate 1 => 2
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(user1, 0, tokenId2);
        escrow.delegate(tokenId1, tokenId2);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 0 => 2
        assertEq(escrow.delegates(tokenId1), 2);
        assertEq(escrow.numCheckpoints(tokenId1), 2);
        IVotingEscrow.Checkpoint memory checkpoint =
            escrow.checkpoints(tokenId1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(tokenId1, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);
        assertEq(escrow.getPastVotes(user1, tokenId1, 604802), 0);
        assertEq(escrow.balanceOfNFT(tokenId1), TOKEN_1);

        // check prior and new checkpoint for tokenId 2
        // expect delegatedBalance 0 => TOKEN_1
        assertEq(escrow.delegates(tokenId2), 0);
        assertEq(escrow.numCheckpoints(tokenId2), 2);
        checkpoint = escrow.checkpoints(tokenId2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(tokenId2, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604802),
            TOKEN_1 + 997260257999312010
        );
        assertEq(escrow.balanceOfNFT(tokenId2), 997260257999312010);
        skipAndRoll(1);

        // delegate 1 => 3
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(user1, tokenId2, tokenId3);
        escrow.delegate(tokenId1, tokenId3);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 2 => 3
        assertEq(escrow.delegates(tokenId1), tokenId3);
        assertEq(escrow.numCheckpoints(tokenId1), 3);
        checkpoint = escrow.checkpoints(tokenId1, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);
        checkpoint = escrow.checkpoints(tokenId1, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId3);
        assertEq(escrow.getPastVotes(user1, tokenId1, 604803), 0);
        assertEq(escrow.balanceOfNFT(tokenId1), TOKEN_1);

        // check prior and new checkpoint for tokenId 2
        // expect delegatedBalance TOKEN_1 => 0
        assertEq(escrow.delegates(tokenId2), 0);
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604803), 997260250071864015
        );
        assertEq(escrow.balanceOfNFT(tokenId2), 997260250071864015);

        // check prior and new checkpoint for tokenId 3
        // expect delegatedBalance 0 => TOKEN_1
        assertEq(escrow.delegates(tokenId3), 0);
        assertEq(escrow.numCheckpoints(tokenId3), 2);
        checkpoint = escrow.checkpoints(tokenId3, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, user3);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(tokenId3, 1);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user3);
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604803),
            TOKEN_1 + 997260250071864015
        );
        assertEq(escrow.balanceOfNFT(tokenId3), 997260250071864015);
        skipAndRoll(1);

        // delegate 1 => 1
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(user1, tokenId3, 0);
        escrow.delegate(tokenId1, tokenId1);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 3 => 0
        assertEq(escrow.delegates(tokenId1), 0);
        assertEq(escrow.numCheckpoints(tokenId1), 4);
        checkpoint = escrow.checkpoints(tokenId1, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId3);
        checkpoint = escrow.checkpoints(tokenId1, 3);
        assertEq(checkpoint.fromTimestamp, 604804);
        assertEq(checkpoint.owner, user1);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(user1, tokenId1, 604804), TOKEN_1);
        assertEq(escrow.balanceOfNFT(1), TOKEN_1);

        // check tokenId 2 checkpoint unchanged
        assertEq(escrow.delegates(tokenId2), 0);
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user2);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604804), 997260242144416020
        );
        assertEq(escrow.balanceOfNFT(tokenId2), 997260242144416020);

        // check prior and new checkpoint for tokenId 3
        // expect delegatedBalance TOKEN_1 => 0
        assertEq(escrow.delegates(tokenId3), 0);
        assertEq(escrow.numCheckpoints(tokenId3), 3);
        checkpoint = escrow.checkpoints(tokenId3, 1);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, user3);
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(tokenId3, 2);
        assertEq(checkpoint.fromTimestamp, 604804);
        assertEq(checkpoint.owner, user3);
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604804), 997260242144416020
        );
        assertEq(escrow.balanceOfNFT(3), 997260242144416020);

        skipAndRoll(1);

        // already self delegating, early exit
        escrow.delegate(tokenId1, 0);

        assertEq(escrow.delegates(tokenId3), 0);
        assertEq(escrow.numCheckpoints(tokenId3), 3);

        // yet to delegate
        assertEq(
            escrow.getPastVotes(user1, tokenId1, 604801), 997260265926760005
        );
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604801), 997260265926760005
        );
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604801), 997260265926760005
        );
        // 1 => 2
        assertEq(escrow.getPastVotes(user1, tokenId1, 604802), 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604802),
            997260257999312010 + TOKEN_1
        );
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604802), 997260257999312010
        );
        // 1 => 3
        assertEq(escrow.getPastVotes(user1, tokenId1, 604803), 0);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604803), 997260250071864015
        );
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604803),
            997260250071864015 + TOKEN_1
        );
        // 1 => 1 / 0
        assertEq(escrow.getPastVotes(user1, tokenId1, 604804), TOKEN_1);
        assertEq(
            escrow.getPastVotes(user2, tokenId2, 604804), 997260242144416020
        );
        assertEq(
            escrow.getPastVotes(user3, tokenId3, 604804), 997260242144416020
        );
    }
}
