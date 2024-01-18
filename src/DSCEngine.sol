// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 * @author Constantin Andrei Todirascu
 * The system is designed to be as minimal as possible, and have the tokens mantain a 1 token == 1 EUR peg.
 * This stable coin has the properties:
 * - Exogenous Collateral
 * - Stable peg
 * - Algorithmically stable
 * It is similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC.
 * Our DSC system should be always overcollateralized. At no point should the value of the collateral be less than the value of the DSC.
 * @notice This contract is the core of the DSC system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__MustBeMostThenZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 indexed amountCollateral);
    event CollateralReedemed(address indexed redeemFrom, address indexed redeemTo, address indexed tokenCollateral, uint256 amountCollateral);

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeMostThenZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @dev Deposits collateral and mints DSC tokens.
     * @param tokenCollateralAddress The address of the collateral token.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDscTomint The amount of DSC tokens to mint.
     * @notice this function is used to deposit collateral and mint DSC tokens in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscTomint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscTomint);
    }

    /**
     * @param tokenCollateralAddress the address of the collateral token
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev Redeems collateral for DSC tokens.
     * @param tokenCollateralAddress The address of the collateral token.
     * @param amountCollateral The amount of collateral to redeem.
     * @param amountDscToBurn The amount of DSC tokens to burn.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, amountCollateral,  tokenCollateralAddress);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern
     * @param amountDscToMint the amount of DSC to mint
     * @notice they must have more collateral value than the minimum treshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 collateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralToRedeem, collateral);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEE_PRECISION);
    }

    function getHealthFactor() external view {}

    // PRIVATE FUNCTIONS //

    /**
     * @dev Internal function to redeem collateral.
     * @param from The address of the account redeeming the collateral.
     * @param to The address where the collateral will be transferred.
     * @param amountCollateralToRedeem The amount of collateral to redeem.
     * @param tokenCollateralAddress The address of the collateral token.
     */
    function _redeemCollateral(
        address from,
        address to,
        uint256 amountCollateralToRedeem,
        address tokenCollateralAddress
    ) internal {
         s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateralToRedeem;
        emit CollateralReedemed(from, to, tokenCollateralAddress, amountCollateralToRedeem);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateralToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amount, address onBehalfOf, address dscFrom) internal {
        s_dscMinted[onBehalfOf] -= amount;
        bool burned = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!burned) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    /**
     * @param user the address of the user
     * @return totalDscMinted the total amount of DSC minted by the user
     * @return collateralValueInEur the total value of the collateral in EUR
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInEur)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInEur = getAccountCollateralValueInEur(user);
    }

    /**
     * Returns how close to liquidation the user is.
     * If a user gets below 1, they chan get liquidated.
     * @param user the address of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInEur) = _getAccountInformation(user);
        uint256 collateralAdjustedForTreshold = (collateralValueInEur * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    // Public and External View Functions //

    /**
     * @param user the address of the user
     * @return totalCollateralValueInEur the total value of the collateral in EUR
     */
    function getAccountCollateralValueInEur(address user) public view returns (uint256 totalCollateralValueInEur) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[user][tokenAddress];
            totalCollateralValueInEur += getUsdValue(tokenAddress, amountCollateral);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * amount) / PRECISION;
    }
}
