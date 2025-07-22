// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 转账回调接口
interface ITokensRecipient {
    function tokensReceived(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external;
}

abstract contract ERC20WithCallback is ERC20 {
    // 带回调的转账函数
    function transferWithCallback(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        // 执行普通转账
        _transfer(msg.sender, recipient, amount);

        // 如果目标地址是合约，尝试调用 tokensReceived
        if (isContract(recipient)) {
            try
                ITokensRecipient(recipient).tokensReceived(
                    msg.sender,
                    recipient,
                    amount,
                    data
                )
            {} catch (bytes memory reason) {
                //可以记录日志
                emit CallbackFailed(recipient, reason);
                revert("CallbackFailed");
            }
        }
        return true;
    }

    // 检查地址是否为合约
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // 回调失败事件
    event CallbackFailed(address indexed recipient, bytes reason);
}

// 完整代币合约示例
contract MyTokenWithCallback is ERC20WithCallback {
    constructor() ERC20("MyToken", "MTK") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}
