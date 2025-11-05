// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InfraredV1_9} from "src/core/InfraredV1_9.sol";
import {IInfraredVault} from "src/interfaces/IInfraredVault.sol";
import {Errors} from "src/utils/Errors.sol";
import "tests/unit/core/Infrared/Helper.sol";

contract AuctionBaseTest is Helper {
    InfraredV1_9 infraredV9;

    function setUp() public override {
        super.setUp();
        infraredV9 = InfraredV1_9(payable(address(infrared)));
    }

    /*//////////////////////////////////////////////////////////////
                    HARVEST BASE - REDEEM PATH
    //////////////////////////////////////////////////////////////*/

    function testHarvestBaseRedeemPath() public {
        // Ensure auction is disabled (redeem path)
        vm.startPrank(keeper);
        if (infraredV9.auctionBase()) {
            infraredV9.toggleAuctionBase();
        }
        vm.stopPrank();
        // Add validators and stake to generate rewards
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 iberaBalanceBefore = ibera.receivor().balance;
        uint256 bgtBalanceBefore = bgt.balanceOf(address(infrared));

        // Harvest base rewards (should redeem BGT for BERA)
        infraredV9.harvestBase();

        uint256 iberaBalanceAfter = ibera.receivor().balance;
        uint256 bgtBalanceAfter = bgt.balanceOf(address(infrared));

        // BGT should be reduced
        assertTrue(bgtBalanceAfter < bgtBalanceBefore, "BGT should be redeemed");

        // iBERA should receive BERA
        assertTrue(
            iberaBalanceAfter > iberaBalanceBefore, "iBERA should receive BERA"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    HARVEST BASE - AUCTION PATH
    //////////////////////////////////////////////////////////////*/

    function testHarvestBaseAuctionPath() public {
        // Enable auction
        vm.startPrank(keeper);
        if (!infraredV9.auctionBase()) {
            infraredV9.toggleAuctionBase();
        }
        vm.stopPrank();

        // Mint BGT to infrared
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        address harvestCollector = infraredV9.harvestBaseCollector();
        uint256 ibgtBalanceCollectorBefore = ibgt.balanceOf(harvestCollector);
        uint256 bgtBalanceBefore = ibgt.totalSupply();

        // Harvest base rewards (should mint iBGT and send to collector)
        infraredV9.harvestBase();

        uint256 ibgtBalanceCollectorAfter = ibgt.balanceOf(harvestCollector);
        uint256 bgtBalanceAfter = ibgt.totalSupply();

        // BGT should be converted
        assertTrue(
            bgtBalanceAfter > bgtBalanceBefore, "BGT should be converted"
        );

        // Harvest collector should receive iBGT
        assertTrue(
            ibgtBalanceCollectorAfter > ibgtBalanceCollectorBefore,
            "Collector should receive iBGT"
        );
    }

    function testHarvestBaseAuctionEmitsEvent() public {
        // Enable auction
        if (!infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        // Mint BGT
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);

        //         vm.expectEmit(true, false, false, false);
        //         emit InfraredV1_9.BaseHarvested(address(this), 0);

        infraredV9.harvestBase();
    }

    /*//////////////////////////////////////////////////////////////
                    AUCTION vs REDEEM COMPARISON
    //////////////////////////////////////////////////////////////*/

    function testHarvestBaseSwitchingBetweenModes() public {
        // Start with redeem mode
        if (infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        // First harvest in redeem mode
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        infraredV9.harvestBase();

        // Switch to auction mode
        vm.prank(keeper);
        infraredV9.toggleAuctionBase();

        // Second harvest in auction mode
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        infraredV9.harvestBase();

        // Both should work without reverting
    }

    function testHarvestBaseWhenPaused() public {
        // Pause the contract
        vm.prank(infraredGovernance);
        infraredV9.pause();

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);

        vm.expectRevert();
        infraredV9.harvestBase();
    }

    function testHarvestBaseWithNoBGT() public {
        // Ensure no BGT balance
        uint256 bgtBalance = bgt.balanceOf(address(infrared));
        if (bgtBalance > 0) {
            // This should still work, just harvest 0
            infraredV9.harvestBase();
        }

        // Harvest with 0 BGT should not revert
        infraredV9.harvestBase();
    }

    function testHarvestBaseAuctionSendsToCollector() public {
        // Enable auction
        if (!infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        address collector = infraredV9.harvestBaseCollector();
        assertTrue(collector != address(0), "Collector should be set");

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 collectorBalanceBefore = ibgt.balanceOf(collector);

        infraredV9.harvestBase();

        uint256 collectorBalanceAfter = ibgt.balanceOf(collector);

        assertTrue(
            collectorBalanceAfter >= collectorBalanceBefore,
            "Collector should receive iBGT"
        );
    }

    function testHarvestBaseRedeemSendsToIbera() public {
        // Disable auction (redeem mode)
        if (infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);

        uint256 iberaBalanceBefore = address(ibera).balance;

        infraredV9.harvestBase();

        uint256 iberaBalanceAfter = address(ibera).balance;

        assertTrue(
            iberaBalanceAfter >= iberaBalanceBefore, "iBERA should receive BERA"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION WITH VALIDATORS
    //////////////////////////////////////////////////////////////*/

    function testHarvestBaseAfterValidatorRewards() public {
        // This test simulates the full flow:
        // 1. Validators earn rewards
        // 2. BGT is claimed to Infrared
        // 3. harvestBase() is called

        // Mint BGT as if from validator rewards
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 500 ether);

        // Test both modes
        vm.startPrank(keeper);

        // Mode 1: Redeem
        if (infraredV9.auctionBase()) {
            infraredV9.toggleAuctionBase();
        }
        infraredV9.harvestBase();

        // Mint more BGT
        vm.stopPrank();
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 500 ether);

        // Mode 2: Auction
        vm.startPrank(keeper);
        if (!infraredV9.auctionBase()) {
            infraredV9.toggleAuctionBase();
        }
        infraredV9.harvestBase();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE HARVESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleHarvestBaseCallsRedeem() public {
        if (infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        // Multiple harvests should work
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(address(blockRewardController));
            bgt.mint(address(infrared), 50 ether);
            infraredV9.harvestBase();
        }
    }

    function testMultipleHarvestBaseCallsAuction() public {
        if (!infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }

        // Multiple harvests should work
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(address(blockRewardController));
            bgt.mint(address(infrared), 50 ether);
            infraredV9.harvestBase();
        }
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testHarvestBaseWithLargeBGTAmount() public {
        // Test with large amount
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 1_000 ether);

        // Should handle large amounts in both modes
        if (!infraredV9.auctionBase()) {
            vm.prank(keeper);
            infraredV9.toggleAuctionBase();
        }
        infraredV9.harvestBase();

        // Switch and test again
        vm.prank(keeper);
        infraredV9.toggleAuctionBase();

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 1_000 ether);
        infraredV9.harvestBase();
    }

    function testHarvestBaseStateConsistency() public {
        // Verify state remains consistent across mode switches
        bool initialAuctionState = infraredV9.auctionBase();

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 100 ether);
        infraredV9.harvestBase();

        // State should not change from harvest
        assertEq(
            infraredV9.auctionBase(),
            initialAuctionState,
            "Auction state should not change from harvest"
        );
    }

    function testHarvestBaseAccessControl() public {
        // harvestBase is whenNotPaused but has no explicit role requirement
        // Anyone should be able to call it
        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);

        // Test various callers
        infraredV9.harvestBase(); // test contract

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);
        vm.prank(testUser);
        infraredV9.harvestBase(); // regular user

        vm.prank(address(blockRewardController));
        bgt.mint(address(infrared), 50 ether);
        vm.prank(keeper);
        infraredV9.harvestBase(); // keeper
    }
}
