// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MyNFTMarket} from "../src/MyNFTMarket.sol";

contract MyNFTMarketScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("LOCAL_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        new MyNFTMarket(0x5FbDB2315678afecb367f032d93F642f64180aa3);
        vm.stopBroadcast();
    }
}
