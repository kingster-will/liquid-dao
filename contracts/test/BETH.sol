// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract BETH is ERC20PresetFixedSupply {

    constructor() ERC20PresetFixedSupply("BETH", "ETH", 50000*1e18, msg.sender) {}
}