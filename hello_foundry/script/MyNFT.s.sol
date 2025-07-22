// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MyNFT} from "../src/MyNFT.sol";

contract MyNFTScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("LOCAL_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        new MyNFT();
        vm.stopBroadcast();
    }
}
