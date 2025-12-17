// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Unit} from "../src/Unit.sol";

/**
 * @title UnitTest
 * @notice Tests for the Unit ERC20 token with permit and voting capabilities
 */
contract UnitTest is Test {
    Unit public unit;

    address public deployer;
    address public alice;
    address public bob;
    address public newRig;

    event Unit__Minted(address account, uint256 amount);
    event Unit__Burned(address account, uint256 amount);
    event Unit__RigSet(address indexed rig);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        newRig = makeAddr("newRig");

        vm.prank(deployer);
        unit = new Unit("Test Unit", "TU");
    }

    /*----------  CONSTRUCTOR TESTS  ------------------------------------*/

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(unit.name(), "Test Unit");
        assertEq(unit.symbol(), "TU");
    }

    function test_constructor_deployer_isInitialRig() public view {
        assertEq(unit.rig(), deployer);
    }

    function test_constructor_zeroInitialSupply() public view {
        assertEq(unit.totalSupply(), 0);
    }

    function test_constructor_hasDecimals18() public view {
        assertEq(unit.decimals(), 18);
    }

    /*----------  SET RIG TESTS  ----------------------------------------*/

    function test_setRig_success() public {
        vm.prank(deployer);
        vm.expectEmit(true, false, false, false);
        emit Unit__RigSet(newRig);
        unit.setRig(newRig);

        assertEq(unit.rig(), newRig);
    }

    function test_setRig_revertsIfNotCurrentRig() public {
        vm.prank(alice);
        vm.expectRevert(Unit.Unit__NotRig.selector);
        unit.setRig(newRig);
    }

    function test_setRig_revertsIfZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(Unit.Unit__InvalidRig.selector);
        unit.setRig(address(0));
    }

    function test_setRig_canBeCalledMultipleTimes() public {
        // First transfer
        vm.prank(deployer);
        unit.setRig(newRig);
        assertEq(unit.rig(), newRig);

        // Second transfer (from newRig)
        address anotherRig = makeAddr("anotherRig");
        vm.prank(newRig);
        unit.setRig(anotherRig);
        assertEq(unit.rig(), anotherRig);
    }

    /*----------  MINT TESTS  -------------------------------------------*/

    function test_mint_success() public {
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        vm.expectEmit(true, false, false, true);
        emit Unit__Minted(alice, amount);
        unit.mint(alice, amount);

        assertEq(unit.balanceOf(alice), amount);
        assertEq(unit.totalSupply(), amount);
    }

    function test_mint_revertsIfNotRig() public {
        vm.prank(alice);
        vm.expectRevert(Unit.Unit__NotRig.selector);
        unit.mint(alice, 1000 ether);
    }

    function test_mint_multipleAccounts() public {
        vm.startPrank(deployer);
        unit.mint(alice, 500 ether);
        unit.mint(bob, 300 ether);
        vm.stopPrank();

        assertEq(unit.balanceOf(alice), 500 ether);
        assertEq(unit.balanceOf(bob), 300 ether);
        assertEq(unit.totalSupply(), 800 ether);
    }

    function test_mint_zeroAmount() public {
        vm.prank(deployer);
        unit.mint(alice, 0);

        assertEq(unit.balanceOf(alice), 0);
        assertEq(unit.totalSupply(), 0);
    }

    function testFuzz_mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        // Limit amount to avoid ERC20Votes overflow (max ~2^208)
        amount = bound(amount, 0, type(uint208).max);

        vm.prank(deployer);
        unit.mint(to, amount);

        assertEq(unit.balanceOf(to), amount);
        assertEq(unit.totalSupply(), amount);
    }

    /*----------  BURN TESTS  -------------------------------------------*/

    function test_burn_success() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 400 ether;

        vm.prank(deployer);
        unit.mint(alice, mintAmount);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Unit__Burned(alice, burnAmount);
        unit.burn(burnAmount);

        assertEq(unit.balanceOf(alice), mintAmount - burnAmount);
        assertEq(unit.totalSupply(), mintAmount - burnAmount);
    }

    function test_burn_entireBalance() public {
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        vm.prank(alice);
        unit.burn(amount);

        assertEq(unit.balanceOf(alice), 0);
        assertEq(unit.totalSupply(), 0);
    }

    function test_burn_revertsIfInsufficientBalance() public {
        vm.prank(deployer);
        unit.mint(alice, 100 ether);

        vm.prank(alice);
        vm.expectRevert();
        unit.burn(200 ether);
    }

    function testFuzz_burn(uint256 mintAmount, uint256 burnAmount) public {
        // Limit amount to avoid ERC20Votes overflow
        mintAmount = bound(mintAmount, 0, type(uint208).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.prank(deployer);
        unit.mint(alice, mintAmount);

        vm.prank(alice);
        unit.burn(burnAmount);

        assertEq(unit.balanceOf(alice), mintAmount - burnAmount);
    }

    /*----------  ERC20 STANDARD TESTS  ---------------------------------*/

    function test_transfer_success() public {
        uint256 amount = 1000 ether;
        uint256 transferAmount = 300 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        vm.prank(alice);
        unit.transfer(bob, transferAmount);

        assertEq(unit.balanceOf(alice), amount - transferAmount);
        assertEq(unit.balanceOf(bob), transferAmount);
    }

    function test_approve_and_transferFrom() public {
        uint256 amount = 1000 ether;
        uint256 transferAmount = 300 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        vm.prank(alice);
        unit.approve(bob, transferAmount);

        vm.prank(bob);
        unit.transferFrom(alice, bob, transferAmount);

        assertEq(unit.balanceOf(alice), amount - transferAmount);
        assertEq(unit.balanceOf(bob), transferAmount);
    }

    /*----------  ERC20 VOTES TESTS  ------------------------------------*/

    function test_votes_selfDelegation() public {
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        // No votes until delegated
        assertEq(unit.getVotes(alice), 0);

        // Self delegate
        vm.prank(alice);
        unit.delegate(alice);

        assertEq(unit.getVotes(alice), amount);
    }

    function test_votes_delegation() public {
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        // Delegate to bob
        vm.prank(alice);
        unit.delegate(bob);

        assertEq(unit.getVotes(alice), 0);
        assertEq(unit.getVotes(bob), amount);
    }

    function test_votes_transferUpdatesVotes() public {
        uint256 amount = 1000 ether;
        uint256 transferAmount = 400 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        // Both delegate to themselves
        vm.prank(alice);
        unit.delegate(alice);
        vm.prank(bob);
        unit.delegate(bob);

        assertEq(unit.getVotes(alice), amount);
        assertEq(unit.getVotes(bob), 0);

        // Transfer
        vm.prank(alice);
        unit.transfer(bob, transferAmount);

        assertEq(unit.getVotes(alice), amount - transferAmount);
        assertEq(unit.getVotes(bob), transferAmount);
    }

    function test_votes_getPastVotes() public {
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        unit.mint(alice, amount);

        vm.prank(alice);
        unit.delegate(alice);

        // Roll forward to mine a new block and then query past
        vm.roll(block.number + 1);
        uint256 blockAfterDelegate = block.number - 1;

        assertEq(unit.getPastVotes(alice, blockAfterDelegate), amount);
    }

    /*----------  ERC20 PERMIT TESTS  -----------------------------------*/

    function test_permit_domainSeparator() public view {
        // Just verify it returns a non-zero value
        bytes32 domainSeparator = unit.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
    }

    function test_permit_nonces() public view {
        assertEq(unit.nonces(alice), 0);
    }

    function test_permit_success() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);
        uint256 amount = 1000 ether;

        vm.prank(deployer);
        unit.mint(signer, amount);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = unit.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                bob,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", unit.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        unit.permit(signer, bob, amount, deadline, v, r, s);

        assertEq(unit.allowance(signer, bob), amount);
        assertEq(unit.nonces(signer), 1);
    }
}
