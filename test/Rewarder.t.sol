// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {Content, ContentFactory} from "../src/ContentFactory.sol";
import {Token, TokenFactory} from "../src/TokenFactory.sol";
import {Rewarder, RewarderFactory} from "../src/RewarderFactory.sol";
import {Core} from "../src/Core.sol";

contract RewarderTest is Test {
    Deploy public deploy;
    MockUSDC public usdc;
    MockToken public mockToken;
    RewarderFactory public rewarderFactory;
    ContentFactory public contentFactory;
    TokenFactory public tokenFactory;
    Core public core;

    function setUp() public {
        deploy = new Deploy();
        deploy.run();

        mockToken = new MockToken();
        usdc = deploy.usdc();
        rewarderFactory = deploy.rewarderFactory();
        contentFactory = deploy.contentFactory();
        tokenFactory = deploy.tokenFactory();
        core = deploy.core();
    }

    function test_Rewarder_Constructor() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Token token = Token(tokenFactory.lastToken());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        assertTrue(rewarder.content() == address(content));
        assertTrue(rewarder.getRewardTokens().length == 2);
        assertTrue(rewarder.totalSupply() == 0);
        assertTrue(rewarder.DURATION() == 7 days);
        assertTrue(rewarder.getRewardTokens()[0] == address(usdc));
        assertTrue(rewarder.getRewardTokens()[1] == address(token));
        assertTrue(rewarder.token_IsReward(address(usdc)) == true);
        assertTrue(rewarder.token_IsReward(address(token)) == true);
    }

    function testRevert_Rewarder_AddRewardToken() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());
        Content content = Content(contentFactory.lastContent());

        vm.expectRevert("Rewarder__NotContent()");
        rewarder.addReward(address(mockToken));

        assertTrue(rewarder.token_IsReward(address(mockToken)) == false);
        assertTrue(rewarder.getRewardTokens().length == 2);

        vm.prank(address(content));
        vm.expectRevert("Rewarder__RewardTokenAlreadyAdded()");
        rewarder.addReward(address(usdc));

        assertTrue(rewarder.getRewardTokens().length == 2);
    }

    function test_Rewarder_AddRewardToken() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());
        Content content = Content(contentFactory.lastContent());

        vm.prank(address(content));
        rewarder.addReward(address(mockToken));

        assertTrue(rewarder.getRewardTokens().length == 3);
        assertTrue(rewarder.getRewardTokens()[2] == address(mockToken));
        assertTrue(rewarder.token_IsReward(address(mockToken)) == true);
    }

    function test_Rewarder_GetRewardNoBalance() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        rewarder.getReward(address(0x123));
        assertTrue(usdc.balanceOf(address(0x123)) == 0);
        assertTrue(token.balanceOf(address(0x123)) == 0);
    }

    function test_Rewarder_NotifyRewardAmountLessThanDuration() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x123);

        usdc.mint(user1, 100);
        vm.prank(user1);
        usdc.approve(address(rewarder), 100);

        vm.prank(user1);
        rewarder.notifyRewardAmount(address(usdc), 100);

        (uint256 periodFinish, uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardPerTokenStored) =
            rewarder.token_RewardData(address(usdc));

        assertTrue(periodFinish > 0);
        assertTrue(rewardRate > 0);
        assertTrue(lastUpdateTime > 0);
        assertTrue(rewardPerTokenStored == 0);
    }

    function testRevert_Rewarder_NotifyRewardAmountNotRewardToken() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x123);

        usdc.mint(user1, 100);
        usdc.approve(address(rewarder), 100);

        vm.prank(address(core));
        vm.expectRevert("Rewarder__NotRewardToken()");
        rewarder.notifyRewardAmount(address(mockToken), 1e18);

        (uint256 periodFinish, uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardPerTokenStored) =
            rewarder.token_RewardData(address(usdc));

        assertTrue(periodFinish == 0);
        assertTrue(rewardRate == 0);
        assertTrue(lastUpdateTime == 0);
        assertTrue(rewardPerTokenStored == 0);
    }

    function testRevert_Rewarder_NotifyRewardAmountLessThanLeft() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x123);

        assertTrue(rewarder.left(address(usdc)) == 0);

        usdc.mint(user1, 10e6);

        vm.prank(user1);
        usdc.approve(address(rewarder), 10e6);

        vm.prank(user1);
        rewarder.notifyRewardAmount(address(usdc), 10e6);

        assertTrue(rewarder.left(address(usdc)) > 0);

        usdc.mint(user1, 5e6);

        vm.prank(user1);
        usdc.approve(address(rewarder), 5e6);

        vm.prank(user1);
        vm.expectRevert("Rewarder__RewardSmallerThanLeft()");
        rewarder.notifyRewardAmount(address(usdc), 5e6);
    }

    function test_Rewarder_NotifyRewardAmountZeroTotalSupply() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x123);

        usdc.mint(user1, 10e6);

        vm.prank(user1);
        usdc.approve(address(rewarder), 10e6);

        vm.prank(user1);
        rewarder.notifyRewardAmount(address(usdc), 10e6);

        (uint256 periodFinish, uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardPerTokenStored) =
            rewarder.token_RewardData(address(usdc));

        assertTrue(periodFinish > 0);
        assertTrue(rewardRate > 0);
        assertTrue(lastUpdateTime > 0);
        assertTrue(rewardPerTokenStored == 0);
    }

    function testFuzz_Rewarder_NotifyRewardAmount(uint256 amount) public {
        vm.assume(amount > 604800 && amount < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        vm.prank(address(content));
        rewarder.deposit(address(0x456), 1e6);

        vm.prank(address(content));
        rewarder.deposit(address(0x789), 1e6);

        console.log("0x456 balance of rewarder", rewarder.account_Balance(address(0x456)));
        console.log("total supply of rewarder", rewarder.totalSupply());

        address user1 = address(0x123);

        usdc.mint(user1, amount);

        vm.prank(user1);
        usdc.approve(address(rewarder), amount);

        vm.prank(user1);
        rewarder.notifyRewardAmount(address(usdc), amount);

        (uint256 periodFinish, uint256 rewardRate, uint256 lastUpdateTime, uint256 rewardPerTokenStored) =
            rewarder.token_RewardData(address(usdc));

        assertTrue(periodFinish > 0);
        assertTrue(rewardRate > 0);
        assertTrue(lastUpdateTime > 0);
        assertTrue(rewardPerTokenStored == 0);

        vm.warp(block.timestamp + 3600);

        vm.prank(address(content));
        rewarder.withdraw(address(0x789), 1e6);

        (periodFinish, rewardRate, lastUpdateTime, rewardPerTokenStored) = rewarder.token_RewardData(address(usdc));

        assertTrue(periodFinish > 0);
        assertTrue(rewardRate > 0);
        assertTrue(lastUpdateTime > 0);
        assertTrue(rewardPerTokenStored > 0);
    }

    function testRevert_Rewarder_Deposit() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);

        vm.prank(address(content));
        vm.expectRevert("Rewarder__ZeroAmount()");
        rewarder.deposit(address(0x123), 0);

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);

        vm.prank(address(0x123));
        vm.expectRevert("Rewarder__NotContent()");
        rewarder.deposit(address(0x123), 1e6);

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);
    }

    function testFuzz_Rewarder_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);

        vm.prank(address(content));
        rewarder.deposit(address(0x123), amount);

        assertTrue(rewarder.account_Balance(address(0x123)) == amount);
        assertTrue(rewarder.totalSupply() == amount);
    }

    function testFuzz_Rewarder_Withdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);

        vm.prank(address(content));
        rewarder.deposit(address(0x123), amount);

        assertTrue(rewarder.account_Balance(address(0x123)) == amount);
        assertTrue(rewarder.totalSupply() == amount);

        vm.prank(address(content));
        rewarder.withdraw(address(0x123), amount);

        assertTrue(rewarder.account_Balance(address(0x123)) == 0);
        assertTrue(rewarder.totalSupply() == 0);
    }

    function testFuzz_Rewarder_GetReward(uint256 amount) public {
        vm.assume(amount > 604800 && amount < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x456);
        address user2 = address(0x789);
        address user3 = address(0x101);

        vm.prank(address(content));
        rewarder.deposit(user1, 1e6);

        vm.prank(address(content));
        rewarder.deposit(user2, 1e6);

        usdc.mint(address(content), amount);

        vm.prank(address(content));
        usdc.approve(address(rewarder), amount);

        vm.prank(address(content));
        rewarder.notifyRewardAmount(address(usdc), amount);

        vm.warp(block.timestamp + 3600);

        assertTrue(usdc.balanceOf(user1) == 0);
        assertTrue(rewarder.earned(user1, address(usdc)) > 0);

        vm.prank(user1);
        rewarder.getReward(user1);

        assertTrue(usdc.balanceOf(user1) > 0);
        assertTrue(usdc.balanceOf(user3) == 0);
        assertTrue(rewarder.earned(user3, address(usdc)) == 0);

        vm.prank(user3);
        rewarder.getReward(user3);

        assertTrue(usdc.balanceOf(user3) == 0);

        vm.prank(address(content));
        rewarder.withdraw(user2, 1e6);

        assertTrue(rewarder.account_Balance(user2) == 0);
        assertTrue(rewarder.earned(user2, address(usdc)) > 0);
        assertTrue(usdc.balanceOf(user2) == 0);

        rewarder.getReward(user2);

        assertTrue(usdc.balanceOf(user2) > 0);
        assertTrue(rewarder.earned(user2, address(usdc)) == 0);
    }

    function test_Rewarder_Coverage() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        address user1 = address(0x456);
        address user2 = address(0x789);
        address user3 = address(0x101);

        vm.prank(address(content));
        rewarder.deposit(user1, 1e6);

        vm.prank(address(content));
        rewarder.deposit(user2, 1e6);

        assertTrue(rewarder.getRewardForDuration(address(usdc)) == 0);

        usdc.mint(address(content), 10e6);

        vm.prank(address(content));
        usdc.approve(address(rewarder), 10e6);

        vm.prank(address(content));
        rewarder.notifyRewardAmount(address(usdc), 10e6);

        vm.warp(block.timestamp + 3600);

        vm.prank(user1);
        rewarder.getReward(user1);

        vm.prank(user3);
        rewarder.getReward(user3);

        vm.prank(address(content));
        rewarder.withdraw(user2, 1e6);

        rewarder.getReward(user2);

        assertTrue(rewarder.account_Token_LastRewardPerToken(user1, address(usdc)) > 0);
        assertTrue(rewarder.account_Token_LastRewardPerToken(user2, address(usdc)) > 0);
        assertTrue(rewarder.account_Token_LastRewardPerToken(user3, address(usdc)) > 0);

        assertTrue(rewarder.getRewardForDuration(address(usdc)) > 0);
    }
}
