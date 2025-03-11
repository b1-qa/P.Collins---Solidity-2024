// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16; //solidity version

contract SimpleStorage {
    uint256 public myFavoriteNumber;
    struct Person{
        uint256 favoriteNumber;
        string name;
    }

    Person[] public listOfPeople; // []

    function store(uint256 _favoriteNumber) public virtual{
        myFavoriteNumber = _favoriteNumber;
    } 

    function retrieve() public view returns(uint256) {
        return myFavoriteNumber;
    } 

    mapping (string => uint256) public nameToFavoriteNumber;

    //calldata vs memory vs storage
    //memory: a variable inside a memory function can be changed temporarily just for the function
    //calldata: a variable inside a calldata function can't be changed at all
    //storage: a variable inside a storage function can be changed and then it'll be stored on-chain, like myFavoriteNumber

    function addPerson(string calldata _name, uint256  _favoriteNumber) public {
        listOfPeople.push( Person(_favoriteNumber, _name) );
        nameToFavoriteNumber[_name] = _favoriteNumber;
    }
}