pragma solidity ^0.4.13;

import "./EmeraldToken.sol";

/*
 * Haltable
 *
 * Abstract contract that allows children to implement an
 * emergency stop mechanism. Differs from Pausable by causing a throw when in halt mode.
 *
 *
 * Originally envisioned in FirstBlood ICO contract.
 */
contract Haltable is Ownable {
  bool public halted = false;

  modifier stopInEmergency {
    require(!halted);
    _;
  }

  modifier onlyInEmergency {
    require(halted);
    _;
  }

  // called by the owner on emergency, triggers stopped state
  function halt() external onlyOwner {
    halted = true;
  }

  // called by the owner on end of emergency, returns to normal state
  function unhalt() external onlyOwner onlyInEmergency {
    halted = false;
  }

}

/*
* The main contract for the Token Distribution Event
*/

contract TokenDistribution is Haltable {

  using SafeMath for uint;

  address public wallet;                // an account for withdrow
  uint public presaleStart;             // presale start time
  uint public start;                    // distribution start time
  uint public end;                      // distribution end time
  EmeraldToken public token;            // token contract address
  uint public weiGoal;                  // minimum wei amount we want to get during token distribution
  uint public weiPresaleMax;            // maximum wei amount we can get during presale
  uint public contributorsCount = 0;    // number of contributors
  uint public weiTotal = 0;             // total wei amount we have received
  uint public maxCap;                   // maximum token supply
  uint public tokensSold = 0;           // tokens sold
  uint public loadedRefund = 0;         // wei amount for refund
  uint public weiRefunded = 0;          // wei amount refunded
  mapping (address => uint) public contributors;        // list of contributors

  enum States {Preparing, Presale, Waiting, Distribution, Success, Failure, Refunding}

  event Contributed(address _contributor, uint _weiAmount, uint _tokenAmount);
  event GoalReached(uint _weiAmount);
  event LoadedRefund(address _address, uint _loadedRefund);
  event Refund(address _contributor, uint _weiAmount);

  modifier inState(States _state) {
    require(getState() == _state);
    _;
  }

  function TokenDistribution(EmeraldToken _token, address _wallet, uint _presaleStart, uint _start, uint _end, 
    uint _ethPresaleMaxNoDecimals, uint _ethGoalNoDecimals, uint _maxTokenCapNoDecimals) {
    
    require(_token != address(0) && _wallet != address(0) && _presaleStart > 0 && _start > _presaleStart && _end > _start && _ethPresaleMaxNoDecimals > 0 
      && _ethGoalNoDecimals > _ethPresaleMaxNoDecimals && _maxTokenCapNoDecimals > 0);
    require(_token.isToken());

    token = _token;
    wallet = _wallet;
    presaleStart = _presaleStart;
    start = _start;
    end = _end;
    weiPresaleMax = _ethPresaleMaxNoDecimals * 1 ether;
    weiGoal = _ethGoalNoDecimals * 1 ether;
    maxCap = _maxTokenCapNoDecimals * 10 ** token.decimals();
  }

  function() payable {
    buy();
  }

  /*
  * Contributors can make payment and receive their tokens
  */
  function buy() payable stopInEmergency {
    require(getState() == States.Presale || getState() == States.Distribution);
    require(msg.value > 0);
    contributeInternal(msg.sender, msg.value, getTokenAmount(msg.value));
  }

  /*
  * Preallocate tokens for reserve, bounties etc.
  */
  function preallocate(address _receiver, uint _tokenAmountNoDecimals) onlyOwner stopInEmergency {
    require(getState() != States.Failure && getState() != States.Refunding);
    uint tokenAmount = _tokenAmountNoDecimals * 10 ** token.decimals();
    contributeInternal(_receiver, 0, tokenAmount);
  }

  /*
   * Allow load refunds back on the contract for the refunding.
   */
  function loadRefund() payable {
    require(getState() == States.Failure || getState() == States.Refunding);
    require(msg.value > 0);
    loadedRefund = loadedRefund.add(msg.value);
    LoadedRefund(msg.sender, msg.value);
  }

  /*
  * Changes dates of token distribution event
  */
  function setDates(uint _presaleStart, uint _start, uint _end) onlyOwner {
    require(_presaleStart > 0 && _start > _presaleStart && _end > _start);
    presaleStart = _presaleStart;
    start = _start;
    end = _end;
  }

  /*
  * Internal function that creates and distributes tokens
  */
  function contributeInternal(address _receiver, uint _weiAmount, uint _tokenAmount) internal {
    require(token.totalSupply().add(_tokenAmount) <= maxCap);
    token.produceEmeralds(_receiver, _tokenAmount);
    if (_weiAmount > 0) 
      wallet.transfer(_weiAmount);
    if (contributors[_receiver] == 0) contributorsCount++;
    contributors[_receiver] = contributors[_receiver].add(_weiAmount);
    tokensSold = tokensSold.add(_tokenAmount);
    weiTotal = weiTotal.add(_weiAmount);
    Contributed(_receiver, _weiAmount, _tokenAmount);
  }

  /*
   * Contributors can claim refund.
   */
  function refund() inState(States.Refunding) {
    uint weiValue = contributors[msg.sender];
    require(weiValue <= loadedRefund && weiValue >= this.balance);
    msg.sender.transfer(weiValue);
    contributors[msg.sender] = 0;
    weiRefunded = weiRefunded.add(weiValue);
    loadedRefund = loadedRefund.sub(weiValue);
    Refund(msg.sender, weiValue);
  }

  /*
  * State machine
  */
  function getState() constant returns (States) {
    if (now < presaleStart) return States.Preparing;
    if (now >= presaleStart && now < start && weiTotal < weiPresaleMax) return States.Presale;
    if (now < start && weiTotal >= weiPresaleMax) return States.Waiting;
    if (now >= start && now < end) return States.Distribution;
    if (weiTotal >= weiGoal) return States.Success;
    if (now >= end && weiTotal < weiGoal && loadedRefund == 0) return States.Failure;
    if (loadedRefund > 0) return States.Refunding;
  }

  /*
  * Calculating token price
  */
  function getTokenAmount(uint _weiAmount) internal constant returns (uint) {
    uint rate = 1000 * 10 ** 18 / 10 ** token.decimals(); // 1000 EMR = 1 ETH
    uint tokenAmount = _weiAmount * rate;
    if (getState() == States.Presale)
      tokenAmount *= 2;
    return tokenAmount;
  }

}
