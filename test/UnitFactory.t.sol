// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Unit} from "../src/Unit.sol";
import {UnitFactory} from "../src/UnitFactory.sol";

/**
 * @title UnitFactoryTest
 * @notice Tests for the UnitFactory contract
 */
contract UnitFactoryTest is Test {
    UnitFactory public factory;

    address public deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        factory = new UnitFactory();
    }

    /*----------  DEPLOY TESTS  -----------------------------------------*/

    function test_deploy_createsUnitToken() public {
        address unitAddr = factory.deploy("Test Token", "TT");

        Unit unit = Unit(unitAddr);
        assertEq(unit.name(), "Test Token");
        assertEq(unit.symbol(), "TT");
    }

    function test_deploy_setsCallerAsRig() public {
        vm.prank(deployer);
        address unitAddr = factory.deploy("Test Token", "TT");

        Unit unit = Unit(unitAddr);
        // Factory calls setRig(msg.sender) after deployment
        assertEq(unit.rig(), deployer);
    }

    function test_deploy_differentAddressesPerDeploy() public {
        address unit1 = factory.deploy("Token 1", "T1");
        address unit2 = factory.deploy("Token 2", "T2");

        assertTrue(unit1 != unit2);
    }

    function test_deploy_emptyNameWorks() public {
        // Empty name is allowed at contract level
        address unitAddr = factory.deploy("", "TT");
        Unit unit = Unit(unitAddr);
        assertEq(unit.name(), "");
    }

    function test_deploy_emptySymbolWorks() public {
        // Empty symbol is allowed at contract level
        address unitAddr = factory.deploy("Test Token", "");
        Unit unit = Unit(unitAddr);
        assertEq(unit.symbol(), "");
    }

    function test_deploy_callerCanMint() public {
        vm.startPrank(deployer);
        address unitAddr = factory.deploy("Test Token", "TT");
        Unit unit = Unit(unitAddr);

        // Deployer should be able to mint since they're the rig
        unit.mint(deployer, 1000 ether);
        assertEq(unit.balanceOf(deployer), 1000 ether);
        vm.stopPrank();
    }

    function test_deploy_differentCallersGetDifferentPermissions() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.prank(alice);
        address unit1Addr = factory.deploy("Token 1", "T1");

        vm.prank(bob);
        address unit2Addr = factory.deploy("Token 2", "T2");

        Unit unit1 = Unit(unit1Addr);
        Unit unit2 = Unit(unit2Addr);

        // Alice can only mint on unit1
        vm.prank(alice);
        unit1.mint(alice, 100 ether);

        // Alice cannot mint on unit2
        vm.prank(alice);
        vm.expectRevert(Unit.Unit__NotRig.selector);
        unit2.mint(alice, 100 ether);

        // Bob can only mint on unit2
        vm.prank(bob);
        unit2.mint(bob, 100 ether);

        // Bob cannot mint on unit1
        vm.prank(bob);
        vm.expectRevert(Unit.Unit__NotRig.selector);
        unit1.mint(bob, 100 ether);
    }

    function testFuzz_deploy_anyName(string memory name) public {
        address unitAddr = factory.deploy(name, "TT");
        Unit unit = Unit(unitAddr);
        assertEq(unit.name(), name);
    }

    function testFuzz_deploy_anySymbol(string memory symbol) public {
        address unitAddr = factory.deploy("Test", symbol);
        Unit unit = Unit(unitAddr);
        assertEq(unit.symbol(), symbol);
    }
}
