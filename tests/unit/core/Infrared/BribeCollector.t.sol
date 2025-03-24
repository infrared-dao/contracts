// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlUpgradeable} from
    "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {
    UUPSUpgradeable,
    ERC1967Utils
} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import "./Helper.sol";
import {Errors} from "src/utils/Errors.sol";

contract BribeCollectorTest is Helper {
    BribeCollectorV2 public bribeCollectorV2;

    function testSetPayoutAmount() public {
        vm.startPrank(infraredGovernance);
        collector.setPayoutAmount(1 ether);
        vm.stopPrank();
    }

    function testSetPayoutAmountWhenNotGovernor() public {
        vm.startPrank(keeper);
        vm.expectRevert();
        collector.setPayoutAmount(1 ether);
        vm.stopPrank();
    }

    function testClaimFeesSuccess() public {
        // set collectBribesWeight 50%
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(1e6 / 2);

        address searcher = address(777);

        // Arrange
        address recipient = address(3);
        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(ibgt);
        feeTokens[1] = address(honey);

        uint256[] memory feeAmounts = new uint256[](2);
        feeAmounts[0] = 1 ether;
        feeAmounts[1] = 2 ether;

        // simulate bribes collected by the collector contract
        deal(address(ibgt), address(collector), 1 ether);
        deal(address(honey), address(collector), 2 ether);

        address payoutToken = collector.payoutToken();
        uint256 payoutAmount = collector.payoutAmount();

        // searcher approves payoutAmount to the collector contract
        // deal(payoutToken, searcher, payoutAmount);
        // since payoutToken is wbera, deal and deposit
        vm.deal(searcher, payoutAmount);
        vm.prank(searcher);
        wbera.deposit{value: payoutAmount}();

        // Act
        vm.startPrank(searcher);
        ERC20(payoutToken).approve(address(collector), payoutAmount);
        collector.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();

        // Assert
        assertEq(wbera.balanceOf(address(ibgtVault)), payoutAmount / 2);
        assertEq(address(receivor).balance, payoutAmount / 2);
        assertEq(honey.balanceOf(recipient), 2 ether);
        assertEq(ibgt.balanceOf(recipient), 1 ether);
    }

    function testClaimFeesRejectsPayoutTokenAndSweepPayoutToken() public {
        // now test
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = collector.payoutToken(); // Malicious attempt

        deal(address(wbera), address(collector), 10 ether);
        deal(address(wbera), address(this), collector.payoutAmount());

        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 10 ether;

        wbera.approve(address(collector), collector.payoutAmount());

        vm.expectRevert(Errors.InvalidFeeToken.selector);
        collector.claimFees(recipient, feeTokens, feeAmounts);

        // update bribe split to test better
        uint256 balBefore = address(receivor).balance;
        deal(address(wbera), collector.payoutAmount() / 2);
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(500000);

        vm.prank(infraredGovernance);
        collector.sweepPayoutToken();

        assertEq(
            wbera.balanceOf(address(infrared.ibgtVault())),
            collector.payoutAmount() / 2
        );
        assertEq(
            address(receivor).balance, balBefore + collector.payoutAmount() / 2
        );
        assertEq(wbera.balanceOf(address(collector)), 0);
    }

    function testUpgrades() public {
        assertEq(collector.payoutToken(), address(wbera));
        assertEq(collector.payoutAmount(), 10 ether);

        // deploy new implementation
        bribeCollectorV2 = new BribeCollectorV2();

        // perform proxy upgrade
        vm.prank(infraredGovernance);
        (bool success,) = address(collector).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)", address(bribeCollectorV2), ""
            )
        );
        require(success, "Upgrade failed");

        // initialize
        // point at proxy
        bribeCollectorV2 = BribeCollectorV2(address(collector));
        vm.prank(infraredGovernance);
        bribeCollectorV2.initializeV2(12345, 6789);

        // assert prev vars in tact
        assertEq(address(bribeCollectorV2.infrared()), address(infrared));
        assertEq(bribeCollectorV2.payoutToken(), address(wbera));
        assertEq(bribeCollectorV2.payoutAmount(), 10 ether);

        // assert new vars
        assertEq(bribeCollectorV2.randomVar(), 12345);
        assertEq(bribeCollectorV2.randomVar2(), 6789);
        assertEq(
            bribeCollectorV2.NEW_ROLE_NOT_CONSTANT(), keccak256("NEW_ROLE")
        );
    }
}

