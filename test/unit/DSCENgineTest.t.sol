// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    //state variables
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address wbtc;

    address btcUsdPriceFeed;
    address public USER = makeAddr("USER");
    uint256 collateralToCover = 20 ether;
    address liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant REDEEM_AMOUNT = 5 ether;
    uint256 public constant MINT_AMOUNT = 100 ether;
    uint256 public constant MAX_MINT_AMOUNT = 10000 ether;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 public constant BURN_AMOUNT = 50;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRICE = 1e10;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 amountToMint = 100 ether;

    //events

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }
    ////////////////
    ///constructor tests
    ////////////////

    address[] public tokenAddresses;
    address[] public pricefeedAddresses;

    function testRevertsIfTokenLengthDosentMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        pricefeedAddresses.push(ethUsdPriceFeed);
        pricefeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, pricefeedAddresses, address(dsc));
    }

    //////////////////////
    ///pricefeed tests////
    //////////////////////

    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualValue);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // 2000$/ ETH , 100$ => 0.05 ether ETH
        uint256 epectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(epectedWeth, actualWeth);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        // collateral value in usd = 10ETH*2000 = 20,000$ + (10*1000BTC = 10,000$ ) = 30,000
        uint256 actualCollateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = (
            uint256(ETH_USD_PRICE) * AMOUNT_COLLATERAL + uint256(BTC_USD_PRICE) * AMOUNT_COLLATERAL
        ) * ADDITIONAL_FEED_PRICE / PRECISION;
        assertEq(actualCollateralValue, expectedCollateralValue);
    }

    //////////////////////////////
    ///deposit collateral tests///
    //////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEnging__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevebersWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEnging__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        // Call the DepositCollateralAndMintDsc function and expect it to succeed
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();

        // Check that the user's collateral balance has been updated correctly
        uint256 expectedCollateralBalance = AMOUNT_COLLATERAL;
        uint256 actualCollateralBalance = dsce.getAccountCollateralAmount(USER, weth);
        assertEq(actualCollateralBalance, expectedCollateralBalance);

        // Check that the user's DSC balance has been updated correctly
        uint256 expectedDscBalance = MINT_AMOUNT;
        uint256 actualDscBalance = dsc.balanceOf(USER);
        assertEq(actualDscBalance, expectedDscBalance);
        // Check that the total supply of DSC tokens has been updated correctly

        uint256 expectedTotalSupply = 0 + MINT_AMOUNT;
        uint256 actualTotalSupply = dsc.totalSupply();
        assertEq(actualTotalSupply, expectedTotalSupply);
    }

    function testDepositCollateralEmitsTheCorrectEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dsce));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    //////////////////////////////
    ///redeem collateral tests////
    //////////////////////////////

    function testRedeemCollateralReducesUserBalance() public depositedCollateral {
        // Define the amount of collateral to redeem
        uint256 userCollateralBalance = dsce.getAccountCollateralAmount(USER, weth);
        // Call the redeemCollateral function and expect it to succeed
        vm.prank(USER);
        dsce.redeemCollateral(weth, REDEEM_AMOUNT);
        // vm.prank(USER);
        // dsce.redeemCollateral(weth, REDEEM_AMOUNT);
        uint256 finalCollateralValueInUsd = dsce.getAccountCollateralAmount(USER, weth);
        assertEq(userCollateralBalance, finalCollateralValueInUsd + REDEEM_AMOUNT);
    }

    function testRedeemCollateralEmitsTheCorrectEvent() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(USER, USER, weth, REDEEM_AMOUNT);
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, REDEEM_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public depositedCollateral mintedDSC {
        // Get the initial collateral balance and DSC balance of the user
        uint256 initialCollateralBalance = dsce.getAccountCollateralAmount(USER, weth);
        uint256 initialDscBalance = dsc.balanceOf(USER);

        // Call the redeemCollateral function and expect it to succeed
        vm.startPrank(USER);
        dsc.approve(address(dsce), BURN_AMOUNT);
        dsce.redeemCollateralForDsc(weth, REDEEM_AMOUNT, BURN_AMOUNT);
        vm.stopPrank();
        uint256 finalCollateralBalance = dsce.getAccountCollateralAmount(USER, weth);
        uint256 finalDscBalance = dsc.balanceOf(USER);

        // Assert that the collateral balance has decreased by the redeemed amount
        assertEq(
            finalCollateralBalance,
            initialCollateralBalance - REDEEM_AMOUNT,
            "Collateral balance should decrease after redemption"
        );

        assertEq(finalDscBalance, initialDscBalance - BURN_AMOUNT, "DSC balance should decrease after redemption");
    }
    ////////////////////
    ///mint/burn dsc tests///
    ////////////////////

    modifier mintedDSC() {
        vm.prank(USER);
        dsce.mintDsc(MINT_AMOUNT);
        _;
    }

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        pricefeedAddresses = [ethUsdPriceFeed];

        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, pricefeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMintDsc() public depositedCollateral mintedDSC {
        uint256 initialBalance = dsc.balanceOf(USER);
        vm.prank(USER);
        dsce.mintDsc(MINT_AMOUNT);
        uint256 finalBalance = dsc.balanceOf(USER);
        assertEq(finalBalance, initialBalance + MINT_AMOUNT);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEnging__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testHealthFactorCalculation() public depositedCollateral mintedDSC {
        uint256 collateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        expectedHealthFactor = (expectedHealthFactor * PRECISION) / MINT_AMOUNT;
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testMintRevertsIfHealthIsBroken() public {
        vm.prank(USER);
        uint256 amountToMint = 1;

        uint256 expectedHealthFactor = 0;
        bytes memory expectedRevertBytes =
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor);
        vm.expectRevert(expectedRevertBytes);
        dsce.mintDsc(amountToMint);
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dsce.mintDsc(MINT_AMOUNT);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, MINT_AMOUNT);
    }

    function testBrunDsc() public depositedCollateral mintedDSC {
        uint256 initialBalance = dsc.balanceOf(USER);
        vm.startPrank(USER);
        dsc.approve(address(dsce), BURN_AMOUNT);
        dsce.burnDsc(BURN_AMOUNT);
        vm.stopPrank();
        uint256 finalBalance = dsc.balanceOf(USER);
        assertEq(finalBalance, initialBalance - BURN_AMOUNT);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEnging__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        pricefeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, pricefeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, MINT_AMOUNT);
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, MINT_AMOUNT);
        dsc.approve(address(dsce), MINT_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOkay.selector);
        dsce.liquidate(weth, USER, MINT_AMOUNT);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, MINT_AMOUNT);

        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, USER, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth, MINT_AMOUNT)
            + (dsce.getTokenAmountFromUsd(weth, MINT_AMOUNT) / dsce.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
}
