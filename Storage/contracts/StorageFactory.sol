// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18; //solidity version

import {SimpleStorage} from "./SimpleStorage.sol";

contract StorageFactory{

    //uint256 public favoriteNumber
    //type visibility name
    SimpleStorage [] public listOfSimpleStorageContracts;

    function createSimpleStorageContract() public {
        SimpleStorage newSimpleStorageContract = new SimpleStorage();
        listOfSimpleStorageContracts.push(newSimpleStorageContract);
    }

    function sfStore(uint256 _simpleStorageIndex, uint256 _newSimpleStorageNumber) public {
        //Address
        //ABI
        listOfSimpleStorageContracts[_simpleStorageIndex].store(_newSimpleStorageNumber);
    } 

    function sfGet(uint256 _simpleStorageIndex) public view returns(uint256) {
        return listOfSimpleStorageContracts[_simpleStorageIndex].retrieve();
    }
}