// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title Deploy DSC
 * @notice This contract is used to deploy the DSC system
 */
contract DeployDSC is Script {
    address[] public collateralTokens;
    address[] public priceFeeds;

    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        collateralTokens = [weth, wbtc];
        priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(address(this));
        DSCEngine dscEngine = new DSCEngine(collateralTokens, priceFeeds, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine);
    }
}
