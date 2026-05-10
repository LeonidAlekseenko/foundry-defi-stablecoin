// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDsc} from "../../script/DeployDSC.s.sol";


contract DSCEngineTest is Test{
    DeployDsc deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public user = makeAddr("user");


function setUp() public {
    deployer = new DeployDsc();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
}

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
function testGetUsdEthValue() public {
        // eth/usd = 2000
        uint256 ethAmpunt = 15e18;
        // 15e18 * 2000e8
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmpunt);
        assertEq(expectedUsd, actualUsd);
}

function testGetUsdBtcValue() public {
        // btc/usd = 1000
        uint256 btcAmount = 15e18;
        // 15e18 * 1000e8
        uint256 expectedUsd = 15_000e18;
        uint256 actualUsd = engine.getUsdValue(wbtc, btcAmount);
        assertEq(expectedUsd, actualUsd);
}

function testGetUsdValueWithZeroAmount() public {
    uint256 amount = 0;
    uint256 expectedUsd = 0;
    uint256 actualUsd = engine.getUsdValue(weth, amount);
    assertEq(expectedUsd, actualUsd);
}

function testGetUsdValueWithTinyAmount() public {
    uint256 amount = 1; // 1 wei
    // (2000e8 * 1e10 * 1) / 1e18 = 2000
    uint256 expectedUsd = 2000; 
    uint256 actualUsd = engine.getUsdValue(weth, amount);
    assertEq(expectedUsd, actualUsd);
}


   /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/



}