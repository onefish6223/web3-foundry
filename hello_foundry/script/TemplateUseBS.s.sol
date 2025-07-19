// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseScript.s.sol";
import {Counter} from "../src/Counter.sol";

contract CounterScript is BaseScript {
    function run() public broadcaster {
<<<<<<< HEAD
        Counter counter = new Counter();
        console.log("Counter deployed on %s", address(counter));
        saveContract("Counter", address(counter));
    }
}
=======
        Counuter counter = new Counter();
        console.log("Counter deployed on %s", address(counter));
        saveContract("Counter", address(counter));
    }
}
>>>>>>> 46080c177287393fe0cab7e337a44b8565ddca4b
