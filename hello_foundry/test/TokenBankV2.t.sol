// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/TokenBankV2.sol";

// 简单的ERC20WithCallback测试代币
contract TestToken is IERC20WithCallback {
    string public name = "TestToken";
    string public symbol = "TT";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public bank;

    constructor(uint256 _supply) {
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
    }

    function setBank(address _bank) external {
        bank = _bank;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
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
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient");
        require(allowance[sender][msg.sender] >= amount, "Not allowed");
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferWithCallback(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        // 回调
        TokenBankV2(bank).tokensReceived(msg.sender, recipient, amount, data);
        return true;
    }
}

contract TokenBankV2Test is Test {
    TestToken token;
    TokenBankV2 bank;
    struct Depositor {
        address addr;
        uint256 amount;
    }
    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address user4 = address(0x5);

    function setUp() public {
        vm.startPrank(admin);
        token = new TestToken(1_000_000 ether);
        bank = new TokenBankV2(address(token));
        token.setBank(address(bank));

        // 给用户分配代币
        token.transfer(user1, 1000 ether);
        token.transfer(user2, 2000 ether);
        token.transfer(user3, 3000 ether);
        token.transfer(user4, 4000 ether);
        vm.stopPrank();
    }

    function testDepositUpdatesBalance() public {
        /**
        断言检查存款前后用户在 Bank 合约中的存款额更新是否正确
        */
        vm.startPrank(user1);
        token.approve(address(bank), 200 ether);

        bank.deposit(100 ether);
        assertEq(bank.getUserBalance(user1), 100 ether);

        bank.deposit(50 ether);
        assertEq(bank.getUserBalance(user1), 150 ether);
        vm.stopPrank();
    }

    function testTop3Users() public {
        /**
        检查存款金额的前 3 名用户是否正确，分别检查有1个、2个、3个、4 个用户， 
        以及同一个用户多次存款的情况。
        */
        // 1个用户
        vm.startPrank(user1);
        token.approve(address(bank), 100 ether);
        bank.deposit(100 ether);
        vm.stopPrank();
        assertEq(bank.getUserBalance(user1), 100 ether);

        // 2个用户
        vm.startPrank(user2);
        token.approve(address(bank), 200 ether);
        bank.deposit(200 ether);
        vm.stopPrank();
        assertEq(bank.getUserBalance(user2), 200 ether);

        // 3个用户
        vm.startPrank(user3);
        token.approve(address(bank), 300 ether);
        bank.deposit(300 ether);
        vm.stopPrank();
        assertEq(bank.getUserBalance(user3), 300 ether);

        // 4个用户
        vm.startPrank(user4);
        token.approve(address(bank), 400 ether);
        bank.deposit(400 ether);
        vm.stopPrank();
        assertEq(bank.getUserBalance(user4), 400 ether);

        // 同一用户多次存款
        vm.startPrank(user1);
        token.approve(address(bank), 50 ether);
        bank.deposit(50 ether);
        vm.stopPrank();
        assertEq(bank.getUserBalance(user1), 150 ether);

        // 前3名断言
        (address daddr1, ) = bank.topDepositors(0);
        (address daddr2, ) = bank.topDepositors(1);
        (address daddr3, ) = bank.topDepositors(2);
        assertEq(daddr1, user4);
        assertEq(daddr2, user3);
        assertEq(daddr3, user2);
    }

    function testOnlyAdminCanWithdraw() public {
        //检查只有管理员可取款，其他人不可以取款。
        // admin存款
        vm.startPrank(admin);
        token.approve(address(bank), 500 ether);
        bank.deposit(500 ether);
        vm.stopPrank();

        // 非管理员取款应失败
        vm.startPrank(user1);
        vm.expectRevert();
        bank.withdraw(10 ether);
        vm.stopPrank();

        // 管理员取款成功
        vm.startPrank(admin);
        bank.withdraw(100 ether);
        assertEq(bank.getUserBalance(admin), 400 ether);
        vm.stopPrank();
    }
}
