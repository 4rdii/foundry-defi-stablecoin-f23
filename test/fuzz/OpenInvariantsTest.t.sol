// // SPDX-License-Identifier: MIT

// /**
//  * @notice what are our invariants/properties?
//  *
//  * 1. Total supply of DSC shold be less than total value of collateral
//  * 2. getter view functions should never revert <- evergreen invariants
//  *
//  */
// spragma solidity 0.8.19;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
// import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract InvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DecentralizedStableCoin dsc;
//     DSCEngine dsce;
//     HelperConfig config;
//     address ethUsdPriceFeed;
//     address weth;
//     address btcUsdPriceFeed;
//     address wbtc;
//     address public USER = makeAddr("USER");
//     uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
//     // IERC20 weth;
//     // IERC20 wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
//         // ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
//         // ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
//         targetContract(address(dsce));
//     }

//     function invariant_protocloMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
//         console.log("weth value:", wethValue);
//         console.log("wbtc value:", wbtcValue);
//         console.log("total value:", totalSupply);
//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
