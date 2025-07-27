// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/interfaces/IERC1363.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title MyTokenBankV4
 * @dev 支持以太币和ERC20、ERC20Permit、ERC1363代币的银行合约
 */
contract MyTokenBank is ReentrancyGuard, EIP712 {
    // 存储每个用户的以太币余额
    mapping(address => uint256) private _ethBalances;
    
    // 存储每种代币的每个用户余额 (token address => user address => balance)
    mapping(address => mapping(address => uint256)) private _tokenBalances;
    
    // 记录合约的总以太币余额
    uint256 private _totalEthBalance;
    
    // 事件：当用户存入以太币时触发
    event EthDeposited(address indexed user, uint256 amount);
    
    // 事件：当用户取出以太币时触发
    event EthWithdrawn(address indexed user, uint256 amount);
    
    // 事件：当用户进行以太币转账时触发
    event EthTransferred(address indexed from, address indexed to, uint256 amount);
    
    // 事件：当用户存入代币时触发
    event TokenDeposited(address indexed token, address indexed user, uint256 amount);
    
    // 事件：当用户取出代币时触发
    event TokenWithdrawn(address indexed token, address indexed user, uint256 amount);
    
    // 事件：当用户进行代币转账时触发
    event TokenTransferred(
        address indexed token, 
        address indexed from, 
        address indexed to, 
        uint256 amount
    );
    
    // EIP-712 相关设置
    bytes32 private constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    
    constructor() EIP712("Bank", "1") {
        // 初始化EIP712
    }
    
    /**
     * @dev 存款以太币
     */
    function depositEth() external payable nonReentrant {
        depositETHInContract();
    }
    function depositETHInContract() internal {
        require(msg.value > 0, "The deposit amount must be greater than 0");
        
        _ethBalances[msg.sender] += msg.value;
        _totalEthBalance += msg.value;
        
        emit EthDeposited(msg.sender, msg.value);
    }
    
    /**
     * @dev 取款以太币
     * @param amount 要取出的金额
     */
    function withdrawEth(uint256 amount) external nonReentrant {
        require(amount > 0, "The withdrawal amount must be greater than 0");
        require(_ethBalances[msg.sender] >= amount, "Insufficient balance");
        require(_totalEthBalance >= amount, "Insufficient balance in the contract");
        
        _ethBalances[msg.sender] -= amount;
        _totalEthBalance -= amount;
        
        emit EthWithdrawn(msg.sender, amount);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev 以太币转账
     * @param to 接收方地址
     * @param amount 转账金额
     */
    function transferEth(address to, uint256 amount) external nonReentrant {
        require(to != address(0), "The receiving address cannot be 0");
        require(to != msg.sender, "You cannot transfer money to yourself.");
        require(amount > 0, "The transfer amount must be greater than 0");
        require(_ethBalances[msg.sender] >= amount, "Insufficient balance");
        
        _ethBalances[msg.sender] -= amount;
        _ethBalances[to] += amount;
        
        emit EthTransferred(msg.sender, to, amount);
    }
    
    /**
     * @dev 存款ERC20代币
     * @param token 代币合约地址
     * @param amount 存款金额
     */
    function depositToken(address token, uint256 amount) external nonReentrant {
        require(token != address(0), "The token address cannot be 0");
        require(amount > 0, "The deposit amount must be greater than 0.");
        
        IERC20 erc20 = IERC20(token);
        require(erc20.allowance(msg.sender, address(this)) >= amount, "Insufficient tokens have not been authorized");
        
        // 转移代币到合约
        // wake-disable
        bool success = erc20.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        // 更新余额
        _tokenBalances[token][msg.sender] += amount;
        
        emit TokenDeposited(token, msg.sender, amount);
    }
    
    /**
     * @dev 通过ERC1363回调接收代币存款
     * @param sender 发送方地址
     * @param amount 存款金额
     * @param data 附加数据
     */
    function onTransferReceived(
        address, 
        address sender, 
        uint256 amount, 
        bytes calldata data
    ) external returns (bytes4) {
        // 验证调用者是ERC1363代币合约
        require(IERC1363(msg.sender).supportsInterface(type(IERC1363).interfaceId), "It is not an ERC1363 token");
        
        // 更新余额
        _tokenBalances[msg.sender][sender] += amount;
        
        emit TokenDeposited(msg.sender, sender, amount);
        
        return this.onTransferReceived.selector;
    }
    
    /**
     * @dev 使用ERC20Permit存款代币
     * @param token 代币合约地址
     * @param amount 存款金额
     * @param deadline 签名有效期
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     */
    function depositWithPermit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(token != address(0), "The token address cannot be 0");
        require(amount > 0, "The deposit amount must be greater than 0.");
        
        IERC20Permit erc20Permit = IERC20Permit(token);
        
        // 验证并使用授权
        erc20Permit.permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        IERC20 erc20 = IERC20(token);
        // 转移代币到合约
        bool success = erc20.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        // 更新余额
        _tokenBalances[token][msg.sender] += amount;
        
        emit TokenDeposited(token, msg.sender, amount);
    }
    
    /**
     * @dev 取款代币
     * @param token 代币合约地址
     * @param amount 取款金额
     */
    function withdrawToken(address token, uint256 amount) external nonReentrant {
        require(token != address(0), "The token address cannot be 0");
        require(amount > 0, "The withdrawal amount must be greater than 0");
        require(_tokenBalances[token][msg.sender] >= amount, "Insufficient balance");
        
        // 更新余额
        _tokenBalances[token][msg.sender] -= amount;
        
        // 转移代币给用户
        IERC20 erc20 = IERC20(token);
        bool success = erc20.transfer(msg.sender, amount);
        require(success, "Token transfer failed");
        
        emit TokenWithdrawn(token, msg.sender, amount);
    }
    
    /**
     * @dev 代币转账
     * @param token 代币合约地址
     * @param to 接收方地址
     * @param amount 转账金额
     */
    function transferToken(address token, address to, uint256 amount) external nonReentrant {
        require(token != address(0), "The token address cannot be 0");
        require(to != address(0), "The receiving address cannot be 0");
        require(to != msg.sender, "You cannot transfer money to yourself.");
        require(amount > 0, "The transfer amount must be greater than 0");
        require(_tokenBalances[token][msg.sender] >= amount, "Insufficient balance");
        
        // 更新余额
        _tokenBalances[token][msg.sender] -= amount;
        _tokenBalances[token][to] += amount;
        
        emit TokenTransferred(token, msg.sender, to, amount);
    }
    
    /**
     * @dev 查询用户的以太币余额
     * @param account 用户地址
     * @return 以太币余额
     */
    function getEthBalance(address account) external view returns (uint256) {
        return _ethBalances[account];
    }
    
    /**
     * @dev 查询用户的代币余额
     * @param token 代币合约地址
     * @param account 用户地址
     * @return 代币余额
     */
    function getTokenBalance(address token, address account) external view returns (uint256) {
        return _tokenBalances[token][account];
    }
    
    /**
     * @dev 查询合约的总以太币余额
     * @return 总以太币余额
     */
    function getTotalEthBalance() external view returns (uint256) {
        return _totalEthBalance;
    }
    
    /**
     * @dev 接收以太币的回调函数
     */
    receive() external payable {
        depositETHInContract();
    }
}
