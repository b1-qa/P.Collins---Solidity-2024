// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";
import {DeployFundMe} from "../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    FundMe fundMe;
    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    uint256 constant SEND_VALUE = 0.1 ether; // 100000000000000000 wei
    uint256 constant STARTING_BALANCE = 10 ether;

    modifier fundedByUser1() {
        vm.prank(USER);
        vm.deal(USER, STARTING_BALANCE);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    modifier fundedByUser2() {
        vm.prank(USER2);
        vm.deal(USER2, STARTING_BALANCE);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    function setUp() external {
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
    }

    function testMinimumDollarIsFive() public view {
        assertEq(fundMe.minimumUsd(), 5e8);
        console.log(fundMe.minimumUsd());
    }

    function testOwnerIsMsgSender() public view {
        console.log(fundMe.i_owner());
        console.log(msg.sender);
        assertEq(fundMe.i_owner(), msg.sender);
    }

    function testPriceFeedVersionIsAccurate() public view {
        uint256 version = fundMe.getVersion();
        assertEq(version, 4);
    }

    function testFundFailsWithoutEnoughETH() public {
        vm.expectRevert(); //next line should revert
        fundMe.fund(); //execute fundMe function without sending anything
    }

    function testFundUpdatesFundedDataStructure() public fundedByUser1 {
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER); //get the amount funded by USER
        assertEq(amountFunded, SEND_VALUE); //check if the amount funded is equal to the amount sent
    }

    function testAddsFunderToArrayOfFunders() public fundedByUser1 {
        assertEq(fundMe.getFunder(0), USER);
    }

    function testFallback() public {
        vm.prank(USER);
        vm.deal(USER, STARTING_BALANCE);
        (bool success, ) = address(fundMe).call{value: SEND_VALUE}("");
        require(success, "Fallback function call failed");
        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE);
    }

    function testReceive() public {
        vm.prank(USER);
        vm.deal(USER, STARTING_BALANCE);
        (bool success, ) = address(fundMe).call{value: SEND_VALUE}("blabla");
        require(success, "Fallback function call failed");
        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE);
    }

    function testChangeMinimumUsd() public {
        address owner = fundMe.i_owner();
        vm.prank(owner);
        fundMe.changeMinimumUsd(10);
        assertEq(fundMe.minimumUsd(), 10e8);
    }

    function testChangeFunderAddress() public fundedByUser1 {
        address newAddress = makeAddr("newAddress");
        vm.prank(USER);
        fundMe.changeFunder(newAddress);
        assertEq(fundMe.getAddressToAmountFunded(newAddress), SEND_VALUE);
    }

    function testPartialWithdrawal() public fundedByUser1 {
        vm.prank(USER);
        fundMe.partialWithdraw(SEND_VALUE / 2);
        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE / 2);
    }

    function testTotalWithdrawal() public fundedByUser1 {
        vm.prank(USER);
        fundMe.totalWithdraw();
        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
    }

    function testOwnerWithdrawFunds() public fundedByUser1 {
        address owner = fundMe.i_owner();
        uint256 ownerBalanceBefore = address(owner).balance;
        vm.prank(owner);
        fundMe.ownerWithdrawFunds();
        assertEq(owner.balance, ownerBalanceBefore + SEND_VALUE);
    }

    function testOnlyOwnerCanWithdrawFunds() public fundedByUser1 {
        vm.expectRevert(); //next function should revert
        vm.prank(USER);
        fundMe.ownerWithdrawFunds();
    }

    function testCleanAfterOwnerWithdrawalWithTwoUsers()
        public
        fundedByUser1
        fundedByUser2
    {
        address owner = fundMe.i_owner();
        vm.prank(owner);
        fundMe.ownerWithdrawFunds();
        assertEq(fundMe.getFundersCount(), 0);
        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getAddressToAmountFunded(USER2), 0);
    }

    function testCleanAfterUserWithdrawal() public fundedByUser1 {
        vm.prank(USER2);
        vm.deal(USER2, STARTING_BALANCE);
        fundMe.fund{value: SEND_VALUE}();
        vm.prank(USER);
        fundMe.totalWithdraw();
        assertEq(fundMe.getFundersCount(), 1);
        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getAddressToAmountFunded(USER2), SEND_VALUE);
    }
}
