// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Core} from "../src/Core.sol";
import {ICore} from "../src/interfaces/ICore.sol";
import {Unit} from "../src/Unit.sol";
import {Rig} from "../src/Rig.sol";
import {Auction} from "../src/Auction.sol";
import {UnitFactory} from "../src/UnitFactory.sol";
import {RigFactory} from "../src/RigFactory.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {Multicall} from "../src/Multicall.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockUniswapV2Factory, MockUniswapV2Router, MockLP} from "../src/mocks/MockUniswapV2.sol";
import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title BaseTest
 * @notice Common test setup and utilities for all test files
 */
abstract contract BaseTest is Test {
    /*----------  CONTRACTS  --------------------------------------------*/

    Core public core;
    UnitFactory public unitFactory;
    RigFactory public rigFactory;
    AuctionFactory public auctionFactory;
    Multicall public multicall;
    MockWETH public weth;
    MockToken public donut;
    MockUniswapV2Factory public uniswapFactory;
    MockUniswapV2Router public uniswapRouter;

    /*----------  USERS  ------------------------------------------------*/

    address public owner;
    address public protocolFeeAddress;
    address public alice;
    address public bob;
    address public charlie;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MIN_DONUT_FOR_LAUNCH = 100 ether;

    // Default launch parameters
    uint256 public constant DEFAULT_DONUT_AMOUNT = 1000 ether;
    uint256 public constant DEFAULT_UNIT_AMOUNT = 1000 ether;
    uint256 public constant DEFAULT_INITIAL_UPS = 1e18; // 1 token/second
    uint256 public constant DEFAULT_TAIL_UPS = 1e16; // 0.01 tokens/second minimum
    uint256 public constant DEFAULT_HALVING_PERIOD = 365 days;
    uint256 public constant DEFAULT_RIG_EPOCH_PERIOD = 1 hours;
    uint256 public constant DEFAULT_RIG_PRICE_MULTIPLIER = 1.5e18; // 150%
    uint256 public constant DEFAULT_RIG_MIN_INIT_PRICE = 1e15; // 0.001 WETH
    uint256 public constant DEFAULT_AUCTION_INIT_PRICE = 1e15;
    uint256 public constant DEFAULT_AUCTION_EPOCH_PERIOD = 1 hours;
    uint256 public constant DEFAULT_AUCTION_PRICE_MULTIPLIER = 1.5e18;
    uint256 public constant DEFAULT_AUCTION_MIN_INIT_PRICE = 1e15;

    /*----------  SETUP  ------------------------------------------------*/

    function setUp() public virtual {
        // Setup accounts
        owner = makeAddr("owner");
        protocolFeeAddress = makeAddr("protocolFee");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy contracts as owner
        vm.startPrank(owner);

        // Deploy mocks
        weth = new MockWETH();
        donut = new MockToken("Donut Token", "DONUT");
        uniswapFactory = new MockUniswapV2Factory();
        uniswapRouter = new MockUniswapV2Router(address(uniswapFactory));

        // Deploy factories
        unitFactory = new UnitFactory();
        rigFactory = new RigFactory();
        auctionFactory = new AuctionFactory();

        // Deploy Core
        core = new Core(
            address(weth),
            address(donut),
            address(uniswapFactory),
            address(uniswapRouter),
            address(unitFactory),
            address(rigFactory),
            address(auctionFactory),
            protocolFeeAddress,
            MIN_DONUT_FOR_LAUNCH
        );

        // Deploy Multicall
        multicall = new Multicall(address(core), address(weth), address(donut));

        vm.stopPrank();

        // Fund users
        _fundUsers();
    }

    /*----------  HELPERS  ----------------------------------------------*/

    function _fundUsers() internal {
        // Fund ETH
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);

        // Mint DONUT tokens
        donut.mint(alice, INITIAL_BALANCE * 10);
        donut.mint(bob, INITIAL_BALANCE * 10);
        donut.mint(charlie, INITIAL_BALANCE * 10);

        // Mint WETH
        vm.prank(alice);
        weth.deposit{value: INITIAL_BALANCE / 2}();
        vm.prank(bob);
        weth.deposit{value: INITIAL_BALANCE / 2}();
        vm.prank(charlie);
        weth.deposit{value: INITIAL_BALANCE / 2}();
    }

    function _getDefaultLaunchParams(address launcher) internal pure returns (Core.LaunchParams memory) {
        return Core.LaunchParams({
            launcher: launcher,
            tokenName: "Test Unit Token",
            tokenSymbol: "TUT",
            uri: "https://example.com/token.json",
            donutAmount: DEFAULT_DONUT_AMOUNT,
            unitAmount: DEFAULT_UNIT_AMOUNT,
            initialUps: DEFAULT_INITIAL_UPS,
            tailUps: DEFAULT_TAIL_UPS,
            halvingPeriod: DEFAULT_HALVING_PERIOD,
            rigEpochPeriod: DEFAULT_RIG_EPOCH_PERIOD,
            rigPriceMultiplier: DEFAULT_RIG_PRICE_MULTIPLIER,
            rigMinInitPrice: DEFAULT_RIG_MIN_INIT_PRICE,
            auctionInitPrice: DEFAULT_AUCTION_INIT_PRICE,
            auctionEpochPeriod: DEFAULT_AUCTION_EPOCH_PERIOD,
            auctionPriceMultiplier: DEFAULT_AUCTION_PRICE_MULTIPLIER,
            auctionMinInitPrice: DEFAULT_AUCTION_MIN_INIT_PRICE
        });
    }

    function _launchRig(address launcher) internal returns (address unit, address rig, address auction, address lp) {
        Core.LaunchParams memory params = _getDefaultLaunchParams(launcher);

        vm.startPrank(launcher);
        donut.approve(address(core), params.donutAmount);
        (unit, rig, auction, lp) = core.launch(params);
        vm.stopPrank();

        return (unit, rig, auction, lp);
    }

    function _launchRigViaMulticall(address launcher)
        internal
        returns (address unit, address rig, address auction, address lp)
    {
        Core.LaunchParams memory coreParams = _getDefaultLaunchParams(launcher);

        ICore.LaunchParams memory params = ICore.LaunchParams({
            launcher: coreParams.launcher,
            tokenName: coreParams.tokenName,
            tokenSymbol: coreParams.tokenSymbol,
            uri: coreParams.uri,
            donutAmount: coreParams.donutAmount,
            unitAmount: coreParams.unitAmount,
            initialUps: coreParams.initialUps,
            tailUps: coreParams.tailUps,
            halvingPeriod: coreParams.halvingPeriod,
            rigEpochPeriod: coreParams.rigEpochPeriod,
            rigPriceMultiplier: coreParams.rigPriceMultiplier,
            rigMinInitPrice: coreParams.rigMinInitPrice,
            auctionInitPrice: coreParams.auctionInitPrice,
            auctionEpochPeriod: coreParams.auctionEpochPeriod,
            auctionPriceMultiplier: coreParams.auctionPriceMultiplier,
            auctionMinInitPrice: coreParams.auctionMinInitPrice
        });

        vm.startPrank(launcher);
        donut.approve(address(multicall), params.donutAmount);
        (unit, rig, auction, lp) = multicall.launch(params);
        vm.stopPrank();

        return (unit, rig, auction, lp);
    }

    function _mineRig(address miner, address rig, uint256 wethAmount) internal returns (uint256 price) {
        Rig rigContract = Rig(rig);
        uint256 epochId = rigContract.epochId();
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(miner);
        weth.approve(rig, wethAmount);
        price = rigContract.mine(miner, epochId, deadline, wethAmount, "miner-uri");
        vm.stopPrank();
    }

    function _mineRigViaMulticall(address miner, address rig, uint256 ethAmount) internal {
        Rig rigContract = Rig(rig);
        uint256 epochId = rigContract.epochId();
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxPrice = rigContract.getPrice();

        vm.prank(miner);
        multicall.mine{value: ethAmount}(rig, epochId, deadline, maxPrice, "miner-uri");
    }

    function _buyFromAuction(address buyer, address rig, uint256 lpAmount) internal {
        address auction = core.rigToAuction(rig);
        address lpToken = Auction(auction).paymentToken();
        uint256 epochId = Auction(auction).epochId();
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(buyer);
        IERC20(lpToken).approve(address(multicall), lpAmount);
        multicall.buy(rig, epochId, deadline, lpAmount);
        vm.stopPrank();
    }
}
