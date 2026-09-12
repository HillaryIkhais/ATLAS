// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AgentHistory {
    event RepaymentRecorded(address indexed agent, uint256 amount, uint256 timestamp, bytes32 repaymentId);

    event CollateralUpdated(address indexed agent, uint256 collateral, uint256 timestamp);

    mapping(address => uint256) public repaymentCount;
    mapping(address => uint256) public totalRepaid;
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public lastRepaymentBlock;

    function recordRepayment(address agent, uint256 amount, bytes32 repaymentId) external {
        require(agent != address(0), "AgentHistory: zero address");
        require(amount > 0, "AgentHistory: zero amount");

        repaymentCount[agent]++;
        totalRepaid[agent] += amount;
        lastRepaymentBlock[agent] = block.number;

        emit RepaymentRecorded(agent, amount, block.timestamp, repaymentId);
    }

    function updateCollateral(address agent, uint256 _collateral) external {
        require(agent != address(0), "AgentHistory: zero address");

        collateral[agent] = _collateral;
        emit CollateralUpdated(agent, _collateral, block.timestamp);
    }

    function getAgentHistory(address agent)
        external
        view
        returns (uint256 count, uint256 total, uint256 col, uint256 lastBlock)
    {
        return (repaymentCount[agent], totalRepaid[agent], collateral[agent], lastRepaymentBlock[agent]);
    }
}
