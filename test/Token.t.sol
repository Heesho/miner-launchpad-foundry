// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Token, TokenFactory} from "../src/TokenFactory.sol";
import {Content, ContentFactory} from "../src/ContentFactory.sol";
import {Rewarder, RewarderFactory} from "../src/RewarderFactory.sol";
import {Core} from "../src/Core.sol";

contract TokenTest is Test {
    Deploy public deploy;
    MockUSDC public usdc;
    TokenFactory public tokenFactory;
    ContentFactory public contentFactory;
    RewarderFactory public rewarderFactory;
    Core public core;

    function setUp() public {
        deploy = new Deploy();
        deploy.run();

        usdc = deploy.usdc();
        tokenFactory = deploy.tokenFactory();
        contentFactory = deploy.contentFactory();
        rewarderFactory = deploy.rewarderFactory();
        core = deploy.core();
    }

    function test_Token_Constructor() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address quote = core.quote();
        address content = contentFactory.lastContent();
        address rewarder = rewarderFactory.lastRewarder();

        assertTrue(token.quote() == quote);
        assertTrue(token.content() == content);
        assertTrue(token.rewarder() == rewarder);

        assertTrue(token.quoteDecimals() == 6);

        assertTrue(token.maxSupply() == 1_000_000_000 * 1e18);
        assertTrue(token.totalDebtRaw() == 0);
    }

    function test_Token_Buy() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, 100e6);

        vm.prank(user1);
        usdc.approve(address(token), 100e6);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(100e6, 0, deadline, user1, address(0));
    }

    function testFuzz_Token_Buy(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        assertTrue(token.balanceOf(user1) == 0);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        assertTrue(token.balanceOf(user1) > 0);
    }

    function testFuzzRevert_Token_BuyRevertSlippage(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        vm.expectRevert("Token__Slippage()");
        token.buy(amount, type(uint256).max, deadline, user1, address(0));
    }

    function testRevert_Token_BuyZeroInput() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        vm.prank(user1);
        vm.expectRevert("Token__MinTradeSize()");
        token.buy(0, 0, block.timestamp + 3600, user1, address(0));
    }

    function testFuzzRevert_Token_BuyExpired(uint256 deadline) public {
        vm.warp(block.timestamp + 100 weeks);

        vm.assume(deadline > 0 && deadline < block.timestamp);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, 100e6);

        vm.prank(user1);
        usdc.approve(address(token), 100e6);

        vm.prank(user1);
        vm.expectRevert("Token__Expired()");
        token.buy(100e6, 0, deadline, user1, address(0));
    }

    function testFuzz_Token_BuyWithProvider(address provider, uint256 amount) public {
        vm.assume(provider != address(0));
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        assertTrue(usdc.balanceOf(provider) == 0);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, provider);

        assertTrue(usdc.balanceOf(provider) > 0);
    }

    function testFuzz_Token_Sell(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        uint256 tokenAmt = token.balanceOf(user1);

        vm.prank(user1);
        token.sell(tokenAmt, 0, deadline, user1, address(0));
    }

    function testFuzz_Token_SellWithProvider(address provider, uint256 amount) public {
        vm.assume(provider != address(0));
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        uint256 tokenAmt = token.balanceOf(user1);

        vm.prank(user1);
        token.sell(tokenAmt, 0, deadline, user1, provider);
    }

    function testFuzzRevert_Token_SellBelowTradeMin(uint256 amount, uint256 sellAmount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        vm.assume(sellAmount < 1000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.prank(user1);
        vm.expectRevert("Token__MinTradeSize()");
        token.sell(sellAmount, 0, deadline, user1, address(0));
    }

    function testRevertFuzz_Token_SellSlippage(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        uint256 tokenAmt = token.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert("Token__Slippage()");
        token.sell(tokenAmt, type(uint256).max, deadline, user1, address(0));
    }

    function testRevertFuzz_Token_SellExpired(uint256 deadline) public {
        vm.warp(block.timestamp + 100 weeks);
        vm.assume(deadline > 0 && deadline < block.timestamp);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, 100e6);

        vm.prank(user1);
        usdc.approve(address(token), 100e6);

        vm.prank(user1);
        token.buy(100e6, 0, block.timestamp + 10000, user1, address(0));

        uint256 tokenAmt = token.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert("Token__Expired()");
        token.sell(tokenAmt, 0, deadline, user1, address(0));
    }

    function testFuzz_Token_BorrowMax(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditAmt = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditAmt);
        vm.assertTrue(token.totalDebtRaw() == creditAmt);
    }

    function testFuzz_Token_Borrow(uint256 amount, uint256 creditAmt) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.assume(creditAmt > 0 && creditAmt <= creditMax);

        vm.prank(user1);
        token.borrow(user1, creditAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditAmt);
        vm.assertTrue(token.totalDebtRaw() == creditAmt);
    }

    function testFuzzRevert_Token_BorrowOverCredit(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditAmt = token.getAccountCredit(user1);

        vm.prank(user1);
        vm.expectRevert("Token__CreditExceeded()");
        token.borrow(user1, creditAmt + amount);

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);
    }

    function testFuzz_Token_RepayMax(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.prank(user1);
        usdc.approve(address(token), creditMax);

        vm.prank(user1);
        token.repay(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);
    }

    function testFuzz_Token_Repay(uint256 amount, uint256 repayAmt) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.assume(repayAmt > 0 && repayAmt <= creditMax);

        vm.prank(user1);
        usdc.approve(address(token), repayAmt);

        vm.prank(user1);
        token.repay(user1, repayAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax - repayAmt);
        vm.assertTrue(token.totalDebtRaw() == creditMax - repayAmt);
    }

    function testRevert_Token_RepayZeroAmount() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, 1000e6);

        vm.prank(user1);
        usdc.approve(address(token), 1000e6);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(1000e6, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.prank(user1);
        vm.expectRevert("Token__ZeroInput()");
        token.repay(user1, 0);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);
    }

    function testFuzz_Token_TransferMax(uint256 amount, uint256 repayAmt) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);
        address user2 = address(0x456);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.assume(repayAmt > 0 && repayAmt <= creditMax);

        vm.prank(user1);
        usdc.approve(address(token), repayAmt);

        vm.prank(user1);
        token.repay(user1, repayAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax - repayAmt);
        vm.assertTrue(token.totalDebtRaw() == creditMax - repayAmt);

        uint256 transferAmt = token.getAccountTransferrable(user1);

        vm.prank(user1);
        token.transfer(user2, transferAmt);

        vm.assertTrue(token.getAccountTransferrable(user1) == 0);
        vm.assertTrue(token.getAccountTransferrable(user2) == transferAmt);
    }

    function testFuzz_Token_Transfer(uint256 amount, uint256 repayAmt, uint256 transferAmt) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);
        address user2 = address(0x456);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.assume(repayAmt > 0 && repayAmt <= creditMax);

        vm.prank(user1);
        usdc.approve(address(token), repayAmt);

        vm.prank(user1);
        token.repay(user1, repayAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax - repayAmt);
        vm.assertTrue(token.totalDebtRaw() == creditMax - repayAmt);

        vm.assume(transferAmt > 0 && transferAmt <= token.getAccountTransferrable(user1));

        vm.prank(user1);
        token.transfer(user2, transferAmt);

        vm.assertTrue(token.getAccountTransferrable(user2) == transferAmt);
    }

    function testFuzzRevert_Token_TransferOverTransferable(uint256 amount, uint256 repayAmt, uint256 transferAmt)
        public
    {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);
        address user2 = address(0x456);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(token), amount);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(amount, 0, deadline, user1, address(0));

        vm.assertTrue(token.account_DebtRaw(user1) == 0);
        vm.assertTrue(token.totalDebtRaw() == 0);

        uint256 creditMax = token.getAccountCredit(user1);

        vm.prank(user1);
        token.borrow(user1, creditMax);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax);
        vm.assertTrue(token.totalDebtRaw() == creditMax);

        vm.assume(repayAmt > 0 && repayAmt <= creditMax);

        vm.prank(user1);
        usdc.approve(address(token), repayAmt);

        vm.prank(user1);
        token.repay(user1, repayAmt);

        vm.assertTrue(token.account_DebtRaw(user1) == creditMax - repayAmt);
        vm.assertTrue(token.totalDebtRaw() == creditMax - repayAmt);

        vm.assume(transferAmt > token.getAccountTransferrable(user1));

        vm.prank(user1);
        vm.expectRevert("Token__CollateralLocked()");
        token.transfer(user2, transferAmt);
    }

    function testFuzz_Token_Heal(uint256 buyAmt, uint256 healAmt) public {
        vm.assume(buyAmt > 1000 && buyAmt < 1_000_000_000_000_000_000);
        vm.assume(healAmt > 0 && healAmt < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, buyAmt);

        vm.prank(user1);
        usdc.approve(address(token), buyAmt);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(buyAmt, 0, deadline, user1, address(0));

        usdc.mint(user1, healAmt);

        vm.prank(user1);
        usdc.approve(address(token), healAmt);

        vm.prank(user1);
        token.heal(healAmt);
    }

    function testFuzz_Token_Burn(uint256 buyAmt, uint256 burnAmt) public {
        vm.assume(buyAmt > 1000 && buyAmt < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, buyAmt);

        vm.prank(user1);
        usdc.approve(address(token), buyAmt);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(buyAmt, 0, deadline, user1, address(0));

        vm.assume(burnAmt > 0 && burnAmt < token.balanceOf(user1));

        vm.prank(user1);
        token.burn(burnAmt);
    }

    function testFuzz_Token_Prices(uint256 buyAmt, uint256 burnAmt) public {
        vm.assume(buyAmt > 1000 && buyAmt < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());

        address user1 = address(0x123);

        usdc.mint(user1, buyAmt);

        vm.prank(user1);
        usdc.approve(address(token), buyAmt);

        uint256 deadline = block.timestamp + 10000;
        vm.prank(user1);
        token.buy(buyAmt, 0, deadline, user1, address(0));

        vm.assume(burnAmt > 0 && burnAmt < token.balanceOf(user1));

        vm.prank(user1);
        token.burn(burnAmt);

        uint256 marketPrice = token.getMarketPrice();
        uint256 floorPrice = token.getFloorPrice();

        vm.assertTrue(marketPrice >= floorPrice);
        vm.assertTrue(marketPrice > 0);
        vm.assertTrue(floorPrice > 0);
    }
}
