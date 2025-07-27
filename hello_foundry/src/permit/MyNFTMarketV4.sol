// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title NFTMarket
 * @dev 支持ERC721、ERC1155标准和白名单离线授权购买的NFT市场合约
 */
contract NFTMarket is ReentrancyGuard, Ownable, EIP712 {

    using ECDSA for bytes32;
    
    // 计数器：用于跟踪listing ID
    uint256 private _listingIdCounter;
    
    // 平台手续费比例（万分比，100 = 1%）
    uint256 public platformFeePercentage = 0; // 默认2%
    
    // 平台手续费接收地址
    address public feeReceiver;
    
    // 项目方签名者地址（用于白名单签名）
    address public signer;
    
    // 防止重放攻击：记录已使用的签名
    mapping(bytes32 => bool) public usedSignatures;
    
    // 代币类型枚举
    enum TokenType {
        ERC721,
        ERC1155
    }
    
    // NFT Listing结构体
    struct Listing {
        uint256 id;             // listing ID
        address nftContract;    // NFT合约地址
        uint256 tokenId;        // NFT token ID
        TokenType tokenType;    // 代币类型
        address seller;         // 卖家地址
        address buyer;          // 买家地址（未售出为address(0)）
        uint256 price;          // 单价（以wei为单位）
        uint256 amount;         // 数量（仅ERC1155使用）
        bool active;            // 是否有效（未售出且未取消）
        bool requiresWhitelist; // 是否需要白名单才能购买
    }
    
    // 存储所有listings：listing ID => Listing
    mapping(uint256 => Listing) public listings;
    
    // 记录NFT是否已被上架：nft合约地址 => tokenId => listing ID
    mapping(address => mapping(uint256 => uint256)) public nftToListingId;
    
    // EIP-712 相关设置
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "PermitBuy(address buyer,uint256 listingId,uint256 nonce,uint256 deadline)"
    );
    
    // 每个地址的nonce，用于防止重放攻击
    mapping(address => uint256) public nonces;
    
    // 事件：当NFT被上架时触发
    event ListingCreated(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        TokenType tokenType,
        address seller,
        uint256 price,
        uint256 amount,
        bool requiresWhitelist,
        uint256 timestamp
    );
    
    // 事件：当NFT listing被取消时触发
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        TokenType tokenType,
        address seller,
        uint256 timestamp
    );
    
    // 事件：当NFT被购买时触发
    event NFTPurchased(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        TokenType tokenType,
        address seller,
        address buyer,
        uint256 price,
        uint256 amount,
        uint256 platformFee,
        bool isPermitBuy,
        uint256 timestamp
    );
    
    // 事件：当平台手续费比例更新时触发
    event PlatformFeeUpdated(uint256 newFeePercentage, uint256 timestamp);
    
    // 事件：当手续费接收地址更新时触发
    event FeeReceiverUpdated(address newFeeReceiver, uint256 timestamp);
    
    // 事件：当签名者地址更新时触发
    event SignerUpdated(address newSigner, uint256 timestamp);
    
    /**
     * @dev 构造函数，初始化EIP712、手续费接收地址和签名者地址
     * @param _signer 项目方签名者地址
     */
    constructor(address _signer) EIP712("NFTMarket", "1")Ownable(_signer) {
        require(_signer != address(0), "Invalid signer address");
        feeReceiver = msg.sender;
        signer = _signer;
        _listingIdCounter++;
    }
    
    /**
     * @dev 设置签名者地址（仅所有者）
     * @param _signer 新的签名者地址
     */
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Invalid signer address");
        signer = _signer;
        emit SignerUpdated(_signer, block.timestamp);
    }
    
    /**
     * @dev 创建ERC721 NFT listing（上架NFT）
     * @param nftContract NFT合约地址
     * @param tokenId NFT的token ID
     * @param price 售价（以wei为单位）
     * @param requiresWhitelist 是否需要白名单才能购买
     */
    function create721Listing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool requiresWhitelist
    ) external nonReentrant {
        require(nftContract != address(0), "NFT contract address cannot be zero");
        require(price > 0, "Price must be greater than 0");
        require(nftToListingId[nftContract][tokenId] == 0, "This NFT is already listed");
        
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "You are not the owner of this NFT");
        require(
            nft.isApprovedForAll(msg.sender, address(this)) || 
            nft.getApproved(tokenId) == address(this),
            "Contract is not authorized for this NFT"
        );
        
        // 生成新的listing ID
        uint256 listingId = _listingIdCounter++;
        
        // 创建新的listing（ERC721数量固定为1）
        listings[listingId] = Listing({
            id: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            tokenType: TokenType.ERC721,
            seller: msg.sender,
            buyer: address(0),
            price: price,
            amount: 1,
            active: true,
            requiresWhitelist: requiresWhitelist
        });
        
        // 记录NFT对应的listing ID
        nftToListingId[nftContract][tokenId] = listingId;
        
        emit ListingCreated(
            listingId,
            nftContract,
            tokenId,
            TokenType.ERC721,
            msg.sender,
            price,
            1,
            requiresWhitelist,
            block.timestamp
        );
    }
    
    /**
     * @dev 创建ERC1155 NFT listing（上架NFT）
     * @param nftContract NFT合约地址
     * @param tokenId NFT的token ID
     * @param price 单价（以wei为单位）
     * @param amount 数量
     * @param requiresWhitelist 是否需要白名单才能购买
     */
    function create1155Listing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 amount,
        bool requiresWhitelist
    ) external nonReentrant {
        require(nftContract != address(0), "NFT contract address cannot be zero");
        require(price > 0, "Price must be greater than 0");
        require(amount > 0, "Amount must be greater than 0");
        require(nftToListingId[nftContract][tokenId] == 0, "This NFT is already listed");
        
        IERC1155 nft = IERC1155(nftContract);
        require(nft.balanceOf(msg.sender, tokenId) >= amount, "Insufficient NFT balance");
        require(
            nft.isApprovedForAll(msg.sender, address(this)),
            "Contract is not authorized for this NFT"
        );
        
        // 生成新的listing ID
        uint256 listingId = _listingIdCounter++;
        
        // 创建新的listing
        listings[listingId] = Listing({
            id: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            tokenType: TokenType.ERC1155,
            seller: msg.sender,
            buyer: address(0),
            price: price,
            amount: amount,
            active: true,
            requiresWhitelist: requiresWhitelist
        });
        
        // 记录NFT对应的listing ID
        nftToListingId[nftContract][tokenId] = listingId;
        
        emit ListingCreated(
            listingId,
            nftContract,
            tokenId,
            TokenType.ERC1155,
            msg.sender,
            price,
            amount,
            requiresWhitelist,
            block.timestamp
        );
    }
    
    /**
     * @dev 取消NFT listing（下架NFT）
     * @param listingId 要取消的listing ID
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.id == listingId, "Listing does not exist");
        require(listing.seller == msg.sender, "You are not the seller of this listing");
        require(listing.active, "This listing is already inactive");
        
        // 标记为失效
        listing.active = false;
        
        // 清除NFT与listing的关联
        nftToListingId[listing.nftContract][listing.tokenId] = 0;
        
        emit ListingCancelled(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.tokenType,
            msg.sender,
            block.timestamp
        );
    }
    
    /**
     * @dev 普通购买NFT（适用于不需要白名单的listing）
     * @param listingId 要购买的NFT的listing ID
     * @param amount 购买数量（仅对ERC1155有效，ERC721固定为1）
     */
    function buyNFT(uint256 listingId, uint256 amount) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        // 如果需要白名单，则不能通过普通购买
        require(!listing.requiresWhitelist, "This NFT requires whitelist, use permitBuy()");
        
        _processPurchase(listingId, amount, msg.sender, false);
    }
    
    /**
     * @dev 通过白名单授权购买NFT
     * @param listingId 要购买的NFT的listing ID
     * @param amount 购买数量
     * @param deadline 签名有效期
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     */
    function permitBuy(
        uint256 listingId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.id == listingId, "Listing does not exist");
        require(block.timestamp <= deadline, "Signature has expired");
        require(listing.requiresWhitelist, "This NFT does not require whitelist, use buyNFT()");
        
        // 构建签名消息
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                msg.sender,
                listingId,
                nonces[msg.sender]++,
                deadline
            )
        );
        
        bytes32 hash = _hashTypedDataV4(structHash);
        
        // 验证签名是否为授权签名者所签
        address signerAddress = hash.recover(v, r, s);
        require(signerAddress == signer, "Invalid signature");
        
        // 防止重放攻击
        require(!usedSignatures[hash], "Signature has already been used");
        usedSignatures[hash] = true;
        
        // 执行购买流程
        _processPurchase(listingId, amount, msg.sender, true);
    }
    
    /**
     * @dev 处理购买逻辑（内部函数）
     */
    function _processPurchase(
        uint256 listingId,
        uint256 amount,
        address buyer,
        bool isPermitBuy
    ) internal {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "This listing is inactive");
        require(listing.seller != buyer, "Cannot purchase your own NFT");
        
        // 对于ERC721，强制amount为1
        uint256 actualAmount = listing.tokenType == TokenType.ERC721 ? 1 : amount;
        
        require(actualAmount > 0, "Purchase amount must be greater than 0");
        require(actualAmount <= listing.amount, "Purchase amount exceeds available quantity");
        
        // 计算总价格
        uint256 totalPrice = listing.price * actualAmount;
        require(msg.value == totalPrice, "Payment amount does not match total price");
        
        // 计算平台手续费和卖家所得
        uint256 platformFee = (totalPrice * platformFeePercentage) / 10000;
        uint256 sellerAmount = totalPrice - platformFee;
        
        // 更新listing状态
        if (actualAmount == listing.amount) {
            // 如果全部购买，标记为失效
            listing.active = false;
            nftToListingId[listing.nftContract][listing.tokenId] = 0;
        } else {
            // 部分购买，更新剩余数量
            listing.amount -= actualAmount;
        }
        listing.buyer = buyer;
        
        // 转移NFT给买家
        // wake-
        if (listing.tokenType == TokenType.ERC721) {
            // wake-disable-next-line
            IERC721(listing.nftContract).transferFrom(
                listing.seller,
                buyer,
                listing.tokenId
            );
        } else {
            // wake-disable-next-line
            IERC1155(listing.nftContract).safeTransferFrom(
                listing.seller,
                buyer,
                listing.tokenId,
                actualAmount,
                ""
            );
        }
        
        // 向卖家转账
        // wake-disable-next-line
        (bool sellerSuccess, ) = payable(listing.seller).call{value: sellerAmount}("");
        require(sellerSuccess, "Failed to transfer to seller");
        
        // 向平台转账手续费
        if ( platformFee >0 ){
            (bool feeSuccess, ) = payable(feeReceiver).call{value: platformFee}("");
            require(feeSuccess, "Failed to transfer platform fee");
        }
        
        emit NFTPurchased(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.tokenType,
            listing.seller,
            buyer,
            listing.price,
            actualAmount,
            platformFee,
            isPermitBuy,
            block.timestamp
        );
    }
    
    /**
     * @dev 更新平台手续费比例（仅所有者）
     * @param newFeePercentage 新的手续费比例（万分比）
     */
    function setPlatformFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee cannot exceed 10%");
        platformFeePercentage = newFeePercentage;
        
        emit PlatformFeeUpdated(newFeePercentage, block.timestamp);
    }
    
    /**
     * @dev 更新手续费接收地址（仅所有者）
     * @param newFeeReceiver 新的手续费接收地址
     */
    function setFeeReceiver(address newFeeReceiver) external onlyOwner {
        require(newFeeReceiver != address(0), "Receiver address cannot be zero");
        feeReceiver = newFeeReceiver;
        
        emit FeeReceiverUpdated(newFeeReceiver, block.timestamp);
    }
    
    /**
     * @dev 获取指定数量的最新listings
     * @param count 要获取的数量
     * @return 最新的listings数组
     */
    function getLatestListings(uint256 count) external view returns (Listing[] memory) {
        uint256 totalListings = _listingIdCounter;
        count = count > totalListings ? totalListings : count;
        
        Listing[] memory result = new Listing[](count);
        uint256 resultIndex = 0;
        
        for (uint256 i = totalListings; i > 0 && resultIndex < count; i--) {
            if (listings[i].active) {
                result[resultIndex] = listings[i];
                resultIndex++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev 获取指定用户的所有listings
     * @param user 用户地址
     * @return 用户的listings数组
     */
    function getUserListings(address user) external view returns (Listing[] memory) {
        uint256 totalListings = _listingIdCounter;
        uint256 count = 0;
        
        // 先计算用户的listings数量
        for (uint256 i = 1; i <= totalListings; i++) {
            if (listings[i].seller == user) {
                count++;
            }
        }
        
        // 填充结果数组
        Listing[] memory result = new Listing[](count);
        uint256 resultIndex = 0;
        
        for (uint256 i = 1; i <= totalListings; i++) {
            if (listings[i].seller == user) {
                result[resultIndex] = listings[i];
                resultIndex++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev 获取指定NFT的listing信息（如果已上架）
     * @param nftContract NFT合约地址
     * @param tokenId NFT的token ID
     * @return 对应的listing信息
     */
    function getNFTListing(address nftContract, uint256 tokenId) 
        external 
        view 
        returns (Listing memory) 
    {
        uint256 listingId = nftToListingId[nftContract][tokenId];
        return listings[listingId];
    }

    // 供测试调用的哈希函数（仅在测试环境使用，生产环境可移除或限制权限）
    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

}
