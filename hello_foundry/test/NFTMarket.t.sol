// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/NFTMarket.sol";

// 简单ERC20
contract TestERC20 is IERC20 {
    string public name = "TestToken";
    string public symbol = "TT";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(uint256 _supply) {
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient");
        require(allowance[from][msg.sender] >= amount, "Not allowed");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        return true;
    }
}

// 简单ERC721
contract TestERC721 is IERC721 {
    mapping(uint256 => address) public override ownerOf;
    mapping(uint256 => address) public override getApproved;
    mapping(address => mapping(address => bool)) public override isApprovedForAll;
    mapping(address => uint256) public override balanceOf;

    function mint(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == address(0), "Already minted");
        ownerOf[tokenId] = to;
        balanceOf[to] += 1;
        emit Transfer(address(0), to, tokenId);
    }

    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf[tokenId];
        require(owner == msg.sender || isApprovedForAll[owner][msg.sender], "Not authorized");
        getApproved[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external override {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        transferFrom(from, to, tokenId);
        // No ERC721Receiver check for simplicity
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external override {
        transferFrom(from, to, tokenId);
        // No ERC721Receiver check for simplicity
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        address owner = ownerOf[tokenId];
        require(owner == from, "Not owner");
        require(
            msg.sender == owner ||
            getApproved[tokenId] == msg.sender ||
            isApprovedForAll[owner][msg.sender],
            "Not authorized"
        );
        ownerOf[tokenId] = to;
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        getApproved[tokenId] = address(0);
        emit Transfer(from, to, tokenId);
    }

    // IERC721接口要求的其它方法
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721).interfaceId;
    }

    function name() external pure returns (string memory) {
        return "TestNFT";
    }

    function symbol() external pure returns (string memory) {
        return "TNFT";
    }

    function tokenURI(uint256) external pure returns (string memory) {
        return "";
    }
}

contract NFTMarketTest is Test {
    NFTMarket market;
    TestERC20 token;
    TestERC721 nft;
    address seller = address(0x1);
    address buyer = address(0x2);

    function setUp() public {
        market = new NFTMarket();
        token = new TestERC20(1_000_000 ether);
        nft = new TestERC721();

        // mint NFT
        nft.mint(seller, 1);
        nft.mint(seller, 2);

        // 给买家ERC20
        token.transfer(buyer, 1000 ether);

        // 授权market
        vm.startPrank(seller);
        nft.setApprovalForAll(address(market), true);
        vm.stopPrank();
    }

    function testListNFTSuccess() public {
        vm.startPrank(seller);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Listed(
            address(nft),
            1,
            seller,
            address(token),
            100 ether
        );
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();
    }

    function testListNFTFailNotOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("Not owner");
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();
    }

    function testListNFTFailAlreadyListed() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.expectRevert("Already listed");
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();
    }

    function testBuyNFTSuccess() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 100 ether);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Purchased(
            address(nft),
            1,
            buyer,
            address(token),
            100 ether
        );
        market.buyNFT(address(nft), 1);
        assertEq(nft.ownerOf(1), buyer);
        vm.stopPrank();
    }

    function testBuyNFTFailSelfBuy() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.expectRevert("Cannot buy your own NFT");
        market.buyNFT(address(nft), 1);
        vm.stopPrank();
    }

    function testBuyNFTFailRepeatBuy() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 100 ether);
        market.buyNFT(address(nft), 1);
        vm.expectRevert("Not listed");
        market.buyNFT(address(nft), 1);
        vm.stopPrank();
    }

    function testBuyNFTFailOverPay() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 200 ether);
        market.buyNFT(address(nft), 1);
        assertEq(token.balanceOf(buyer), 900 ether); // 只扣实际价格
        vm.stopPrank();
    }

    function testBuyNFTFailUnderPay() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 50 ether);
        vm.expectRevert("Insufficient allowance");
        market.buyNFT(address(nft), 1);
        vm.stopPrank();
    }

    function testFuzzListAndBuy(uint256 price, address fuzzBuyer) public {
        price = bound(price, 1e16, 1e22); // 0.01 ~ 10000 token
        vm.startPrank(seller);
        market.listNFT(address(nft), 2, address(token), price);
        vm.stopPrank();

        token.transfer(fuzzBuyer, price);
        vm.startPrank(fuzzBuyer);
        token.approve(address(market), price);
        market.buyNFT(address(nft), 2);
        assertEq(nft.ownerOf(2), fuzzBuyer);
        vm.stopPrank();
    }

    function invariantMarketNeverHoldToken() public {
        vm.startPrank(seller);
        market.listNFT(address(nft), 1, address(token), 100 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 100 ether);
        market.buyNFT(address(nft), 1);
        vm.stopPrank();

        assertEq(token.balanceOf(address(market)), 0);
    }
}
