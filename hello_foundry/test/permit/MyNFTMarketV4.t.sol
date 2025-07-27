// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/permit/MyNFTMarketV4.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// 测试用ERC721合约
contract TestERC721 is ERC721 {
    constructor() ERC721("Test721", "T721") {}
    
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

// 测试用ERC1155合约
contract TestERC1155 is ERC1155 {
    constructor() ERC1155("https://test.com/{id}.json") {}
    
    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}

contract NFTMarketTest is Test {
    NFTMarket public market;
    TestERC721 public nft721;
    TestERC1155 public nft1155;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public carol = address(0x3);
    address public signer = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    // 定义测试账户私钥（与地址对应）
    uint256 public signerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    
    uint256 public constant PRICE = 1 ether;
    uint256 public constant TOKEN_ID_721 = 100;
    uint256 public constant TOKEN_ID_1155 = 200;
    uint256 public constant AMOUNT_1155 = 5;

    function setUp() public {
        // 部署合约
        market = new NFTMarket(signer);
        nft721 = new TestERC721();
        nft1155 = new TestERC1155();
        
        //  mint测试NFT并授权市场合约
        nft721.mint(alice, TOKEN_ID_721);
        vm.prank(alice);
        nft721.setApprovalForAll(address(market), true);
        
        nft1155.mint(alice, TOKEN_ID_1155, AMOUNT_1155);
        vm.prank(alice);
        nft1155.setApprovalForAll(address(market), true);

        // 给测试账户转账以太币
        vm.deal(alice, PRICE * 10);
        vm.deal(bob, PRICE * 10);
        vm.deal(carol, PRICE * 10);
        vm.deal(signer, PRICE * 10);
    }

    // ==== ERC721测试 ====
    function testCreate721Listing() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.ListingCreated(
            1,
            address(nft721),
            TOKEN_ID_721,
            NFTMarket.TokenType.ERC721,
            alice,
            PRICE,
            1,
            false,
            block.timestamp
        );
        
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            false
        );
        
        // 验证listing状态
        NFTMarket.Listing memory listing = market.getNFTListing(address(nft721), TOKEN_ID_721);
        assertEq(listing.id, 1);
        assertEq(listing.seller, alice);
        assertEq(listing.price, PRICE);
        assertTrue(listing.active);
    }

    function testBuy721NFT() public {
        // 创建listing
        vm.prank(alice);
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            false
        );
        NFTMarket.Listing memory testls = market.getNFTListing(address(nft721), TOKEN_ID_721);
        assertTrue(testls.active);
        // 记录初始余额
        uint256 aliceBalanceBefore = alice.balance;
        
        // 购买NFT
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.NFTPurchased(
            1,
            address(nft721),
            TOKEN_ID_721,
            NFTMarket.TokenType.ERC721,
            alice,
            bob,
            PRICE,
            1,
            0,
            false,
            block.timestamp
        );
        vm.prank(bob);
        market.buyNFT{value: PRICE}(1, 1);
        
        // 验证NFT所有权转移
        assertEq(nft721.ownerOf(TOKEN_ID_721), bob);
        
        // 验证资金转移
        assertEq(alice.balance, aliceBalanceBefore + PRICE);
        
        // 验证listing状态
        NFTMarket.Listing memory listing = market.getUserListings(alice)[0];
        assertFalse(listing.active);
        assertEq(listing.buyer, bob);
    }

    // ==== ERC1155测试 ====
    function testCreate1155Listing() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.ListingCreated(
            1,
            address(nft1155),
            TOKEN_ID_1155,
            NFTMarket.TokenType.ERC1155,
            alice,
            PRICE,
            AMOUNT_1155,
            false,
            block.timestamp
        );
        
        market.create1155Listing(
            address(nft1155),
            TOKEN_ID_1155,
            PRICE,
            AMOUNT_1155,
            false
        );
        
        // 验证listing状态
        NFTMarket.Listing memory listing = market.getNFTListing(address(nft1155), TOKEN_ID_1155);
        assertEq(listing.id, 1);
        assertEq(listing.amount, AMOUNT_1155);
        assertTrue(listing.active);
    }

    function testBuy1155NFT() public {
        // 创建listing
        vm.prank(alice);
        market.create1155Listing(
            address(nft1155),
            TOKEN_ID_1155,
            PRICE,
            AMOUNT_1155,
            false
        );
        
        uint256 buyAmount = 2;
        uint256 totalPrice = PRICE * buyAmount;
        
        // 购买部分数量
        vm.prank(bob);
        market.buyNFT{value: totalPrice}(1, buyAmount);
        
        // 验证NFT余额
        assertEq(nft1155.balanceOf(bob, TOKEN_ID_1155), buyAmount);
        assertEq(nft1155.balanceOf(alice, TOKEN_ID_1155), AMOUNT_1155 - buyAmount);
        
        // 验证listing状态（仍有剩余数量）
        NFTMarket.Listing memory listing = market.getNFTListing(address(nft1155), TOKEN_ID_1155);
        assertTrue(listing.active);
        assertEq(listing.amount, AMOUNT_1155 - buyAmount);
    }

    // ==== 白名单功能测试 ====
    function testPermitBuyWithWhitelist() public {
        // 创建需要白名单的listing
        vm.prank(alice);
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            true
        );
        
        // 构建签名
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = market.nonces(bob);
        
        bytes32 structHash = keccak256(
            abi.encode(
                market.PERMIT_TYPEHASH(),
                bob,
                1,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = market.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        
        // 使用签名购买
        vm.prank(bob);
        market.permitBuy{value: PRICE}(1, 1, deadline, v, r, s);
        
        // 验证NFT所有权
        assertEq(nft721.ownerOf(TOKEN_ID_721), bob);
    }

    function testRevertIfInvalidSignature() public {
        // 创建需要白名单的listing
        vm.prank(alice);
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            true
        );
        
        // 使用无效签名者的签名
        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(
            abi.encode(
                market.PERMIT_TYPEHASH(),
                bob,
                1,
                0,
                deadline
            )
        );
        
        bytes32 hash = market.hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(carol)), hash); // 使用非signer地址签名
        
        // 预期失败
        vm.prank(bob);
        vm.expectRevert("Invalid signature");
        market.permitBuy{value: PRICE}(1, 1, deadline, v, r, s);
    }

    // ==== 取消Listing测试 ====
    function testCancelListing() public {
        // 创建listing
        vm.prank(alice);
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            false
        );
        
        // 取消listing
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.ListingCancelled(
            1,
            address(nft721),
            TOKEN_ID_721,
            NFTMarket.TokenType.ERC721,
            alice,
            block.timestamp
        );
        market.cancelListing(1);
        
        // 验证listing状态
        NFTMarket.Listing memory listing = market.getNFTListing(address(nft721), TOKEN_ID_721);
        assertFalse(listing.active);
    }

    function testRevertIfNonOwnerCancel() public {
        // 创建listing
        vm.prank(alice);
        market.create721Listing(
            address(nft721),
            TOKEN_ID_721,
            PRICE,
            false
        );
        
        // 非所有者尝试取消
        vm.prank(bob);
        vm.expectRevert("You are not the seller of this listing");
        market.cancelListing(1);
    }

    // ==== 平台手续费测试 ====
    function testPlatformFee() public {
        // 设置2%手续费
        vm.prank(signer); // 所有者是signer
        market.setPlatformFeePercentage(200); // 200 = 2%
        vm.prank(signer); 
        market.setFeeReceiver(signer); // 设置手续费接收者
        
        // 创建listing并购买
        vm.prank(alice);
        market.create721Listing(address(nft721), TOKEN_ID_721, PRICE, false);
        
        uint256 feeReceiverBefore = market.feeReceiver().balance;
        uint256 aliceBefore = alice.balance;
        
        vm.prank(bob);
        market.buyNFT{value: PRICE}(1, 1);
        
        // 验证手续费计算
        uint256 fee = (PRICE * 200) / 10000;
        assertEq(market.feeReceiver().balance, feeReceiverBefore + fee);
        assertEq(alice.balance, aliceBefore + (PRICE - fee));
    }

    // ==== 失败场景测试 ====
    function testRevertIfBuyOwnNFT() public {
        vm.prank(alice);
        market.create721Listing(address(nft721), TOKEN_ID_721, PRICE, false);
        
        // 尝试购买自己的NFT
        vm.prank(alice);
        vm.expectRevert("Cannot purchase your own NFT");
        market.buyNFT{value: PRICE}(1, 1);
    }

    function testRevertIfInsufficientPayment() public {
        vm.prank(alice);
        market.create721Listing(address(nft721), TOKEN_ID_721, PRICE, false);
        
        // 支付不足
        vm.prank(bob);
        vm.expectRevert("Payment amount does not match total price");
        market.buyNFT{value: PRICE - 1}(1, 1);
    }

    function testRevertIfDuplicateListing() public {
        vm.prank(alice);
        market.create721Listing(address(nft721), TOKEN_ID_721, PRICE, false);
        
        // 重复上架
        vm.prank(alice);
        vm.expectRevert("This NFT is already listed");
        market.create721Listing(address(nft721), TOKEN_ID_721, PRICE, false);
    }
}