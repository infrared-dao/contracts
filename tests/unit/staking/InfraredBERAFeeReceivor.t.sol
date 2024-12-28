// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IInfraredBERAFeeReceivor} from
    "src/interfaces/IInfraredBERAFeeReceivor.sol";
import {InfraredBERAConstants} from "src/staking/InfraredBERAConstants.sol";

import {InfraredBERABaseTest} from "./InfraredBERABase.t.sol";
import {Errors} from "src/utils/Errors.sol";
import {console2} from "@forge-std/console2.sol";

contract InfraredBERAFeeReceivorTest is InfraredBERABaseTest {
    function testDistributionReturnsWhenFeeZero() public {
        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(amount, address(receivor).balance);
        assertEq(fees, 0);
    }

    function testDistributionReturnsWhenFeeGreaterThanZero() public {
        uint16 feeShareholders = 4; // 25% fee
        vm.prank(governor);
        ibera.setFeeDivisorShareholders(feeShareholders);
        assertEq(ibera.feeDivisorShareholders(), feeShareholders);

        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(
            amount,
            address(receivor).balance
                - address(receivor).balance / feeShareholders
        );
        assertEq(fees, address(receivor).balance / feeShareholders);
    }

    function testDistributionReturnsWhenAccumulatedFeesGreaterThanZero()
        public
    {
        testDistributionReturnsWhenFeeGreaterThanZero();
        uint256 balanceReceivor = address(receivor).balance;
        uint16 feeShareholders = ibera.feeDivisorShareholders();
        uint256 shareholderFees = receivor.shareholderFees();

        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, balanceReceivor - balanceReceivor / feeShareholders);
        assertEq(fees_, balanceReceivor / feeShareholders);

        uint256 shareholderFees_ = receivor.shareholderFees();
        assertEq(receivor.shareholderFees(), shareholderFees + fees_);

        // add in some more fees
        uint256 value = 0.5 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value + shareholderFees_);

        // should not include already swept distribution in fees charged
        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(amount, value - value / feeShareholders);
        assertEq(fees, value / feeShareholders);
    }

    function testSweepUpdatesProtocolFees() public {
        uint16 feeShareholders = 4; // 25% fee
        vm.prank(governor);
        ibera.setFeeDivisorShareholders(feeShareholders);
        assertEq(ibera.feeDivisorShareholders(), feeShareholders);

        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (, uint256 fees) = receivor.distribution();
        assertTrue(fees > 0);

        uint256 shareholderFees_ = receivor.shareholderFees();
        (, uint256 fees_) = receivor.sweep();
        assertEq(fees_, fees);
        assertEq(receivor.shareholderFees(), shareholderFees_ + fees);

        // check distribution zeros
        (uint256 amountAfter, uint256 feesAfter) = receivor.distribution();
        assertEq(amountAfter, 0);
        assertEq(feesAfter, 0);
    }

    function testSweepNotUpdatesProtocolFeesWhenFeesZero() public {
        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (, uint256 fees) = receivor.distribution();
        assertTrue(fees == 0);

        uint256 shareholderFees_ = receivor.shareholderFees();
        (, uint256 fees_) = receivor.sweep();
        assertEq(fees_, 0);
        assertEq(receivor.shareholderFees(), shareholderFees_);

        // check distribution zeros
        (uint256 amountAfter, uint256 feesAfter) = receivor.distribution();
        assertEq(amountAfter, 0);
        assertEq(feesAfter, 0);
    }

    function testSweepUpdatesProtocolFeesWhenAccumulatedFeesGreaterThanZero()
        public
    {
        testDistributionReturnsWhenFeeGreaterThanZero();
        (uint256 amount, uint256 fees) = receivor.distribution();
        assertTrue(amount > 0);
        assertTrue(fees > 0);

        uint256 shareholderFees = receivor.shareholderFees();
        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, amount);
        assertEq(fees_, fees);
        assertEq(receivor.shareholderFees(), shareholderFees + fees);
    }

    function testSweepTransfersETH() public {
        uint16 feeShareholders = 4; // 25% fee
        vm.prank(governor);
        ibera.setFeeDivisorShareholders(feeShareholders);
        assertEq(ibera.feeDivisorShareholders(), feeShareholders);

        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(amount, value - value / feeShareholders);
        assertEq(fees, value / feeShareholders);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceReceivor = address(receivor).balance;

        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, amount);
        assertEq(fees_, fees);

        assertEq(address(depositor).balance, balanceDepositor + amount);
        assertEq(address(receivor).balance, balanceReceivor - amount);
    }

    function testSweepTransfersETHWhenFeesZero() public {
        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(amount, value);
        assertEq(fees, 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceReceivor = address(receivor).balance;

        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, amount);
        assertEq(fees_, fees);

        assertEq(address(depositor).balance, balanceDepositor + amount);
        assertEq(address(receivor).balance, balanceReceivor - amount);
    }

    function testSweepTransfersETHWhenAccumulatedFeesGreaterThanZero() public {
        testDistributionReturnsWhenAccumulatedFeesGreaterThanZero();
        (uint256 amount, uint256 fees) = receivor.distribution();
        assertTrue(amount > 0);
        assertTrue(fees > 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceReceivor = address(receivor).balance;

        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, amount);
        assertEq(fees_, fees);

        assertEq(address(depositor).balance, balanceDepositor + amount);
        assertEq(address(receivor).balance, balanceReceivor - amount);
    }

    function testSweepEmitsSweep() public {
        uint16 feeShareholders = 4; // 25% fee
        vm.prank(governor);
        ibera.setFeeDivisorShareholders(feeShareholders);
        assertEq(ibera.feeDivisorShareholders(), feeShareholders);

        uint256 value = 1 ether;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertEq(amount, value - value / feeShareholders);
        assertEq(fees, value / feeShareholders);

        vm.expectEmit();
        emit IInfraredBERAFeeReceivor.Sweep(address(ibera), amount, fees);
        receivor.sweep();
    }

    function testSweepPassesBelowMin() public {
        uint256 value = InfraredBERAConstants.MINIMUM_DEPOSIT;
        (bool success,) = address(receivor).call{value: value}("");
        assertTrue(success);
        assertEq(address(receivor).balance, value);

        (uint256 amount, uint256 fees) = receivor.distribution();
        assertTrue(
            amount
                < InfraredBERAConstants.MINIMUM_DEPOSIT
                    + InfraredBERAConstants.MINIMUM_DEPOSIT_FEE
        );
        assertEq(fees, 0);

        uint256 balanceDepositor = address(depositor).balance;
        uint256 balanceReceivor = address(receivor).balance;
        uint256 shareholderFees = receivor.shareholderFees();

        (uint256 amount_, uint256 fees_) = receivor.sweep();
        assertEq(amount_, 0);
        assertEq(fees_, 0);

        assertEq(address(depositor).balance, balanceDepositor);
        assertEq(address(receivor).balance, balanceReceivor);
        assertEq(shareholderFees, receivor.shareholderFees());
    }

    // todo: refactor  receivor.collect();

    function testCollectUpdatesProtocolFees() public {
        testSweepTransfersETHWhenAccumulatedFeesGreaterThanZero();
        uint256 shareholderFees = receivor.shareholderFees();
        assertTrue(shareholderFees > 0);

        vm.prank(address(ibera));
        receivor.collect();
        assertEq(receivor.shareholderFees(), 1);
    }

    function testCollectMintingShares() public {
        testSweepTransfersETHWhenAccumulatedFeesGreaterThanZero();
        uint256 shareholderFees = receivor.shareholderFees();
        assertTrue(shareholderFees > 0);

        uint256 balanceReceivor = address(receivor).balance;
        uint256 infraredBalance = ibera.balanceOf(address(infrared));

        vm.prank(address(ibera));
        uint256 sharesMinted = receivor.collect();

        // Check shares were minted to Infrared
        assertEq(
            ibera.balanceOf(address(infrared)), infraredBalance + sharesMinted
        );
        // Check ETH was transferred from receivor
        assertEq(
            address(receivor).balance, balanceReceivor - (shareholderFees - 1)
        );
        // Check shareholderFees was updated
        assertEq(receivor.shareholderFees(), 1);
    }

    function testCollectRevertsWhenNotGovernor() public {
        testSweepTransfersETHWhenAccumulatedFeesGreaterThanZero();
        uint256 shareholderFees = receivor.shareholderFees();
        assertTrue(shareholderFees > 0);

        vm.expectRevert();
        receivor.collect();
    }

    function testCollectWhenShareholderFeesZero() public {
        uint256 shareholderFees = receivor.shareholderFees();
        assertTrue(shareholderFees == 0);

        vm.prank(address(ibera));
        uint256 sharesMinted = receivor.collect();
        assertEq(sharesMinted, 0);
    }

    function testRoundingLossIsMinimal() public {
        // Test with common fee denominators
        uint16[] memory denominators = new uint16[](4);
        denominators[0] = 3; // 33.33%
        denominators[1] = 4; // 25%
        denominators[2] = 5; // 20%
        denominators[3] = 10; // 10%

        // Test with different amounts
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1e15; // 0.001 ETH
        amounts[1] = 1e16; // 0.01 ETH
        amounts[2] = 1e17; // 0.1 ETH
        amounts[3] = 1e18; // 1 ETH

        for (uint256 i = 0; i < denominators.length; i++) {
            vm.prank(governor);
            ibera.setFeeDivisorShareholders(denominators[i]);

            for (uint256 j = 0; j < amounts.length; j++) {
                uint256 amount = amounts[j];

                // Calculate exact division
                uint256 fee = amount / denominators[i];
                uint256 remainder = amount % denominators[i];

                // Verify with actual contract
                vm.deal(address(receivor), 0);
                (bool success,) = address(receivor).call{value: amount}("");
                assertTrue(success);
                (, uint256 actualFees) = receivor.distribution();

                assertEq(fee, actualFees, "Fee calculation matches");
                assertEq(
                    remainder,
                    amount - (fee * denominators[i]),
                    "Remainder calculation matches"
                );
                assertTrue(
                    remainder < denominators[i],
                    "Remainder is always less than denominator"
                );

                // For denominator 3 we know there's 1 wei remainder
                if (denominators[i] == 3) {
                    assertEq(
                        remainder, 1, "Denominator 3 always has 1 wei remainder"
                    );
                } else {
                    // For powers of 2 and 5 we expect no remainder
                    assertEq(
                        remainder,
                        0,
                        "No remainder for power of 2 and 5 denominators"
                    );
                }
            }
        }
    }
}
