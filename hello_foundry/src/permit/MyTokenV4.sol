// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";

contract MyToken is ERC1363, ERC20Permit {
    constructor() 
        ERC20("LiMengxiang", "LMX")
        ERC20Permit("LiMengxiang") 
    {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}
