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

contract CoreTest is Test {
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

    function test_Core_Constructor() public view {
        assertEq(core.quote(), address(usdc));
        assertEq(core.tokenFactory(), address(tokenFactory));
        assertEq(core.contentFactory(), address(contentFactory));
        assertEq(core.rewarderFactory(), address(rewarderFactory));
    }

    function test_Core_Create_Index() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);
        address lastToken = tokenFactory.lastToken();

        assertTrue(lastToken != address(0));
        assertTrue(core.index() == 1);
        assertTrue(core.index_Token(1) == lastToken);
        assertTrue(core.index_Token(2) == address(0));
        assertTrue(core.token_Index(lastToken) == 1);

        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test2", "TEST2", "ipfs://test2", address(1), false, amountQuoteIn, 1e18);
        address lastToken2 = tokenFactory.lastToken();

        assertTrue(lastToken2 != address(0));
        assertTrue(core.index() == 2);
        assertTrue(core.index_Token(1) == lastToken);
        assertTrue(core.index_Token(2) == lastToken2);
        assertTrue(core.index_Token(3) == address(0));
        assertTrue(core.token_Index(lastToken2) == 2);
    }

    function test_Core_Create_Token(uint256 createQuoteAmount) public {
        vm.assume(createQuoteAmount > 1000 && createQuoteAmount < 10_000_000_000_000);
        usdc.mint(address(1), createQuoteAmount);

        vm.prank(address(1));
        usdc.approve(address(core), createQuoteAmount);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, createQuoteAmount, 1e18);

        address lastToken = tokenFactory.lastToken();
        address lastContent = contentFactory.lastContent();
        address lastRewarder = rewarderFactory.lastRewarder();

        Token token = Token(lastToken);

        assertTrue(token.content() == lastContent);
        assertTrue(token.rewarder() == lastRewarder);
        assertTrue(keccak256(bytes(token.name())) == keccak256(bytes("Test1")));
        assertTrue(keccak256(bytes(token.symbol())) == keccak256(bytes("TEST1")));
        assertTrue(token.maxSupply() == 1_000_000_000 * 1e18);
    }

    function test_Core_Ownership() public {
        address owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address notOwner = address(0xBAD);
        address newOwner = address(0xBEEF);

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        core.transferOwnership(newOwner);
        assertTrue(core.owner() == owner);
        assertTrue(core.owner() != newOwner);

        vm.prank(owner);
        core.transferOwnership(newOwner);
        assertTrue(core.owner() == newOwner);
    }

    function test_Core_SetTreasury() public {
        address defaultEOA = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address newTreasury = address(0x123);

        vm.prank(defaultEOA);
        core.setTreasury(newTreasury);
        assertTrue(core.treasury() == newTreasury);

        vm.prank(address(0xBAD));
        vm.expectRevert("Ownable: caller is not the owner");
        core.setTreasury(address(0x222));
        assertTrue(core.treasury() == newTreasury);
    }

    function test_Core_SetTokenFactory() public {
        address owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address newTokenFactory = address(0x111);

        vm.prank(owner);
        core.setTokenFactory(newTokenFactory);
        assertEq(core.tokenFactory(), newTokenFactory);

        vm.prank(address(0xBAD));
        vm.expectRevert("Ownable: caller is not the owner");
        core.setTokenFactory(address(0x222));
        assertEq(core.tokenFactory(), newTokenFactory);
    }

    function test_Core_SetContentFactory() public {
        address owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address newContentFactory = address(0x111);

        vm.prank(owner);
        core.setContentFactory(newContentFactory);
        assertEq(core.contentFactory(), newContentFactory);

        vm.prank(address(0xBAD));
        vm.expectRevert("Ownable: caller is not the owner");
        core.setContentFactory(address(0x222));
        assertEq(core.contentFactory(), newContentFactory);
    }

    function test_Core_SetRewarderFactory() public {
        address owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        address newRewarderFactory = address(0x111);

        vm.prank(owner);
        core.setRewarderFactory(newRewarderFactory);
        assertEq(core.rewarderFactory(), newRewarderFactory);

        vm.prank(address(0xBAD));
        vm.expectRevert("Ownable: caller is not the owner");
        core.setRewarderFactory(address(0x222));
        assertEq(core.rewarderFactory(), newRewarderFactory);
    }
}
