// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NFTMarket {
    struct Listing {
        address seller;
        address erc20;
        uint256 price;
    }

    // nft合约 => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) public listings;

    event Listed(
        address indexed nft,
        uint256 indexed tokenId,
        address indexed seller,
        address erc20,
        uint256 price
    );
    event Purchased(
        address indexed nft,
        uint256 indexed tokenId,
        address indexed buyer,
        address erc20,
        uint256 price
    );

    // 上架NFT
    function listNFT(
        address nft,
        uint256 tokenId,
        address erc20,
        uint256 price
    ) external {
        require(price > 0, "Price must be positive");
        require(listings[nft][tokenId].seller == address(0), "Already listed");
        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "Not owner");
        require(
            IERC721(nft).isApprovedForAll(msg.sender, address(this)) ||
                IERC721(nft).getApproved(tokenId) == address(this),
            "Market not approved"
        );

        listings[nft][tokenId] = Listing(msg.sender, erc20, price);
        emit Listed(nft, tokenId, msg.sender, erc20, price);
    }

    // 购买NFT
    function buyNFT(address nft, uint256 tokenId) external {
        Listing memory l = listings[nft][tokenId];
        require(l.seller != address(0), "Not listed");
        require(msg.sender != l.seller, "Cannot buy your own NFT");
        require(
            IERC20(l.erc20).allowance(msg.sender, address(this)) >= l.price,
            "Insufficient allowance"
        );
        require(
            IERC20(l.erc20).balanceOf(msg.sender) >= l.price,
            "Insufficient balance"
        );

        // 转账
        // wake-disable
        bool ok = IERC20(l.erc20).transferFrom(msg.sender, l.seller, l.price);
        require(ok, "ERC20 transfer failed");

        // 转NFT
        IERC721(nft).safeTransferFrom(l.seller, msg.sender, tokenId);

        delete listings[nft][tokenId];
        emit Purchased(nft, tokenId, msg.sender, l.erc20, l.price);
    }
}
