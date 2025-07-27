// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/permit/MyTokenBankV4.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";

// 测试用 ERC20 代币（基础版）
contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

// 测试用 ERC20Permit 代币
contract TestERC20Permit is ERC20Permit {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20Permit(name) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

// 测试用 ERC1363 代币
contract TestERC1363 is ERC1363 {
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract MyTokenBankTest is Test {
    MyTokenBank public bank;
    TestERC20 public basicToken;         // 基础 ERC20
    TestERC20Permit public permitToken;  // 带 Permit 的 ERC20
    TestERC1363 public erc1363Token;     // ERC1363 代币

    address public alice = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address public bob = address(0x2);
    address public carol = address(0x3);
    // 定义测试账户私钥（与地址对应）
    uint256 public alicePrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public bobPrivateKey = 0x2;

    uint256 public constant ETH_AMOUNT = 1 ether;
    uint256 public constant TOKEN_AMOUNT = 1000e18;

    function setUp() public {
        // 部署合约
        bank = new MyTokenBank();
        basicToken = new TestERC20("BasicToken", "BT", TOKEN_AMOUNT * 10);
        permitToken = new TestERC20Permit("PermitToken", "PT", TOKEN_AMOUNT * 10);
        erc1363Token = new TestERC1363("ERC1363Token", "E1363", TOKEN_AMOUNT * 10);

        // 给测试账户转账代币
        // vm.prank(address(this)); // 用部署者地址转账
        basicToken.transfer(alice, TOKEN_AMOUNT);
        permitToken.transfer(alice, TOKEN_AMOUNT);
        erc1363Token.transfer(alice, TOKEN_AMOUNT);

        // 给测试账户转账以太币
        vm.deal(alice, ETH_AMOUNT * 10);
        vm.deal(bob, ETH_AMOUNT * 10);
    }

    // ------------------------------ 以太币功能测试 ------------------------------
    function testDepositEth() public {
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, false, false, true);
        emit MyTokenBank.EthDeposited(alice, ETH_AMOUNT);

        bank.depositEth{value: ETH_AMOUNT}();
        
        // 验证余额
        assertEq(bank.getEthBalance(alice), ETH_AMOUNT);
        assertEq(bank.getTotalEthBalance(), ETH_AMOUNT);
    }

    function testDepositEthZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("The deposit amount must be greater than 0");
        bank.depositEth{value: 0}();
    }

    function testWithdrawEth() public {
        // 先存款
        vm.prank(alice);
        bank.depositEth{value: ETH_AMOUNT}();

        // 取款前余额
        uint256 aliceEthBefore = alice.balance;

        // 执行取款
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, false, true);
        emit MyTokenBank.EthWithdrawn(alice, ETH_AMOUNT / 2);
        bank.withdrawEth(ETH_AMOUNT / 2);

        // 验证余额
        assertEq(bank.getEthBalance(alice), ETH_AMOUNT / 2);
        assertEq(bank.getTotalEthBalance(), ETH_AMOUNT / 2);
        assertEq(alice.balance, aliceEthBefore + ETH_AMOUNT / 2); 
    }

    function testWithdrawEthInsufficientBalance() public {
        vm.prank(alice);
        bank.depositEth{value: ETH_AMOUNT}();

        // 取款金额超过余额
        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        bank.withdrawEth(ETH_AMOUNT * 2);
    }

    function testTransferEth() public {
        // Alice 存款
        vm.prank(alice);
        bank.depositEth{value: ETH_AMOUNT}();

        // Alice 转账给 Bob
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit MyTokenBank.EthTransferred(alice, bob, ETH_AMOUNT / 2);
        bank.transferEth(bob, ETH_AMOUNT / 2);

        // 验证余额
        assertEq(bank.getEthBalance(alice), ETH_AMOUNT / 2);
        assertEq(bank.getEthBalance(bob), ETH_AMOUNT / 2);
        assertEq(bank.getTotalEthBalance(), ETH_AMOUNT); // 总余额不变
    }

    function testTransferEthToSelf() public {
        vm.prank(alice);
        bank.depositEth{value: ETH_AMOUNT}();

        // 禁止向自己转账
        vm.prank(alice);
        vm.expectRevert("You cannot transfer money to yourself.");
        bank.transferEth(alice, ETH_AMOUNT / 2);
    }

    // ------------------------------ 基础 ERC20 功能测试 ------------------------------
    function testDepositToken() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;

        // Alice 授权银行使用代币
        vm.prank(alice);
        basicToken.approve(address(bank), depositAmount);

        // 存款
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, false, true);
        emit MyTokenBank.TokenDeposited(address(basicToken), alice, depositAmount);
        bank.depositToken(address(basicToken), depositAmount);

        // 验证余额
        assertEq(bank.getTokenBalance(address(basicToken), alice), depositAmount);
        assertEq(basicToken.balanceOf(address(bank)), depositAmount);
    }

    function testWithdrawToken() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;

        // 先存款
        vm.prank(alice);
        basicToken.approve(address(bank), depositAmount);
        vm.prank(alice);
        bank.depositToken(address(basicToken), depositAmount);

        // 取款前余额
        uint256 aliceTokenBefore = basicToken.balanceOf(alice);

        // 执行取款
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, false, true);
        emit MyTokenBank.TokenWithdrawn(address(basicToken), alice, depositAmount / 2);
        bank.withdrawToken(address(basicToken), depositAmount / 2);

        // 验证余额
        assertEq(bank.getTokenBalance(address(basicToken), alice), depositAmount / 2);
        assertEq(basicToken.balanceOf(alice), aliceTokenBefore + depositAmount / 2);
        assertEq(basicToken.balanceOf(address(bank)), depositAmount / 2);
    }

    function testTransferToken() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;

        // Alice 存款
        vm.prank(alice);
        basicToken.approve(address(bank), depositAmount);
        vm.prank(alice);
        bank.depositToken(address(basicToken), depositAmount);

        // Alice 转账给 Bob
        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, true, true);
        emit MyTokenBank.TokenTransferred(address(basicToken), alice, bob, depositAmount / 2);
        bank.transferToken(address(basicToken), bob, depositAmount / 2);

        // 验证余额
        assertEq(bank.getTokenBalance(address(basicToken), alice), depositAmount / 2);
        assertEq(bank.getTokenBalance(address(basicToken), bob), depositAmount / 2);
        assertEq(basicToken.balanceOf(address(bank)), depositAmount); // 银行总余额不变
    }

    // ------------------------------ ERC20Permit 功能测试 ------------------------------
    function testDepositWithPermit() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;
        uint256 deadline = block.timestamp + 1 days;

        // Alice 生成 Permit 签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePrivateKey, // 使用 Alice 的私钥签名（Foundry 内置方法）
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permitToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                            alice,
                            address(bank),
                            depositAmount,
                            permitToken.nonces(alice), // 获取当前 nonce
                            deadline
                        )
                    )
                )
            )
        );

        // 使用 Permit 存款
        vm.prank(alice);
        bank.depositWithPermit(
            address(permitToken),
            depositAmount,
            deadline,
            v,
            r,
            s
        );

        // 验证余额
        assertEq(bank.getTokenBalance(address(permitToken), alice), depositAmount);
        assertEq(permitToken.balanceOf(address(bank)), depositAmount);
    }

    // ------------------------------ ERC1363 功能测试 ------------------------------
    function testERC1363Deposit() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;

        // Alice 授权并通过 ERC1363 的 transferAndCall 存款
        vm.prank(alice);
        erc1363Token.approve(address(erc1363Token), depositAmount); // 授权代币合约转账

        vm.prank(alice);
        // 验证事件
        vm.expectEmit(true, true, false, true);
        emit MyTokenBank.TokenDeposited(address(erc1363Token), alice, depositAmount);
        bool success = erc1363Token.transferAndCall(
            address(bank),
            depositAmount,
            "" // 附加数据（可选）
        );
        assertEq(success, true);

        // 验证余额
        assertEq(bank.getTokenBalance(address(erc1363Token), alice), depositAmount);
        assertEq(erc1363Token.balanceOf(address(bank)), depositAmount); 
    }

    // ------------------------------ 异常场景测试 ------------------------------
    function testRevertDepositTokenZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("The deposit amount must be greater than 0.");
        bank.depositToken(address(basicToken), 0);
    }

    function testRevertWithdrawTokenInsufficient() public {
        // 未存款却取款
        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        bank.withdrawToken(address(basicToken), 100);
    }

    function testRevertTransferTokenToSelf() public {
        uint256 depositAmount = TOKEN_AMOUNT / 2;

        // 先存款
        vm.prank(alice);
        basicToken.approve(address(bank), depositAmount);
        vm.prank(alice);
        bank.depositToken(address(basicToken), depositAmount);

        // 禁止向自己转账
        vm.prank(alice);
        vm.expectRevert("You cannot transfer money to yourself.");
        bank.transferToken(address(basicToken), alice, 100);
    }

    function testRevertEthTransferToZero() public {
        vm.prank(alice);
        bank.depositEth{value: ETH_AMOUNT}();

        // 禁止转账给零地址
        vm.prank(alice);
        vm.expectRevert("The receiving address cannot be 0");
        bank.transferEth(address(0), ETH_AMOUNT / 2);
    }
}