// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {Helper} from "./Helper.sol";
import {InfraredV1_8} from "src/core/upgrades/InfraredV1_8.sol";
import {BribeCollectorV1_4} from "src/core/upgrades/BribeCollectorV1_4.sol";
import {Errors} from "src/utils/Errors.sol";

contract BribeCollectorV1_4Test is Helper {
    BribeCollectorV1_4 collectorV4;

    function setUp() public override {
        super.setUp();

        collectorV4 = BribeCollectorV1_4(address(collector));

        // set ibgt as payout token
        vm.prank(infraredGovernance);
        collectorV4.setPayoutToken(address(ibgt));
    }

    function testInitializeV1_4Success() public view {
        assertEq(collectorV4.payoutToken(), address(ibgt));
        assertEq(collectorV4.payoutAmount(), 10 ether);
    }

    function testSetPayoutAmount() public {
        vm.startPrank(infraredGovernance);
        collectorV4.setPayoutAmount(1 ether);
        vm.stopPrank();
        assertEq(collectorV4.payoutAmount(), 1 ether);
    }

    function testSetPayoutAmountRevertZero() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAmount.selector);
        collectorV4.setPayoutAmount(0);
    }

    function testSetPayoutAmountWhenNotGovernor() public {
        vm.startPrank(keeper);
        vm.expectRevert();
        collectorV4.setPayoutAmount(1 ether);
        vm.stopPrank();
    }

    function testSetPayoutToken() public {
        address newToken = address(0x123); // Mock a new token address
        vm.prank(infraredGovernance);
        collectorV4.setPayoutToken(newToken);
        assertEq(collectorV4.payoutToken(), newToken);
    }

    function testSetPayoutTokenRevertZero() public {
        vm.prank(infraredGovernance);
        vm.expectRevert(Errors.ZeroAddress.selector);
        collectorV4.setPayoutToken(address(0));
    }

    function testSetPayoutTokenRevertNotGovernor() public {
        vm.prank(keeper);
        vm.expectRevert();
        collectorV4.setPayoutToken(address(0x123));
    }

    function testClaimFeesIbgt() public {
        // set collectBribesWeight 50%
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(1e6 / 2);

        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(honey);
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 1 ether;

        // Simulate bribes collected
        deal(address(honey), address(collector), 1 ether);

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        // Approve spending
        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        // Attempt to claim fees as keeper
        // vm.prank(keeper);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();

        assertEq(honey.balanceOf(recipient), 1 ether);
        assertEq(
            ERC20(wiBGT).balanceOf(address(ibgtVault)),
            collectorV4.payoutAmount() / 2
        );
        assertEq(
            ibgt.balanceOf(
                InfraredV1_8(payable(address(infrared))).harvestBaseCollector()
            ),
            collectorV4.payoutAmount() / 2
        );
    }

    function testClaimFeesMultipleTokens() public {
        // Assume another whitelisted token, e.g., mock a second token
        address mockToken2 = address(new MockERC20("Mock2", "M2", 18));
        vm.prank(infraredGovernance);
        infrared.updateWhiteListedRewardTokens(mockToken2, true);

        // set collectBribesWeight 50%
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(1e6 / 2);

        address recipient = address(3);
        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(honey);
        feeTokens[1] = mockToken2;
        uint256[] memory feeAmounts = new uint256[](2);
        feeAmounts[0] = 1 ether;
        feeAmounts[1] = 2 ether;

        // Simulate bribes collected
        deal(address(honey), address(collector), 1 ether);
        deal(mockToken2, address(collector), 2 ether);

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        // Approve spending
        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        // Claim fees
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();

        assertEq(honey.balanceOf(recipient), 1 ether);
        assertEq(ERC20(mockToken2).balanceOf(recipient), 2 ether);
        assertEq(
            ERC20(wiBGT).balanceOf(address(ibgtVault)),
            collectorV4.payoutAmount() / 2
        );
        assertEq(
            ibgt.balanceOf(
                InfraredV1_8(payable(address(infrared))).harvestBaseCollector()
            ),
            collectorV4.payoutAmount() / 2
        );
    }

    function testClaimFeesEmptyArrays() public {
        // set collectBribesWeight 50%
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(1e6 / 2);

        address recipient = address(3);
        address[] memory feeTokens = new address[](0);
        uint256[] memory feeAmounts = new uint256[](0);

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        // Approve spending
        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        // Claim fees (should still transfer payout but no fees)
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();

        assertEq(
            ERC20(wiBGT).balanceOf(address(ibgtVault)),
            collectorV4.payoutAmount() / 2
        );
        assertEq(
            ibgt.balanceOf(
                InfraredV1_8(payable(address(infrared))).harvestBaseCollector()
            ),
            collectorV4.payoutAmount() / 2
        );
    }

    function testClaimFeesRevertLengthMismatch() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(honey);
        uint256[] memory feeAmounts = new uint256[](2); // Mismatch

        vm.prank(keeper);
        vm.expectRevert(Errors.InvalidArrayLength.selector);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
    }

    function testClaimFeesRevertZeroRecipient() public {
        address[] memory feeTokens = new address[](0);
        uint256[] memory feeAmounts = new uint256[](0);

        vm.prank(keeper);
        vm.expectRevert(Errors.ZeroAddress.selector);
        collectorV4.claimFees(address(0), feeTokens, feeAmounts);
    }

    function testClaimFeesRevertInsufficientSenderBalance() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](0);
        uint256[] memory feeAmounts = new uint256[](0);

        // No deal to keeper, so balance 0
        vm.prank(keeper);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
    }

    function testClaimFeesRevertInvalidFeeToken() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(ibgt); // Same as payoutToken
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 1 ether;

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        vm.expectRevert(Errors.InvalidFeeToken.selector);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();
    }

    function testClaimFeesRevertNotWhitelisted() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(0xABC); // Assume not whitelisted
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 1 ether;

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        vm.expectRevert(Errors.FeeTokenNotWhitelisted.selector);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();
    }

    function testClaimFeesRevertInsufficientFeeBalance() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(honey);
        uint256[] memory feeAmounts = new uint256[](1);
        feeAmounts[0] = 1 ether;

        // No deal to collector, so balance 0

        // Give keeper enough iBGT
        deal(address(ibgt), keeper, collectorV4.payoutAmount());

        vm.startPrank(keeper);
        ERC20(collectorV4.payoutToken()).approve(
            address(collector), collectorV4.payoutAmount()
        );

        vm.expectRevert(Errors.InsufficientFeeTokenBalance.selector);
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
        vm.stopPrank();
    }

    function testClaimFeesRevertNotKeeper() public {
        address recipient = address(3);
        address[] memory feeTokens = new address[](0);
        uint256[] memory feeAmounts = new uint256[](0);

        vm.prank(address(4)); // Random address
        vm.expectRevert();
        collectorV4.claimFees(recipient, feeTokens, feeAmounts);
    }

    // Tests for sweepPayoutToken
    function testSweepPayoutTokenSuccess() public {
        // set collectBribesWeight 50%
        vm.prank(infraredGovernance);
        infrared.updateInfraredBERABribeSplit(1e6 / 2);

        // Simulate some payoutToken balance in collector (e.g., accidental transfer)
        deal(address(ibgt), address(collector), 1 ether);

        // Call sweep (anyone can call, as it's external with no modifier)
        collectorV4.sweepPayoutToken();

        assertEq(ibgt.balanceOf(address(collector)), 0);
        assertEq(ERC20(wiBGT).balanceOf(address(ibgtVault)), 0.5 ether);
        assertEq(
            ibgt.balanceOf(
                InfraredV1_8(payable(address(infrared))).harvestBaseCollector()
            ),
            0.5 ether
        );
    }

    function testSweepPayoutTokenRevertInsufficientBalance() public {
        // No balance
        vm.expectRevert(Errors.InsufficientBalance.selector);
        collectorV4.sweepPayoutToken();
    }
}
