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

contract ContentTest is Test {
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

    function test_Content_Constructor() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Token token = Token(tokenFactory.lastToken());
        Content content = Content(contentFactory.lastContent());

        assertTrue(address(content) == token.content());
        assertTrue(content.rewarder() == rewarderFactory.lastRewarder());
        assertTrue(content.token() == address(token));
        assertTrue(content.quote() == address(usdc));
        assertTrue(content.nextTokenId() == 0);
    }

    function testRevert_Content_CreateAccountZero() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);
        Content content = Content(contentFactory.lastContent());

        vm.expectRevert("Content__ZeroTo()");
        content.create(address(0), "ipfs://content1");
    }

    function test_Content_Create() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        content.create(address(0x123), "ipfs://content1");
        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));

        content.create(address(0x456), "ipfs://content2");
        nextTokenId = content.nextTokenId();
        price = content.id_Price(2);
        creator = content.id_Creator(2);

        assertTrue(nextTokenId == 2);
        assertTrue(price == 0);
        assertTrue(creator == address(0x456));

        content.create(address(0x789), "ipfs://content3");
        nextTokenId = content.nextTokenId();
        price = content.id_Price(3);
        creator = content.id_Creator(3);

        assertTrue(nextTokenId == 3);
        assertTrue(price == 0);
        assertTrue(creator == address(0x789));
    }

    function test_Content_Collect() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Token token = Token(tokenFactory.lastToken());

        usdc.mint(address(0x789), 1e6);

        vm.prank(address(0x789));
        usdc.approve(address(token), 1e6);

        vm.prank(address(0x789));
        token.buy(1e6, 0, 0, address(0x789), address(0));

        content.create(address(0x123), "ipfs://content1");
        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);
        address owner = content.ownerOf(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));
        assertTrue(owner == address(0x123));

        uint256 nextPrice = content.getNextPrice(1);
        assertTrue(nextPrice == 1e6);

        usdc.mint(address(0x456), 1e6);

        vm.prank(address(0x456));
        usdc.approve(address(content), 1e6);

        vm.prank(address(0x456));
        content.collect(address(0x456), 1, nextPrice);

        nextTokenId = content.nextTokenId();
        price = content.id_Price(1);
        creator = content.id_Creator(1);
        owner = content.ownerOf(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 1e6);
        assertTrue(creator == address(0x123));
        assertTrue(owner == address(0x456));

        nextPrice = content.getNextPrice(1);
        assertTrue(nextPrice == (price * 11) / 10 + 1e6);
    }

    function test_Content_CollectManyTimes() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Token token = Token(tokenFactory.lastToken());

        usdc.mint(address(0x789), 1e6);

        vm.prank(address(0x789));
        usdc.approve(address(token), 1e6);

        vm.prank(address(0x789));
        token.buy(1e6, 0, 0, address(0x789), address(0));

        content.create(address(0x123), "ipfs://content1");
        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);
        address owner = content.ownerOf(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));
        assertTrue(owner == address(0x123));

        for (uint256 i = 0; i < 200; i++) {
            address user = address(uint160(i + 1));
            uint256 lastPrice = content.id_Price(1);
            price = content.getNextPrice(1);
            assertTrue(price == (lastPrice * 11) / 10 + 1e6);

            usdc.mint(user, price);

            vm.prank(user);
            usdc.approve(address(content), price);

            vm.prank(user);
            content.collect(user, 1, price);

            uint256 nextPrice = content.getNextPrice(1);
            creator = content.id_Creator(1);
            owner = content.ownerOf(1);

            assertTrue(nextPrice == (price * 11) / 10 + 1e6);
            assertTrue(creator == address(0x123));
            assertTrue(owner == user);
        }
    }

    function test_Content_CollectMaxPriceExceeded() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Token token = Token(tokenFactory.lastToken());

        usdc.mint(address(0x789), 1e6);

        vm.prank(address(0x789));
        usdc.approve(address(token), 1e6);

        vm.prank(address(0x789));
        token.buy(1e6, 0, 0, address(0x789), address(0));

        content.create(address(0x123), "ipfs://content1");
        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);
        address owner = content.ownerOf(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));
        assertTrue(owner == address(0x123));

        address user = address(0x456);
        price = content.getNextPrice(1);

        usdc.mint(user, price);

        vm.prank(user);
        usdc.approve(address(content), price);

        vm.prank(user);
        vm.expectRevert("Content__MaxPriceExceeded()");
        content.collect(user, 1, price - 1);

        vm.prank(user);
        content.collect(user, 1, price + 1);
    }

    function test_Content_Distribute(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 1_000_000_000_000_000_000);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Token token = Token(tokenFactory.lastToken());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        content.distribute();
        uint256 tokenBalanceContent = token.balanceOf(address(content));
        uint256 tokenBalanceRewarder = token.balanceOf(address(rewarder));
        uint256 usdcBalanceContent = usdc.balanceOf(address(content));
        uint256 usdcBalanceRewarder = usdc.balanceOf(address(rewarder));

        assertTrue(tokenBalanceContent == 0);
        assertTrue(tokenBalanceRewarder == 0);

        usdc.mint(address(0x123), amount);

        vm.prank(address(0x123));
        usdc.approve(address(token), amount);

        vm.prank(address(0x123));
        token.buy(amount, 0, 0, address(0x123), address(0));

        usdc.mint(address(content), amount);

        uint256 userTokenBalance = token.balanceOf(address(0x123));

        vm.prank(address(0x123));
        token.transfer(address(content), userTokenBalance);

        uint256 tokenToDistro = token.balanceOf(address(content));
        uint256 usdcToDistro = usdc.balanceOf(address(content));

        content.distribute();

        tokenBalanceContent = token.balanceOf(address(content));
        tokenBalanceRewarder = token.balanceOf(address(rewarder));
        usdcBalanceContent = usdc.balanceOf(address(content));
        usdcBalanceRewarder = usdc.balanceOf(address(rewarder));

        uint256 duration = rewarder.DURATION();

        if (tokenToDistro > duration) {
            assertTrue(tokenBalanceContent == 0);
            assertTrue(tokenBalanceRewarder > 0);
        } else {
            assertTrue(tokenBalanceContent > 0);
            assertTrue(tokenBalanceRewarder == 0);
        }

        if (usdcToDistro > duration) {
            assertTrue(usdcBalanceContent == 0);
            assertTrue(usdcBalanceRewarder > 0);
        } else {
            assertTrue(usdcBalanceContent > 0);
            assertTrue(usdcBalanceRewarder == 0);
        }
    }

    function testRevert_Content_Transfer() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        content.create(address(0x123), "ipfs://content1");
        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);
        address owner = content.ownerOf(1);

        assertTrue(nextTokenId == 1);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));
        assertTrue(owner == address(0x123));

        vm.prank(address(0x123));
        vm.expectRevert("Content__TransferDisabled()");
        content.transferFrom(address(0x123), address(0x456), 1);

        owner = content.ownerOf(1);
        assertTrue(owner == address(0x123));

        vm.prank(address(0x123));
        vm.expectRevert("Content__TransferDisabled()");
        content.safeTransferFrom(address(0x123), address(0x456), 1);

        owner = content.ownerOf(1);
        assertTrue(owner == address(0x123));

        vm.prank(address(0x123));
        vm.expectRevert("Content__TransferDisabled()");
        content.safeTransferFrom(address(0x123), address(0x456), 1, "0x");

        owner = content.ownerOf(1);
        assertTrue(owner == address(0x123));
    }

    function test_Content_SupportsInterface() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        assertTrue(content.supportsInterface(0x80ac58cd));
        assertTrue(content.supportsInterface(0x5b5e139f));
        assertTrue(content.supportsInterface(0x780e9d63));
        assertTrue(content.supportsInterface(0x01ffc9a7));
        assertFalse(content.supportsInterface(0x12345678));
    }

    function test_Content_TokenURI() public {
        uint256 amountQuoteIn = 1e6;
        usdc.mint(address(1), amountQuoteIn);

        vm.prank(address(1));
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(address(1));
        core.create("Test1", "TEST1", "ipfs://test1", address(1), false, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        content.create(address(0x123), "ipfs://content1");
        string memory tokenURI1 = content.tokenURI(1);

        assertTrue(keccak256(bytes(tokenURI1)) == keccak256(bytes("ipfs://content1")));

        content.create(address(0x456), "ipfs://content2");
        string memory tokenURI2 = content.tokenURI(2);

        assertTrue(keccak256(bytes(tokenURI2)) == keccak256(bytes("ipfs://content2")));

        content.create(address(0x789), "ipfs://content3");
        string memory tokenURI3 = content.tokenURI(3);

        assertTrue(keccak256(bytes(tokenURI3)) == keccak256(bytes("ipfs://content3")));
    }

    function test_Content_CreateModerated() public {
        address owner = address(0x123);

        uint256 amountQuoteIn = 1e6;
        usdc.mint(owner, amountQuoteIn);

        vm.prank(owner);
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(owner);
        core.create("Test1", "TEST1", "ipfs://test1", owner, true, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        address user = address(0x456);

        vm.prank(user);
        content.create(owner, "ipfs://content1");
        vm.prank(owner);
        vm.expectRevert("Content__NotApproved()");
        content.collect(owner, 1, 1e6);

        vm.prank(user);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert("Content__NotModerator()");
        content.approveContents(tokenIds);

        address[] memory moderators = new address[](1);
        moderators[0] = user;
        vm.prank(owner);
        content.setModerators(moderators, true);

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        content.setModerators(moderators, false);

        vm.prank(owner);
        content.create(user, "ipfs://content2");
        tokenIds[0] = 2;
        vm.prank(owner);
        content.approveContents(tokenIds);

        vm.prank(owner);
        content.create(owner, "ipfs://content3");

        vm.prank(user);
        tokenIds[0] = 3;
        content.approveContents(tokenIds);
    }

    function test_Content_CreateMakeUnmoderated() public {
        address owner = address(0x722);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(owner, amountQuoteIn);

        vm.prank(owner);
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(owner);
        core.create("Test1", "TEST1", "ipfs://test1", owner, true, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        vm.prank(address(0x123));
        content.create(address(0x123), "ipfs://content1");
        assertTrue(content.id_IsApproved(1) == false);

        vm.prank(address(0x123));
        vm.expectRevert();
        content.setIsModerated(false);

        vm.prank(owner);
        content.setIsModerated(false);

        vm.prank(address(0x123));
        content.create(address(0x123), "ipfs://content2");
        assertTrue(content.id_IsApproved(2) == true);

        uint256 nextTokenId = content.nextTokenId();
        uint256 price = content.id_Price(1);
        address creator = content.id_Creator(1);

        assertTrue(nextTokenId == 2);
        assertTrue(price == 0);
        assertTrue(creator == address(0x123));

        vm.prank(address(0x456));
        content.create(address(0x456), "ipfs://content3");
        assertTrue(content.id_IsApproved(3) == true);

        nextTokenId = content.nextTokenId();
        price = content.id_Price(3);
        creator = content.id_Creator(3);

        assertTrue(nextTokenId == 3);
        assertTrue(price == 0);
        assertTrue(creator == address(0x456));

        vm.prank(address(0x789));
        content.create(address(0x789), "ipfs://content4");
        assertTrue(content.id_IsApproved(4) == true);

        nextTokenId = content.nextTokenId();
        price = content.id_Price(4);
        creator = content.id_Creator(4);

        assertTrue(nextTokenId == 4);
        assertTrue(price == 0);
        assertTrue(creator == address(0x789));
    }

    function test_Content_AddRewardToken() public {
        address owner = address(0x123);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(owner, amountQuoteIn);

        vm.prank(owner);
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(owner);
        core.create("Test1", "TEST1", "ipfs://test1", owner, true, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());
        Rewarder rewarder = Rewarder(rewarderFactory.lastRewarder());

        MockToken mockToken = new MockToken();

        vm.expectRevert("Ownable: caller is not the owner");
        content.addReward(address(mockToken));

        vm.prank(owner);
        content.addReward(address(mockToken));

        assertTrue(rewarder.getRewardTokens().length == 3);
        assertTrue(rewarder.getRewardTokens()[2] == address(mockToken));
        assertTrue(rewarder.token_IsReward(address(mockToken)) == true);
    }

    function test_Content_SetUri() public {
        address owner = address(0x123);
        uint256 amountQuoteIn = 1e6;
        usdc.mint(owner, amountQuoteIn);

        vm.prank(owner);
        usdc.approve(address(core), amountQuoteIn);

        vm.prank(owner);
        core.create("Test1", "TEST1", "ipfs://test1", owner, true, amountQuoteIn, 1e18);

        Content content = Content(contentFactory.lastContent());

        vm.expectRevert("Ownable: caller is not the owner");
        content.setUri("ipfs://test2");

        assertTrue(keccak256(bytes(content.uri())) == keccak256(bytes("ipfs://test1")));

        vm.prank(owner);
        content.setUri("ipfs://test2");

        assertTrue(keccak256(bytes(content.uri())) == keccak256(bytes("ipfs://test2")));
    }
}
