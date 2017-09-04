pragma solidity ^0.4.13;

import "./SimpleToken.sol";

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

contract SimpleDistribution is Haltable {

  using SafeMath for uint;

  address public wallet;                // an account for receiving 
  uint public start;                    // start time
  uint public end;                      // end time
  SimpleToken public token;             // token contract address
  uint public weiGoal;                  // minimum wei amount we want to get
  uint public contributorsCount = 0;    // number of contributors
  uint public weiTotal = 0;             // total wei amount we have received
  uint public tokensSold = 0;           // tokens sold
  uint public loadedRefund = 0;         // wei amount for refund
  uint public weiRefunded = 0;          // wei amount refunded
  mapping (address => uint) public contributed;        // list of contributors
  mapping (address => uint) public preallocatedTokens;        // list of preallocated tokens receivers

  enum States {Preparing, Distribution, Success, Failure, Refunding}

  event Contributed(address _contributor, uint _weiAmount, uint _tokenAmount);
  event Refund(address _contributor, uint _weiAmount);

  function SimpleDistribution(SimpleToken _token, address _wallet, uint _start, uint _end, uint _weiGoal) {
    
    require(_token != address(0) && _wallet != address(0) && _start != 0 && _end != 0 && _start < _end);
    require(_token.isToken());

    token = _token;
    start = _start;
    end = _end;
    weiGoal = _weiGoal;
    wallet = _wallet;
  }

  function contributeInternal(address _receiver, uint _weiAmount, uint _tokenAmount) stopInEmergency internal {
    if (contributed[_receiver] == 0 && _weiAmount > 0) contributorsCount++;
    contributed[_receiver] = contributed[_receiver].add(_weiAmount);
    tokensSold = tokensSold.add(_tokenAmount);
    weiTotal = weiTotal.add(_weiAmount);
    token.distribute(_receiver, _tokenAmount);
    wallet.transfer(_weiAmount);
    Contributed(_receiver, _weiAmount, _tokenAmount);
  }

  /*
  * Contributors can make payment and receive their tokens
  */
  function buy() payable inState(States.Distribution) {
    require(msg.value > 0);
    uint price = 1000 * 10 ** 18 / 10 ** token.decimals(); // 1000 EMR = 1 ETH
    uint tokenAmount = msg.value * price;
    contributeInternal(msg.sender, msg.value, tokenAmount);
  }

  function preallocate(address _receiver, uint _tokenAmount) onlyOwner {
    preallocatedTokens[_receiver] = _tokenAmount;
    contributeInternal(_receiver, 0, _tokenAmount);
  }

  /*
   * Allow load refunds back on the contract for the refunding.
   */
  function loadRefund() payable inState(States.Failure) {
    require(msg.value > 0);
    loadedRefund = loadedRefund.add(msg.value);
  }

  /*
   * Contributors can claim refund.
   */
  function refund() inState(States.Refunding) {
    uint weiValue = contributed[msg.sender];
    require(weiValue > 0);
    contributed[msg.sender] = 0;
    weiRefunded = weiRefunded.add(weiValue);
    Refund(msg.sender, weiValue);
    msg.sender.transfer(weiValue);
  }

  function() payable {
    buy();
  }

  /*
  * State machine
  */
  function getState() constant returns (States) {
    if (token.distributionContract() == address(0) || now < start) return States.Preparing;
    if (now >= start && now < end) return States.Distribution;
    if (weiTotal >= weiGoal) return States.Success;
    if (now >= end && weiTotal < weiGoal && loadedRefund == 0) return States.Failure;
    if (loadedRefund > 0) return States.Refunding;
  }

  modifier inState(States _state) {
    require(getState() == _state);
    _;
  }

}
