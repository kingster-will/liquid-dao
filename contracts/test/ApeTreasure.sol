// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ApeTreasure is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public apeClaim;
    uint public nextReleaseTime;
    uint public releaseInterval;
    uint public releaseNonce;
    // release nonce => released amount
    mapping (uint => uint) public releasedAmount;

    constructor() {}

    function initialize(IERC20 token_, address apeClaim_) public initializer {
        token = token_;
        apeClaim = apeClaim_;
        nextReleaseTime = block.timestamp;
        releaseInterval = 30 minutes;
        releaseNonce = 0;
    }

    function release(uint amount) external {
        require(amount <= 100*1e18, "Please not release too much, <= 100 ETH");
        require(block.timestamp > nextReleaseTime, "Be patient, can only release once per hour");
        require(token.balanceOf(address(this)) >= amount, "No more fund can be released");
        token.safeTransfer(apeClaim, amount);
        releasedAmount[releaseNonce] = amount;
        releaseNonce += 1;
    }
}