// Test contracts for upgrades
abstract contract UpgradeableV2 is UUPSUpgradeable, AccessControlUpgradeable {
    // Access control constants.
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // new vars
    bytes32 public NEW_ROLE_NOT_CONSTANT;

    // Reserve storage space for upgrades
    uint256[19] private __gap;

    /**
     * @notice Modifier to restrict access to KEEPER_ROLE.
     */
    modifier onlyKeeper() {
        _checkRole(KEEPER_ROLE);
        _;
    }

    /**
     * @notice Modifier to restrict access to GOVERNANCE_ROLE.
     */
    modifier onlyGovernor() {
        _checkRole(GOVERNANCE_ROLE);
        _;
    }

    modifier whenInitialized() {
        uint64 _version = _getInitializedVersion();
        if (_version == 0 || _version == type(uint64).max) {
            revert Errors.NotInitialized();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Ensure the contract cannot be initialized through the logic contract
    }

    /**
     * @notice Initialize the upgradeable contract.
     */
    function __Upgradeable_init() internal {
        NEW_ROLE_NOT_CONSTANT = keccak256("NEW_ROLE");
        // __UUPSUpgradeable_init();
        // __AccessControl_init();
    }

    /**
     * @dev Restrict upgrades to only the governor.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyGovernor
    {
        // allow only owner to upgrade the implementation
        // will be called by upgradeToAndCall
    }

    /**
     * @notice Returns the current implementation address.
     */
    function currentImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /**
     * @notice Alias for `currentImplementation` for clarity.
     */
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}

abstract contract InfraredUpgradeableV2 is UpgradeableV2 {
    /// @notice Infrared coordinator contract
    IInfrared public infrared;

    // Reserve storage space for upgrades
    uint256[9] private __gap;

    // new vars
    uint256 public randomVar;

    modifier onlyInfrared() {
        if (msg.sender != address(infrared)) revert Errors.NotInfrared();
        _;
    }

    constructor() {
        // prevents implementation contracts from being used
        _disableInitializers();
    }

    function __InfraredUpgradeable_init(uint256 _randomVar) internal {
        randomVar = _randomVar;
        __Upgradeable_init();
    }
}

contract BribeCollectorV2 is InfraredUpgradeableV2 {
    using SafeTransferLib for ERC20;

    /// @notice Payout token, required to be WBERA token as its unwrapped and used to compound rewards in the `iBera` system.
    address public payoutToken;

    /// @notice Payout amount is a constant value that is paid out the caller of the `claimFees` function.
    uint256 public payoutAmount;

    // new vars
    uint256 public randomVar2;

    // Reserve storage slots for future upgrades for safety
    uint256[39] private __gap;

    // constructor(address _infrared) InfraredUpgradeableV2(_infrared) {
    //     if (_infrared == address(0)) revert Errors.ZeroAddress();
    // }

    function initializeV2(uint256 _randomVarVaule, uint256 _randomVar2Value)
        external
    {
        randomVar2 = _randomVar2Value;

        // init upgradeable components
        __InfraredUpgradeable_init(_randomVarVaule);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the payout token for the bribe collector.
    /// @dev Only callable by the governor and should be set to WBERA token since iBERA  requires BERA to compound rewards.
    function setPayoutAmount(uint256 _newPayoutAmount) external onlyGovernor {
        payoutAmount = _newPayoutAmount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WRITE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function claimFees(
        address _recipient,
        address[] calldata _feeTokens,
        uint256[] calldata _feeAmounts
    ) external {
        if (_feeTokens.length != _feeAmounts.length) {
            revert Errors.InvalidArrayLength();
        }
        if (_recipient == address(0)) revert Errors.ZeroAddress();
        // transfer price of claiming tokens (payoutAmount) from the sender to this contract
        ERC20(payoutToken).safeTransferFrom(
            msg.sender, address(this), payoutAmount
        );
        // increase the allowance of the payout token to the infrared contract to be send to
        // validator distribution contract
        ERC20(payoutToken).safeApprove(address(infrared), payoutAmount);
        // Callback into infrared post auction to split amount to vaults and protocol
        infrared.collectBribes(payoutToken, payoutAmount);
        // payoutAmount will be transferred out at this point

        // From all the specified fee tokens, transfer them to the recipient.
        for (uint256 i = 0; i < _feeTokens.length; i++) {
            address feeToken = _feeTokens[i];
            uint256 feeAmount = _feeAmounts[i];
            ERC20(feeToken).safeTransfer(_recipient, feeAmount);
        }
    }
}
