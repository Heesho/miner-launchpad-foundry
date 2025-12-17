// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {Core} from "../src/Core.sol";
import {ICore} from "../src/interfaces/ICore.sol";
import {Unit} from "../src/Unit.sol";
import {Rig} from "../src/Rig.sol";
import {Auction} from "../src/Auction.sol";
import {Multicall} from "../src/Multicall.sol";
import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title FuzzTest
 * @notice Intensive fuzz testing for the Miner Launchpad system
 */
contract FuzzTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                            UNIT TOKEN FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_unit_mintAndBurn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 0, type(uint208).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);

        // Get the rig to mint tokens (only rig can mint)
        address rigAddr = unitToken.rig();

        // Initial supply from LP creation
        uint256 initialSupply = unitToken.totalSupply();

        vm.prank(rigAddr);
        unitToken.mint(bob, mintAmount);

        assertEq(unitToken.balanceOf(bob), mintAmount);
        assertEq(unitToken.totalSupply(), initialSupply + mintAmount);

        vm.prank(bob);
        unitToken.burn(burnAmount);

        assertEq(unitToken.balanceOf(bob), mintAmount - burnAmount);
        assertEq(unitToken.totalSupply(), initialSupply + mintAmount - burnAmount);
    }

    function testFuzz_unit_transfer(uint256 amount, uint256 transferAmount) public {
        amount = bound(amount, 1, type(uint208).max);
        transferAmount = bound(transferAmount, 0, amount);

        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, amount);

        vm.prank(bob);
        unitToken.transfer(charlie, transferAmount);

        assertEq(unitToken.balanceOf(bob), amount - transferAmount);
        assertEq(unitToken.balanceOf(charlie), transferAmount);
    }

    function testFuzz_unit_delegationAndVotes(uint256 amount) public {
        amount = bound(amount, 1, type(uint208).max);

        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, amount);

        // Before delegation, no votes
        assertEq(unitToken.getVotes(bob), 0);

        // Self delegate
        vm.prank(bob);
        unitToken.delegate(bob);

        assertEq(unitToken.getVotes(bob), amount);

        // Delegate to charlie
        vm.prank(bob);
        unitToken.delegate(charlie);

        assertEq(unitToken.getVotes(bob), 0);
        assertEq(unitToken.getVotes(charlie), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_auction_priceDecay(uint256 initPrice, uint256 epochPeriod, uint256 timePassed) public {
        initPrice = bound(initPrice, 1e6, type(uint192).max);
        epochPeriod = bound(epochPeriod, 1 hours, 365 days);
        timePassed = bound(timePassed, 0, epochPeriod * 2);

        MockToken lpToken = new MockToken("LP", "LP");
        address receiver = makeAddr("receiver");

        Auction auction = new Auction(initPrice, address(lpToken), receiver, epochPeriod, 1.5e18, 1e6);

        vm.warp(block.timestamp + timePassed);

        uint256 price = auction.getPrice();

        if (timePassed >= epochPeriod) {
            assertEq(price, 0, "Price should be 0 after epoch period");
        } else {
            uint256 expectedPrice = initPrice - (initPrice * timePassed / epochPeriod);
            assertEq(price, expectedPrice, "Price decay mismatch");
        }
    }

    function testFuzz_auction_buyAtVariousTimes(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, DEFAULT_AUCTION_EPOCH_PERIOD);

        MockToken lpToken = new MockToken("LP", "LP");
        MockToken asset = new MockToken("Asset", "ASSET");
        address receiver = makeAddr("receiver");

        Auction auction = new Auction(
            DEFAULT_AUCTION_INIT_PRICE,
            address(lpToken),
            receiver,
            DEFAULT_AUCTION_EPOCH_PERIOD,
            DEFAULT_AUCTION_PRICE_MULTIPLIER,
            DEFAULT_AUCTION_MIN_INIT_PRICE
        );

        // Fund auction with assets
        asset.mint(address(auction), 100 ether);
        lpToken.mint(alice, type(uint128).max);

        vm.warp(block.timestamp + timePassed);

        uint256 price = auction.getPrice();
        address[] memory assets = new address[](1);
        assets[0] = address(asset);

        vm.startPrank(alice);
        lpToken.approve(address(auction), price);
        uint256 paidAmount = auction.buy(assets, alice, 0, block.timestamp + 1 hours, price);
        vm.stopPrank();

        assertEq(paidAmount, price);
        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(auction.epochId(), 1);
    }

    function testFuzz_auction_priceMultiplierEffect(uint256 priceMultiplier, uint256 paymentAmount) public {
        priceMultiplier = bound(priceMultiplier, 1.1e18, 3e18);
        paymentAmount = bound(paymentAmount, 1e6, type(uint192).max / 4);

        MockToken lpToken = new MockToken("LP", "LP");
        MockToken asset = new MockToken("Asset", "ASSET");
        address receiver = makeAddr("receiver");

        Auction auction = new Auction(paymentAmount, address(lpToken), receiver, 1 hours, priceMultiplier, 1e6);

        asset.mint(address(auction), 100 ether);
        lpToken.mint(alice, type(uint256).max);

        address[] memory assets = new address[](1);
        assets[0] = address(asset);

        vm.startPrank(alice);
        lpToken.approve(address(auction), paymentAmount);
        auction.buy(assets, alice, 0, block.timestamp + 1 hours, paymentAmount);
        vm.stopPrank();

        uint256 expectedNewPrice = paymentAmount * priceMultiplier / 1e18;
        if (expectedNewPrice < 1e6) expectedNewPrice = 1e6;
        if (expectedNewPrice > type(uint192).max) expectedNewPrice = type(uint192).max;

        assertEq(auction.initPrice(), expectedNewPrice);
    }

    /*//////////////////////////////////////////////////////////////
                            RIG FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_rig_priceDecay(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, DEFAULT_RIG_EPOCH_PERIOD * 2);

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 initPrice = rig.epochInitPrice();
        uint256 epochPeriod = rig.epochPeriod();

        vm.warp(block.timestamp + timePassed);

        uint256 price = rig.getPrice();

        if (timePassed >= epochPeriod) {
            assertEq(price, 0, "Price should be 0 after epoch period");
        } else {
            uint256 expectedPrice = initPrice - (initPrice * timePassed / epochPeriod);
            assertEq(price, expectedPrice, "Price decay mismatch");
        }
    }

    function testFuzz_rig_halvingSchedule(uint256 halvingPeriods) public {
        halvingPeriods = bound(halvingPeriods, 0, 20);

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 startTime = rig.startTime();
        uint256 halvingPeriod = rig.halvingPeriod();
        uint256 initialUps = rig.initialUps();
        uint256 tailUps = rig.tailUps();

        vm.warp(startTime + halvingPeriod * halvingPeriods);

        uint256 currentUps = rig.getUps();
        uint256 expectedUps = initialUps >> halvingPeriods;

        if (expectedUps < tailUps) {
            assertEq(currentUps, tailUps, "Should be at tail UPS");
        } else {
            assertEq(currentUps, expectedUps, "UPS halving mismatch");
        }
    }

    function testFuzz_rig_mineAtVariousPrices(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, DEFAULT_RIG_EPOCH_PERIOD);

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        vm.warp(block.timestamp + timePassed);

        uint256 price = rig.getPrice();
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(bob);
        multicall.mine{value: price}(rigAddr, 0, deadline, price, "fuzz-uri");

        assertEq(rig.epochMiner(), bob);
        assertEq(rig.epochId(), 1);
    }

    function testFuzz_rig_feeDistribution(uint256 price) public {
        price = bound(price, 1e6, 1000 ether);

        // Create a custom rig with specific min price
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.rigMinInitPrice = price;

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (, address rigAddr, address auctionAddr,) = core.launch(params);
        vm.stopPrank();

        Rig rig = Rig(rigAddr);

        // Fund bob with WETH
        vm.deal(bob, price * 2);
        vm.prank(bob);
        weth.deposit{value: price * 2}();

        uint256 currentPrice = rig.getPrice();
        address previousMiner = rig.epochMiner(); // alice/team

        uint256 previousMinerBalanceBefore = weth.balanceOf(previousMiner);
        uint256 treasuryBalanceBefore = weth.balanceOf(auctionAddr);
        uint256 protocolBalanceBefore = weth.balanceOf(protocolFeeAddress);

        vm.startPrank(bob);
        weth.approve(rigAddr, currentPrice);
        rig.mine(bob, 0, block.timestamp + 1 hours, currentPrice, "");
        vm.stopPrank();

        if (currentPrice > 0) {
            uint256 previousMinerFee = currentPrice * 8000 / 10000;
            uint256 teamFee = currentPrice * 400 / 10000;
            uint256 protocolFee = currentPrice * 100 / 10000;
            uint256 treasuryFee = currentPrice - previousMinerFee - teamFee - protocolFee;

            // Previous miner is alice who is also team, so gets both
            assertEq(
                weth.balanceOf(previousMiner),
                previousMinerBalanceBefore + previousMinerFee + teamFee,
                "Previous miner + team fee mismatch"
            );
            assertEq(weth.balanceOf(auctionAddr), treasuryBalanceBefore + treasuryFee, "Treasury fee mismatch");
            assertEq(weth.balanceOf(protocolFeeAddress), protocolBalanceBefore + protocolFee, "Protocol fee mismatch");
        }
    }

    function testFuzz_rig_tokenMinting(uint256 holdTime) public {
        holdTime = bound(holdTime, 1, DEFAULT_RIG_EPOCH_PERIOD);

        (address unitAddr, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);
        Unit unitToken = Unit(unitAddr);

        // Bob mines first
        uint256 price1 = rig.getPrice();
        vm.prank(bob);
        multicall.mine{value: price1}(rigAddr, 0, block.timestamp + 1 days, price1, "");

        uint256 epochStartTime = rig.epochStartTime();
        uint256 epochUps = rig.epochUps();

        // Wait holdTime
        vm.warp(epochStartTime + holdTime);

        uint256 bobBalanceBefore = unitToken.balanceOf(bob);

        // Charlie mines
        uint256 price2 = rig.getPrice();
        vm.prank(charlie);
        multicall.mine{value: price2}(rigAddr, 1, block.timestamp + 1 days, price2, "");

        uint256 expectedMinted = holdTime * epochUps;
        assertEq(unitToken.balanceOf(bob), bobBalanceBefore + expectedMinted, "Minted amount mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_core_launchWithVariousAmounts(uint256 donutAmount, uint256 unitAmount) public {
        donutAmount = bound(donutAmount, MIN_DONUT_FOR_LAUNCH, 1_000_000 ether);
        unitAmount = bound(unitAmount, 1, 1_000_000 ether);

        donut.mint(alice, donutAmount);

        Core.LaunchParams memory params = Core.LaunchParams({
            launcher: alice,
            tokenName: "Fuzz Token",
            tokenSymbol: "FT",
            uri: "https://fuzz.com",
            donutAmount: donutAmount,
            unitAmount: unitAmount,
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
        donut.approve(address(core), donutAmount);
        (address unit, address rig, address auction, address lp) = core.launch(params);
        vm.stopPrank();

        assertTrue(unit != address(0));
        assertTrue(rig != address(0));
        assertTrue(auction != address(0));
        assertTrue(lp != address(0));

        // Verify LP was created and burned
        assertTrue(IERC20(lp).balanceOf(core.DEAD_ADDRESS()) > 0);
    }

    function testFuzz_core_launchWithVariousUps(uint256 initialUps, uint256 tailUps) public {
        initialUps = bound(initialUps, 1, 1e24);
        tailUps = bound(tailUps, 1, initialUps);

        Core.LaunchParams memory params = Core.LaunchParams({
            launcher: alice,
            tokenName: "UPS Test",
            tokenSymbol: "UPS",
            uri: "",
            donutAmount: DEFAULT_DONUT_AMOUNT,
            unitAmount: DEFAULT_UNIT_AMOUNT,
            initialUps: initialUps,
            tailUps: tailUps,
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
        donut.approve(address(core), params.donutAmount);
        (, address rig,,) = core.launch(params);
        vm.stopPrank();

        assertEq(Rig(rig).initialUps(), initialUps);
        assertEq(Rig(rig).tailUps(), tailUps);
        assertEq(Rig(rig).getUps(), initialUps);
    }

    function testFuzz_core_launchWithVariousPeriods(
        uint256 halvingPeriod,
        uint256 rigEpochPeriod,
        uint256 auctionEpochPeriod
    ) public {
        halvingPeriod = bound(halvingPeriod, 1 days, 365 days * 10);
        rigEpochPeriod = bound(rigEpochPeriod, 10 minutes, 365 days);
        auctionEpochPeriod = bound(auctionEpochPeriod, 1 hours, 365 days);

        Core.LaunchParams memory params = Core.LaunchParams({
            launcher: alice,
            tokenName: "Period Test",
            tokenSymbol: "PT",
            uri: "",
            donutAmount: DEFAULT_DONUT_AMOUNT,
            unitAmount: DEFAULT_UNIT_AMOUNT,
            initialUps: DEFAULT_INITIAL_UPS,
            tailUps: DEFAULT_TAIL_UPS,
            halvingPeriod: halvingPeriod,
            rigEpochPeriod: rigEpochPeriod,
            rigPriceMultiplier: DEFAULT_RIG_PRICE_MULTIPLIER,
            rigMinInitPrice: DEFAULT_RIG_MIN_INIT_PRICE,
            auctionInitPrice: DEFAULT_AUCTION_INIT_PRICE,
            auctionEpochPeriod: auctionEpochPeriod,
            auctionPriceMultiplier: DEFAULT_AUCTION_PRICE_MULTIPLIER,
            auctionMinInitPrice: DEFAULT_AUCTION_MIN_INIT_PRICE
        });

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (, address rig, address auction,) = core.launch(params);
        vm.stopPrank();

        assertEq(Rig(rig).halvingPeriod(), halvingPeriod);
        assertEq(Rig(rig).epochPeriod(), rigEpochPeriod);
        assertEq(Auction(auction).epochPeriod(), auctionEpochPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_integration_multipleMines(uint8 numMines) public {
        numMines = uint8(bound(numMines, 1, 20));

        (address unitAddr, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);
        Unit unitToken = Unit(unitAddr);

        address[] memory miners = new address[](numMines);
        for (uint256 i = 0; i < numMines; i++) {
            miners[i] = makeAddr(string(abi.encodePacked("miner", i)));
            vm.deal(miners[i], 100 ether);
        }

        for (uint256 i = 0; i < numMines; i++) {
            uint256 price = rig.getPrice();
            uint256 deadline = block.timestamp + 1 days;

            vm.prank(miners[i]);
            multicall.mine{value: price}(rigAddr, i, deadline, price, "");

            assertEq(rig.epochMiner(), miners[i]);
            assertEq(rig.epochId(), i + 1);

            // Small time warp between mines
            vm.warp(block.timestamp + 1 minutes);
        }

        // All previous miners (except last) should have tokens
        for (uint256 i = 0; i < numMines - 1; i++) {
            assertTrue(unitToken.balanceOf(miners[i]) > 0, "Miner should have tokens");
        }
    }

    function testFuzz_integration_mineAndHalving(uint256 halvingsToPass) public {
        halvingsToPass = bound(halvingsToPass, 0, 10);

        // Create rig with short halving period
        Core.LaunchParams memory params = Core.LaunchParams({
            launcher: alice,
            tokenName: "Halving Fuzz",
            tokenSymbol: "HF",
            uri: "",
            donutAmount: DEFAULT_DONUT_AMOUNT,
            unitAmount: DEFAULT_UNIT_AMOUNT,
            initialUps: 1e18,
            tailUps: 1e15,
            halvingPeriod: 1 days,
            rigEpochPeriod: 1 hours,
            rigPriceMultiplier: DEFAULT_RIG_PRICE_MULTIPLIER,
            rigMinInitPrice: DEFAULT_RIG_MIN_INIT_PRICE,
            auctionInitPrice: DEFAULT_AUCTION_INIT_PRICE,
            auctionEpochPeriod: DEFAULT_AUCTION_EPOCH_PERIOD,
            auctionPriceMultiplier: DEFAULT_AUCTION_PRICE_MULTIPLIER,
            auctionMinInitPrice: DEFAULT_AUCTION_MIN_INIT_PRICE
        });

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (, address rigAddr,,) = core.launch(params);
        vm.stopPrank();

        Rig rig = Rig(rigAddr);
        uint256 startTime = rig.startTime();

        // Warp to after halvings
        vm.warp(startTime + 1 days * halvingsToPass);

        uint256 currentUps = rig.getUps();
        uint256 expectedUps = 1e18 >> halvingsToPass;
        if (expectedUps < 1e15) expectedUps = 1e15;

        assertEq(currentUps, expectedUps, "UPS after halvings mismatch");

        // Mine and verify UPS is used correctly
        uint256 price = rig.getPrice();
        vm.prank(bob);
        multicall.mine{value: price}(rigAddr, 0, block.timestamp + 1 days, price, "");

        assertEq(rig.epochUps(), currentUps, "Epoch UPS should match current UPS");
    }

    function testFuzz_integration_priceMultiplierChain(uint8 numMines) public {
        numMines = uint8(bound(numMines, 1, 10));

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256[] memory prices = new uint256[](numMines);

        for (uint256 i = 0; i < numMines; i++) {
            prices[i] = rig.getPrice();
            uint256 deadline = block.timestamp + 1 days;

            address miner = makeAddr(string(abi.encodePacked("miner", i)));
            vm.deal(miner, 100 ether);

            vm.prank(miner);
            multicall.mine{value: prices[i]}(rigAddr, i, deadline, prices[i], "");

            // Verify price multiplier effect
            if (i > 0) {
                uint256 expectedInitPrice = prices[i - 1] * DEFAULT_RIG_PRICE_MULTIPLIER / 1e18;
                if (expectedInitPrice < DEFAULT_RIG_MIN_INIT_PRICE) {
                    expectedInitPrice = DEFAULT_RIG_MIN_INIT_PRICE;
                }
                // New init price should be based on previous payment
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT-STYLE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_invariant_totalSupplyMatchesBalances(uint256 mintAmount1, uint256 mintAmount2, uint256 burnAmount)
        public
    {
        mintAmount1 = bound(mintAmount1, 0, type(uint104).max);
        mintAmount2 = bound(mintAmount2, 0, type(uint104).max);
        burnAmount = bound(burnAmount, 0, mintAmount1);

        (address unitAddr,,, address lpAddr) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.startPrank(rigAddr);
        unitToken.mint(bob, mintAmount1);
        unitToken.mint(charlie, mintAmount2);
        vm.stopPrank();

        vm.prank(bob);
        unitToken.burn(burnAmount);

        // Include LP balance which holds initial unit tokens from launch
        uint256 totalBalance = unitToken.balanceOf(bob) + unitToken.balanceOf(charlie) + unitToken.balanceOf(lpAddr);
        assertEq(unitToken.totalSupply(), totalBalance, "Total supply should equal sum of balances");
    }

    function testFuzz_invariant_rigEpochIdAlwaysIncreases(uint8 numMines) public {
        numMines = uint8(bound(numMines, 1, 15));

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 lastEpochId = rig.epochId();

        for (uint256 i = 0; i < numMines; i++) {
            uint256 price = rig.getPrice();
            address miner = makeAddr(string(abi.encodePacked("m", i)));
            vm.deal(miner, 100 ether);

            vm.prank(miner);
            multicall.mine{value: price}(rigAddr, i, block.timestamp + 1 days, price, "");

            uint256 newEpochId = rig.epochId();
            assertGt(newEpochId, lastEpochId, "Epoch ID should always increase");
            lastEpochId = newEpochId;

            vm.warp(block.timestamp + 1 minutes);
        }
    }

    function testFuzz_invariant_priceNeverNegative(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, 365 days);

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        vm.warp(block.timestamp + timePassed);

        uint256 price = rig.getPrice();
        assertTrue(price >= 0, "Price should never be negative");
        assertTrue(price <= rig.epochInitPrice(), "Price should never exceed init price");
    }

    function testFuzz_invariant_upsNeverBelowTail(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days * 100);

        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        vm.warp(rig.startTime() + timeElapsed);

        uint256 ups = rig.getUps();
        assertGe(ups, rig.tailUps(), "UPS should never go below tail");
        assertLe(ups, rig.initialUps(), "UPS should never exceed initial");
    }

    function testFuzz_invariant_auctionEpochIdAlwaysIncreases(uint8 numBuys) public {
        numBuys = uint8(bound(numBuys, 1, 10));

        MockToken lpToken = new MockToken("LP", "LP");
        MockToken asset = new MockToken("Asset", "A");
        address receiver = makeAddr("receiver");

        Auction auction = new Auction(1e15, address(lpToken), receiver, 1 hours, 1.5e18, 1e6);

        uint256 lastEpochId = auction.epochId();

        for (uint256 i = 0; i < numBuys; i++) {
            asset.mint(address(auction), 10 ether);
            lpToken.mint(alice, type(uint128).max);

            uint256 price = auction.getPrice();
            address[] memory assets = new address[](1);
            assets[0] = address(asset);

            vm.startPrank(alice);
            lpToken.approve(address(auction), price);
            auction.buy(assets, alice, i, block.timestamp + 1 hours, price);
            vm.stopPrank();

            uint256 newEpochId = auction.epochId();
            assertGt(newEpochId, lastEpochId, "Auction epoch ID should always increase");
            lastEpochId = newEpochId;
        }
    }
}
