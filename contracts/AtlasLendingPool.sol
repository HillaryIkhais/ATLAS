// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AtlasLendingPool
/// @notice Minimal lending pool that represents the actual Creditcoin state
///         change protected by ATLAS.  Borrow, repay, deposit, withdraw.
/// @dev The execution guard is the only address authorized to call `borrow`.
///      This is what makes ATLAS more than a dashboard: protected actions
///      produce real token transfers.
contract AtlasLendingPool {
    address public guard;

    uint256 public liquidity;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public debts;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed depositor, uint256 amount);
    event Borrowed(address indexed agent, uint256 amount, uint256 capId);
    event Repaid(address indexed agent, uint256 amount);

    error OnlyGuard();
    error ZeroAmount();
    error InsufficientLiquidity();

    modifier onlyGuard() {
        if (msg.sender != guard) revert OnlyGuard();
        _;
    }

    constructor() {}

    /// @notice Set the execution guard (the only authorized borrower).
    function setGuard(address _guard) external {
        require(_guard != address(0));
        guard = _guard;
    }

    // ─── Liquidity ────────────────────────────────────────────────────

    function deposit() external payable {
        require(msg.value > 0, "AtlasLendingPool: zero value");
        deposits[msg.sender] += msg.value;
        liquidity += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "AtlasLendingPool: zero amount");
        require(deposits[msg.sender] >= amount, "AtlasLendingPool: insufficient deposit");
        deposits[msg.sender] -= amount;
        liquidity -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "AtlasLendingPool: ETH transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    // ─── Guard-protected actions ───────────────────────────────────────

    /// @notice Issue a loan.  Only callable by AtlasExecutionGuard.
    function borrow(address agent, uint256 amount, uint256 capId) external onlyGuard {
        require(amount > 0, "AtlasLendingPool: zero amount");
        if (amount > liquidity) revert InsufficientLiquidity();
        liquidity -= amount;
        debts[agent] += amount;
        // Real token transfer to the agent
        (bool ok,) = agent.call{value: amount}("");
        require(ok, "AtlasLendingPool: ETH transfer failed");
        emit Borrowed(agent, amount, capId);
    }

    // ─── Repayment ────────────────────────────────────────────────────

    function repay() external payable {
        require(msg.value > 0, "AtlasLendingPool: zero value");
        uint256 debt = debts[msg.sender];
        require(msg.value <= debt, "AtlasLendingPool: overpay");
        debts[msg.sender] = debt - msg.value;
        liquidity += msg.value;
        emit Repaid(msg.sender, msg.value);
    }

    // ─── View ─────────────────────────────────────────────────────────

    function getDebt(address agent) external view returns (uint256) {
        return debts[agent];
    }

    function getDeposit(address depositor) external view returns (uint256) {
        return deposits[depositor];
    }

    receive() external payable {}
}
