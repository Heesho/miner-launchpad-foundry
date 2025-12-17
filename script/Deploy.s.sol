// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UnitFactory} from "../src/UnitFactory.sol";
import {RigFactory} from "../src/RigFactory.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {Core} from "../src/Core.sol";
import {Multicall} from "../src/Multicall.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockUniswapV2Factory, MockUniswapV2Router} from "../src/mocks/MockUniswapV2.sol";
import {MockToken} from "../test/mocks/MockToken.sol";

contract Deploy is Script {
    MockWETH public weth;
    MockToken public donut;
    MockUniswapV2Factory public uniswapFactory;
    MockUniswapV2Router public uniswapRouter;
    UnitFactory public unitFactory;
    RigFactory public rigFactory;
    AuctionFactory public auctionFactory;
    Core public core;
    Multicall public multicall;

    function run() public {
        vm.startBroadcast();

        // Deploy mocks
        weth = new MockWETH();
        console.log("MockWETH deployed at:", address(weth));

        donut = new MockToken("Donut Token", "DONUT");
        console.log("Donut deployed at:", address(donut));

        uniswapFactory = new MockUniswapV2Factory();
        console.log("UniswapV2Factory deployed at:", address(uniswapFactory));

        uniswapRouter = new MockUniswapV2Router(address(uniswapFactory));
        console.log("UniswapV2Router deployed at:", address(uniswapRouter));

        // Deploy factories
        unitFactory = new UnitFactory();
        console.log("UnitFactory deployed at:", address(unitFactory));

        rigFactory = new RigFactory();
        console.log("RigFactory deployed at:", address(rigFactory));

        auctionFactory = new AuctionFactory();
        console.log("AuctionFactory deployed at:", address(auctionFactory));

        // Deploy Core
        core = new Core(
            address(weth),
            address(donut),
            address(uniswapFactory),
            address(uniswapRouter),
            address(unitFactory),
            address(rigFactory),
            address(auctionFactory),
            msg.sender, // protocolFeeAddress
            100 ether // minDonutForLaunch
        );
        console.log("Core deployed at:", address(core));

        // Deploy Multicall
        multicall = new Multicall(address(core), address(weth), address(donut));
        console.log("Multicall deployed at:", address(multicall));

        vm.stopBroadcast();
    }
}
