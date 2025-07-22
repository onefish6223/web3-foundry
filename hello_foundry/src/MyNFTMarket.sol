// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Counters.sol";

contract MyNFTMarket is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _listingIdCounter; //用于生成市场列表的id
    //市场列表的单行结构体
    struct Listing {
        address seller;
        uint256 price;
        address nftContract;
        uint256 tokenId;
    }

    mapping(uint256 => Listing) public listings; // 映射 listingId 到 Listing
    //nftContract => (tokenid => listingid)
    mapping(address => mapping(uint256 => uint256)) public nftToListing; // 映射 NFT 到上架信息

    IERC20 public paymentToken; // 用于支付的 ERC20 代币

    constructor(address _paymentToken) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
    }

    // 上架函数
    function list(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external {
        //调用者 需要持有tokenId对应的NFT
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "You do not own this NFT"
        );
        require(price > 0, "Price must be greater than 0");

        _listingIdCounter.increment();
        uint256 listingId = _listingIdCounter.current();

        listings[listingId] = Listing({
            seller: msg.sender,
            price: price,
            nftContract: nftContract,
            tokenId: tokenId
        });

        nftToListing[nftContract][tokenId] = listingId;

        //这个方法暂时不能调 需要实现回调 ERC721Utils.sol,使用在不需要授权的业务场景--由用户在NFT合约直接调用，该合约内单独实现回调函数onERC721Received();
        // IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        // 将 NFT 从卖家地址转到合约地址以避免交易后卖家撤销. 需要持有者 先在ERC721合约对NFTMarket合约地址进行授权
        // wake-disable
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        emit Listed(listingId, msg.sender, nftContract, tokenId, price);
    }

    // 回调函数
    // 用户通过在ERC20合约里调用ERC20的ransferWithCallback函数 触发此函数
    function tokensReceived(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data // 需要客户传 listingId
    ) external {
        // 确保调用者是代币合约
        require(
            msg.sender == address(paymentToken),
            "Only token contract can call this"
        );
        // 确保接收者是本合约
        require(recipient == address(this), "Invalid recipient");
        // 确保标识有效
        uint256 listingId = abi.decode(data, (uint256));

        Listing memory listing = listings[listingId];
        require(listing.price > 0, "This NFT is not for sale");
        uint256 price = listing.price;
        address seller = listing.seller;
        address nftContract = listing.nftContract;
        uint256 tokenId = listing.tokenId;
        // 确保支付的金额 等于NFT的价格
        require(amount == price, "Invalid amount");
        // 从当前合约账户转账代币到卖家
        paymentToken.transferFrom(address(this), seller, price);
        // 将 NFT 转到买家
        IERC721(nftContract).transferFrom(address(this), sender, tokenId);

        // 移除上架信息
        delete listings[listingId];
        delete nftToListing[nftContract][tokenId];

        emit Purchased(listingId, msg.sender, nftContract, tokenId, price);
    }

    // 普通的购买 NFT 功能，用户转入所定价的 token 数量，获得对应的 NFT
    // 这种购买方式 需要用户 先在ERC20 token合约内 授权NFTMarket合约地址相应的金额，此后 当前合约调用ERC20的转账函数才能成功
    function buyNFT(uint256 listingId) external {
        Listing memory listing = listings[listingId];
        require(listing.price > 0, "This NFT is not for sale");

        uint256 price = listing.price;
        address seller = listing.seller;
        address nftContract = listing.nftContract;
        uint256 tokenId = listing.tokenId;

        // 确保买家有足够的支付代币
        require(
            paymentToken.balanceOf(msg.sender) >= price,
            "Insufficient funds"
        );

        // 从买家账户转账代币到卖家
        paymentToken.transferFrom(msg.sender, seller, price);

        // 将 NFT 转到买家
        IERC721(nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        // 移除上架信息
        delete listings[listingId];
        delete nftToListing[nftContract][tokenId];

        emit Purchased(listingId, msg.sender, nftContract, tokenId, price);
    }

    event Listed(
        uint256 listingId,
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    event Purchased(
        uint256 listingId,
        address buyer,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
}
