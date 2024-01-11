// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title Deploy DSC
 * @notice This contract is used to deploy the DSC system
 */
contract DeployDSC is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(address(this));
        //DSCEngine dscEngine = new DSCEngine();
        vm.stopBroadcast();
    }
}