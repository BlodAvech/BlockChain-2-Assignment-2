// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken public token;
    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant INITIAL_SUPPLY = 100_000 * 10 ** 18;

    function setUp() public {
        owner   = makeAddr("owner");
        alice   = makeAddr("alice");
        bob     = makeAddr("bob");
        charlie = makeAddr("charlie");

        vm.prank(owner);
        token = new MyToken("MyToken", "MTK", INITIAL_SUPPLY);
    }

    function testTokenName() public view {
        assertEq(token.name(), "MyToken");
    }

    function testTokenSymbol() public view {
        assertEq(token.symbol(), "MTK");
    }

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testOwnerHasInitialBalance() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function testTransfer() public {
        vm.prank(owner);
        token.transfer(alice, 1000 * 10 ** 18);
        assertEq(token.balanceOf(alice), 1000 * 10 ** 18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 1000 * 10 ** 18);
    }

    function testTransferEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(owner, alice, 500 * 10 ** 18);
        vm.prank(owner);
        token.transfer(alice, 500 * 10 ** 18);
    }

    function testRevertTransferInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1);
    }

    function testApproveAndTransferFrom() public {
        vm.prank(owner);
        token.approve(alice, 1000 * 10 ** 18);
        vm.prank(alice);
        token.transferFrom(owner, bob, 600 * 10 ** 18);
        assertEq(token.balanceOf(bob), 600 * 10 ** 18);
        assertEq(token.allowance(owner, alice), 400 * 10 ** 18);
    }

    function testRevertTransferFromExceedsAllowance() public {
        vm.prank(owner);
        token.approve(alice, 100);
        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(owner, bob, 101);
    }

    function testMintByOwner() public {
        vm.prank(owner);
        token.mint(alice, 5000 * 10 ** 18);
        assertEq(token.balanceOf(alice), 5000 * 10 ** 18);
    }

    function testRevertMintByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(bob, 1000);
    }

    function testBurn() public {
        vm.prank(owner);
        token.burn(1000 * 10 ** 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - 1000 * 10 ** 18);
    }

    function testRevertBurnMoreThanBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.burn(1);
    }

    function testTransferZeroAmount() public {
        vm.prank(owner);
        token.transfer(alice, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApproveOverwritesAllowance() public {
        vm.prank(owner);
        token.approve(alice, 1000);
        vm.prank(owner);
        token.approve(alice, 500);
        assertEq(token.allowance(owner, alice), 500);
    }

    // FUZZ TEST 1
    function testFuzzTransfer(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(recipient != owner);
        amount = bound(amount, 1, INITIAL_SUPPLY);

        vm.prank(owner);
        token.transfer(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    // FUZZ TEST 2
    function testFuzzApproveAndTransferFrom(
        uint256 approveAmt,
        uint256 sendAmt
    ) public {
        vm.prank(owner);
        token.transfer(alice, INITIAL_SUPPLY / 2);

        approveAmt = bound(approveAmt, 0, INITIAL_SUPPLY / 2);
        sendAmt    = bound(sendAmt, 0, approveAmt);

        vm.prank(alice);
        token.approve(bob, approveAmt);

        vm.prank(bob);
        token.transferFrom(alice, charlie, sendAmt);

        assertEq(token.balanceOf(charlie), sendAmt);
        assertEq(token.allowance(alice, bob), approveAmt - sendAmt);
    }
}