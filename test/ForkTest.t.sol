// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

contract ForkTest is Test {
    address constant USDC    = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH    = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ROUTER  = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address constant WHALE   = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("ETH_RPC_URL"), 19_000_000);
        vm.selectFork(mainnetFork);
    }

    // TEST 1: Read real USDC total supply
    function testUSDCTotalSupply() public view {
        uint256 supply = IERC20(USDC).totalSupply();
        // USDC has 6 decimals, supply should be in billions
        assertGt(supply, 1_000_000_000 * 1e6, "USDC supply should be over 1 billion");
        console.log("USDC Total Supply:", supply / 1e6, "USDC");
    }

    // TEST 2: Read USDC balance of whale
    function testWhaleHasUSDC() public view {
        uint256 balance = IERC20(USDC).balanceOf(WHALE);
        assertGt(balance, 0, "Whale should have USDC");
        console.log("Whale USDC balance:", balance / 1e6, "USDC");
    }

    // TEST 3: Simulate Uniswap V2 swap USDC -> WETH
    function testUniswapV2Swap() public {
        uint256 amountIn = 10_000 * 1e6; // 10,000 USDC

        vm.startPrank(WHALE);

        IERC20(USDC).approve(ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint256[] memory expected = IUniswapV2Router(ROUTER).getAmountsOut(amountIn, path);
        console.log("Expected WETH out:", expected[1]);

        uint256 wethBefore = IERC20(WETH).balanceOf(WHALE);

        IUniswapV2Router(ROUTER).swapExactTokensForTokens(
            amountIn,
            expected[1] * 95 / 100, // 5% slippage tolerance
            path,
            WHALE,
            block.timestamp + 300
        );

        uint256 wethAfter = IERC20(WETH).balanceOf(WHALE);

        assertGt(wethAfter, wethBefore, "WETH balance should increase after swap");
        console.log("WETH received:", wethAfter - wethBefore);

        vm.stopPrank();
    }

    // TEST 4: vm.rollFork — change block number
    function testRollFork() public {
        uint256 blockBefore = block.number;
        assertEq(blockBefore, 19_000_000);

        vm.rollFork(19_000_100);
        assertEq(block.number, 19_000_100);

        console.log("Rolled from block", blockBefore, "to", block.number);
    }
}