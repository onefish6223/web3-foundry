// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
        counter.setNumber(0);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);

        console.log("Block number", block.number);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        //gittest
        assertEq(counter.number(), x);
    }
}
