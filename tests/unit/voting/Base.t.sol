// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from
    "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "tests/unit/mocks/MockWbera.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import "tests/unit/mocks/MockDistributor.sol";
import "tests/unit/mocks/MockCollector.sol";
import "@berachain/pol/rewards/RewardVaultFactory.sol";

import "src/voting/VotingEscrow.sol";
import "src/voting/Voter.sol";
import "src/core/InfraredGovernanceToken.sol";

import "src/core/InfraredBGT.sol";
import "src/core/Infrared.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

/// @notice Base contract used for tests and deployment scripts
abstract contract Base is Test {
    MockWbera public WBERA;
    InfraredGovernanceToken public ir;
    MockERC20 public honey;
    address[] public stakingTokens;
    InfraredBGT public ibgt;
    address public bgt;

    /// @dev Core v2 Deployment
    VotingEscrow public escrow;
    Voter public voter;
    address public constant keeper = address(888);
    Infrared public infrared;

    RewardVaultFactory public rewardsFactory;
    address public chef = makeAddr("chef"); // TODO: actual chef
    MockERC20 public ibera;

    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals

    uint256 constant DURATION = 7 days;
    uint256 constant WEEK = 1 weeks;
    /// @dev Use same value as in voting escrow
    uint256 constant MAXTIME = 4 * 365 * 86400;
    uint256 constant MAX_BPS = 10_000;
    address constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address admin = makeAddr("admin");
    address user1 = address(0x1);
    address user2 = address(0x2);
    address user3 = address(0x3);

    address manager = address(0x4);
    address manager2 = address(0x5);

    function setUp() public {
        // Mock non transferable token BGT token
        bgt = address(new MockERC20("BGT", "BGT", 18));
        // ibgt = new InfraredBGT(bgt);
        WBERA = new MockWbera();
        honey = new MockERC20("HONEY", "HONEY", 18);
        ibera = new MockERC20("iBERA", "iBERA", 18);

        rewardsFactory = new RewardVaultFactory();

        // initialize Infrared contracts
        infrared = Infrared(payable(setupProxy(address(new Infrared()))));

        // Governance and Lock token
        ibgt = new InfraredBGT(address(this), address(infrared), address(this));
        ir = new InfraredGovernanceToken(
            address(ibgt),
            address(infrared),
            address(this),
            address(this),
            address(this)
        );

        address collector = address(new MockCollector(address(WBERA)));
        address distributor = address(new MockDistributor(address(ibera)));

        // IRED voting
        voter = Voter(setupProxy(address(new Voter(address(infrared)))));
        escrow = new VotingEscrow(
            address(this), address(ir), address(voter), address(infrared)
        );

        Infrared.InitializationData memory data = Infrared.InitializationData(
            address(this),
            keeper,
            address(bgt),
            address(rewardsFactory),
            address(chef),
            payable(address(WBERA)),
            address(honey),
            collector,
            distributor,
            address(voter),
            address(ibera),
            1 days
        );
        infrared.initialize(data);
        voter.initialize(address(escrow), address(this), keeper);

        escrow.setVoterAndDistributor(address(voter), keeper);
        escrow.setAllowedManager(keeper);

        ir.grantRole(ir.MINTER_ROLE(), user1);
        ir.grantRole(ir.MINTER_ROLE(), user2);
        ir.grantRole(ir.MINTER_ROLE(), user3);

        address bribeRewardToken =
            address(new MockERC20("BribeRewardToken", "BRT", 18));
        address bribeRewardToken2 =
            address(new MockERC20("BribeRewardToken2", "BRT2", 18));

        stakingTokens.push(bribeRewardToken);
        stakingTokens.push(bribeRewardToken2);

        // whitelist staking tokens on infrared
        for (uint256 i = 0; i < stakingTokens.length; i++) {
            infrared.updateWhiteListedRewardTokens(stakingTokens[i], true);
        }

        registerVaults(stakingTokens);

        address[] memory _stakingTokens = new address[](2);
        _stakingTokens[0] = stakingTokens[0];
        _stakingTokens[1] = stakingTokens[1];

        deal(stakingTokens[0], address(this), TOKEN_10M);
        deal(stakingTokens[1], address(this), TOKEN_10M);
        deal(address(ir), address(this), TOKEN_10M);

        vm.startPrank(keeper);
        voter.createBribeVault(_stakingTokens[0], _stakingTokens);
        voter.createBribeVault(_stakingTokens[1], _stakingTokens);
        vm.stopPrank();

        // seed set up with initial time
        skip(1 weeks);
    }

    function registerVaults(address[] memory _tokens) public {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(ibgt);
        rewardTokens[1] = address(ir);

        for (uint256 i = 0; i < _tokens.length; i++) {
            vm.startPrank(keeper);
            infrared.registerVault(_tokens[i]);
            vm.stopPrank();
        }
    }

    /// @dev Helper utility to forward time to next week
    ///      note epoch requires at least one second to have
    ///      passed into the new epoch
    function skipToNextEpoch(uint256 offset) public {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }

    function skipAndRoll(uint256 timeOffset) public {
        skip(timeOffset);
        vm.roll(block.number + 1);
    }

    function createLock(address _user) public returns (uint256 tokenId) {
        deal(address(ir), _user, TOKEN_1);
        vm.startPrank(_user);
        ir.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
    }

    /// @dev Used to convert IVotingEscrow int128s to uint256
    ///      These values are always positive
    function convert(int128 _amount) internal pure returns (uint256) {
        return uint256(uint128(_amount));
    }

    // creates a labeled address and the corresponding private key
    function makeAddrAndKey(string memory name)
        internal
        override
        returns (address addr, uint256 privateKey)
    {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    // creates a labeled address
    function makeAddr(string memory name)
        internal
        override
        returns (address addr)
    {
        (addr,) = makeAddrAndKey(name);
    }

    function setupProxy(address implementation)
        internal
        returns (address proxy)
    {
        proxy = address(new ERC1967Proxy(implementation, ""));
    }
}
