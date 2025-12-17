// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";
import {Core} from "../src/Core.sol";
import {Unit} from "../src/Unit.sol";
import {Rig} from "../src/Rig.sol";
import {Auction} from "../src/Auction.sol";

/**
 * @title GasTest
 * @notice Gas consumption benchmarks and limits
 */
contract GasTest is BaseTest {
    // Gas limits (adjust based on requirements)
    uint256 constant MAX_LAUNCH_GAS = 6_000_000;
    uint256 constant MAX_MINE_GAS = 300_000;
    uint256 constant MAX_BUY_GAS = 200_000;
    uint256 constant MAX_TRANSFER_GAS = 100_000;
    uint256 constant MAX_DELEGATE_GAS = 150_000;

    /*//////////////////////////////////////////////////////////////
                            CORE GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_launch() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);

        uint256 gasBefore = gasleft();
        core.launch(params);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for launch:", gasUsed);
        assertLt(gasUsed, MAX_LAUNCH_GAS, "Launch exceeds gas limit");
    }

    /*//////////////////////////////////////////////////////////////
                            RIG GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_mine() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 price = rig.getPrice();

        vm.startPrank(bob);
        weth.approve(rigAddr, price);

        uint256 gasBefore = gasleft();
        rig.mine(bob, 0, block.timestamp + 1 hours, price, "");
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for mine:", gasUsed);
        assertLt(gasUsed, MAX_MINE_GAS, "Mine exceeds gas limit");
    }

    function test_gas_mineWithLongUri() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 price = rig.getPrice();

        // Create a long URI string (1000 chars)
        bytes memory longUri = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            longUri[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
        }

        vm.startPrank(bob);
        weth.approve(rigAddr, price);

        uint256 gasBefore = gasleft();
        rig.mine(bob, 0, block.timestamp + 1 hours, price, string(longUri));
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for mine with long URI:", gasUsed);
        // Long URIs cost more but should still be reasonable
        assertLt(gasUsed, MAX_MINE_GAS * 3, "Mine with long URI exceeds limit");
    }

    function test_gas_mineAfterManyEpochs() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Mine 50 times to increase epoch count
        for (uint256 i = 0; i < 50; i++) {
            uint256 price = rig.getPrice();
            address miner = makeAddr(string(abi.encodePacked("miner", i)));
            vm.deal(miner, price);

            vm.startPrank(miner);
            weth.deposit{value: price}();
            weth.approve(rigAddr, price);
            rig.mine(miner, rig.epochId(), block.timestamp + 1 hours, price, "");
            vm.stopPrank();
        }

        // Now mine and measure gas
        uint256 price = rig.getPrice();

        // Fund bob with enough WETH for this price
        vm.deal(bob, price + 1 ether);
        vm.startPrank(bob);
        weth.deposit{value: price}();
        weth.approve(rigAddr, price);

        uint256 gasBefore = gasleft();
        rig.mine(bob, rig.epochId(), block.timestamp + 1 hours, price, "");
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for mine after 50 epochs:", gasUsed);
        // Gas should be constant regardless of epoch count
        assertLt(gasUsed, MAX_MINE_GAS, "Mine gas increases with epochs");
    }

    function test_gas_getPrice() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 gasBefore = gasleft();
        rig.getPrice();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for getPrice:", gasUsed);
        assertLt(gasUsed, 10_000, "getPrice exceeds limit");
    }

    function test_gas_getUps() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 gasBefore = gasleft();
        rig.getUps();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for getUps:", gasUsed);
        assertLt(gasUsed, 10_000, "getUps exceeds limit");
    }

    function test_gas_getUpsAfterManyHalvings() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Warp through 100 halving periods
        vm.warp(rig.startTime() + rig.halvingPeriod() * 100);

        uint256 gasBefore = gasleft();
        rig.getUps();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for getUps after 100 halvings:", gasUsed);
        // Gas should be O(log n) due to halving calculation
        assertLt(gasUsed, 15_000, "getUps gas increases too much with halvings");
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_buy() public {
        (,, address auctionAddr, address lpAddr) = _launchRig(alice);
        Auction auctionContract = Auction(auctionAddr);

        // Fund auction
        weth.deposit{value: 10 ether}();
        weth.transfer(auctionAddr, 10 ether);

        uint256 price = auctionContract.getPrice();
        deal(lpAddr, bob, price);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        vm.startPrank(bob);
        IERC20(lpAddr).approve(auctionAddr, price);

        uint256 gasBefore = gasleft();
        auctionContract.buy(assets, bob, 0, block.timestamp + 1 hours, price);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for buy:", gasUsed);
        assertLt(gasUsed, MAX_BUY_GAS, "Buy exceeds gas limit");
    }

    function test_gas_buyMultipleAssets() public {
        (,, address auctionAddr, address lpAddr) = _launchRig(alice);
        Auction auctionContract = Auction(auctionAddr);

        // Fund auction with multiple assets
        weth.deposit{value: 10 ether}();
        weth.transfer(auctionAddr, 10 ether);

        // Create additional mock tokens
        MockToken token2 = new MockToken("Token2", "T2");
        MockToken token3 = new MockToken("Token3", "T3");
        MockToken token4 = new MockToken("Token4", "T4");
        MockToken token5 = new MockToken("Token5", "T5");

        token2.mint(auctionAddr, 10 ether);
        token3.mint(auctionAddr, 10 ether);
        token4.mint(auctionAddr, 10 ether);
        token5.mint(auctionAddr, 10 ether);

        uint256 price = auctionContract.getPrice();
        deal(lpAddr, bob, price);

        address[] memory assets = new address[](5);
        assets[0] = address(weth);
        assets[1] = address(token2);
        assets[2] = address(token3);
        assets[3] = address(token4);
        assets[4] = address(token5);

        vm.startPrank(bob);
        IERC20(lpAddr).approve(auctionAddr, price);

        uint256 gasBefore = gasleft();
        auctionContract.buy(assets, bob, 0, block.timestamp + 1 hours, price);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for buy 5 assets:", gasUsed);
        // Gas should scale linearly with number of assets
        assertLt(gasUsed, MAX_BUY_GAS * 3, "Buy multiple assets exceeds limit");
    }

    /*//////////////////////////////////////////////////////////////
                            UNIT TOKEN GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_transfer() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        vm.startPrank(bob);

        uint256 gasBefore = gasleft();
        unitToken.transfer(charlie, 50 ether);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for transfer:", gasUsed);
        assertLt(gasUsed, MAX_TRANSFER_GAS, "Transfer exceeds gas limit");
    }

    function test_gas_transferWithDelegation() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        // Both sender and receiver have delegation
        vm.prank(bob);
        unitToken.delegate(bob);

        vm.prank(charlie);
        unitToken.delegate(charlie);

        vm.startPrank(bob);

        uint256 gasBefore = gasleft();
        unitToken.transfer(charlie, 50 ether);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for transfer with delegation:", gasUsed);
        // Transfers with delegation cost more due to checkpoint updates
        assertLt(gasUsed, MAX_TRANSFER_GAS * 2, "Transfer with delegation exceeds limit");
    }

    function test_gas_delegate() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        vm.startPrank(bob);

        uint256 gasBefore = gasleft();
        unitToken.delegate(charlie);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for delegate:", gasUsed);
        assertLt(gasUsed, MAX_DELEGATE_GAS, "Delegate exceeds gas limit");
    }

    function test_gas_mint() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.startPrank(rigAddr);

        uint256 gasBefore = gasleft();
        unitToken.mint(bob, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for mint:", gasUsed);
        assertLt(gasUsed, 100_000, "Mint exceeds gas limit");
    }

    function test_gas_burn() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        vm.startPrank(bob);

        uint256 gasBefore = gasleft();
        unitToken.burn(50 ether);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for burn:", gasUsed);
        assertLt(gasUsed, 50_000, "Burn exceeds gas limit");
    }

    /*//////////////////////////////////////////////////////////////
                            MULTICALL GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_multicallMine() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 price = rig.getPrice();
        vm.deal(bob, price);

        vm.startPrank(bob);

        uint256 gasBefore = gasleft();
        multicall.mine{value: price}(rigAddr, 0, block.timestamp + 1 hours, price, "");
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for multicall mine:", gasUsed);
        // Multicall adds overhead for WETH wrapping
        assertLt(gasUsed, MAX_MINE_GAS + 100_000, "Multicall mine exceeds limit");
    }

    function test_gas_multicallLaunch() public {
        ICore.LaunchParams memory params = ICore.LaunchParams({
            launcher: alice,
            tokenName: "Gas Test Token",
            tokenSymbol: "GTT",
            uri: "https://test.com",
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

        vm.startPrank(alice);
        donut.approve(address(multicall), params.donutAmount);

        uint256 gasBefore = gasleft();
        multicall.launch(params);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Gas used for multicall launch:", gasUsed);
        assertLt(gasUsed, MAX_LAUNCH_GAS + 100_000, "Multicall launch exceeds limit");
    }

    /*//////////////////////////////////////////////////////////////
                            GAS COMPARISON TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_comparison_directVsMulticall() public {
        // Direct launch
        Core.LaunchParams memory params1 = _getDefaultLaunchParams(alice);
        params1.tokenName = "Direct Token";
        params1.tokenSymbol = "DT";

        vm.startPrank(alice);
        donut.approve(address(core), params1.donutAmount);

        uint256 gasBefore1 = gasleft();
        core.launch(params1);
        uint256 directGas = gasBefore1 - gasleft();

        vm.stopPrank();

        // Multicall launch
        ICore.LaunchParams memory params2 = ICore.LaunchParams({
            launcher: bob,
            tokenName: "Multicall Token",
            tokenSymbol: "MT",
            uri: "https://test.com",
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

        vm.startPrank(bob);
        donut.approve(address(multicall), params2.donutAmount);

        uint256 gasBefore2 = gasleft();
        multicall.launch(params2);
        uint256 multicallGas = gasBefore2 - gasleft();

        vm.stopPrank();

        console.log("Direct launch gas:", directGas);
        console.log("Multicall launch gas:", multicallGas);

        // Calculate overhead safely (multicall could be cheaper in some cases)
        uint256 overhead = multicallGas > directGas ? multicallGas - directGas : 0;
        console.log("Overhead:", overhead);

        // Multicall should not be significantly more expensive
        assertLt(multicallGas, directGas + 100_000, "Multicall overhead too high");
    }
}

// Import for gas tests
import {ICore} from "../src/interfaces/ICore.sol";
import {MockToken} from "./mocks/MockToken.sol";
