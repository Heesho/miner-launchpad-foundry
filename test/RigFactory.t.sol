// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Rig} from "../src/Rig.sol";
import {RigFactory} from "../src/RigFactory.sol";
import {Unit} from "../src/Unit.sol";
import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title RigFactoryTest
 * @notice Tests for the RigFactory contract
 */
contract RigFactoryTest is Test {
    RigFactory public factory;
    Unit public unit;
    MockToken public weth;

    address public deployer;
    address public treasury;
    address public team;
    address public core;

    // Test parameters
    uint256 public constant INITIAL_UPS = 1e18;
    uint256 public constant TAIL_UPS = 1e16;
    uint256 public constant HALVING_PERIOD = 365 days;
    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 1.5e18;
    uint256 public constant MIN_INIT_PRICE = 1e15;

    function setUp() public {
        deployer = makeAddr("deployer");
        treasury = makeAddr("treasury");
        team = makeAddr("team");
        core = makeAddr("core");

        factory = new RigFactory();
        weth = new MockToken("Wrapped ETH", "WETH");

        vm.prank(deployer);
        unit = new Unit("Test Unit", "TU");
    }

    /*----------  DEPLOY TESTS  -----------------------------------------*/

    function test_deploy_createsRig() public {
        vm.prank(deployer);
        address rigAddr = factory.deploy(
            address(unit),
            address(weth),
            treasury,
            team,
            core,
            "https://example.com/rig.json",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        Rig rig = Rig(rigAddr);
        assertEq(rig.unit(), address(unit));
        assertEq(rig.quote(), address(weth));
        assertEq(rig.treasury(), treasury);
        assertEq(rig.team(), team);
        assertEq(rig.core(), core);
        assertEq(rig.uri(), "https://example.com/rig.json");
        assertEq(rig.initialUps(), INITIAL_UPS);
        assertEq(rig.tailUps(), TAIL_UPS);
        assertEq(rig.halvingPeriod(), HALVING_PERIOD);
        assertEq(rig.epochPeriod(), EPOCH_PERIOD);
        assertEq(rig.priceMultiplier(), PRICE_MULTIPLIER);
        assertEq(rig.minInitPrice(), MIN_INIT_PRICE);
    }

    function test_deploy_transfersOwnershipToCaller() public {
        vm.prank(deployer);
        address rigAddr = factory.deploy(
            address(unit),
            address(weth),
            treasury,
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        Rig rig = Rig(rigAddr);
        assertEq(rig.owner(), deployer);
    }

    function test_deploy_differentAddresses() public {
        vm.startPrank(deployer);

        address rig1 = factory.deploy(
            address(unit),
            address(weth),
            treasury,
            team,
            core,
            "rig1",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        Unit unit2 = new Unit("Test Unit 2", "TU2");
        address rig2 = factory.deploy(
            address(unit2),
            address(weth),
            treasury,
            team,
            core,
            "rig2",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        vm.stopPrank();

        assertTrue(rig1 != rig2);
    }

    function test_deploy_withMinValues() public {
        vm.prank(deployer);
        address rigAddr = factory.deploy(
            address(unit),
            address(weth),
            treasury,
            team,
            core,
            "",
            1, // minimum initialUps
            1, // minimum tailUps
            1 days, // MIN_HALVING_PERIOD
            10 minutes, // MIN_EPOCH_PERIOD
            1.1e18, // MIN_PRICE_MULTIPLIER
            1e6 // ABS_MIN_INIT_PRICE
        );

        Rig rig = Rig(rigAddr);
        assertEq(rig.initialUps(), 1);
        assertEq(rig.tailUps(), 1);
        assertEq(rig.halvingPeriod(), 1 days);
        assertEq(rig.epochPeriod(), 10 minutes);
        assertEq(rig.priceMultiplier(), 1.1e18);
        assertEq(rig.minInitPrice(), 1e6);
    }

    function test_deploy_withMaxValues() public {
        uint256 maxInitPrice = type(uint192).max;

        vm.prank(deployer);
        address rigAddr = factory.deploy(
            address(unit),
            address(weth),
            treasury,
            team,
            core,
            "",
            1e24, // MAX_INITIAL_UPS
            1, // tailUps
            365 days * 100, // large halving period
            365 days, // MAX_EPOCH_PERIOD
            3e18, // MAX_PRICE_MULTIPLIER
            maxInitPrice
        );

        Rig rig = Rig(rigAddr);
        assertEq(rig.initialUps(), 1e24);
        assertEq(rig.epochPeriod(), 365 days);
        assertEq(rig.priceMultiplier(), 3e18);
        assertEq(rig.minInitPrice(), maxInitPrice);
    }

    function test_deploy_revertsOnInvalidParams() public {
        // Invalid unit
        vm.expectRevert(Rig.Rig__InvalidUnit.selector);
        factory.deploy(
            address(0),
            address(weth),
            treasury,
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Invalid quote
        vm.expectRevert(Rig.Rig__InvalidQuote.selector);
        factory.deploy(
            address(unit),
            address(0),
            treasury,
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Invalid treasury
        vm.expectRevert(Rig.Rig__InvalidTreasury.selector);
        factory.deploy(
            address(unit),
            address(weth),
            address(0),
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Invalid team
        vm.expectRevert(Rig.Rig__InvalidTeam.selector);
        factory.deploy(
            address(unit),
            address(weth),
            treasury,
            address(0),
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        // Invalid core
        vm.expectRevert(Rig.Rig__InvalidCore.selector);
        factory.deploy(
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

    function test_deploy_differentCallersGetOwnership() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        Unit aliceUnit = new Unit("Alice Unit", "AU");
        Unit bobUnit = new Unit("Bob Unit", "BU");

        vm.prank(alice);
        address rig1Addr = factory.deploy(
            address(aliceUnit),
            address(weth),
            treasury,
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        vm.prank(bob);
        address rig2Addr = factory.deploy(
            address(bobUnit),
            address(weth),
            treasury,
            team,
            core,
            "",
            INITIAL_UPS,
            TAIL_UPS,
            HALVING_PERIOD,
            EPOCH_PERIOD,
            PRICE_MULTIPLIER,
            MIN_INIT_PRICE
        );

        Rig rig1 = Rig(rig1Addr);
        Rig rig2 = Rig(rig2Addr);

        assertEq(rig1.owner(), alice);
        assertEq(rig2.owner(), bob);
    }
}
