// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import {BeraChef} from "@berachain/pol/rewards/BeraChef.sol";
import {IBeaconDeposit as IBerachainBeaconDeposit} from
    "@berachain/pol/interfaces/IBeaconDeposit.sol";
import {Distributor as BerachainDistributor} from
    "@berachain/pol/rewards/Distributor.sol";
import {IRewardVaultFactory as IBerachainRewardsVaultFactory} from
    "@berachain/pol/interfaces/IRewardVaultFactory.sol";

import {IBerachainBGT} from "src/interfaces/IBerachainBGT.sol";
import {IBerachainBGTStaker} from "src/interfaces/IBerachainBGTStaker.sol";
import {IFeeCollector as IBerachainFeeCollector} from
    "@berachain/pol/interfaces/IFeeCollector.sol";

import {Infrared} from "src/core/Infrared.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";
import {Voter} from "src/voting/Voter.sol";
import {VotingEscrow} from "src/voting/VotingEscrow.sol";
import {InfraredBERA} from "src/staking/InfraredBERA.sol";
import {InfraredBERAClaimor} from "src/staking/InfraredBERAClaimor.sol";
import {InfraredBERADepositor} from "src/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/core/BribeCollector.sol";

import {RED} from "src/core/RED.sol";
import {IWBERA} from "src/interfaces/IWBERA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {InfraredDeployer} from "script/InfraredDeployer.s.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";

contract HelperForkTest is Test {
    string constant CARTIO_RPC_URL = "https://amberdew-eth-cartio.berachain.com";

    uint64 internal constant HISTORY_BUFFER_LENGTH = 8191;

    InfraredDeployer public deployer;

    Infrared public infrared;
    InfraredBGT public ibgt;
    RED public red;

    Voter public voter;
    VotingEscrow public ired;

    InfraredBERA public ibera;
    InfraredBERADepositor public depositor;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAClaimor public claimor;
    InfraredBERAFeeReceivor public receivor;

    BribeCollector internal collector;
    InfraredDistributor internal infraredDistributor;

    address internal admin;
    address internal keeper;
    address internal infraredGovernance;

    address stakingAsset;
    address poolAddress;

    IInfraredVault internal ibgtVault;
    InfraredVault internal infraredVault;

    BeraChef internal beraChef;
    IBerachainBGT internal bgt;
    IBerachainBGTStaker internal bgtStaker;
    // BlockRewardController internal blockRewardController;
    IBerachainRewardsVaultFactory internal factory;
    IBerachainFeeCollector internal feeCollector;
    BerachainDistributor internal distributor;

    IWBERA internal wbera;
    IBerachainBeaconDeposit beaconDepositContract;

    struct ValData {
        bytes32 beaconBlockRoot;
        uint64 index;
        bytes pubkey;
        bytes32[] proposerIndexProof;
        bytes32[] pubkeyProof;
    }

    ValData internal valData;

    uint256 internal cartioFork;

    // create a cartio fork during setup
    function setUp() public virtual {
        // custom params
        admin = address(this);
        keeper = address(1);
        infraredGovernance = address(2);

        address _votingKeeper = address(this);
        uint256 _rewardsDuration = 30 days;
        uint256 _bribeCollectorPayoutAmount = 10 ether;

        // todo: generate cartio validator proof, using (https://github.com/sandybradley/ConsensusLayerVerifier/blob/main/py/merkle_proof_generator/main.py)
        valData = abi.decode(
            stdJson.parseRaw(
                vm.readFile(
                    string.concat(
                        vm.projectRoot(),
                        "/test/pol/fixtures/validator_data_proofs.json"
                    )
                ),
                "$"
            ),
            (ValData)
        );

        // create fork
        cartioFork = vm.createFork(CARTIO_RPC_URL);
        vm.selectFork(cartioFork);

        // Cartio deployments
        beraChef = BeraChef(0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1);
        // blockRewardController = BlockRewardController(0x25A37b8E0a090Aa952F037B8534ace17AC3DbC60);
        factory = IBerachainRewardsVaultFactory(
            0xE2257F3C674a7CBBFFCf7C01925D5bcB85ea0367
        );
        distributor =
            BerachainDistributor(0x211bE45338B7C6d5721B5543Eb868547088Aca39);
        bgt = IBerachainBGT(0x289274787bAF083C15A45a174b7a8e44F0720660);
        bgtStaker =
            IBerachainBGTStaker(0x7B4fba14B2eae33Dd9E780E4bD406fC0429c96af);
        beaconDepositContract =
            IBerachainBeaconDeposit(0x4242424242424242424242424242424242424242);
        wbera = IWBERA(0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1);

        // RewardVaultFactory 0xE2257F3C674a7CBBFFCf7C01925D5bcB85ea0367
        // RewardVault 0xBED0D947E914C499877162cA01E44ca3173CB74B
        // FeeCollector 0x7B7aae85E651285f754830506086120621A04031

        // todo: honey address cartio?
        MockERC20 honey = new MockERC20("HONEY", "HONEY", 18);

        // deploy
        deployer = new InfraredDeployer();
        deployer.run(
            admin,
            _votingKeeper,
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
        voter = deployer.voter();
        ired = deployer.veIRED();
        ibgt = deployer.ibgt();
        red = RED(address(deployer.red()));

        ibera = deployer.ibera();
        depositor = deployer.depositor();
        withdrawor = deployer.withdrawor();
        claimor = deployer.claimor();
        receivor = deployer.receivor();

        ibera.grantRole(ibera.GOVERNANCE_ROLE(), address(this));
        ibera.grantRole(ibera.KEEPER_ROLE(), keeper);

        uint16 feeShareholders = 4; // 25% of fees
        // address(this) is the governor
        ibera.setFeeDivisorShareholders(feeShareholders);

        // set access control
        infrared.grantRole(infrared.KEEPER_ROLE(), keeper);
        infrared.grantRole(infrared.GOVERNANCE_ROLE(), infraredGovernance);
    }

    /// @notice Simulates distribution of POL for current block.number
    function distributePol() public {
        distributor.distributeFor(
            uint64(block.number),
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
    }

    /// @notice Simulates rolling of chain forward to block `number` distributing POL rewards for each block to `coinbase` in the process
    /// @dev `number` must be greater than the current `block.number`
    /// @param number   uint256  The block number to roll to
    function rollPol(uint256 number) public {
        require(number > block.number, "rolling number <= block.number");
        uint256 delta = number - block.number;
        for (uint256 i = 1; i < delta + 1; i++) {
            vm.roll(block.number + i);
            distributePol();
        }
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
