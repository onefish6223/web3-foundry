// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseScript.s.sol";
import {Counter} from "../src/Counter.sol";

contract CounterScript is BaseScript {
    function run() public broadcaster {
        Counuter counter = new Counter();
        console.log("Counter deployed on %s", address(counter));
        saveContract("Counter", address(counter));
    }
}