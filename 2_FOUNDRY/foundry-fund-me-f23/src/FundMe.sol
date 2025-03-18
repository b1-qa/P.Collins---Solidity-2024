// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./SafeCast.sol"; //import the library OpenZeppelin SafeCast
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
using SafeCast for int256; //declare we use the library in this file.

error FundMe__NotOwner();

contract FundMe {
    bool private locked;
    address public immutable i_owner; //immutable if variable never changes, save gas.
    uint256 public minimumUsd;

    address[] private s_funders;
    mapping(address => uint256) private s_addressToIndexInFundersArray;
    mapping(address => bool) private s_addressIsActiveFunder;
    mapping(address => uint256) private s_addressToAvailableAmount;

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    modifier noReentrant() {
        //if locked == true, entrancy isn't allowed
        require(locked == false, "No re-entrancy allowed, please try again.");

        //if locked == false, locked will be equal to true, and then it'll run the function with modifier
        locked = true;
        //function with modifier will execute at this exact moment thanks to "_;"
        _;
        //after the function execution, locked is put back to false.
        locked = false;
    }

    AggregatorV3Interface private s_priceFeed;

    constructor(address priceFeed) {
        i_owner = msg.sender;
        s_priceFeed = AggregatorV3Interface(priceFeed);
        //added minimumUsd in a constructor so the value is initialised at contract creation.
        minimumUsd = 5 * 1e8;
    }

    //allow wallets to send funds to the contract directly, which will run fund() instead of them losing the amount sent.
    receive() external payable {
        fund();
    }

    //allow devs to send funds to the contract with data, which will run fund() instead of them losing their amount sent.
    fallback() external payable {
        fund();
    }

    //changeMinimumUsd can only be called by owner, and cannot be changed to the same value.
    function changeMinimumUsd(uint256 _newMinimumUsd) public onlyOwner {
        uint256 newMinimumUsd = _newMinimumUsd * 1e8;
        require(
            newMinimumUsd != minimumUsd,
            "Cannot change the value of minimumUsd to the same value."
        );
        minimumUsd = newMinimumUsd;
    }

    //wallets can use fund() to add money in the contract,
    //and we verify that the value they send is superior or equal to minimumUsd
    //then we add that amount to the addressToAvailableAmount mapping so we can track how much is their wallet's balance on the contract
    function fund() public payable {
        uint256 price = getPrice(s_priceFeed);
        uint256 conversionRate = getConversionRate(price, msg.value);
        require(conversionRate >= minimumUsd, "didn't send enough USD");
        if (!s_addressIsActiveFunder[msg.sender]) {
            s_addressToIndexInFundersArray[msg.sender] = s_funders.length;
            s_funders.push(msg.sender);
            s_addressIsActiveFunder[msg.sender] = true;
        }
        s_addressToAvailableAmount[msg.sender] += msg.value;
    }

    function changeFunder(address _newAddress) public noReentrant {
        require(
            s_addressIsActiveFunder[msg.sender],
            "Wallet address is not a funder."
        );
        uint256 balanceFunder = s_addressToAvailableAmount[msg.sender];
        cleanAfterUserWithdrawal();
        s_addressToAvailableAmount[_newAddress] += balanceFunder;
        if (!s_addressIsActiveFunder[_newAddress]) {
            s_addressToIndexInFundersArray[msg.sender] = s_funders.length;
            s_funders.push(msg.sender);
            s_addressIsActiveFunder[_newAddress] = true;
        }
    }

    //msg.sender can withdraw his wallet's contract balance partially only if his balance is > 0
    function partialWithdraw(uint256 _amount) public noReentrant {
        require(
            s_addressIsActiveFunder[msg.sender] == true,
            "Wallet address is not a funder."
        );
        s_addressToAvailableAmount[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success == true, "Transfer failed.");

        //if current address has no more balance anymore, it will call cleanAfterWithdrawal();
        if (s_addressToAvailableAmount[msg.sender] <= 0) {
            cleanAfterUserWithdrawal();
        }
    }

    //msg.sender can withdraw his wallet's contract balance totally only if his balance is > 0
    function totalWithdraw() public noReentrant {
        uint256 balance = s_addressToAvailableAmount[msg.sender];
        require(balance > 0, "Insufficient balance");
        s_addressToAvailableAmount[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success == true, "Transfer failed.");
        cleanAfterUserWithdrawal();
    }

    function ownerWithdrawFunds() public onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success == true, "Transfer failed.");
        cleanAfterOwnerWithdrawal();
    }

    //function that will clean mappings & array if the owner withdraw funds from contract
    function cleanAfterOwnerWithdrawal() internal {
        for (uint256 i = 0; i < s_funders.length; i++) {
            address funder = s_funders[i];
            s_addressToAvailableAmount[funder] = 0;
            s_addressToIndexInFundersArray[funder] = 0;
            s_addressIsActiveFunder[funder] = false;
        }
        //here, reset the funders array
        //could have used funders = new address[](0) but it's more costly in gas.
        delete s_funders;
    }

    //(1) remove msg.sender's address from funders
    //(2) delete his index from array,
    //(3) state he's not an active funder
    function cleanAfterUserWithdrawal() internal {
        address lastFunderAddress = s_funders[s_funders.length - 1];
        uint256 currentFunderIndex = s_addressToIndexInFundersArray[msg.sender];
        //if current address is not the last funder, it will:
        //(4) give last funder the current funder's position
        if (
            s_addressToIndexInFundersArray[msg.sender] != s_funders.length - 1
        ) {
            s_funders[currentFunderIndex] = lastFunderAddress;
            //(4)
            s_addressToIndexInFundersArray[
                lastFunderAddress
            ] = currentFunderIndex;
        }
        //(1)
        s_funders.pop();
        //(2)
        delete s_addressToIndexInFundersArray[msg.sender];
        //(3)
        s_addressIsActiveFunder[msg.sender] = false;
    }

    //getPrice() uses Chainlink to get the latest price of ETH/USD, and verify that the price is not negative.
    function getPrice(
        AggregatorV3Interface priceFeed
    ) public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(priceFeed)
            .latestRoundData();
        require(price > 0, "Negative price not allowed.");
        return price.toUint256();
    }

    function getVersion() public view returns (uint256) {
        return s_priceFeed.version();
    }

    //getConversionRate() will find out what's the value of a specific amount of WEI(ETH) in USD.
    function getConversionRate(
        uint256 _price,
        uint256 _amountInWEI
    ) public pure returns (uint256) {
        return (_price * _amountInWEI) / 1e18;
    }

    /**
     * View/Pure functions (getters)
     */

    function getAddressToAmountFunded(
        address _fundingAddress
    ) external view returns (uint256) {
        return s_addressToAvailableAmount[_fundingAddress];
    }

    function getFunder(uint256 _index) external view returns (address) {
        return s_funders[_index];
    }

    function getFundersCount() external view returns (uint256) {
        return s_funders.length;
    }
}
