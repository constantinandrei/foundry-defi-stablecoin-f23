// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] collateralTokens;
        address[] priceFeeds;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        activeNetworkConfig = getSepoliaConfig();
    }

    function getSepoliaConfig() private view returns (NetworkConfig memory) {
        NetworkConfig memory config;
        config.collateralTokens = new address[](2);
        config.collateralTokens[0] = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;
        config.collateralTokens[1] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        config.priceFeeds = new address[](2);
        config.priceFeeds[0] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        config.priceFeeds[1] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        config.deployerKey = vm.envUint("PRIVATE_KEY");
        return config;
    }

    function getOrCreateAnvilEthConfig() private view returns (NetworkConfig memory) {
        if (activeNetworkConfig.priceFeeds[0] != address(0)) {
            return activeNetworkConfig;
        }
    }
}