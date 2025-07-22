// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 引入 OpenZeppelin 的 ERC721 合约
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Counters.sol";

// 定义 NFT 合约
contract MyNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    
    // 计数器，用于生成唯一的 token ID
    Counters.Counter private _tokenIdCounter;

    // 构造函数，传入 NFT 的名称和符号
    constructor() ERC721("LimengxNFT", "LMXNFT") Ownable(msg.sender){}

    // 内部函数，生成新的 token ID
    function _mintNFT(address to,string memory tokenURI) internal returns (uint256) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        return tokenId;
    }

    // 公共函数，用于用户铸造新的 NFT
    function mint(string memory tokenURI) public onlyOwner returns (uint256) {
        return _mintNFT(msg.sender,tokenURI);
    }

    // 公共函数，用于用户铸造给指定地址的 NFT
    function mintTo(address to,string memory tokenURI) public onlyOwner returns (uint256) {
        return _mintNFT(to,tokenURI);
    }

    // 查询当前 NFT 总数
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
}
