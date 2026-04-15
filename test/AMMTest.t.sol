// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "../src/LPToken.sol";
import "../src/MyToken.sol";

contract AMMTest is Test {
    AMM     public amm;
    MyToken public tokenA;
    MyToken public tokenB;

    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint256 constant INITIAL = 1_000_000 ether;

    function setUp() public {
        tokenA = new MyToken("Token A", "TKA", INITIAL);
        tokenB = new MyToken("Token B", "TKB", INITIAL);
        amm    = new AMM(address(tokenA), address(tokenB));

        tokenA.transfer(alice, 100_000 ether);
        tokenB.transfer(alice, 100_000 ether);
        tokenA.transfer(bob,   100_000 ether);
        tokenB.transfer(bob,   100_000 ether);
        tokenA.transfer(carol, 100_000 ether);
        tokenB.transfer(carol, 100_000 ether);
    }

    // TEST 1: First liquidity provider
    function testAddLiquidityFirst() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        uint256 lp = amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        assertGt(lp, 0);
        assertEq(amm.lpToken().balanceOf(alice), lp);
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(rA, 10_000 ether);
        assertEq(rB, 10_000 ether);
    }

    // TEST 2: Second liquidity provider
    function testAddLiquiditySubsequent() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 5_000 ether);
        tokenB.approve(address(amm), 5_000 ether);
        uint256 lpBob = amm.addLiquidity(5_000 ether, 5_000 ether, 0);
        vm.stopPrank();

        assertGt(lpBob, 0);
        assertEq(amm.lpToken().balanceOf(bob), lpBob);
    }

    // TEST 3: Remove liquidity partial
    function testRemoveLiquidityPartial() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        uint256 lp = amm.addLiquidity(10_000 ether, 10_000 ether, 0);

        uint256 half = lp / 2;
        amm.lpToken().approve(address(amm), half);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(half, 0, 0);
        vm.stopPrank();

        assertGt(outA, 0);
        assertGt(outB, 0);
    }

    // TEST 4: Remove liquidity full
    function testRemoveLiquidityFull() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        uint256 lp = amm.addLiquidity(10_000 ether, 10_000 ether, 0);

        amm.lpToken().approve(address(amm), lp);
        amm.removeLiquidity(lp, 0, 0);
        vm.stopPrank();

        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(rA, 0);
        assertEq(rB, 0);
    }

    // TEST 5: Swap A -> B
    function testSwapAtoB() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 ether);
        uint256 out = amm.swap(address(tokenA), 100 ether, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertGt(tokenB.balanceOf(bob), 100_000 ether);
    }

    // TEST 6: Swap B -> A
    function testSwapBtoA() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenB.approve(address(amm), 100 ether);
        uint256 out = amm.swap(address(tokenB), 100 ether, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertGt(tokenA.balanceOf(bob), 100_000 ether);
    }

    // TEST 7: k stays constant or increases after swap
    function testKInvariantAfterSwap() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        (uint256 rA0, uint256 rB0) = amm.getReserves();
        uint256 kBefore = rA0 * rB0;

        vm.startPrank(bob);
        tokenA.approve(address(amm), 500 ether);
        amm.swap(address(tokenA), 500 ether, 0);
        vm.stopPrank();

        (uint256 rA1, uint256 rB1) = amm.getReserves();
        uint256 kAfter = rA1 * rB1;

        assertGe(kAfter, kBefore, "k must not decrease after swap");
    }

    // TEST 8: Slippage protection reverts
    function testSlippageProtection() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), 100 ether);
        vm.expectRevert();
        amm.swap(address(tokenA), 100 ether, type(uint256).max);
        vm.stopPrank();
    }

    // TEST 9: Zero amount reverts on addLiquidity
    function testRevertAddLiquidityZero() public {
        vm.startPrank(alice);
        vm.expectRevert();
        amm.addLiquidity(0, 1000 ether, 0);
        vm.stopPrank();
    }

    // TEST 10: Zero amount reverts on swap
    function testRevertSwapZero() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert();
        amm.swap(address(tokenA), 0, 0);
        vm.stopPrank();
    }

    // TEST 11: Invalid token reverts
    function testRevertInvalidToken() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert();
        amm.swap(address(0xdead), 100 ether, 0);
        vm.stopPrank();
    }

    // TEST 12: Large swap causes high price impact
    function testLargeSwapPriceImpact() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        uint256 smallOut = amm.getAmountOut(100 ether, 10_000 ether, 10_000 ether);
        uint256 largeOut = amm.getAmountOut(5_000 ether, 10_000 ether, 10_000 ether);

        assertLt(largeOut * 100 / 5_000 ether, smallOut * 100 / 100 ether);
    }

    // TEST 13: getAmountOut with 0.3% fee
    function testGetAmountOutFee() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        uint256 out = amm.getAmountOut(1000 ether, 10_000 ether, 10_000 ether);
        assertGt(out, 0);
        assertLt(out, 1000 ether);
    }

    // TEST 14: Removing more LP than owned reverts
    function testRevertRemoveTooMuchLP() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        uint256 lp = amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        amm.lpToken().approve(address(amm), lp + 1);
        vm.expectRevert();
        amm.removeLiquidity(lp + 1, 0, 0);
        vm.stopPrank();
    }

    // TEST 15: Events emitted correctly
    function testEventsEmitted() public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        vm.expectEmit(true, false, false, false);
        emit AMM.LiquidityAdded(alice, 10_000 ether, 10_000 ether, 0);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();
    }

    // FUZZ TEST: Swap amount
    function testFuzzSwap(uint256 amountIn) public {
        vm.startPrank(alice);
        tokenA.approve(address(amm), 10_000 ether);
        tokenB.approve(address(amm), 10_000 ether);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);
        vm.stopPrank();

        amountIn = bound(amountIn, 1 ether, 5_000 ether);

        vm.startPrank(bob);
        tokenA.approve(address(amm), amountIn);
        uint256 out = amm.swap(address(tokenA), amountIn, 0);
        vm.stopPrank();

        assertGt(out, 0);

        (uint256 rA, uint256 rB) = amm.getReserves();
        assertGt(rA * rB, 10_000 ether * 10_000 ether - 1);
    }
}