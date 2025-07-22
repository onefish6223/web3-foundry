// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 扩展的ERC20接口，包含transferWithCallback
interface IERC20WithCallback is IERC20 {
    function transferWithCallback(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

contract TokenBank {
    struct Depositor {
        address addr;
        uint256 amount;
    }
    Depositor[3] public topDepositors;
    // 存储的代币合约地址
    IERC20 public token;
    // 管理员地址
    address public admin;
    // 记录每个地址的存款余额
    mapping(address => uint256) public balances;

    // 事件：存款
    event Deposit(address indexed user, uint256 amount);

    // 事件：取款
    event Withdraw(address indexed user, uint256 amount);

    // 构造函数，传入要存储的代币合约地址
    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
        admin = msg.sender;
    }

    // 更新前三存款人
    function _updateTopDepositors(
        address depositor,
        uint256 newBalance
    ) private {
        uint256 insertIndex = 3; // 默认不插入

        // 检查是否已在前三名中
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i].addr == depositor) {
                // 更新现有存款人金额
                topDepositors[i].amount = newBalance;
                insertIndex = i; // 标记需要重新排序的位置
                break;
            }
        }

        // 如果是新存款人且金额足够大
        if (insertIndex == 3) {
            // 找到应该插入的位置
            for (uint i = 0; i < 3; i++) {
                if (newBalance > topDepositors[i].amount) {
                    insertIndex = i;
                    break;
                }
            }
        }

        // 如果需要插入新记录
        if (insertIndex < 3) {
            // 创建新存款人记录
            Depositor memory newDepositor = Depositor({
                addr: depositor,
                amount: newBalance
            });

            // 向后移动较低排名的记录
            for (uint j = 2; j > insertIndex; j--) {
                topDepositors[j] = topDepositors[j - 1];
            }

            // 插入新记录
            topDepositors[insertIndex] = newDepositor;
        }
    }
    // 标准存款函数 需要先 approve
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");

        // 将代币从用户转移到合约
        // wake-disable
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        // 更新用户余额
        balances[msg.sender] += amount;
        // 更新前三名
        _updateTopDepositors(msg.sender, balances[msg.sender]);
        emit Deposit(msg.sender, amount);
    }

    // 取款函数
    function withdraw(uint256 amount) external {
        require(msg.sender == admin, "Only admin");
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // 更新用户余额
        balances[msg.sender] -= amount;

        // 将代币从合约转移回用户
        bool success = token.transfer(msg.sender, amount);
        require(success, "Transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    // 查询合约中的代币总余额
    function getBankBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // 查询用户的存款余额
    function getUserBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}

contract TokenBankV2 is TokenBank {
    // 构造函数，传入要存储的代币合约地址
    constructor(address _tokenAddress) TokenBank(_tokenAddress) {
        token = IERC20WithCallback(_tokenAddress);
    }
    bytes public tdata;

    // 通过transferWithCallback直接存款
    function tokensReceived(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external {
        // 确保调用者是代币合约
        require(
            msg.sender == address(token),
            "Only token contract can call this"
        );

        // 确保接收者是本合约
        require(recipient == address(this), "Invalid recipient");
        tdata = data;
        // 更新用户余额
        balances[sender] += amount;

        emit Deposit(sender, amount);
    }
}
