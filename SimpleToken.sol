pragma solidity ^0.4.13;

import "./SafeMath.sol";

/*
 * ERC20 interface
 * see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
  uint public totalSupply;
  function balanceOf(address who) constant returns (uint);
  function allowance(address owner, address spender) constant returns (uint);

  function transfer(address to, uint value) returns (bool);
  function transferFrom(address from, address to, uint value) returns (bool);
  function approve(address spender, uint value) returns (bool ok);
  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
}


/**
 * Standard ERC20 token with Short Hand Attack and approve() race condition mitigation.
 *
 * Based on code by FirstBlood:
 * https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20 {

  using SafeMath for uint;

  /* Actual balances of token holders */
  mapping(address => uint) balances;

  /* approve() allowances */
  mapping (address => mapping (address => uint)) allowed;

  /* Interface declaration */
  function isToken() public constant returns (bool) {
    return true;
  }

  /**
   *
   * Fix for the ERC20 short address attack
   *
   * http://vessenes.com/the-erc20-short-address-attack-explained/
   */
  modifier onlyPayloadSize(uint size) {
    require(msg.data.length >= size + 4);
    _;
  }

  function transfer(address _to, uint _value) onlyPayloadSize(2 * 32) returns (bool) {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint _value) returns (bool) {
    uint _allowance = allowed[_from][msg.sender];

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner];
  }

  function approve(address _spender, uint _value) returns (bool success) {

    // To change the approve amount you first have to reduce the addresses`
    //  allowance to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require((_value == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  function allowance(address _owner, address _spender) constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }

}



/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) onlyOwner {
    require(newOwner != address(0));      
    owner = newOwner;
  }

}


contract SimpleToken is StandardToken, Ownable {

  string public name;
  string public symbol;
  uint public decimals;

  address public distributionContract;

  bool public released = false;

  /*
  * Only distribution contract allowed
  */
  modifier onlyDistribution() {
    require(msg.sender == distributionContract);
    _;
  }

  /**
   * Limit token transfer until the distribution is over.
   *
   */
  modifier canTransfer(address _sender) {
    require(released);
    _;
  }

  function SimpleToken(string _name, string _symbol, uint _totalSupply, uint _decimals) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    totalSupply = _totalSupply;
  }

  /**
   * Distribution contract sets its and wallet addresses. All token balance is assigned to wallet address.
   */
  function initialize(address _distributionContract, address _initialAddr) {
    // The function can start only once
    require(distributionContract ==  address(0));
    require((_distributionContract != address(0)) && (_initialAddr != address(0)));
    distributionContract = _distributionContract;
    balances[_initialAddr] = totalSupply;
  }

  /*
  * This function sends tokens from wallet to contributors
  * Only distribution contract can assign tokens
  */
  function distribute(address _sender, address _receiver, uint _amount) onlyDistribution {
    balances[_receiver] = balances[_receiver].add(_amount);
    balances[_sender] = balances[_sender].sub(_amount);
    Transfer(_sender, _receiver, _amount);
  }

  /**
   * One way function to release the tokens to the wild.
   */
  function releaseTokenTransfer() onlyOwner {
    released = true;
  }

  function transfer(address _to, uint _value) canTransfer(msg.sender) returns (bool) {
    // Call StandardToken.transfer()
   return super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) canTransfer(_from) returns (bool) {
    // Call StandardToken.transferForm()
    return super.transferFrom(_from, _to, _value);
  }

}

