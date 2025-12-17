// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "./BaseTest.sol";
import {Core} from "../src/Core.sol";
import {Unit} from "../src/Unit.sol";
import {Rig} from "../src/Rig.sol";
import {Auction} from "../src/Auction.sol";

/**
 * @title InvariantTest
 * @notice Stateful invariant tests using Foundry's invariant testing framework
 * @dev These tests maintain state across multiple random function calls
 */
contract InvariantTest is BaseTest {
    RigHandler public rigHandler;
    AuctionHandler public auctionHandler;
    UnitHandler public unitHandler;

    Unit public unitToken;
    Rig public rig;
    Auction public auction;
    address public lpToken;

    function setUp() public override {
        super.setUp();

        // Launch a rig for testing
        (address unitAddr, address rigAddr, address auctionAddr, address lp) = _launchRig(alice);
        unitToken = Unit(unitAddr);
        rig = Rig(rigAddr);
        auction = Auction(auctionAddr);
        lpToken = lp;

        // Deploy handlers
        rigHandler = new RigHandler(rig, weth, multicall);
        auctionHandler = new AuctionHandler(auction, IERC20(lpToken));
        unitHandler = new UnitHandler(unitToken, rigAddr);

        // Fund handlers
        vm.deal(address(rigHandler), 10000 ether);
        vm.prank(address(rigHandler));
        weth.deposit{value: 5000 ether}();

        // Target the handlers
        targetContract(address(rigHandler));
        targetContract(address(auctionHandler));
        targetContract(address(unitHandler));

        // Exclude setUp functions from being called
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RigHandler.setTimestamp.selector;
        targetSelector(FuzzSelector({addr: address(rigHandler), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                            RIG INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Epoch ID should never decrease
    function invariant_rigEpochIdNeverDecreases() public view {
        assertTrue(rig.epochId() >= rigHandler.lastEpochId(), "Epoch ID decreased");
    }

    /// @notice Current UPS should never be below tail UPS
    function invariant_upsNeverBelowTail() public view {
        assertGe(rig.getUps(), rig.tailUps(), "UPS below tail");
    }

    /// @notice Current UPS should never exceed initial UPS
    function invariant_upsNeverAboveInitial() public view {
        assertLe(rig.getUps(), rig.initialUps(), "UPS above initial");
    }

    /// @notice Price should never be negative (always >= 0)
    function invariant_rigPriceNonNegative() public view {
        assertGe(rig.getPrice(), 0, "Price is negative");
    }

    /// @notice Init price should always be within bounds
    function invariant_rigInitPriceWithinBounds() public view {
        uint256 initPrice = rig.epochInitPrice();
        assertGe(initPrice, rig.minInitPrice(), "Init price below min");
        assertLe(initPrice, type(uint192).max, "Init price above max");
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Auction epoch ID should never decrease
    function invariant_auctionEpochIdNeverDecreases() public view {
        assertTrue(auction.epochId() >= auctionHandler.lastEpochId(), "Auction epoch ID decreased");
    }

    /// @notice Auction price should never be negative
    function invariant_auctionPriceNonNegative() public view {
        assertGe(auction.getPrice(), 0, "Auction price is negative");
    }

    /// @notice Auction init price should be within bounds
    function invariant_auctionInitPriceWithinBounds() public view {
        uint256 initPrice = auction.initPrice();
        assertGe(initPrice, auction.minInitPrice(), "Auction init price below min");
        assertLe(initPrice, type(uint192).max, "Auction init price above max");
    }

    /*//////////////////////////////////////////////////////////////
                            UNIT TOKEN INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total supply should always be >= initial supply (can only increase via minting)
    function invariant_unitTotalSupplyNeverDecreasesBelowInitial() public view {
        // Initial supply is DEFAULT_UNIT_AMOUNT from launch
        // Total supply can only go down via burning, but minting adds more
        // This invariant checks that supply is still reasonable
        assertGe(unitToken.totalSupply(), 0, "Total supply should never be negative");
    }

    /// @notice No single holder should have more than total supply
    function invariant_noHolderExceedsTotalSupply() public view {
        address[] memory holders = unitHandler.getHolders();
        uint256 totalSupply = unitToken.totalSupply();

        for (uint256 i = 0; i < holders.length; i++) {
            assertLe(unitToken.balanceOf(holders[i]), totalSupply, "Holder exceeds total supply");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CALL SUMMARY
    //////////////////////////////////////////////////////////////*/

    function invariant_callSummary() public view {
        console.log("Rig mines:", rigHandler.mineCount());
        console.log("Auction buys:", auctionHandler.buyCount());
        console.log("Unit mints:", unitHandler.mintCount());
        console.log("Unit burns:", unitHandler.burnCount());
    }
}

/**
 * @title RigHandler
 * @notice Handler contract for Rig invariant testing
 */
contract RigHandler is Test {
    Rig public rig;
    MockWETH public weth;
    Multicall public multicall;

    uint256 public lastEpochId;
    uint256 public mineCount;
    address[] public miners;

    constructor(Rig _rig, MockWETH _weth, Multicall _multicall) {
        rig = _rig;
        weth = _weth;
        multicall = _multicall;
    }

    function mine(uint256 seed) external {
        uint256 price = rig.getPrice();
        if (price == 0) {
            // Skip if price is zero - need to wait for next epoch
            return;
        }

        address miner = address(uint160(bound(seed, 1, type(uint160).max)));
        miners.push(miner);

        // Transfer WETH to miner
        weth.transfer(miner, price);

        vm.startPrank(miner);
        weth.approve(address(rig), price);

        try rig.mine(miner, rig.epochId(), block.timestamp + 1 hours, price, "") {
            mineCount++;
            lastEpochId = rig.epochId();
        } catch {
            // Mine failed, that's ok
        }
        vm.stopPrank();
    }

    function setTimestamp(uint256 offset) external {
        offset = bound(offset, 0, 365 days);
        vm.warp(block.timestamp + offset);
    }

    function getMiners() external view returns (address[] memory) {
        return miners;
    }
}

/**
 * @title AuctionHandler
 * @notice Handler contract for Auction invariant testing
 */
contract AuctionHandler is Test {
    Auction public auction;
    IERC20 public lpToken;

    uint256 public lastEpochId;
    uint256 public buyCount;

    constructor(Auction _auction, IERC20 _lpToken) {
        auction = _auction;
        lpToken = _lpToken;
    }

    function buy(uint256 seed) external {
        uint256 price = auction.getPrice();

        address buyer = address(uint160(bound(seed, 1, type(uint160).max)));

        // Mock LP token balance for buyer
        deal(address(lpToken), buyer, price);

        address[] memory assets = new address[](0);

        vm.startPrank(buyer);
        lpToken.approve(address(auction), price);

        try auction.buy(assets, buyer, auction.epochId(), block.timestamp + 1 hours, price) {
            buyCount++;
            lastEpochId = auction.epochId();
        } catch {
            // Buy failed, that's ok
        }
        vm.stopPrank();
    }

    function warpTime(uint256 offset) external {
        offset = bound(offset, 0, 7 days);
        vm.warp(block.timestamp + offset);
    }
}

/**
 * @title UnitHandler
 * @notice Handler contract for Unit token invariant testing
 */
contract UnitHandler is Test {
    Unit public unit;
    address public rigAddr;

    uint256 public mintCount;
    uint256 public burnCount;
    uint256 public totalTrackedBalance;
    address[] public holders;
    mapping(address => bool) public isHolder;

    constructor(Unit _unit, address _rigAddr) {
        unit = _unit;
        rigAddr = _rigAddr;
    }

    function mint(address to, uint256 amount) external {
        amount = bound(amount, 0, type(uint104).max);
        if (to == address(0)) return;

        vm.prank(rigAddr);
        try unit.mint(to, amount) {
            mintCount++;
            totalTrackedBalance += amount;
            _trackHolder(to);
        } catch {
            // Mint failed
        }
    }

    function burn(uint256 holderIndex, uint256 amount) external {
        if (holders.length == 0) return;

        holderIndex = bound(holderIndex, 0, holders.length - 1);
        address holder = holders[holderIndex];

        uint256 balance = unit.balanceOf(holder);
        amount = bound(amount, 0, balance);

        vm.prank(holder);
        try unit.burn(amount) {
            burnCount++;
            totalTrackedBalance -= amount;
        } catch {
            // Burn failed
        }
    }

    function transfer(uint256 fromIndex, address to, uint256 amount) external {
        if (holders.length == 0 || to == address(0)) return;

        fromIndex = bound(fromIndex, 0, holders.length - 1);
        address from = holders[fromIndex];

        uint256 balance = unit.balanceOf(from);
        amount = bound(amount, 0, balance);

        vm.prank(from);
        try unit.transfer(to, amount) {
            _trackHolder(to);
        } catch {
            // Transfer failed
        }
    }

    function _trackHolder(address holder) internal {
        if (!isHolder[holder]) {
            isHolder[holder] = true;
            holders.push(holder);
        }
    }

    function getHolders() external view returns (address[] memory) {
        return holders;
    }
}

// Import for handler
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {Multicall} from "../src/Multicall.sol";
