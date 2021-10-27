// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./ApeClaim.sol";

contract ApeClaimErc20 is ApeClaim, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 public token;
    function initialize(IERC20 token_) public initializer {
        token = token_;
    }

    function _transferFund(address to_, uint amount_) internal virtual override {
        token.safeTransfer(to_, amount_);
    }

    function _getBalance(address who_) internal view virtual override returns(uint) {
        return token.balanceOf(who_);
    }

}
