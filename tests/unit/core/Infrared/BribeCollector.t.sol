// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Helper.sol";

contract BribeCollectorTest is Helper {
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
        feeTokens[0] = address(wbera);
        feeTokens[1] = address(honey);

        uint256[] memory feeAmounts = new uint256[](2);
        feeAmounts[0] = 1 ether;
        feeAmounts[1] = 2 ether;

        // simulate bribes collected by the collector contract
        deal(address(wbera), address(collector), 1 ether);
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
        assertEq(wbera.balanceOf(recipient), 1 ether);
    }
}
