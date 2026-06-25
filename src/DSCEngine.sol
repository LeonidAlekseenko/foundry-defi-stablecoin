// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NoAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBellowMinimum();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();

    /*//////////////////////////////////////////////////////////////
                            State Variables
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200$
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /// @dev фиды
    mapping(address token => address priceFeed) private s_priceFeeds;

    /// @dev внесенные средства
    // 📦  Alice (0xaaa...)
    //         ├── [ Ячейка WETH (0x111...) ] ──> 📄 Баланс: 5.0
    //         ├── [ Ячейка WBTC (0x222...) ] ──> 📄 Баланс: 0.1
    //         └── [ Ячейка LINK (0x333...) ] ──> 📄 Баланс: 100.0

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    /// @dev отчеканенные dsc
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    /// @dev адреса залоговых токенов
    address[] private s_collateralTokens;

    /// @dev адрес контракта стейблкоина
    DecentralizedStableCoin private immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                                 Event
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /*/////////////////////////////////////////////////////////////
                                Modifier
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAlowedToken(address token) {
        // Если для этого токена адрес ценового фида равен нулю, значит токен не разрешен!
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NoAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                              Constructor
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                                Function
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////*/

    /// @dev Функция внесения залога и чеканка
    function depositCollateralAndMintDsc(
        address tocenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tocenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @dev Функция внесения залога
    /// @param tokenCollateralAddress - адрес залогового токена
    /// @param amountCollateral - сумма залога
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAlowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// выкуп залога и сжигание стейблкоинов
    /// @param tokenCollateralAddress - адрес залогового токена weth, wbtc
    /// @param amountCollateral - количество выкупаемы токенов
    /// @param amountDscToBurn - количество сжигаемых токенов
    function redemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /// @dev выкуп залога
    /// @param tokenCollateralAddress - адрес залогового токена weth, wbtc
    /// @param amountCollateral - количество выкупаемых залоговых токенов
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            DSCEngine__TransferFailed;
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// Минт стейбла
    /// @param amountDscToMint - количество стейблов
    /// @dev  _revertIfHealthFactorIsBroken(msg.sender) revert if HF < 1e18
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// сжигаем стейблкоины
    /// @param amount - количество сжигаемых стейблкоинов
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_DSCMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk;
        }
    }

    /// Фактор здоровья
    /// @param user - Адресс пользователя
    /// @dev totalDscMinted - сколько пользователь занял (долг)
    /// @dev collateralValueInUsd - стоимость его залога в USD
    /// @dev collateralAdjustedForThreshold - обеспечение, cкорректированное c учетом порогового Значения
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //500е18                          //1000е18                   //50                     //100
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        //500е18                    1e18           500е18
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        // 500е18 * 1е18 = 500е36, 500e36 / 500e18 = 1e18
    }

    /// функция реверта если _healthFactor < 1e18
    /// @param user - адр польз
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBellowMinimum();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Getters
    //////////////////////////////////////////////////////////////*/
    function getHealthFactor(address user) public view {}

    /// Стоимость всего залога в долларах США
    /// @param user - адрес пользователя.
    /// @return totalCollateralValueInUsd - общая Стоимость Обеспечения В Долларах Сша
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    /// Общее количество отчеканенных DSC, стоимость всего залога в долларах США для одного пользователя
    /// @param user - адрес пользователя
    /// @return totalDscMinted - объем отчеканенных монет DSC
    /// @return collateralValueInUsd - Стоимость залога в долларах США
    function _getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// переводит токены в доллары
    /// @param token - токен адрес контракта
    /// @param amount - количество залога в вей
    /// @return USD 1e18
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeeds = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeeds.latestRoundData();

        //Масштабирование цены: uint256(price) * ADDITIONAL_FEED_PRECISION
        //приводит цену из 8 знаков (стандарт Chainlink для USD) к 18 знакам.
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}

