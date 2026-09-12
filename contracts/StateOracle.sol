// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IStateOracle.sol";

/// @title StateOracle
/// @notice Records verified cross-chain state observations and evaluates
///         state predicates against CURRENT state at execution time.
/// @dev This is the core of ATLAS: a capability's authority is only valid
///      while the predicate that justified it remains satisfied by the
///      latest verified observation. Freshness is enforced by requiring the
///      caller to present the CURRENT evidence root AND by bounding how old
///      an observation may be. A stale or superseded proof yields INVALID,
///      so the protected state transition refuses to execute.
contract StateOracle is IStateOracle {
    enum Operator {
        GT,
        GTE,
        LT,
        LTE,
        EQ,
        NEQ
    }

    struct Observation {
        uint256 value;
        uint64 sourceBlock;
        uint64 recordedAt;
        bytes32 evidenceRoot;
        bool exists;
    }

    struct Predicate {
        uint256 metricId;
        Operator operator;
        uint256 threshold;
        bool exists;
    }

    /// Chain + contract uniquely identify the source of truth for a metric.
    mapping(address => mapping(bytes32 => mapping(address => mapping(uint256 => Observation)))) private
        _latestBySubject;

    /// Content-addressed predicate registry.
    mapping(bytes32 => Predicate) private _predicates;

    mapping(address => bool) public verifiers;
    mapping(bytes32 => bytes32) public predicateSubjectHash;
    mapping(bytes32 => bytes32) public predicateMetricHash;

    uint256 public maxStaleness;

    uint256 private _observationCount;
    uint256 private _predicateCount;

    event ObservationRecorded(
        bytes32 indexed sourceChain,
        address indexed sourceContract,
        address indexed subject,
        uint256 metricId,
        uint256 value,
        uint64 sourceBlock,
        bytes32 evidenceRoot
    );

    event PredicateCreated(bytes32 indexed predicateHash, uint256 metricId, Operator operator, uint256 threshold);

    event PredicateChecked(bytes32 indexed predicateHash, bool valid, uint256 observedValue);

    error Unauthorized();
    error NonZero();

    modifier onlyVerifier() {
        if (!verifiers[msg.sender]) revert Unauthorized();
        _;
    }

    constructor(uint256 freshnessWindow) {
        maxStaleness = freshnessWindow;
    }

    /// @notice Register an authorized verifier (a USC worker in production)
    function setVerifier(address verifier, bool authorized) external {
        verifiers[verifier] = authorized;
    }

    /// @notice Record a fresh, USC-verified state observation.
    /// @param sourceChain      Source chain identifier (e.g., keccak256 of chain id)
    /// @param sourceContract   Contract on the source chain that emitted the state
    /// @param subject          The agent/subject this observation concerns
    /// @param metricId         Identifier of the metric (e.g., keccak256("collateral_ratio"))
    /// @param value            The observed metric value
    /// @param sourceBlock      Block number on the source chain
    /// @param evidenceRoot     Merkle/USC root that PROVED this value on the source chain
    function recordStateObservation(
        bytes32 sourceChain,
        address sourceContract,
        address subject,
        uint256 metricId,
        uint256 value,
        uint64 sourceBlock,
        bytes32 evidenceRoot
    ) external onlyVerifier {
        if (evidenceRoot == bytes32(0)) revert NonZero();
        require(subject != address(0), "StateOracle: zero subject");
        require(sourceContract != address(0), "StateOracle: zero source contract");

        _latestBySubject[subject][sourceChain][sourceContract][metricId] = Observation({
            value: value,
            sourceBlock: sourceBlock,
            recordedAt: uint64(block.timestamp),
            evidenceRoot: evidenceRoot,
            exists: true
        });

        _observationCount++;
        emit ObservationRecorded(sourceChain, sourceContract, subject, metricId, value, sourceBlock, evidenceRoot);
    }

    /// @notice Register a state predicate. The returned hash is what a state-bound
    ///         capability commits to at creation time.
    function createPredicate(uint256 metricId, Operator operator, uint256 threshold)
        external
        returns (bytes32 predicateHash)
    {
        predicateHash = keccak256(abi.encodePacked(metricId, operator, threshold));
        if (!_predicates[predicateHash].exists) {
            _predicates[predicateHash] =
                Predicate({metricId: metricId, operator: operator, threshold: threshold, exists: true});
            _predicateCount++;
            emit PredicateCreated(predicateHash, metricId, operator, threshold);
        }
    }

    /// @notice Evaluate a predicate against the CURRENT verified state.
    /// @dev Returns false if the predicate is unknown, no observation exists,
    ///      the presented evidence root is stale (not the latest), or the
    ///      observation is too old. This closes the TOCTOU gap: the executor
    ///      must prove state is still current at the moment of execution.
    function checkStatePredicate(
        bytes32 sourceChain,
        address sourceContract,
        address subject,
        bytes32 statePredicateHash,
        bytes32 freshEvidenceRoot
    ) external view returns (bool) {
        Predicate storage predicate = _predicates[statePredicateHash];
        if (!predicate.exists) return false;

        if (freshEvidenceRoot == bytes32(0)) return false;

        Observation storage obs = _latestBySubject[subject][sourceChain][sourceContract][predicate.metricId];
        if (!obs.exists) return false;

        // Freshness 1: freshest evidence root must be presented, else the old
        // proof is being replayed after the source state changed.
        if (obs.evidenceRoot != freshEvidenceRoot) return false;

        // Freshness 2: observation can't be older than the freshness window.
        if (block.timestamp - obs.recordedAt > maxStaleness) return false;

        bool valid = _evaluate(predicate.operator, obs.value, predicate.threshold);
        return valid;
    }

    /// @notice Get the latest observation for a subject/metric.
    function getLatestObservation(bytes32 sourceChain, address sourceContract, address subject, uint256 metricId)
        external
        view
        returns (uint256 value, uint64 sourceBlock, uint64 recordedAt, bytes32 evidenceRoot, bool exists)
    {
        Observation storage obs = _latestBySubject[subject][sourceChain][sourceContract][metricId];
        return (obs.value, obs.sourceBlock, obs.recordedAt, obs.evidenceRoot, obs.exists);
    }

    /// @notice Read back a registered predicate.
    function getPredicate(bytes32 predicateHash)
        external
        view
        returns (uint256 metricId, Operator operator, uint256 threshold, bool exists)
    {
        Predicate storage p = _predicates[predicateHash];
        return (p.metricId, p.operator, p.threshold, p.exists);
    }

    function getObservationCount() external view returns (uint256) {
        return _observationCount;
    }

    function getPredicateCount() external view returns (uint256) {
        return _predicateCount;
    }

    function _evaluate(Operator op, uint256 value, uint256 threshold) internal pure returns (bool) {
        if (op == Operator.GT) return value > threshold;
        if (op == Operator.GTE) return value >= threshold;
        if (op == Operator.LT) return value < threshold;
        if (op == Operator.LTE) return value <= threshold;
        if (op == Operator.EQ) return value == threshold;
        return value != threshold;
    }
}
