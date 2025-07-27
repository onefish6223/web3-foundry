// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFTV4 is ERC721, Ownable {
    uint256 private _tokenIdCounter;
    
    constructor() ERC721("LMXNFT", "LNT") Ownable(msg.sender) {
        _tokenIdCounter = 1;
    }
    
    function mint() external onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);
        return tokenId;
    }
}
