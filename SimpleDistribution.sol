pragma solidity 0.4.11;

import "./SafeMathLib.sol";
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
  bool public halted;

  modifier stopInEmergency {
    if (halted) revert();
    _;
  }

  modifier onlyInEmergency {
    if (!halted) revert();
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

  using SafeMathLib for uint;

  address public wallet; // an account for receiving 
  uint public start;
  uint public end;
  SimpleToken public token;
  uint public weiGoal;
  uint public contributorsCount = 0;
  uint public weiTotal = 0;
  uint public tokensSold = 0;
  uint public loadedRefund = 0;
  uint public weiRefunded = 0;
  mapping (address => uint) public contributed;

  enum States {Preparing, Distribution, Success, Failure, Refunding}

  event Contributed(address contributor, uint weiAmount, uint tokenAmount);
  event Refund(address contributor, uint weiAmount);

  function SimpleDistribution(SimpleToken _token, address _wallet, uint _start, uint _end, uint _weiGoal) {
    
    if (_token == address(0) || _wallet == address(0) || _start == 0 || _end == 0 || _start >= _end) revert();

    token = _token;
    
    if (!token.isToken()) revert();
    
    start = _start;
    end = _end;
    weiGoal = _weiGoal;
    wallet = _wallet;

    token.initialize(this, wallet);
    if (token.distributionContract() != address(this)) revert();
  }

  function contributeInternal(address receiver, uint weiAmount) stopInEmergency internal {
    uint tokenAmount = weiAmount * 1000;
    if (contributed[receiver] == 0) contributorsCount++;
    contributed[receiver] = contributed[receiver].plus(weiAmount);    
    tokensSold = tokensSold.plus(tokenAmount);
    weiTotal = weiTotal.plus(weiAmount);
    token.distribute(wallet, receiver, tokenAmount);
    wallet.transfer(weiAmount);
    Contributed(receiver, weiAmount, tokenAmount);
  }

  /*
  * Contributors can make payment and receive their tokens
  */
  function contribute() payable inState(States.Distribution) {
    if (msg.value == 0) revert();
    contributeInternal(msg.sender, msg.value);
  }

  /*
   * Allow load refunds back on the contract for the refunding.
   */
  function loadRefund() payable inState(States.Failure) {
    if(msg.value == 0) revert();
    loadedRefund = loadedRefund.plus(msg.value);
  }

  /*
   * Contributors can claim refund.
   */
  function refund() inState(States.Refunding) {
    uint weiValue = contributed[msg.sender];
    if (weiValue == 0) revert();
    contributed[msg.sender] = 0;
    weiRefunded = weiRefunded.plus(weiValue);
    Refund(msg.sender, weiValue);
    msg.sender.transfer(weiValue);
  }

  function() payable {
    revert();
  }

  /*
  * State machine
  */
  function getState() constant returns (States) {
    if (token.distributionContract() == address(0) || now < start) return States.Preparing;
    else if (now >= start && now < end) return States.Distribution;
    else if (weiTotal >= weiGoal) return States.Success;
    else if (now >= end && weiTotal < weiGoal && loadedRefund == 0) return States.Failure;
    else if (loadedRefund > 0) return States.Refunding;
  }

  modifier inState(States state) {
    if(getState() != state) revert();
    _;
  }

}
