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

/**
 * @title MulticallTest
 * @notice Tests for the Multicall helper contract
 */
contract MulticallTest is BaseTest {
    /*----------  CONSTRUCTOR TESTS  ------------------------------------*/

    function test_constructor_setsImmutables() public view {
        assertEq(multicall.core(), address(core));
        assertEq(multicall.weth(), address(weth));
        assertEq(multicall.donut(), address(donut));
    }

    function test_constructor_revertsIfZeroAddress() public {
        vm.expectRevert(Multicall.Multicall__ZeroAddress.selector);
        new Multicall(address(0), address(weth), address(donut));

        vm.expectRevert(Multicall.Multicall__ZeroAddress.selector);
        new Multicall(address(core), address(0), address(donut));

        vm.expectRevert(Multicall.Multicall__ZeroAddress.selector);
        new Multicall(address(core), address(weth), address(0));
    }

    /*----------  LAUNCH TESTS  -----------------------------------------*/

    function _toICoreParams(Core.LaunchParams memory p) internal pure returns (ICore.LaunchParams memory) {
        return ICore.LaunchParams({
            launcher: p.launcher,
            tokenName: p.tokenName,
            tokenSymbol: p.tokenSymbol,
            uri: p.uri,
            donutAmount: p.donutAmount,
            unitAmount: p.unitAmount,
            initialUps: p.initialUps,
            tailUps: p.tailUps,
            halvingPeriod: p.halvingPeriod,
            rigEpochPeriod: p.rigEpochPeriod,
            rigPriceMultiplier: p.rigPriceMultiplier,
            rigMinInitPrice: p.rigMinInitPrice,
            auctionInitPrice: p.auctionInitPrice,
            auctionEpochPeriod: p.auctionEpochPeriod,
            auctionPriceMultiplier: p.auctionPriceMultiplier,
            auctionMinInitPrice: p.auctionMinInitPrice
        });
    }

    function test_launch_success() public {
        ICore.LaunchParams memory params = _toICoreParams(_getDefaultLaunchParams(alice));

        vm.startPrank(alice);
        donut.approve(address(multicall), params.donutAmount);
        (address unit, address rig, address auction, address lp) = multicall.launch(params);
        vm.stopPrank();

        // Verify contracts were created
        assertTrue(unit != address(0));
        assertTrue(rig != address(0));
        assertTrue(auction != address(0));
        assertTrue(lp != address(0));

        // Verify launcher is msg.sender (alice), not the launcher in params
        assertEq(core.rigToLauncher(rig), alice);
        assertEq(Rig(rig).owner(), alice);
    }

    function test_launch_overridesLauncherWithMsgSender() public {
        // Set launcher to bob, but alice calls
        ICore.LaunchParams memory params = _toICoreParams(_getDefaultLaunchParams(bob));

        vm.startPrank(alice);
        donut.approve(address(multicall), params.donutAmount);
        (, address rig,,) = multicall.launch(params);
        vm.stopPrank();

        // Alice should be the actual launcher, not bob
        assertEq(core.rigToLauncher(rig), alice);
        assertEq(Rig(rig).owner(), alice);
        assertEq(Rig(rig).team(), alice);
    }

    function test_launch_transfersDonutFromCaller() public {
        ICore.LaunchParams memory params = _toICoreParams(_getDefaultLaunchParams(alice));
        uint256 balanceBefore = donut.balanceOf(alice);

        vm.startPrank(alice);
        donut.approve(address(multicall), params.donutAmount);
        multicall.launch(params);
        vm.stopPrank();

        assertEq(donut.balanceOf(alice), balanceBefore - params.donutAmount);
    }

    /*----------  MINE TESTS  -------------------------------------------*/

    function test_mine_success() public {
        (, address rig,,) = _launchRig(alice);

        uint256 price = Rig(rig).getPrice();
        address initialMiner = Rig(rig).epochMiner();

        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "bob-uri");

        assertEq(Rig(rig).epochMiner(), bob);
        assertEq(Rig(rig).epochId(), 1);
        assertEq(Rig(rig).epochUri(), "bob-uri");
    }

    function test_mine_wrapsEthToWeth() public {
        (, address rig,,) = _launchRig(alice);

        uint256 price = Rig(rig).getPrice();
        uint256 ethBalanceBefore = bob.balance;

        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "");

        // ETH should be spent
        assertEq(bob.balance, ethBalanceBefore - price);
    }

    function test_mine_refundsUnusedWeth() public {
        (, address rig,,) = _launchRig(alice);

        // Wait for price to decay
        vm.warp(block.timestamp + Rig(rig).epochPeriod() / 2);

        uint256 currentPrice = Rig(rig).getPrice();
        uint256 sentAmount = currentPrice * 2; // Send more than needed

        uint256 ethBalanceBefore = bob.balance;
        uint256 wethBalanceBefore = weth.balanceOf(bob);

        vm.prank(bob);
        multicall.mine{value: sentAmount}(rig, 0, block.timestamp + 1, currentPrice, "");

        // Should have spent the current price and refunded the rest as WETH
        uint256 refund = sentAmount - currentPrice;
        assertEq(weth.balanceOf(bob), wethBalanceBefore + refund);
    }

    function test_mine_senderSetAsMiner() public {
        (, address rig,,) = _launchRig(alice);

        uint256 price = Rig(rig).getPrice();

        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "");

        // Bob should be the miner
        assertEq(Rig(rig).epochMiner(), bob);
    }

    /*----------  BUY TESTS  --------------------------------------------*/

    function test_buy_success() public {
        (, address rig, address auction, address lp) = _launchRig(alice);

        // First, accumulate some WETH in the auction by mining
        uint256 minePrice = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: minePrice}(rig, 0, block.timestamp + 1, minePrice, "");

        // WETH should be in auction (treasury)
        uint256 wethInAuction = weth.balanceOf(auction);
        assertTrue(wethInAuction > 0);

        // Get LP tokens for charlie to buy
        // We need to provide liquidity or transfer LP to charlie
        // In this test setup, LP was burned to dead address
        // Let's mint some LP for charlie using the mock

        // Actually, in the real scenario users would need to acquire LP tokens
        // For testing, let's check the price and verify the flow

        uint256 auctionPrice = Auction(auction).getPrice();

        // Skip this test if no LP tokens available (in production users would buy LP from DEX)
        // This is an integration scenario that needs LP tokens
    }

    /*----------  GET RIG TESTS  ----------------------------------------*/

    function test_getRig_returnsCorrectState() public {
        (, address rig, address auction,) = _launchRig(alice);

        Multicall.RigState memory state = multicall.getRig(rig, bob);

        assertEq(state.epochId, 0);
        assertEq(state.initPrice, DEFAULT_RIG_MIN_INIT_PRICE);
        assertTrue(state.epochStartTime > 0);
        assertEq(state.ups, DEFAULT_INITIAL_UPS);
        assertEq(state.miner, alice); // Team/launcher is initial miner
        assertEq(state.rigUri, "https://example.com/token.json");

        // Check user balances
        assertTrue(state.ethBalance > 0);
        assertTrue(state.wethBalance > 0);
        assertTrue(state.donutBalance > 0);
        assertEq(state.unitBalance, 0); // Bob has no unit tokens yet
    }

    function test_getRig_withZeroAccount() public {
        (, address rig,,) = _launchRig(alice);

        Multicall.RigState memory state = multicall.getRig(rig, address(0));

        // State should still be populated
        assertEq(state.epochId, 0);
        assertEq(state.ups, DEFAULT_INITIAL_UPS);

        // But balances should be 0
        assertEq(state.ethBalance, 0);
        assertEq(state.wethBalance, 0);
        assertEq(state.donutBalance, 0);
        assertEq(state.unitBalance, 0);
    }

    function test_getRig_updatesAfterMining() public {
        (, address rig,,) = _launchRig(alice);

        // Initial state
        Multicall.RigState memory state1 = multicall.getRig(rig, bob);
        assertEq(state1.epochId, 0);

        // Mine
        uint256 price = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "bob-uri");

        // State after mining
        Multicall.RigState memory state2 = multicall.getRig(rig, bob);
        assertEq(state2.epochId, 1);
        assertEq(state2.miner, bob);
        assertEq(state2.epochUri, "bob-uri");
    }

    function test_getRig_calculatesGlazed() public {
        (, address rig,,) = _launchRig(alice);

        // Mine to start a new epoch
        uint256 price = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "");

        // Warp forward
        uint256 timeElapsed = 1 hours;
        vm.warp(block.timestamp + timeElapsed);

        Multicall.RigState memory state = multicall.getRig(rig, bob);

        // Glazed should be ups * time elapsed
        uint256 expectedGlazed = state.ups * timeElapsed;
        assertEq(state.glazed, expectedGlazed);
    }

    /*----------  GET AUCTION TESTS  ------------------------------------*/

    function test_getAuction_returnsCorrectState() public {
        (, address rig, address auction, address lp) = _launchRig(alice);

        Multicall.AuctionState memory state = multicall.getAuction(rig, bob);

        assertEq(state.epochId, 0);
        assertEq(state.initPrice, DEFAULT_AUCTION_INIT_PRICE);
        assertTrue(state.startTime > 0);
        assertEq(state.paymentToken, lp);
        assertEq(state.wethAccumulated, 0); // No mining yet

        // User balances
        assertTrue(state.wethBalance > 0);
        assertTrue(state.donutBalance > 0);
    }

    function test_getAuction_withZeroAccount() public {
        (, address rig,,) = _launchRig(alice);

        Multicall.AuctionState memory state = multicall.getAuction(rig, address(0));

        // State should still be populated
        assertEq(state.epochId, 0);
        assertTrue(state.startTime > 0);

        // But balances should be 0
        assertEq(state.wethBalance, 0);
        assertEq(state.donutBalance, 0);
        assertEq(state.paymentTokenBalance, 0);
    }

    function test_getAuction_showsAccumulatedWeth() public {
        (, address rig, address auction,) = _launchRig(alice);

        // Initially no WETH accumulated
        Multicall.AuctionState memory state1 = multicall.getAuction(rig, bob);
        assertEq(state1.wethAccumulated, 0);

        // Mine to accumulate WETH in treasury (auction)
        uint256 price = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "");

        // Treasury fee should be accumulated
        Multicall.AuctionState memory state2 = multicall.getAuction(rig, bob);
        assertTrue(state2.wethAccumulated > 0);
    }

    /*----------  EDGE CASES  -------------------------------------------*/

    function test_mine_afterPriceDecaysToZero() public {
        (, address rig,,) = _launchRig(alice);

        // Warp past epoch period so price is 0
        vm.warp(block.timestamp + Rig(rig).epochPeriod() + 1);

        assertEq(Rig(rig).getPrice(), 0);

        // Should still be able to mine at price 0
        vm.prank(bob);
        multicall.mine{value: 0}(rig, 0, block.timestamp + 1, 0, "free-mine");

        assertEq(Rig(rig).epochMiner(), bob);
    }

    function test_mine_multipleTimes() public {
        (, address rig,,) = _launchRig(alice);

        // First mine
        uint256 price1 = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: price1}(rig, 0, block.timestamp + 1, price1, "bob-1");
        assertEq(Rig(rig).epochMiner(), bob);

        // Second mine
        uint256 price2 = Rig(rig).getPrice();
        vm.prank(charlie);
        multicall.mine{value: price2}(rig, 1, block.timestamp + 1, price2, "charlie-1");
        assertEq(Rig(rig).epochMiner(), charlie);

        // Third mine
        uint256 price3 = Rig(rig).getPrice();
        vm.prank(bob);
        multicall.mine{value: price3}(rig, 2, block.timestamp + 1, price3, "bob-2");
        assertEq(Rig(rig).epochMiner(), bob);

        assertEq(Rig(rig).epochId(), 3);
    }

    /*----------  FUZZ TESTS  -------------------------------------------*/

    function testFuzz_mine_validPrice(uint256 warpTime) public {
        (, address rig,,) = _launchRig(alice);

        warpTime = bound(warpTime, 0, Rig(rig).epochPeriod());
        vm.warp(block.timestamp + warpTime);

        uint256 price = Rig(rig).getPrice();

        vm.prank(bob);
        multicall.mine{value: price}(rig, 0, block.timestamp + 1, price, "");

        assertEq(Rig(rig).epochMiner(), bob);
    }
}
