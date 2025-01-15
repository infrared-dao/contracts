// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DataTypes} from "src/utils/DataTypes.sol";
import {HarvestForkTest} from "./HarvestForkTest.t.sol";

contract HarvestBribesForkTest is HarvestForkTest {
/*
    function setUp() public virtual override {
        super.setUp();
        deal(address(honey), address(infrared), 10 ether);
        deal(address(infrared), 10 ether);
    }

    function testSetUp() public virtual override {
        super.testSetUp();
        assertEq(honey.balanceOf(address(infrared)), 10 ether);
        assertEq(address(infrared).balance, 10 ether);
    }

    function testHarvestBribesForERC20(uint256 protocolFeeRate) public {
        vm.assume(protocolFeeRate < FEE_UNIT);
        vm.startPrank(admin);

        // set protocol fee rate
        infrared.updateProtocolFeeRate(address(honey), protocolFeeRate);
        assertEq(infrared.protocolFeeRates(address(honey)), protocolFeeRate);

        uint256 balanceInfrared = honey.balanceOf(address(infrared));
        uint256 balanceCollector = honey.balanceOf(address(collector));
        uint256 protocolFeeAmount = infrared.protocolFeeAmounts(address(honey));

        uint256 amount = balanceInfrared - protocolFeeAmount;
        uint256 fees = (amount * protocolFeeRate) / FEE_UNIT;

        // harvest bribes
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(honey);
        infrared.harvestBribes(_tokens);

        // check balances updated
        assertEq(
            honey.balanceOf(address(infrared)), balanceInfrared - amount + fees
        );
        assertEq(
            honey.balanceOf(address(collector)),
            balanceCollector + amount - fees
        );

        // check protocol fee amounts updated
        assertEq(
            infrared.protocolFeeAmounts(address(honey)),
            protocolFeeAmount + fees
        );

        vm.stopPrank();
    }

    function testHarvestBribesForNativeAsset(uint256 protocolFeeRate) public {
        vm.assume(protocolFeeRate < FEE_UNIT);
        vm.startPrank(admin);

        // set protocol fee rate
        infrared.updateProtocolFeeRate(address(wbera), protocolFeeRate);
        assertEq(infrared.protocolFeeRates(address(wbera)), protocolFeeRate);

        uint256 balanceInfrared = wbera.balanceOf(address(infrared));
        uint256 balanceCollector = wbera.balanceOf(address(collector));
        uint256 protocolFeeAmount = infrared.protocolFeeAmounts(address(wbera));

        uint256 amount = address(infrared).balance - protocolFeeAmount;
        uint256 fees = (amount * protocolFeeRate) / FEE_UNIT;

        // harvest bribes
        address[] memory _tokens = new address[](1);
        _tokens[0] = DataTypes.NATIVE_ASSET;
        infrared.harvestBribes(_tokens);

        // check balances updated
        assertEq(address(infrared).balance, 0);
        assertEq(wbera.balanceOf(address(infrared)), balanceInfrared + fees);
        assertEq(
            wbera.balanceOf(address(collector)),
            balanceCollector + amount - fees
        );

        // check protocol fee amounts updated
        assertEq(
            infrared.protocolFeeAmounts(address(wbera)),
            protocolFeeAmount + fees
        );

        vm.stopPrank();
    }
    */
}
