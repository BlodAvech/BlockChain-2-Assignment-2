// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LendingPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 public constant LTV             = 75;   // 75% max borrow
    uint256 public constant LIQUIDATION_LTV = 80;   // liquidate above 80%
    uint256 public constant INTEREST_RATE   = 5;    // 5% per year
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct Position {
        uint256 deposited;
        uint256 borrowed;
        uint256 borrowTimestamp;
    }

    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 amount);

    constructor(address _token) {
        require(_token != address(0), "Zero address");
        token = IERC20(_token);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        token.safeTransferFrom(msg.sender, address(this), amount);
        positions[msg.sender].deposited += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        require(amount > 0, "Zero amount");
        require(pos.deposited >= amount, "Insufficient deposit");

        uint256 debt = getDebt(msg.sender);
        uint256 remainingDeposit = pos.deposited - amount;
        if (debt > 0) {
            require(
                remainingDeposit * LTV / 100 >= debt,
                "Health factor too low"
            );
        }

        pos.deposited -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "Zero amount");
        Position storage pos = positions[msg.sender];
        require(pos.deposited > 0, "No collateral");

        uint256 currentDebt = getDebt(msg.sender);
        uint256 maxBorrow = pos.deposited * LTV / 100;
        require(currentDebt + amount <= maxBorrow, "Exceeds LTV");

        // Update borrowed with accrued interest first
        pos.borrowed = currentDebt;
        pos.borrowTimestamp = block.timestamp;
        pos.borrowed += amount;

        token.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "Zero amount");
        Position storage pos = positions[msg.sender];

        uint256 debt = getDebt(msg.sender);
        require(debt > 0, "No debt");

        uint256 repayAmount = amount > debt ? debt : amount;

        token.safeTransferFrom(msg.sender, address(this), repayAmount);

        pos.borrowed = debt - repayAmount;
        pos.borrowTimestamp = block.timestamp;

        emit Repaid(msg.sender, repayAmount);
    }

    function liquidate(address user) external {
        uint256 debt = getDebt(user);
        require(debt > 0, "No debt");

        Position storage pos = positions[user];
        uint256 ltv = debt * 100 / pos.deposited;
        require(ltv >= LIQUIDATION_LTV, "Position is healthy");

        uint256 collateral = pos.deposited;

        pos.deposited  = 0;
        pos.borrowed   = 0;
        pos.borrowTimestamp = 0;

        token.safeTransferFrom(msg.sender, address(this), debt);
        token.safeTransfer(msg.sender, collateral);

        emit Liquidated(user, msg.sender, debt);
    }

    function getDebt(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.borrowed == 0) return 0;

        uint256 elapsed = block.timestamp - pos.borrowTimestamp;
        uint256 interest = pos.borrowed * INTEREST_RATE * elapsed / (100 * SECONDS_PER_YEAR);
        return pos.borrowed + interest;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        uint256 debt = getDebt(user);
        if (debt == 0) return type(uint256).max;
        return pos.deposited * LTV / 100 * 1e18 / debt;
    }
}