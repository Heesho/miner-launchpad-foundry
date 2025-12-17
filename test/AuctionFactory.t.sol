// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Auction} from "../src/Auction.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title AuctionFactoryTest
 * @notice Tests for the AuctionFactory contract
 */
contract AuctionFactoryTest is Test {
    AuctionFactory public factory;
    MockToken public paymentToken;

    address public paymentReceiver;

    // Test parameters
    uint256 public constant INIT_PRICE = 1e15;
    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 1.5e18;
    uint256 public constant MIN_INIT_PRICE = 1e15;

    function setUp() public {
        factory = new AuctionFactory();
        paymentToken = new MockToken("LP Token", "LP");
        paymentReceiver = makeAddr("paymentReceiver");
    }

    /*----------  DEPLOY TESTS  -----------------------------------------*/

    function test_deploy_createsAuction() public {
        address auctionAddr = factory.deploy(
            INIT_PRICE, address(paymentToken), paymentReceiver, EPOCH_PERIOD, PRICE_MULTIPLIER, MIN_INIT_PRICE
        );

        Auction auction = Auction(auctionAddr);
        assertEq(auction.initPrice(), INIT_PRICE);
        assertEq(auction.paymentToken(), address(paymentToken));
        assertEq(auction.paymentReceiver(), paymentReceiver);
        assertEq(auction.epochPeriod(), EPOCH_PERIOD);
        assertEq(auction.priceMultiplier(), PRICE_MULTIPLIER);
        assertEq(auction.minInitPrice(), MIN_INIT_PRICE);
    }

    function test_deploy_differentAddresses() public {
        address auction1 = factory.deploy(
            INIT_PRICE, address(paymentToken), paymentReceiver, EPOCH_PERIOD, PRICE_MULTIPLIER, MIN_INIT_PRICE
        );

        MockToken paymentToken2 = new MockToken("LP Token 2", "LP2");
        address auction2 = factory.deploy(
            INIT_PRICE * 2, address(paymentToken2), paymentReceiver, EPOCH_PERIOD * 2, PRICE_MULTIPLIER, MIN_INIT_PRICE
        );

        assertTrue(auction1 != auction2);
    }

    function test_deploy_withMinValues() public {
        address auctionAddr = factory.deploy(
            1e6, // ABS_MIN_INIT_PRICE
            address(paymentToken),
            paymentReceiver,
            1 hours, // MIN_EPOCH_PERIOD
            1.1e18, // MIN_PRICE_MULTIPLIER
            1e6 // ABS_MIN_INIT_PRICE
        );

        Auction auction = Auction(auctionAddr);
        assertEq(auction.initPrice(), 1e6);
        assertEq(auction.epochPeriod(), 1 hours);
        assertEq(auction.priceMultiplier(), 1.1e18);
        assertEq(auction.minInitPrice(), 1e6);
    }

    function test_deploy_withMaxValues() public {
        uint256 maxInitPrice = type(uint192).max;

        address auctionAddr = factory.deploy(
            maxInitPrice,
            address(paymentToken),
            paymentReceiver,
            365 days, // MAX_EPOCH_PERIOD
            3e18, // MAX_PRICE_MULTIPLIER
            1e6
        );

        Auction auction = Auction(auctionAddr);
        assertEq(auction.initPrice(), maxInitPrice);
        assertEq(auction.epochPeriod(), 365 days);
        assertEq(auction.priceMultiplier(), 3e18);
    }

    function test_deploy_revertsOnInvalidParams() public {
        // Test that factory passes through validation errors from Auction
        vm.expectRevert(Auction.Auction__InvalidPaymentToken.selector);
        factory.deploy(INIT_PRICE, address(0), paymentReceiver, EPOCH_PERIOD, PRICE_MULTIPLIER, MIN_INIT_PRICE);

        vm.expectRevert(Auction.Auction__InvalidPaymentReceiver.selector);
        factory.deploy(INIT_PRICE, address(paymentToken), address(0), EPOCH_PERIOD, PRICE_MULTIPLIER, MIN_INIT_PRICE);

        vm.expectRevert(Auction.Auction__EpochPeriodBelowMin.selector);
        factory.deploy(INIT_PRICE, address(paymentToken), paymentReceiver, 1, PRICE_MULTIPLIER, MIN_INIT_PRICE);
    }

    function testFuzz_deploy_validParams(
        uint256 initPrice,
        uint256 epochPeriod,
        uint256 priceMultiplier,
        uint256 minInitPrice
    ) public {
        initPrice = bound(initPrice, 1e6, type(uint192).max);
        epochPeriod = bound(epochPeriod, 1 hours, 365 days);
        priceMultiplier = bound(priceMultiplier, 1.1e18, 3e18);
        minInitPrice = bound(minInitPrice, 1e6, type(uint192).max);

        // Ensure initPrice >= minInitPrice
        if (initPrice < minInitPrice) {
            initPrice = minInitPrice;
        }

        address auctionAddr = factory.deploy(
            initPrice, address(paymentToken), paymentReceiver, epochPeriod, priceMultiplier, minInitPrice
        );

        Auction auction = Auction(auctionAddr);
        assertEq(auction.initPrice(), initPrice);
        assertEq(auction.epochPeriod(), epochPeriod);
        assertEq(auction.priceMultiplier(), priceMultiplier);
        assertEq(auction.minInitPrice(), minInitPrice);
    }
}
