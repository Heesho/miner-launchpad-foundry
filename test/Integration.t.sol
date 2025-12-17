// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {Token, TokenFactory} from "../src/TokenFactory.sol";
import {Content, ContentFactory} from "../src/ContentFactory.sol";
import {Rewarder, RewarderFactory} from "../src/RewarderFactory.sol";
import {Core} from "../src/Core.sol";
import {Router} from "../src/Router.sol";
import {Multicall} from "../src/Multicall.sol";

contract IntegrationTest is Test {
    Deploy public deploy;
    MockUSDC public usdc;
    TokenFactory public tokenFactory;
    ContentFactory public contentFactory;
    RewarderFactory public rewarderFactory;
    Core public core;
    Router public router;
    Multicall public multicall;

    function setUp() public {
        deploy = new Deploy();
        deploy.run();

        usdc = deploy.usdc();
        tokenFactory = deploy.tokenFactory();
        contentFactory = deploy.contentFactory();
        rewarderFactory = deploy.rewarderFactory();
        core = deploy.core();
        router = deploy.router();
        multicall = deploy.multicall();
    }

    function test_Integration(
        uint256 createQuoteAmount,
        uint256 user1BuyAmount1,
        uint256 user1BuyAmount2,
        uint256 user2BuyAmount1,
        uint256 user1SellAmount1,
        uint256 user1BuyAmount4,
        uint256 user1Borrow1,
        uint256 user1Transfer1,
        uint256 user1Repay1,
        uint256 user1Transfer2,
        uint256 user3BuyAmount1,
        uint256 user1Heal1,
        uint256 user1Heal2,
        uint256 user1Burn1
    ) public {
        address user1 = address(0x101);
        address user2 = address(0x102);
        address user3 = address(0x103);
        address user4 = address(0x104);

        address owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address multisig = address(0x105);
        address treasury = address(0x106);

        // user1 creates wft
        vm.assume(createQuoteAmount > 1000 && createQuoteAmount < 10_000_000_000_000);
        usdc.mint(user1, createQuoteAmount);
        vm.prank(user1);
        usdc.approve(address(router), createQuoteAmount);
        vm.prank(user1);
        Token wft1 = Token(router.createToken("Test1", "TEST1", "ipfs://test1", false, createQuoteAmount));
        Multicall.TokenData memory tokenData = multicall.getTokenData(address(wft1), user1);
        Multicall.ContentData memory contentData = multicall.getContentData(address(wft1), 1);

        // user1 buys wft1
        vm.assume(user1BuyAmount1 > 1000 && user1BuyAmount1 < 10_000_000_000_000);
        (uint256 tokenAmtOut, uint256 slippage, uint256 minTokenAmtOut, uint256 autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), 0, 9800);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), user1BuyAmount1, 9800);
        console.log("quoteRawIn", user1BuyAmount1);
        console.log("tokenAmtOut", tokenAmtOut);
        console.log("slippage", slippage);
        console.log("minTokenAmtOut", minTokenAmtOut);
        console.log("autoMinTokenAmtOut", autoMinTokenAmtOut);
        usdc.mint(user1, user1BuyAmount1);
        vm.prank(user1);
        usdc.approve(address(router), user1BuyAmount1);
        vm.prank(user1);
        router.buy(address(wft1), address(0), user1BuyAmount1, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 buys wft again
        vm.assume(user1BuyAmount2 > 1000 && user1BuyAmount2 < 10_000_000_000_000);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), user1BuyAmount2, 9800);
        usdc.mint(user1, user1BuyAmount2);
        vm.prank(user1);
        usdc.approve(address(router), user1BuyAmount2);
        vm.prank(user1);
        router.buy(address(wft1), address(0), user1BuyAmount2, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 sells all wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user1);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user1);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 1000e6, 9000);
        usdc.mint(user1, 1000e6);
        vm.prank(user1);
        usdc.approve(address(router), 1000e6);
        vm.prank(user1);
        router.buy(address(wft1), address(0), 1000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 buys wft1
        vm.assume(user2BuyAmount1 > 1000 && user2BuyAmount1 < 10_000_000_000_000);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), user2BuyAmount1, 6000);
        usdc.mint(user2, user2BuyAmount1);
        vm.prank(user2);
        usdc.approve(address(router), user2BuyAmount1);
        vm.prank(user2);
        router.buy(address(wft1), address(0), user2BuyAmount1, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user1 sells some wft1
        tokenData = multicall.getTokenData(address(wft1), user1);
        vm.assume(user1SellAmount1 > 1000 && user1SellAmount1 < tokenData.accountTokenBalance);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), user1SellAmount1, 9800);
        vm.prank(user1);
        wft1.approve(address(router), user1SellAmount1);
        vm.prank(user1);
        router.sell(address(wft1), address(0), user1SellAmount1, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 sells all wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user1);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user1);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user2);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user2);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user2);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user3 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user3);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user3);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user3);
        vm.expectRevert("Token__MinTradeSize()");
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user3);

        // user1 buys wft1
        vm.assume(user1BuyAmount4 > 1000 && user1BuyAmount4 < 10_000_000_000_000);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), user1BuyAmount4, 9800);
        usdc.mint(user1, user1BuyAmount4);
        vm.prank(user1);
        usdc.approve(address(router), user1BuyAmount4);
        vm.prank(user1);
        router.buy(address(wft1), address(0), user1BuyAmount4, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 borrows against wft1
        uint256 credit = wft1.getAccountCredit(user1);
        vm.assume(user1Borrow1 > 0 && user1Borrow1 <= credit);
        vm.prank(user1);
        wft1.borrow(user1, user1Borrow1);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 transfers some wft1 to user2
        uint256 maxTransferrable = wft1.getAccountTransferrable(user1);
        vm.assume(user1Transfer1 > 0 && user1Transfer1 <= maxTransferrable);
        vm.prank(user1);
        wft1.transfer(user2, user1Transfer1);
        tokenData = multicall.getTokenData(address(wft1), user1);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user 1 repays some debt
        uint256 debt = wft1.account_DebtRaw(user1);
        vm.assume(user1Repay1 > 0 && user1Repay1 <= debt);
        vm.prank(user1);
        usdc.approve(address(wft1), user1Repay1);
        vm.prank(user1);
        wft1.repay(user1, user1Repay1);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 transfers some wft1 to user2
        maxTransferrable = wft1.getAccountTransferrable(user1);
        vm.assume(user1Transfer2 > 0 && user1Transfer2 <= maxTransferrable);
        vm.prank(user1);
        wft1.transfer(user2, user1Transfer2);
        tokenData = multicall.getTokenData(address(wft1), user1);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user 1 repays all debt
        debt = wft1.account_DebtRaw(user1);
        if (debt > 0) {
            vm.prank(user1);
            usdc.approve(address(wft1), debt);
            vm.prank(user1);
            wft1.repay(user1, debt);
            tokenData = multicall.getTokenData(address(wft1), user1);
        }

        // user1 transfers all wft1 to user2
        uint256 wft1Balance = wft1.balanceOf(user1);
        vm.prank(user1);
        wft1.transfer(user2, wft1Balance);
        tokenData = multicall.getTokenData(address(wft1), user1);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user2 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user2);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user2);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user2);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user1 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 10000e6, 9800);
        usdc.mint(user1, 10000e6);
        vm.prank(user1);
        usdc.approve(address(router), 10000e6);
        vm.prank(user1);
        router.buy(address(wft1), address(0), 10000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 10000e6, 9800);
        usdc.mint(user2, 10000e6);
        vm.prank(user2);
        usdc.approve(address(router), 10000e6);
        vm.prank(user2);
        router.buy(address(wft1), address(0), 10000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user3 buys wft1
        vm.assume(user3BuyAmount1 > 1000 && user3BuyAmount1 < 10_000_000_000_000);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.buyQuoteIn(address(wft1), user3BuyAmount1, 9800);
        usdc.mint(user3, user3BuyAmount1);
        vm.prank(user3);
        usdc.approve(address(router), user3BuyAmount1);
        vm.prank(user3);
        router.buy(address(wft1), address(0), user3BuyAmount1, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user3);

        // user1 heals with usdc
        vm.assume(user1Heal1 > 0 && user1Heal1 < 10_000_000_000_000);
        usdc.mint(user1, user1Heal1);
        vm.prank(user1);
        usdc.approve(address(wft1), user1Heal1);
        vm.prank(user1);
        wft1.heal(user1Heal1);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user3 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user3);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user3);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user3);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user3);

        // user1 heals with usdc
        vm.assume(user1Heal2 > 0 && user1Heal2 < 10_000_000_000_000);
        usdc.mint(user1, user1Heal2);
        vm.prank(user1);
        usdc.approve(address(wft1), user1Heal2);
        vm.prank(user1);
        wft1.heal(user1Heal2);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 burns wft1
        uint256 balanceWft1 = wft1.balanceOf(user1);
        vm.assume(user1Burn1 > 0 && user1Burn1 <= balanceWft1);
        vm.prank(user1);
        wft1.burn(user1Burn1);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // set core treasury to treasury
        vm.prank(owner);
        core.setTreasury(treasury);
        assertEq(core.treasury(), treasury);

        // transfer ownership to multisig
        vm.prank(owner);
        core.transferOwnership(multisig);
        assertEq(core.owner(), multisig);

        // user1 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 10000e6, 9800);
        usdc.mint(user1, 10000e6);
        vm.prank(user1);
        usdc.approve(address(router), 10000e6);
        vm.prank(user1);
        router.buy(address(wft1), user2, 10000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 10000e6, 9800);
        usdc.mint(user2, 10000e6);
        vm.prank(user2);
        usdc.approve(address(router), 10000e6);
        vm.prank(user2);
        router.buy(address(wft1), user3, 10000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user3 buys wft1
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) = multicall.buyQuoteIn(address(wft1), 10000e6, 9800);
        usdc.mint(user3, 10000e6);
        vm.prank(user3);
        usdc.approve(address(router), 10000e6);
        vm.prank(user3);
        router.buy(address(wft1), user1, 10000e6, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user3);

        // user1 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user1);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user1);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user1);
        router.sell(address(wft1), user2, tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user2);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user2);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user2);
        router.sell(address(wft1), user3, tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user3 sells all wft1
        tokenData = multicall.getTokenData(address(wft1), user3);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(user3);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(user3);
        router.sell(address(wft1), treasury, tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), user3);

        // treasury sells all wft1
        tokenData = multicall.getTokenData(address(wft1), treasury);
        (tokenAmtOut, slippage, minTokenAmtOut, autoMinTokenAmtOut) =
            multicall.sellTokenIn(address(wft1), tokenData.accountTokenBalance, 9800);
        vm.prank(treasury);
        wft1.approve(address(router), tokenData.accountTokenBalance);
        vm.prank(treasury);
        router.sell(address(wft1), address(0), tokenData.accountTokenBalance, 0, 0);
        tokenData = multicall.getTokenData(address(wft1), treasury);

        // user1 creates content
        vm.prank(user1);
        router.createContent(address(wft1), "https://ipfs.com/1");
        tokenData = multicall.getTokenData(address(wft1), user1);
        contentData = multicall.getContentData(address(wft1), 1);
        vm.assertTrue(contentData.nextPrice == 1e6);

        // user2 collects content
        contentData = multicall.getContentData(address(wft1), 1);
        uint256 contentPrice = contentData.nextPrice;
        usdc.mint(user2, contentPrice);
        vm.prank(user2);
        usdc.approve(address(router), contentPrice);
        vm.prank(user2);
        router.collectContent(address(wft1), 1, contentPrice);
        tokenData = multicall.getTokenData(address(wft1), user2);
        vm.warp(block.timestamp + 1 days);

        // user3 collects content
        contentData = multicall.getContentData(address(wft1), 1);
        contentPrice = contentData.nextPrice;
        usdc.mint(user3, contentPrice);
        vm.prank(user3);
        usdc.approve(address(router), contentPrice);
        vm.prank(user3);
        router.collectContent(address(wft1), 1, contentPrice);
        tokenData = multicall.getTokenData(address(wft1), user3);
        vm.warp(block.timestamp + 1 days);

        //user1 collects content
        contentData = multicall.getContentData(address(wft1), 1);
        contentPrice = contentData.nextPrice;
        usdc.mint(user1, contentPrice);
        vm.prank(user1);
        usdc.approve(address(router), contentPrice);
        vm.prank(user1);
        router.collectContent(address(wft1), 1, contentPrice);
        tokenData = multicall.getTokenData(address(wft1), user1);
        vm.warp(block.timestamp + 1 days);

        // user1 claims rewards
        vm.prank(user1);
        router.getContentReward(address(wft1));
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user1 claims rewards
        vm.prank(user1);
        router.getContentReward(address(wft1));
        tokenData = multicall.getTokenData(address(wft1), user1);

        // user2 claims rewards
        vm.prank(user2);
        router.getContentReward(address(wft1));
        tokenData = multicall.getTokenData(address(wft1), user2);

        // user3 claims rewards
        vm.prank(user3);
        router.getContentReward(address(wft1));
        tokenData = multicall.getTokenData(address(wft1), user3);

        // user4 notifies reward amount
        vm.warp(block.timestamp + 7 days);
        usdc.mint(user4, 10000e6);
        vm.prank(user4);
        usdc.approve(address(router), 10000e6);
        vm.prank(user4);
        router.notifyContentRewardAmount(address(wft1), address(usdc), 10000e6);
        tokenData = multicall.getTokenData(address(wft1), user4);

        // owner withdraws stuck tokens
        usdc.mint(address(router), 1e6);
        vm.prank(owner);
        router.withdrawStuckTokens(address(usdc), multisig);
    }
}
