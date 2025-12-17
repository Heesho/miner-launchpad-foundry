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
 * @title EdgeCasesTest
 * @notice Tests for edge cases and boundary conditions
 */
contract EdgeCasesTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                            BOUNDARY VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_rig_mineAtExactEpochBoundary() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Warp to exactly epoch end
        vm.warp(rig.startTime() + rig.epochPeriod());

        // Price should be exactly 0 at boundary
        assertEq(rig.getPrice(), 0, "Price should be 0 at exact boundary");

        // Mining at 0 price should work
        vm.prank(bob);
        rig.mine(bob, 0, block.timestamp + 1 hours, 0, "");

        assertEq(rig.epochId(), 1);
    }

    function test_rig_mineOneWeiBeforeEpochEnd() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Warp to 1 second before epoch end
        vm.warp(rig.startTime() + rig.epochPeriod() - 1);

        uint256 price = rig.getPrice();
        // Price should be very small but non-zero
        assertTrue(price > 0, "Price should be non-zero");

        vm.startPrank(bob);
        weth.approve(rigAddr, price);
        rig.mine(bob, 0, block.timestamp + 1 hours, price, "");
        vm.stopPrank();
    }

    function test_rig_halvingAtExactBoundary() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 initialUps = rig.initialUps();

        // Warp to exactly halving period
        vm.warp(rig.startTime() + rig.halvingPeriod());

        // UPS should be exactly halved
        assertEq(rig.getUps(), initialUps / 2, "UPS should be halved at exact boundary");
    }

    function test_rig_halvingOneSecondBefore() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 initialUps = rig.initialUps();

        // Warp to 1 second before halving
        vm.warp(rig.startTime() + rig.halvingPeriod() - 1);

        // UPS should still be initial
        assertEq(rig.getUps(), initialUps, "UPS should be initial before halving");
    }

    function test_auction_buyAtExactEpochBoundary() public {
        (,, address auctionAddr,) = _launchRig(alice);
        Auction auctionContract = Auction(auctionAddr);

        // Fund auction with assets
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();
        weth.transfer(auctionAddr, 10 ether);

        // Record bob's balance before
        uint256 bobBalanceBefore = weth.balanceOf(bob);

        // Warp to exact epoch end
        vm.warp(auctionContract.startTime() + auctionContract.epochPeriod());

        // Price should be 0
        assertEq(auctionContract.getPrice(), 0);

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        // Buy at 0 price
        vm.prank(bob);
        auctionContract.buy(assets, bob, 0, block.timestamp + 1 hours, 0);

        assertEq(weth.balanceOf(bob), bobBalanceBefore + 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            OVERFLOW/UNDERFLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_rig_priceMultiplierNoOverflow() public {
        // Create rig with max price multiplier and high init price
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.rigMinInitPrice = type(uint192).max / 4; // High but safe
        params.rigPriceMultiplier = 3e18; // Max multiplier (3x)

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (, address rigAddr,,) = core.launch(params);
        vm.stopPrank();

        Rig rig = Rig(rigAddr);

        // Mine multiple times to compound price
        for (uint256 i = 0; i < 5; i++) {
            uint256 price = rig.getPrice();

            vm.deal(bob, price);
            vm.startPrank(bob);
            weth.deposit{value: price}();
            weth.approve(rigAddr, price);
            rig.mine(bob, rig.epochId(), block.timestamp + 1 hours, price, "");
            vm.stopPrank();
        }

        // Init price should be capped, not overflow
        assertLe(rig.epochInitPrice(), type(uint192).max);
    }

    function test_unit_mintMaxAmount() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        // Mint max safe amount (bounded by ERC20Votes)
        uint256 maxSafe = type(uint208).max - unitToken.totalSupply();

        vm.prank(rigAddr);
        unitToken.mint(bob, maxSafe);

        assertEq(unitToken.balanceOf(bob), maxSafe);
    }

    function test_rig_manyHalvings() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 tailUps = rig.tailUps();

        // Warp through 100 halving periods
        vm.warp(rig.startTime() + rig.halvingPeriod() * 100);

        // UPS should be clamped to tail, not underflow
        assertEq(rig.getUps(), tailUps, "UPS should be clamped to tail");
    }

    /*//////////////////////////////////////////////////////////////
                            ZERO VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unit_mintZero() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        uint256 supplyBefore = unitToken.totalSupply();

        vm.prank(rigAddr);
        unitToken.mint(bob, 0);

        assertEq(unitToken.totalSupply(), supplyBefore);
        assertEq(unitToken.balanceOf(bob), 0);
    }

    function test_unit_burnZero() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        uint256 supplyBefore = unitToken.totalSupply();
        uint256 balanceBefore = unitToken.balanceOf(bob);

        vm.prank(bob);
        unitToken.burn(0);

        assertEq(unitToken.totalSupply(), supplyBefore);
        assertEq(unitToken.balanceOf(bob), balanceBefore);
    }

    function test_unit_transferZero() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        vm.prank(bob);
        unitToken.transfer(charlie, 0);

        assertEq(unitToken.balanceOf(charlie), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            SAME BLOCK OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function test_rig_cannotMineTwiceInSameEpoch() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        uint256 price = rig.getPrice();

        // First mine
        vm.startPrank(bob);
        weth.approve(rigAddr, price);
        rig.mine(bob, 0, block.timestamp + 1 hours, price, "");
        vm.stopPrank();

        // Second mine attempt in same epoch should use new epoch ID
        uint256 newPrice = rig.getPrice();

        vm.startPrank(charlie);
        weth.approve(rigAddr, newPrice);

        // Using old epoch ID should fail
        vm.expectRevert(Rig.Rig__EpochIdMismatch.selector);
        rig.mine(charlie, 0, block.timestamp + 1 hours, newPrice, "");

        // Using new epoch ID should work
        rig.mine(charlie, 1, block.timestamp + 1 hours, newPrice, "");
        vm.stopPrank();
    }

    function test_auction_cannotBuyTwiceInSameEpoch() public {
        (,, address auctionAddr, address lpAddr) = _launchRig(alice);
        Auction auctionContract = Auction(auctionAddr);

        // Fund auction
        vm.deal(address(this), 30 ether);
        weth.deposit{value: 20 ether}();
        weth.transfer(auctionAddr, 20 ether);

        uint256 price = auctionContract.getPrice();

        address[] memory assets = new address[](1);
        assets[0] = address(weth);

        // First buy
        deal(lpAddr, bob, price);
        vm.startPrank(bob);
        IERC20(lpAddr).approve(auctionAddr, price);
        auctionContract.buy(assets, bob, 0, block.timestamp + 1 hours, price);
        vm.stopPrank();

        // Add more assets
        vm.deal(address(this), 10 ether);
        weth.deposit{value: 10 ether}();
        weth.transfer(auctionAddr, 10 ether);

        // Second buy with old epoch ID should fail
        uint256 newPrice = auctionContract.getPrice();
        deal(lpAddr, charlie, newPrice);

        vm.startPrank(charlie);
        IERC20(lpAddr).approve(auctionAddr, newPrice);

        vm.expectRevert(Auction.Auction__EpochIdMismatch.selector);
        auctionContract.buy(assets, charlie, 0, block.timestamp + 1 hours, newPrice);

        // New epoch ID works
        auctionContract.buy(assets, charlie, 1, block.timestamp + 1 hours, newPrice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            EXTREME TIME TESTS
    //////////////////////////////////////////////////////////////*/

    function test_rig_veryFarFuture() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Warp 1000 years into future
        vm.warp(block.timestamp + 1000 * 365 days);

        // Should not revert, UPS should be at tail
        assertEq(rig.getUps(), rig.tailUps());

        // Price should be 0 (epoch expired long ago)
        assertEq(rig.getPrice(), 0);

        // Mining should still work
        vm.prank(bob);
        rig.mine(bob, rig.epochId(), block.timestamp + 1 hours, 0, "");
    }

    function test_rig_mineAfterLongDelay() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // First mine
        uint256 price1 = rig.getPrice();
        vm.startPrank(bob);
        weth.approve(rigAddr, price1);
        rig.mine(bob, 0, block.timestamp + 1 hours, price1, "");
        vm.stopPrank();

        // Wait 10 years
        vm.warp(block.timestamp + 10 * 365 days);

        // Price should be 0
        assertEq(rig.getPrice(), 0);

        // Mine at 0 price - use large deadline
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(charlie);
        rig.mine(charlie, rig.epochId(), deadline, 0, "");

        // New init price should be at minimum
        assertEq(rig.epochInitPrice(), rig.minInitPrice());
    }

    /*//////////////////////////////////////////////////////////////
                            ADDRESS EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_rig_mineSelfAsPreviousMiner() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // First mine by bob
        uint256 price1 = rig.getPrice();
        vm.startPrank(bob);
        weth.approve(rigAddr, price1);
        rig.mine(bob, 0, block.timestamp + 1 hours, price1, "");
        vm.stopPrank();

        // Bob mines again - he pays himself 80%
        uint256 price2 = rig.getPrice();
        uint256 bobBalanceBefore = weth.balanceOf(bob);

        vm.startPrank(bob);
        weth.approve(rigAddr, price2);
        rig.mine(bob, 1, block.timestamp + 1 hours, price2, "");
        vm.stopPrank();

        // Bob should have received 80% back (minus what he paid)
        uint256 previousMinerFee = price2 * 8000 / 10000;
        uint256 netCost = price2 - previousMinerFee;

        assertEq(weth.balanceOf(bob), bobBalanceBefore - netCost, "Bob net cost mismatch");
    }

    function test_rig_teamReceivesFeeWhenMining() public {
        (, address rigAddr,,) = _launchRig(alice);
        Rig rig = Rig(rigAddr);

        // Alice is team, she mines
        uint256 price = rig.getPrice();
        uint256 aliceBalanceBefore = weth.balanceOf(alice);

        vm.startPrank(alice);
        weth.approve(rigAddr, price);
        rig.mine(alice, 0, block.timestamp + 1 hours, price, "");
        vm.stopPrank();

        // Alice is both previous miner AND team, so she gets 80% + 4%
        uint256 previousMinerFee = price * 8000 / 10000;
        uint256 teamFee = price * 400 / 10000;
        uint256 netCost = price - previousMinerFee - teamFee;

        assertEq(weth.balanceOf(alice), aliceBalanceBefore - netCost, "Alice net cost mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                            DELEGATION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_unit_delegateToSelf() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        // Self delegate
        vm.prank(bob);
        unitToken.delegate(bob);

        assertEq(unitToken.getVotes(bob), 100 ether);
        assertEq(unitToken.delegates(bob), bob);
    }

    function test_unit_delegateToZero() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        // Delegate to someone first
        vm.prank(bob);
        unitToken.delegate(charlie);
        assertEq(unitToken.getVotes(charlie), 100 ether);

        // Delegate to zero (removes delegation)
        vm.prank(bob);
        unitToken.delegate(address(0));
        assertEq(unitToken.getVotes(charlie), 0);
    }

    function test_unit_redelegatePreservesVotes() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);
        address rigAddr = unitToken.rig();

        vm.prank(rigAddr);
        unitToken.mint(bob, 100 ether);

        // Delegate to charlie
        vm.prank(bob);
        unitToken.delegate(charlie);
        assertEq(unitToken.getVotes(charlie), 100 ether);

        // Redelegate to alice
        vm.prank(bob);
        unitToken.delegate(alice);

        assertEq(unitToken.getVotes(charlie), 0);
        assertEq(unitToken.getVotes(alice), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            PERMIT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_unit_permitWithMaxDeadline() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);

        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        address rigAddr = unitToken.rig();
        vm.prank(rigAddr);
        unitToken.mint(owner, 100 ether);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                unitToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        bob,
                        100 ether,
                        0,
                        type(uint256).max // Max deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        unitToken.permit(owner, bob, 100 ether, type(uint256).max, v, r, s);

        assertEq(unitToken.allowance(owner, bob), 100 ether);
    }

    function test_unit_permitExpired() public {
        (address unitAddr,,,) = _launchRig(alice);
        Unit unitToken = Unit(unitAddr);

        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        address rigAddr = unitToken.rig();
        vm.prank(rigAddr);
        unitToken.mint(owner, 100 ether);

        uint256 expiredDeadline = block.timestamp - 1;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                unitToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        bob,
                        100 ether,
                        0,
                        expiredDeadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        vm.expectRevert("ERC20Permit: expired deadline");
        unitToken.permit(owner, bob, 100 ether, expiredDeadline, v, r, s);
    }
}
