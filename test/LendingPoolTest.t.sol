// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/MyToken.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    MyToken     public token;

    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");
    address public liquidator = makeAddr("liquidator");

    uint256 constant INITIAL = 1_000_000 ether;

    function setUp() public {
        token = new MyToken("Test Token", "TST", INITIAL);
        pool  = new LendingPool(address(token));

        token.transfer(alice,     100_000 ether);
        token.transfer(bob,       100_000 ether);
        token.transfer(liquidator, 50_000 ether);
        // Give pool some tokens for lending
        token.transfer(address(pool), 500_000 ether);
    }

    // TEST 1: Deposit works
    function testDeposit() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        vm.stopPrank();

        (uint256 deposited,,) = pool.positions(alice);
        assertEq(deposited, 10_000 ether);
    }

    // TEST 2: Withdraw works
    function testWithdraw() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.withdraw(5_000 ether);
        vm.stopPrank();

        (uint256 deposited,,) = pool.positions(alice);
        assertEq(deposited, 5_000 ether);
    }

    // TEST 3: Borrow within LTV
    function testBorrowWithinLTV() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(7_000 ether); // 70% LTV, within 75%
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 97_000 ether);
    }

    // TEST 4: Borrow exceeds LTV reverts
    function testRevertBorrowExceedsLTV() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        vm.expectRevert();
        pool.borrow(8_000 ether); // 80% LTV, exceeds 75%
        vm.stopPrank();
    }

    // TEST 5: Borrow with no collateral reverts
    function testRevertBorrowNoCollateral() public {
        vm.startPrank(alice);
        vm.expectRevert();
        pool.borrow(1_000 ether);
        vm.stopPrank();
    }

    // TEST 6: Repay full debt
    function testRepayFull() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(5_000 ether);

        token.approve(address(pool), 5_000 ether);
        pool.repay(5_000 ether);
        vm.stopPrank();

        assertEq(pool.getDebt(alice), 0);
    }

    // TEST 7: Repay partial debt
    function testRepayPartial() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(5_000 ether);

        token.approve(address(pool), 2_000 ether);
        pool.repay(2_000 ether);
        vm.stopPrank();

        uint256 debt = pool.getDebt(alice);
        assertGt(debt, 0);
        assertLt(debt, 5_000 ether);
    }

    // TEST 8: Liquidation works after price drop (simulated by warping time)
    function testLiquidation() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(7_500 ether); // exactly 75% LTV
        vm.stopPrank();

        // Warp time to accrue interest and push LTV above 80%
        vm.warp(block.timestamp + 365 days * 2);

        uint256 debt = pool.getDebt(alice);
        uint256 ltv  = debt * 100 / 10_000 ether;
        assertGe(ltv, 80, "LTV should be above 80% after interest");

        vm.startPrank(liquidator);
        token.approve(address(pool), debt);
        pool.liquidate(alice);
        vm.stopPrank();

        (uint256 deposited,,) = pool.positions(alice);
        assertEq(deposited, 0);
    }

    // TEST 9: Healthy position cannot be liquidated
    function testRevertLiquidateHealthyPosition() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(5_000 ether); // 50% LTV, healthy
        vm.stopPrank();

        vm.startPrank(liquidator);
        token.approve(address(pool), 5_000 ether);
        vm.expectRevert();
        pool.liquidate(alice);
        vm.stopPrank();
    }

    // TEST 10: Interest accrual over time
    function testInterestAccrual() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(5_000 ether);
        vm.stopPrank();

        uint256 debtAtStart = pool.getDebt(alice);

        vm.warp(block.timestamp + 365 days);

        uint256 debtAfterYear = pool.getDebt(alice);
        assertGt(debtAfterYear, debtAtStart, "Debt should grow over time");

        // 5% annual rate: 5000 * 5% = 250 interest
        uint256 interest = debtAfterYear - debtAtStart;
        assertApproxEqRel(interest, 250 ether, 0.01e18);
    }

    // TEST 11: Withdraw while having outstanding debt fails if health drops
    function testRevertWithdrawWithDebt() public {
        vm.startPrank(alice);
        token.approve(address(pool), 10_000 ether);
        pool.deposit(10_000 ether);
        pool.borrow(7_000 ether);
        vm.expectRevert();
        pool.withdraw(5_000 ether); 
        vm.stopPrank();
    }

    // TEST 12: Deposit zero reverts
    function testRevertDepositZero() public {
        vm.startPrank(alice);
        vm.expectRevert();
        pool.deposit(0);
        vm.stopPrank();
    }
}