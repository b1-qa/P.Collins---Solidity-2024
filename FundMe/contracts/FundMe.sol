// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

//Get funds from users
//Withdraw funds
//Set a minimum funding value in USD
import "./SafeCast.sol"; //import the library OpenZeppelin SafeCast

using SafeCast for int256; //declare we use the library in this file.

// solhint-disable-next-line interface-starts-with-i
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract FundMe {

    address public owner;
    uint256 public minimumUsd;

    constructor() {
        owner = msg.sender;

        //added minimumUsd in a constructor so the value is initialised at contract creation.
        minimumUsd = 5*1e8;
    }

    //mapping to get a specific wallet address' contribution amount
    mapping (address => uint256) public addressToAvailableAmount;

    //changeMinimumUsd can only be called by owner, and cannot be changed to the same value.
    function changeMinimumUsd(uint256 _newMinimumUsd) public {
        require(msg.sender == owner, "Only the owner of the contract can change the minimum amount of USD.");
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
        addressToAvailableAmount[msg.sender] += msg.value;
    } 

    //msg.sender can withdraw his wallet's contract balance partially only if his balance is > 0
    function partialWithdraw(uint256 _amount) public {
        uint256 balance = addressToAvailableAmount[msg.sender];
        require(balance >= _amount, "Insufficient balance");
        addressToAvailableAmount[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success == true, "Transfer failed.");
    }

    //msg.sender can withdraw his wallet's contract balance totally only if his balance is > 0
    function totalWithdraw() public {
        uint256 balance = addressToAvailableAmount[msg.sender];
        require(balance > 0, "Insufficient balance");
        addressToAvailableAmount[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success == true, "Transfer failed.");
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