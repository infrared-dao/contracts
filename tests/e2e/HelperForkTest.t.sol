// SPDX-License-Identifier: MIT
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

import {Infrared} from "src/depreciated/core/Infrared.sol";
import {InfraredBGT} from "src/core/InfraredBGT.sol";

import {InfraredBERA} from "src/depreciated/staking/InfraredBERA.sol";
import {InfraredBERADepositor} from
    "src/depreciated/staking/InfraredBERADepositor.sol";
import {InfraredBERAWithdrawor} from "src/staking/InfraredBERAWithdrawor.sol";
import {InfraredBERAFeeReceivor} from "src/staking/InfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";
import {InfraredDistributor} from "src/core/InfraredDistributor.sol";
import {BribeCollector} from "src/depreciated/core/BribeCollector.sol";

import {InfraredGovernanceToken} from "src/core/InfraredGovernanceToken.sol";
import {IWBERA} from "src/interfaces/IWBERA.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "tests/unit/mocks/MockERC20.sol";
import {InfraredDeployer} from "script/deploy/InfraredDeployer.s.sol";
import {IInfraredVault, InfraredVault} from "src/core/InfraredVault.sol";

contract HelperForkTest is Test {
    string constant MAINNET_RPC_URL = "https://berachain.drpc.org";

    uint64 internal constant HISTORY_BUFFER_LENGTH = 8191;

    // Validator data struct which will hold proof data for POL distribution
    struct ValData {
        uint64 nextTimestamp;
        uint64 proposerIndex;
        bytes pubkey;
        bytes32[] proposerIndexProof;
        bytes32[] pubkeyProof;
    }

    // InfraredDeployer instance
    InfraredDeployer public deployer;

    // Infrared core contracts
    Infrared public infrared;
    InfraredBGT public ibgt;
    InfraredGovernanceToken public ir;

    // Infrared staking contracts
    InfraredBERA public ibera;
    InfraredBERADepositor public depositor;
    InfraredBERAWithdrawor public withdrawor;
    InfraredBERAFeeReceivor public receivor;

    // Infrared system contracts
    BribeCollector internal collector;
    InfraredDistributor internal infraredDistributor;

    // Addresses
    address internal admin;
    address internal keeper;
    address internal infraredGovernance;
    address internal stakingAsset;
    address internal poolAddress;

    // Vaults
    IInfraredVault internal ibgtVault;
    InfraredVault internal infraredVault;

    // Berachain POL contracts
    BeraChef internal beraChef;
    IBerachainBGT internal bgt;
    IBerachainBGTStaker internal bgtStaker;
    IBerachainRewardsVaultFactory internal factory;
    IBerachainFeeCollector internal feeCollector;
    BerachainDistributor internal distributor;
    IWBERA internal wbera;
    IBerachainBeaconDeposit beaconDepositContract;

    // Tokens for testing
    ERC20 honey;
    ERC20 weth;
    ERC20 usdc;
    ERC20 wbtc;

    // Validator data for POL distribution
    ValData public valData;

    // Mainnet fork ID
    uint256 internal mainnetFork;

    function setUp() public virtual {
        // Set custom parameters
        admin = address(this);
        keeper = address(0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0);
        infraredGovernance = address(0x182a31A27A0D39d735b31e80534CFE1fCd92c38f);

        // Load validator data from fixtures
        _loadValidatorData();

        // Create and select mainnet fork
        uint256 blockNumber = 1972861;
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, blockNumber);

        // Initialize Berachain and Infrared contract references
        _initializeContractReferences();

        // todo: upgrades
    }

    function _loadValidatorData() internal {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/test/pol/fixtures/validator_data_proofs.json"
            )
        );

        // Extract each field individually to ensure correct mapping
        valData.nextTimestamp =
            uint64(stdJson.readUint(json, "$.$0__nextTimestamp"));
        valData.proposerIndex =
            uint64(stdJson.readUint(json, "$.$1__proposerIndex"));
        valData.pubkey = stdJson.readBytes(json, "$.$2__pubkey");

        // For arrays, we need to handle differently
        bytes memory proposerIndexProofData =
            stdJson.parseRaw(json, "$.$3__proposerIndexProof");
        bytes memory pubkeyProofData =
            stdJson.parseRaw(json, "$.$4__pubkeyProof");

        valData.proposerIndexProof =
            abi.decode(proposerIndexProofData, (bytes32[]));
        valData.pubkeyProof = abi.decode(pubkeyProofData, (bytes32[]));
    }

    function _hexStringToBytes32(string memory hexString)
        internal
        pure
        returns (bytes32 result)
    {
        bytes memory strBytes = bytes(hexString);
        require(strBytes.length == 66, "Invalid hex string length"); // "0x" + 64 hex chars

        bytes memory rawBytes = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            uint8 high = uint8(_charToHexDigit(strBytes[2 + i * 2]));
            uint8 low = uint8(_charToHexDigit(strBytes[2 + i * 2 + 1]));
            rawBytes[i] = bytes1((high << 4) | low);
        }

        assembly {
            result := mload(add(rawBytes, 32))
        }
    }

    function _charToHexDigit(bytes1 c) internal pure returns (uint8) {
        if (uint8(c) >= uint8(bytes1("0")) && uint8(c) <= uint8(bytes1("9"))) {
            return uint8(c) - uint8(bytes1("0"));
        }
        if (uint8(c) >= uint8(bytes1("a")) && uint8(c) <= uint8(bytes1("f"))) {
            return 10 + uint8(c) - uint8(bytes1("a"));
        }
        if (uint8(c) >= uint8(bytes1("A")) && uint8(c) <= uint8(bytes1("F"))) {
            return 10 + uint8(c) - uint8(bytes1("A"));
        }
        revert("Invalid hex character");
    }

    function _initializeContractReferences() internal {
        // Berachain POL contracts
        beraChef = BeraChef(0xdf960E8F3F19C481dDE769edEDD439ea1a63426a);
        factory = IBerachainRewardsVaultFactory(
            0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8
        );
        distributor =
            BerachainDistributor(0xD2f19a79b026Fb636A7c300bF5947df113940761);
        bgt = IBerachainBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
        bgtStaker =
            IBerachainBGTStaker(0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6);
        beaconDepositContract =
            IBerachainBeaconDeposit(0x4242424242424242424242424242424242424242);
        wbera = IWBERA(0x6969696969696969696969696969696969696969);

        // Token references
        honey = ERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
        weth = ERC20(0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);
        usdc = ERC20(0x549943e04f40284185054145c6E4e9568C1D3241);
        wbtc = ERC20(0x0555E30da8f98308EdB960aa94C0Db47230d2B9c);

        // Infrared contracts
        infrared = Infrared(payable(0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126));
        ibgt = InfraredBGT(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);

        ibera = InfraredBERA(0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5);
        depositor =
            InfraredBERADepositor(0x04CddC538ea65908106416986aDaeCeFD4CAB7D7);
        withdrawor = InfraredBERAWithdrawor(
            payable(0x8c0E122960dc2E97dc0059c07d6901Dce72818E1)
        );

        receivor = InfraredBERAFeeReceivor(
            payable(0xf6a4A6aCECd5311327AE3866624486b6179fEF97)
        );
        collector = BribeCollector(0x8d44170e120B80a7E898bFba8cb26B01ad21298C);
        infraredDistributor =
            InfraredDistributor(0x1fAD980dfafF71E3Fdd9bef643ab2Ff2BdC4Ccd6);
        infraredVault =
            InfraredVault(0x0dF14916796854d899576CBde69a35bAFb923c22);
        ibgtVault = IInfraredVault(0x4EF0c533D065118907f68e6017467Eb05DBb2c8C);
    }

    function distributePol() public {
        distributor.distributeFor(
            valData.nextTimestamp,
            valData.proposerIndex,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
    }

    function rollPol(uint256 number) public {
        vm.roll(number);
        distributePol();
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

// Mock implementation of the EIP-4788 BeaconRoots contract for testing
contract EnhancedMock4788BeaconRoots {
    bytes32 private mockBeaconBlockRoot;
    mapping(uint256 => bool) private validTimestamps;
    bool private defaultIsTimestampValid;

    // Set if a specific timestamp should be considered valid
    function setTimestampValid(uint256 timestamp, bool isValid) external {
        validTimestamps[timestamp] = isValid;
    }

    // Set the default for timestamps not specifically set
    function setIsTimestampValid(bool _isValid) external {
        defaultIsTimestampValid = _isValid;
    }

    // Set the mock beacon block root to return
    function setMockBeaconBlockRoot(bytes32 _mockBeaconBlockRoot) external {
        mockBeaconBlockRoot = _mockBeaconBlockRoot;
    }

    // Check if a specific timestamp is valid or use the default
    function isTimestampValid(uint256 timestamp) public view returns (bool) {
        if (validTimestamps[timestamp]) {
            return true;
        }
        return defaultIsTimestampValid;
    }

    // This is likely what's being called - match the function signature
    function parentBeaconBlockRoots(uint256 timestamp)
        external
        view
        returns (bytes32)
    {
        require(isTimestampValid(timestamp), "RootNotFound()");
        return mockBeaconBlockRoot;
    }

    // Add a fallback function to catch any other function calls
    fallback() external {
        // Get the timestamp from the calldata
        uint256 ts;
        assembly {
            // Assuming timestamp is the first parameter
            ts := calldataload(4)
        }

        require(isTimestampValid(ts), "RootNotFound()");

        // Return the mock root
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, sload(0)) // Load mockBeaconBlockRoot from storage slot 0
            return(ptr, 32)
        }
    }
}
