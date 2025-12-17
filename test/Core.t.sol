// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {Core} from "../src/Core.sol";
import {Unit} from "../src/Unit.sol";
import {Rig} from "../src/Rig.sol";
import {Auction} from "../src/Auction.sol";
import {UnitFactory} from "../src/UnitFactory.sol";
import {RigFactory} from "../src/RigFactory.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";

/**
 * @title CoreTest
 * @notice Tests for the Core launchpad contract
 */
contract CoreTest is BaseTest {
    event Core__Launched(
        address launcher,
        address unit,
        address rig,
        address auction,
        address lpToken,
        string tokenName,
        string tokenSymbol,
        string uri,
        uint256 donutAmount,
        uint256 unitAmount,
        uint256 initialUps,
        uint256 tailUps,
        uint256 halvingPeriod,
        uint256 rigEpochPeriod,
        uint256 rigPriceMultiplier,
        uint256 rigMinInitPrice,
        uint256 auctionInitPrice,
        uint256 auctionEpochPeriod,
        uint256 auctionPriceMultiplier,
        uint256 auctionMinInitPrice
    );
    event Core__ProtocolFeeAddressSet(address protocolFeeAddress);
    event Core__MinDonutForLaunchSet(uint256 minDonutForLaunch);

    /*----------  CONSTRUCTOR TESTS  ------------------------------------*/

    function test_constructor_setsImmutables() public view {
        assertEq(core.weth(), address(weth));
        assertEq(core.donutToken(), address(donut));
        assertEq(core.uniswapV2Factory(), address(uniswapFactory));
        assertEq(core.uniswapV2Router(), address(uniswapRouter));
        assertEq(core.unitFactory(), address(unitFactory));
        assertEq(core.rigFactory(), address(rigFactory));
        assertEq(core.auctionFactory(), address(auctionFactory));
    }

    function test_constructor_setsInitialState() public view {
        assertEq(core.protocolFeeAddress(), protocolFeeAddress);
        assertEq(core.minDonutForLaunch(), MIN_DONUT_FOR_LAUNCH);
        assertEq(core.deployedRigsLength(), 0);
        assertEq(core.owner(), owner);
    }

    function test_constructor_revertsIfZeroAddress() public {
        vm.expectRevert(Core.Core__ZeroAddress.selector);
        new Core(
            address(0), // weth
            address(donut),
            address(uniswapFactory),
            address(uniswapRouter),
            address(unitFactory),
            address(rigFactory),
            address(auctionFactory),
            protocolFeeAddress,
            MIN_DONUT_FOR_LAUNCH
        );

        vm.expectRevert(Core.Core__ZeroAddress.selector);
        new Core(
            address(weth),
            address(0), // donut
            address(uniswapFactory),
            address(uniswapRouter),
            address(unitFactory),
            address(rigFactory),
            address(auctionFactory),
            protocolFeeAddress,
            MIN_DONUT_FOR_LAUNCH
        );

        vm.expectRevert(Core.Core__ZeroAddress.selector);
        new Core(
            address(weth),
            address(donut),
            address(0), // uniswapFactory
            address(uniswapRouter),
            address(unitFactory),
            address(rigFactory),
            address(auctionFactory),
            protocolFeeAddress,
            MIN_DONUT_FOR_LAUNCH
        );
    }

    /*----------  LAUNCH TESTS  -----------------------------------------*/

    function test_launch_success() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (address unit, address rig, address auction, address lp) = core.launch(params);
        vm.stopPrank();

        // Verify unit token
        assertEq(Unit(unit).name(), params.tokenName);
        assertEq(Unit(unit).symbol(), params.tokenSymbol);
        assertEq(Unit(unit).rig(), rig);

        // Verify rig
        assertEq(Rig(rig).unit(), unit);
        assertEq(Rig(rig).quote(), address(weth));
        assertEq(Rig(rig).treasury(), auction);
        assertEq(Rig(rig).team(), alice);
        assertEq(Rig(rig).owner(), alice);

        // Verify auction
        assertEq(Auction(auction).paymentToken(), lp);
        assertEq(Auction(auction).paymentReceiver(), core.DEAD_ADDRESS());

        // Verify LP creation
        assertTrue(lp != address(0));

        // Verify registry updates
        assertEq(core.deployedRigsLength(), 1);
        assertTrue(core.isDeployedRig(rig));
        assertEq(core.rigToLauncher(rig), alice);
        assertEq(core.rigToUnit(rig), unit);
        assertEq(core.rigToAuction(rig), auction);
        assertEq(core.rigToLP(rig), lp);
        assertEq(core.deployedRigs(0), rig);
    }

    function test_launch_emitsEvent() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);

        // Just check that the event is emitted with correct launcher
        vm.expectEmit(true, false, false, false);
        emit Core__Launched(
            alice,
            address(0), // we don't know addresses yet
            address(0),
            address(0),
            address(0),
            params.tokenName,
            params.tokenSymbol,
            params.uri,
            params.donutAmount,
            params.unitAmount,
            params.initialUps,
            params.tailUps,
            params.halvingPeriod,
            params.rigEpochPeriod,
            params.rigPriceMultiplier,
            params.rigMinInitPrice,
            params.auctionInitPrice,
            params.auctionEpochPeriod,
            params.auctionPriceMultiplier,
            params.auctionMinInitPrice
        );
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_transfersDonutFromLauncher() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        uint256 balanceBefore = donut.balanceOf(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        core.launch(params);
        vm.stopPrank();

        assertEq(donut.balanceOf(alice), balanceBefore - params.donutAmount);
    }

    function test_launch_burnsInitialLP() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (,,, address lp) = core.launch(params);
        vm.stopPrank();

        // LP tokens should be sent to dead address
        assertTrue(IERC20(lp).balanceOf(core.DEAD_ADDRESS()) > 0);
        assertEq(IERC20(lp).balanceOf(address(core)), 0);
    }

    function test_launch_revertsIfInvalidLauncher() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(address(0));

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        vm.expectRevert(Core.Core__InvalidLauncher.selector);
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_revertsIfInsufficientDonut() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.donutAmount = MIN_DONUT_FOR_LAUNCH - 1;

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        vm.expectRevert(Core.Core__InsufficientDonut.selector);
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_revertsIfEmptyTokenName() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.tokenName = "";

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        vm.expectRevert(Core.Core__EmptyTokenName.selector);
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_revertsIfEmptyTokenSymbol() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.tokenSymbol = "";

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        vm.expectRevert(Core.Core__EmptyTokenSymbol.selector);
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_revertsIfInvalidUnitAmount() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.unitAmount = 0;

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        vm.expectRevert(Core.Core__InvalidUnitAmount.selector);
        core.launch(params);
        vm.stopPrank();
    }

    function test_launch_multipleLaunches() public {
        // Launch first rig
        (address unit1, address rig1, address auction1, address lp1) = _launchRig(alice);

        // Launch second rig
        Core.LaunchParams memory params2 = _getDefaultLaunchParams(bob);
        params2.tokenName = "Second Token";
        params2.tokenSymbol = "ST";

        vm.startPrank(bob);
        donut.approve(address(core), params2.donutAmount);
        (address unit2, address rig2, address auction2, address lp2) = core.launch(params2);
        vm.stopPrank();

        // Verify both registered
        assertEq(core.deployedRigsLength(), 2);
        assertEq(core.deployedRigs(0), rig1);
        assertEq(core.deployedRigs(1), rig2);

        // Verify different addresses
        assertTrue(unit1 != unit2);
        assertTrue(rig1 != rig2);
        assertTrue(auction1 != auction2);
        assertTrue(lp1 != lp2);
    }

    function test_launch_rigOwnershipTransferred() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (, address rig,,) = core.launch(params);
        vm.stopPrank();

        // Alice should own the rig
        assertEq(Rig(rig).owner(), alice);

        // Alice can update rig settings
        vm.prank(alice);
        Rig(rig).setUri("new-uri");
        assertEq(Rig(rig).uri(), "new-uri");
    }

    function test_launch_unitMintingLockedToRig() public {
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);

        vm.startPrank(alice);
        donut.approve(address(core), params.donutAmount);
        (address unit, address rig,,) = core.launch(params);
        vm.stopPrank();

        // Rig is set as the minter
        assertEq(Unit(unit).rig(), rig);

        // Core cannot mint anymore
        vm.prank(address(core));
        vm.expectRevert(Unit.Unit__NotRig.selector);
        Unit(unit).mint(alice, 100 ether);

        // Alice cannot mint
        vm.prank(alice);
        vm.expectRevert(Unit.Unit__NotRig.selector);
        Unit(unit).mint(alice, 100 ether);
    }

    /*----------  OWNER FUNCTIONS  --------------------------------------*/

    function test_setProtocolFeeAddress_success() public {
        address newFeeAddress = makeAddr("newFeeAddress");

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit Core__ProtocolFeeAddressSet(newFeeAddress);
        core.setProtocolFeeAddress(newFeeAddress);

        assertEq(core.protocolFeeAddress(), newFeeAddress);
    }

    function test_setProtocolFeeAddress_allowsZero() public {
        vm.prank(owner);
        core.setProtocolFeeAddress(address(0));

        assertEq(core.protocolFeeAddress(), address(0));
    }

    function test_setProtocolFeeAddress_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        core.setProtocolFeeAddress(alice);
    }

    function test_setMinDonutForLaunch_success() public {
        uint256 newMin = 200 ether;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit Core__MinDonutForLaunchSet(newMin);
        core.setMinDonutForLaunch(newMin);

        assertEq(core.minDonutForLaunch(), newMin);
    }

    function test_setMinDonutForLaunch_allowsZero() public {
        vm.prank(owner);
        core.setMinDonutForLaunch(0);

        assertEq(core.minDonutForLaunch(), 0);

        // Now can launch with 0 donut
        Core.LaunchParams memory params = _getDefaultLaunchParams(alice);
        params.donutAmount = 0;
        params.unitAmount = 1000 ether;

        // This will fail because addLiquidity needs both amounts > 0
        // But it won't fail on the donut check
    }

    function test_setMinDonutForLaunch_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        core.setMinDonutForLaunch(200 ether);
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function test_deployedRigsLength() public {
        assertEq(core.deployedRigsLength(), 0);

        _launchRig(alice);
        assertEq(core.deployedRigsLength(), 1);

        _launchRig(bob);
        assertEq(core.deployedRigsLength(), 2);
    }

    /*----------  FUZZ TESTS  -------------------------------------------*/

    function testFuzz_launch_differentParams(
        uint256 donutAmount,
        uint256 unitAmount,
        uint256 initialUps,
        uint256 tailUps
    ) public {
        donutAmount = bound(donutAmount, MIN_DONUT_FOR_LAUNCH, 100000 ether);
        unitAmount = bound(unitAmount, 1, 100000 ether);
        initialUps = bound(initialUps, 1, 1e24);
        tailUps = bound(tailUps, 1, initialUps);

        Core.LaunchParams memory params = Core.LaunchParams({
            launcher: alice,
            tokenName: "Fuzz Token",
            tokenSymbol: "FT",
            uri: "https://fuzz.com",
            donutAmount: donutAmount,
            unitAmount: unitAmount,
            initialUps: initialUps,
            tailUps: tailUps,
            halvingPeriod: DEFAULT_HALVING_PERIOD,
            rigEpochPeriod: DEFAULT_RIG_EPOCH_PERIOD,
            rigPriceMultiplier: DEFAULT_RIG_PRICE_MULTIPLIER,
            rigMinInitPrice: DEFAULT_RIG_MIN_INIT_PRICE,
            auctionInitPrice: DEFAULT_AUCTION_INIT_PRICE,
            auctionEpochPeriod: DEFAULT_AUCTION_EPOCH_PERIOD,
            auctionPriceMultiplier: DEFAULT_AUCTION_PRICE_MULTIPLIER,
            auctionMinInitPrice: DEFAULT_AUCTION_MIN_INIT_PRICE
        });

        donut.mint(alice, donutAmount);

        vm.startPrank(alice);
        donut.approve(address(core), donutAmount);
        (address unit, address rig,,) = core.launch(params);
        vm.stopPrank();

        assertEq(Rig(rig).initialUps(), initialUps);
        assertEq(Rig(rig).tailUps(), tailUps);
    }
}
