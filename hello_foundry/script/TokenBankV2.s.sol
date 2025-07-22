// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {TokenBankV2} from "../src/TokenBankV2.sol";

contract TokenBankV2Script is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("LOCAL_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        new TokenBankV2(
            0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
        );
        vm.stopBroadcast();
    }
}
