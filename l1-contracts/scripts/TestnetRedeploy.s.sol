// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";

contract TestnetRedeploy is Redeploy {
    address public constant PUH_PROXY = address(0x9B956d242e6806044877C7C1B530D475E371d544); // OUTDATED

    function run() external {
        runRedeploy(
            PUH_PROXY,
            true
        );
    }
}
