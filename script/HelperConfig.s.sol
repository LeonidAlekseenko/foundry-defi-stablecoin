// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/moks/MockV3Agregator.sol";
import {ERC20Mock} from "../test/moks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public PUB_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // eth/usd
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // address contract
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();

        // Для локальной сети (Anvil) создаём mock-оракул
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS, // Количество децималей (например, 8)
            ETH_USD_PRICE // Начальная цена ETH в USD
        );

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS, // Количество децималей (например, 8)
            BTC_USD_PRICE // Начальная цена btc в USD
        );

        // Создаём токен
        ERC20Mock wethMock = new ERC20Mock(
            "WETH", // Название токена (например, "WETH")
            "WETH", // Символ (например, "WETH")
            msg.sender, // Кто получит начальные токены
            1000e8 // ← Общее количество токенов
        );

        // Создаём токен
        ERC20Mock wbtcMock = new ERC20Mock(
            "WBTC", // Название токена (например, "WETH")
            "WBTC", // Символ (например, "WETH")
            msg.sender, // Кто получит начальные токены
            1000e8 // ← Общее количество токенов
        );

        vm.stopBroadcast();

        activeNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: PUB_ANVIL_KEY
        });
        return activeNetworkConfig;
    }
}
