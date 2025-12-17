// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Rig} from "../src/Rig.sol";
import {Unit} from "../src/Unit.sol";
import {Core} from "../src/Core.sol";
import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title RigTest
 * @notice Tests for the Rig Dutch auction mining contract
 */
contract RigTest is Test {
    Rig public rig;
    Unit public unit;
    MockToken public weth;
    Core public mockCore;

    address public owner;
    address public treasury;
    address public team;
    address public protocolFeeAddress;
    address public alice;
    address public bob;
    address public charlie;

    // Constants from Rig contract
    uint256 public constant PREVIOUS_MINER_FEE = 8_000;
    uint256 public constant TEAM_FEE = 400;
    uint256 public constant PROTOCOL_FEE = 100;
    uint256 public constant DIVISOR = 10_000;
    uint256 public constant PRECISION = 1e18;

    uint256 public constant MIN_EPOCH_PERIOD = 10 minutes;
    uint256 public constant MAX_EPOCH_PERIOD = 365 days;
    uint256 public constant MIN_PRICE_MULTIPLIER = 1.1e18;
    uint256 public constant MAX_PRICE_MULTIPLIER = 3e18;
    uint256 public constant ABS_MIN_INIT_PRICE = 1e6;
    uint256 public constant ABS_MAX_INIT_PRICE = type(uint192).max;
    uint256 public constant MAX_INITIAL_UPS = 1e24;
    uint256 public constant MIN_HALVING_PERIOD = 1 days;

    // Test parameters
    uint256 public constant INITIAL_UPS = 1e18;
    uint256 public constant TAIL_UPS = 1e16;
    uint256 public constant HALVING_PERIOD = 365 days;
    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 1.5e18;
    uint256 public constant MIN_INIT_PRICE = 1e15;

    event Rig__Mined(address indexed sender, address indexed miner, uint256 price, string uri);
    event Rig__Minted(address indexed miner, uint256 amount);
    event Rig__PreviousMinerFee(address indexed miner, uint256 amount);
    event Rig__TreasuryFee(address indexed treasury, uint256 amount);
    event Rig__TeamFee(address indexed team, uint256 amount);
    event Rig__ProtocolFee(address indexed protocol, uint256 amount);
    event Rig__TreasurySet(address indexed treasury);
    event Rig__TeamSet(address indexed team);
    event Rig__UriSet(string uri);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        team = makeAddr("team");
        protocolFeeAddress = makeAddr("protocolFee");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy mocks
        weth = new MockToken("Wrapped ETH", "WETH");

        // Deploy a mock Core that returns protocol fee address
        mockCore = Core(_deployMockCore());

        // Deploy Unit token
        vm.prank(owner);
        unit = new Unit("Test Unit", "TU");

        // Deploy Rig
        vm.prank(owner);
        rig = new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "https://example.com/rig.json",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Transfer unit minting rights to rig
        vm.prank(owner);
        unit.setRig(address(rig));

        // Fund users with WETH
        weth.mint(alice, 1000 ether);
        weth.mint(bob, 1000 ether);
        weth.mint(charlie, 1000 ether);
    }

    function _deployMockCore() internal returns (address) {
        // Deploy a simple mock that implements ICore.protocolFeeAddress()
        MockCore mock = new MockCore(protocolFeeAddress);
        return address(mock);
    }

    /*----------  CONSTRUCTOR TESTS  ------------------------------------*/

    function test_constructor_setsImmutables() public view {
        assertEq(rig.unit(), address(unit));
        assertEq(rig.quote(), address(weth));
        assertEq(rig.core(), address(mockCore));
        assertEq(rig.initialUps(), INITIAL_UPS);
        assertEq(rig.tailUps(), TAIL_UPS);
        assertEq(rig.halvingPeriod(), HALVING_PERIOD);
        assertEq(rig.epochPeriod(), EPOCH_PERIOD);
        assertEq(rig.priceMultiplier(), PRICE_MULTIPLIER);
        assertEq(rig.minInitPrice(), MIN_INIT_PRICE);
    }

    function test_constructor_setsInitialState() public view {
        assertEq(rig.treasury(), treasury);
        assertEq(rig.team(), team);
        assertEq(rig.uri(), "https://example.com/rig.json");
        assertEq(rig.epochId(), 0);
        assertEq(rig.epochInitPrice(), MIN_INIT_PRICE);
        assertEq(rig.epochUps(), INITIAL_UPS);
        assertEq(rig.epochMiner(), team); // Initial miner is team
    }

    function test_constructor_revertsIfInvalidUnit() public {
        vm.expectRevert(Rig.Rig__InvalidUnit.selector);
        new Rig(
            address(0),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidQuote() public {
        vm.expectRevert(Rig.Rig__InvalidQuote.selector);
        new Rig(
            address(unit),
            address(0),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidTreasury() public {
        vm.expectRevert(Rig.Rig__InvalidTreasury.selector);
        new Rig(
            address(unit),
            address(weth),
            address(0),
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidTeam() public {
        vm.expectRevert(Rig.Rig__InvalidTeam.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            address(0),
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidCore() public {
        vm.expectRevert(Rig.Rig__InvalidCore.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(0),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidInitialUps() public {
        vm.expectRevert(Rig.Rig__InvalidInitialUps.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            0,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInitialUpsExceedsMax() public {
        vm.expectRevert(Rig.Rig__InitialUpsExceedsMax.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            MAX_INITIAL_UPS + 1,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidTailUps() public {
        // tailUps cannot be 0
        vm.expectRevert(Rig.Rig__InvalidTailUps.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            0,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // tailUps cannot exceed initialUps
        vm.expectRevert(Rig.Rig__InvalidTailUps.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            INITIAL_UPS + 1,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfInvalidHalvingPeriod() public {
        vm.expectRevert(Rig.Rig__InvalidHalvingPeriod.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            0,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfHalvingPeriodBelowMin() public {
        vm.expectRevert(Rig.Rig__HalvingPeriodBelowMin.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            MIN_HALVING_PERIOD - 1,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfEpochPeriodOutOfRange() public {
        vm.expectRevert(Rig.Rig__EpochPeriodOutOfRange.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            MIN_EPOCH_PERIOD - 1,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        vm.expectRevert(Rig.Rig__EpochPeriodOutOfRange.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            MAX_EPOCH_PERIOD + 1,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfPriceMultiplierOutOfRange() public {
        vm.expectRevert(Rig.Rig__PriceMultiplierOutOfRange.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            MIN_PRICE_MULTIPLIER - 1,
            MIN_INIT_PRICE
        );

        vm.expectRevert(Rig.Rig__PriceMultiplierOutOfRange.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            MAX_PRICE_MULTIPLIER + 1,
            MIN_INIT_PRICE
        );
    }

    function test_constructor_revertsIfMinInitPriceBelowAbsoluteMin() public {
        vm.expectRevert(Rig.Rig__MinInitPriceBelowAbsoluteMin.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            ABS_MIN_INIT_PRICE - 1
        );
    }

    function test_constructor_revertsIfMinInitPriceAboveAbsoluteMax() public {
        vm.expectRevert(Rig.Rig__MinInitPriceAboveAbsoluteMax.selector);
        new Rig(
            address(unit),
            address(weth),
            treasury,
            team,
            address(mockCore),
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            ABS_MAX_INIT_PRICE + 1
        );
    }

    /*----------  GET PRICE TESTS  --------------------------------------*/

    function test_getPrice_startsAtInitPrice() public view {
        assertEq(rig.getPrice(), MIN_INIT_PRICE);
    }

    function test_getPrice_decaysLinearly() public {
        assertEq(rig.getPrice(), MIN_INIT_PRICE);

        vm.warp(block.timestamp + EPOCH_PERIOD / 2);
        assertEq(rig.getPrice(), MIN_INIT_PRICE / 2);

        vm.warp(block.timestamp + EPOCH_PERIOD / 4);
        assertEq(rig.getPrice(), MIN_INIT_PRICE / 4);
    }

    function test_getPrice_zeroAfterEpochPeriod() public {
        vm.warp(block.timestamp + EPOCH_PERIOD + 1);
        assertEq(rig.getPrice(), 0);
    }

    /*----------  GET UPS TESTS  ----------------------------------------*/

    function test_getUps_returnsInitialUpsAtStart() public view {
        assertEq(rig.getUps(), INITIAL_UPS);
    }

    function test_getUps_halvesAfterHalvingPeriod() public {
        uint256 start = rig.startTime();
        assertEq(rig.getUps(), INITIAL_UPS);

        // After exactly 1 halving period
        vm.warp(start + HALVING_PERIOD);
        assertEq(rig.getUps(), INITIAL_UPS >> 1); // INITIAL_UPS / 2

        // After exactly 2 halving periods
        vm.warp(start + HALVING_PERIOD * 2);
        assertEq(rig.getUps(), INITIAL_UPS >> 2); // INITIAL_UPS / 4
    }

    function test_getUps_respectsTailUps() public {
        // Warp far enough that UPS would go below tailUps
        vm.warp(block.timestamp + HALVING_PERIOD * 20);
        assertEq(rig.getUps(), TAIL_UPS);
    }

    /*----------  MINE TESTS  -------------------------------------------*/

    function test_mine_success() public {
        uint256 price = rig.getPrice();
        address initialMiner = rig.epochMiner();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        vm.expectEmit(true, true, false, true);
        emit Rig__Mined(alice, alice, price, "alice-uri");
        uint256 paidPrice = rig.mine(alice, 0, block.timestamp + 1, price, "alice-uri");
        vm.stopPrank();

        assertEq(paidPrice, price);
        assertEq(rig.epochMiner(), alice);
        assertEq(rig.epochId(), 1);
        assertEq(rig.epochUri(), "alice-uri");
    }

    function test_mine_distributesFees() public {
        uint256 price = rig.getPrice();
        address initialMiner = team; // Initial miner is team

        uint256 previousMinerAmount = price * PREVIOUS_MINER_FEE / DIVISOR;
        uint256 teamAmount = price * TEAM_FEE / DIVISOR;
        uint256 protocolAmount = price * PROTOCOL_FEE / DIVISOR;
        uint256 treasuryAmount = price - previousMinerAmount - teamAmount - protocolAmount;

        uint256 teamBalanceBefore = weth.balanceOf(team);
        uint256 treasuryBalanceBefore = weth.balanceOf(treasury);
        uint256 protocolBalanceBefore = weth.balanceOf(protocolFeeAddress);

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        // Previous miner (team) gets 80% + 4% team fee
        assertEq(weth.balanceOf(team), teamBalanceBefore + previousMinerAmount + teamAmount);
        assertEq(weth.balanceOf(treasury), treasuryBalanceBefore + treasuryAmount);
        assertEq(weth.balanceOf(protocolFeeAddress), protocolBalanceBefore + protocolAmount);
    }

    function test_mine_mintsToPreviousMiner() public {
        // First, alice mines at time 0
        uint256 price1 = rig.getPrice();
        vm.startPrank(alice);
        weth.approve(address(rig), price1);
        rig.mine(alice, 0, block.timestamp + 1, price1, "");
        vm.stopPrank();

        uint256 aliceBalanceBefore = unit.balanceOf(alice);

        // Wait some time
        uint256 mineTime = 1 hours;
        vm.warp(block.timestamp + mineTime);

        // Bob mines
        uint256 price2 = rig.getPrice();
        vm.startPrank(bob);
        weth.approve(address(rig), price2);
        rig.mine(bob, 1, block.timestamp + 1, price2, "");
        vm.stopPrank();

        // Alice should receive mineTime * epochUps tokens
        uint256 expectedMinted = mineTime * INITIAL_UPS;
        assertEq(unit.balanceOf(alice), aliceBalanceBefore + expectedMinted);
    }

    function test_mine_updatesNextEpochPrice() public {
        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        uint256 expectedNewPrice = price * PRICE_MULTIPLIER / PRECISION;
        assertEq(rig.epochInitPrice(), expectedNewPrice);
    }

    function test_mine_clampsToMinInitPrice() public {
        // Wait until price is very low
        vm.warp(block.timestamp + EPOCH_PERIOD - 1);

        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        assertEq(rig.epochInitPrice(), MIN_INIT_PRICE);
    }

    function test_mine_revertsIfInvalidMiner() public {
        vm.prank(alice);
        vm.expectRevert(Rig.Rig__InvalidMiner.selector);
        rig.mine(address(0), 0, block.timestamp + 1, MIN_INIT_PRICE, "");
    }

    function test_mine_revertsIfExpired() public {
        vm.prank(alice);
        vm.expectRevert(Rig.Rig__Expired.selector);
        rig.mine(alice, 0, block.timestamp - 1, MIN_INIT_PRICE, "");
    }

    function test_mine_revertsIfEpochIdMismatch() public {
        vm.prank(alice);
        vm.expectRevert(Rig.Rig__EpochIdMismatch.selector);
        rig.mine(alice, 1, block.timestamp + 1, MIN_INIT_PRICE, "");
    }

    function test_mine_revertsIfMaxPriceExceeded() public {
        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        vm.expectRevert(Rig.Rig__MaxPriceExceeded.selector);
        rig.mine(alice, 0, block.timestamp + 1, price - 1, "");
        vm.stopPrank();
    }

    function test_mine_zeroPriceAllowed() public {
        // Wait until price is 0
        vm.warp(block.timestamp + EPOCH_PERIOD + 1);

        assertEq(rig.getPrice(), 0);

        vm.prank(alice);
        uint256 paidPrice = rig.mine(alice, 0, block.timestamp + 1, 0, "");

        assertEq(paidPrice, 0);
        assertEq(rig.epochMiner(), alice);
    }

    function test_mine_updatesUpsAfterHalving() public {
        // Warp past halving period
        vm.warp(block.timestamp + HALVING_PERIOD + 1);

        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        assertEq(rig.epochUps(), INITIAL_UPS / 2);
    }

    function test_mine_differentMinerThanSender() public {
        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        // Alice sends transaction but sets bob as miner
        rig.mine(bob, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        assertEq(rig.epochMiner(), bob);
    }

    /*----------  TEAM FEE DISABLED TESTS  ------------------------------*/

    function test_mine_noTeamFeeWhenTeamIsZero() public {
        // Set team to address(0)
        vm.prank(owner);
        rig.setTeam(address(0));

        uint256 price = rig.getPrice();
        address initialMiner = team;

        uint256 previousMinerAmount = price * PREVIOUS_MINER_FEE / DIVISOR;
        uint256 protocolAmount = price * PROTOCOL_FEE / DIVISOR;
        // No team fee, treasury gets more
        uint256 treasuryAmount = price - previousMinerAmount - protocolAmount;

        uint256 treasuryBalanceBefore = weth.balanceOf(treasury);

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        assertEq(weth.balanceOf(treasury), treasuryBalanceBefore + treasuryAmount);
    }

    /*----------  OWNER FUNCTIONS  --------------------------------------*/

    function test_setTreasury_success() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Rig__TreasurySet(newTreasury);
        rig.setTreasury(newTreasury);

        assertEq(rig.treasury(), newTreasury);
    }

    function test_setTreasury_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        rig.setTreasury(alice);
    }

    function test_setTreasury_revertsIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Rig.Rig__InvalidTreasury.selector);
        rig.setTreasury(address(0));
    }

    function test_setTeam_success() public {
        address newTeam = makeAddr("newTeam");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Rig__TeamSet(newTeam);
        rig.setTeam(newTeam);

        assertEq(rig.team(), newTeam);
    }

    function test_setTeam_allowsZeroAddress() public {
        vm.prank(owner);
        rig.setTeam(address(0));

        assertEq(rig.team(), address(0));
    }

    function test_setTeam_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        rig.setTeam(alice);
    }

    function test_setUri_success() public {
        string memory newUri = "https://new.example.com/rig.json";

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit Rig__UriSet(newUri);
        rig.setUri(newUri);

        assertEq(rig.uri(), newUri);
    }

    function test_setUri_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        rig.setUri("https://hack.com");
    }

    /*----------  HALVING SCHEDULE TESTS  -------------------------------*/

    function test_halving_multiplePeriods() public {
        uint256 start = rig.startTime();
        assertEq(rig.getUps(), INITIAL_UPS);

        vm.warp(start + HALVING_PERIOD);
        assertEq(rig.getUps(), INITIAL_UPS >> 1); // INITIAL_UPS / 2

        vm.warp(start + HALVING_PERIOD * 2);
        assertEq(rig.getUps(), INITIAL_UPS >> 2); // INITIAL_UPS / 4

        vm.warp(start + HALVING_PERIOD * 3);
        assertEq(rig.getUps(), INITIAL_UPS >> 3); // INITIAL_UPS / 8

        vm.warp(start + HALVING_PERIOD * 4);
        assertEq(rig.getUps(), INITIAL_UPS >> 4); // INITIAL_UPS / 16
    }

    function test_halving_stopsAtTailUps() public {
        // Calculate how many halvings until we reach tailUps
        // INITIAL_UPS = 1e18, TAIL_UPS = 1e16
        // After 7 halvings: 1e18 >> 7 = 7.8125e15 < 1e16, so should be tail

        vm.warp(block.timestamp + HALVING_PERIOD * 7);
        assertEq(rig.getUps(), TAIL_UPS);

        // Even more halvings, still tailUps
        vm.warp(block.timestamp + HALVING_PERIOD * 10);
        assertEq(rig.getUps(), TAIL_UPS);
    }

    /*----------  FUZZ TESTS  -------------------------------------------*/

    function testFuzz_getPrice_linearDecay(uint256 timePassed) public {
        timePassed = bound(timePassed, 0, EPOCH_PERIOD);

        vm.warp(block.timestamp + timePassed);

        uint256 expectedPrice = MIN_INIT_PRICE - MIN_INIT_PRICE * timePassed / EPOCH_PERIOD;
        assertEq(rig.getPrice(), expectedPrice);
    }

    function testFuzz_mine_validInputs(uint256 mineTime, uint256 warpTime) public {
        mineTime = bound(mineTime, 0, EPOCH_PERIOD - 1);
        warpTime = bound(warpTime, 1, EPOCH_PERIOD);

        // First mine
        vm.warp(block.timestamp + mineTime);
        uint256 price = rig.getPrice();

        vm.startPrank(alice);
        weth.approve(address(rig), price);
        rig.mine(alice, 0, block.timestamp + 1, price, "");
        vm.stopPrank();

        assertEq(rig.epochMiner(), alice);
        assertEq(rig.epochId(), 1);
    }
}

/**
 * @title MockCore
 * @notice Simple mock for Core contract to return protocol fee address
 */
contract MockCore {
    address public protocolFeeAddress;

    constructor(address _protocolFeeAddress) {
        protocolFeeAddress = _protocolFeeAddress;
    }

    function setProtocolFeeAddress(address _protocolFeeAddress) external {
        protocolFeeAddress = _protocolFeeAddress;
    }
}
