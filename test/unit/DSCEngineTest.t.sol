// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDsc} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "../moks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address wbeth = 0xa2E3356610840701BDf5611a53974510Ae27E2e1;

    //берет строку-псевдоним и превращает её в Ethereum-адрес.
    address public user = makeAddr("user");
    
    //сумма обеспечения
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTINS_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdEthValue() public {
        // eth/usd = 2000
        uint256 ethAmpunt = 15e18;
        // 15e18(15eth) * 2000e8(2000$) = 30000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmpunt);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdBtcValue() public {
        uint256 btcAmount = 15e18;
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

    function testGetUsdValueNewSintax() public {
        uint256 amount = 1 ether; // 1e18
        uint256 expectedUsd = 2000e18;
        uint256 actualUsd = engine.getUsdValue(weth, amount);
        assertEq(expectedUsd, actualUsd);
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT COLLATERAL TESTS
     //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralZero() public {

        //имитирует действия указанного пользователя.
        vm.startPrank(user);

        //Дает разрешение контракту engine тратить токены. 
        //Это хороший тон в тестах, хотя при передаче нуля approve 
        //технически не влияет на проверку revert.
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        //шпаргалка для Foundry. 
        // ожидает, что следующая строчка кода вызовет указанную ошибку.
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        //сам вызов функции с нулевым значением, который должен упасть.
        engine.depositCollateral(weth, 0);

        //завершает симуляцию действий пользователя.
        vm.stopPrank();

    }


    function testRevertsisAlowedToken() public {

        //Она ожидает, что следующая строчка кода вызовет указанную ошибку.
        vm.expectRevert(DSCEngine.DSCEngine__NoAllowedToken.selector);

        //проверяяем на нулевой адрес
        engine.depositCollateral(address(0), 1000000000);

    }


    function testRevertsIfTokenNotAllowed() public {
    // 1. Создаем случайный адрес, которого точно нет в списке разрешенных
        address ranToken = makeAddr("randomToken"); 
    
    // 2. Ожидаем именно ошибку модификатора (токен не разрешен)
        vm.expectRevert(DSCEngine.DSCEngine__NoAllowedToken.selector); 
    
    // 3. Вызываем функцию
        engine.depositCollateral(ranToken, AMOUNT_COLLATERAL);
    }


    
















}
