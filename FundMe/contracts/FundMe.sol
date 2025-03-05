// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./SafeCast.sol"; //import the library OpenZeppelin SafeCast
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
using SafeCast for int256; //declare we use the library in this file.


contract FundMe {

    bool private locked;
    address public owner;
    uint256 public minimumUsd;

    address[] public funders;
    mapping (address => uint256) public addressToIndexInFundersArray;
    mapping (address => bool) public addressIsActiveFunder;
    mapping (address => uint256) public addressToAvailableAmount;

    modifier onlyOwner() {
        require (msg.sender == owner, "Only owner can execute this function.");
        _;
    }

    modifier noReentrant() {
        //if locked == true, entrancy isn't allowed
        require (locked == false, "No re-entrancy allowed, please try again.");

        //if locked == false, locked will be equal to true, and then it'll run the function with modifier
        locked = true;
        //function with modifier will execute at this exact moment thanks to "_;"
        _;
        //after the function execution, locked is put back to false.
        locked = false;
    }

    constructor() {
        owner = msg.sender;
        //added minimumUsd in a constructor so the value is initialised at contract creation.
        minimumUsd = 5*1e8;
    }

    //allow wallets to send funds to the contract, which will run fund() instead of them losing the amount sent.
    receive() external payable {
        fund();
    }

    //changeMinimumUsd can only be called by owner, and cannot be changed to the same value.
    function changeMinimumUsd(uint256 _newMinimumUsd) onlyOwner public {
        uint256 newMinimumUsd = _newMinimumUsd*1e8;
        require(newMinimumUsd != minimumUsd, "Cannot change the value of minimumUsd to the same value.");
        minimumUsd = newMinimumUsd;
    }

    //wallets can use fund() to add money in the contract,
    //and we verify that the value they send is superior or equal to minimumUsd
    //then we add that amount to the addressToAvailableAmount mapping so we can track how much is their wallet's balance on the contract
    function fund() public payable {
        uint256 price = getPrice();
        uint256 conversionRate = getConversionRate(price, msg.value);
        require(conversionRate >= minimumUsd, "didn't send enough USD");
        if (!addressIsActiveFunder[msg.sender]) {
            addressToIndexInFundersArray[msg.sender] = funders.length;
            funders.push(msg.sender);
            addressIsActiveFunder[msg.sender] = true;
        }
        addressToAvailableAmount[msg.sender] += msg.value;
    }

    //msg.sender can withdraw his wallet's contract balance partially only if his balance is > 0
    function partialWithdraw(uint256 _amount) public noReentrant {
        require(addressIsActiveFunder[msg.sender] == true, "Wallet address is not a funder.");
        addressToAvailableAmount[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success == true, "Transfer failed.");

        //if current address has no more balance anymore, it will call cleanAfterWithdrawal();
        if (addressToAvailableAmount[msg.sender] <= 0){
            cleanAfterUserWithdrawal();
        }
    }

    //msg.sender can withdraw his wallet's contract balance totally only if his balance is > 0
    function totalWithdraw() public noReentrant {
        uint256 balance = addressToAvailableAmount[msg.sender];
        require(balance > 0, "Insufficient balance");
        addressToAvailableAmount[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success == true, "Transfer failed.");
        cleanAfterUserWithdrawal();
    }

    function ownerWithdrawFunds() onlyOwner public {
        require (msg.sender == owner, "Only owner can call this function.");
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success == true, "Transfer failed.");
        cleanAfterOwnerWithdrawal();
    }

    //function that will clean mappings & array if the owner withdraw funds from contract
    function cleanAfterOwnerWithdrawal() internal {
        for (uint256 i = 0; i < funders.length; i++){
            address funder = funders[i];
            addressToIndexInFundersArray[funder] = 0;
            addressIsActiveFunder[funder] = false;
        }
        //here, reset the funders array
        //could have used funders = new address[](0) but it's more costly in gas.
        delete funders;
    }

    //(1) remove msg.sender's address from funders
    //(2) delete his index from array,
    //(3) state he's not an active funder
    function cleanAfterUserWithdrawal() internal {
        address lastFunderAddress = funders[funders.length - 1];
        uint256 currentFunderIndex = addressToIndexInFundersArray[msg.sender];
        //if current address is not the last funder, it will:
        //(4) give last funder the current funder's position
        if (addressToIndexInFundersArray[msg.sender] != funders.length - 1){
            funders[currentFunderIndex] = lastFunderAddress;
            //(4)
            addressToIndexInFundersArray[lastFunderAddress] = currentFunderIndex;
        }
        //(1)
        funders.pop();
        //(2)
        delete addressToIndexInFundersArray[msg.sender];
        //(3)
        addressIsActiveFunder[msg.sender] = false;
    }

    //getPrice() uses Chainlink to get the latest price of ETH/USD, and verify that the price is not negative.
    function getPrice() public view returns (uint256) {
        (,int256 price ,,,) = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306).latestRoundData();
        require(price > 0, "Negative price not allowed.");
        return price.toUint256();
    }

    //getConversionRate() will find out what's the value of a specific amount of WEI(ETH) in USD.
    function getConversionRate(uint256 _price, uint256 _amountInWEI) public pure returns (uint256) {
        return (_price * _amountInWEI)/1e18;
    }

} 