# ATLAS: Cross-Chain Capability Derivation from Verified State

## Project Summary

ATLAS is a protocol that derives, enforces, and revokes machine capabilities from cryptographically verified cross-chain state. It bridges Ethereum repayment history to Creditcoin credit authority through a deterministic, auditable pipeline.

**The primitive:** VERIFIED CROSS-CHAIN STATE → TEMPORARY CAPABILITY → ENFORCED EXECUTION

**The invariant:** capability.scope ≤ policy(scope) | capability.amount ≤ policy(max) | capability.lifetime ≤ policy(TTL) | capability.validity ≤ current verified state

## Problem

Autonomous workers are becoming capable of doing consequential professional work. Failures are inevitable. But "recovery" cannot mean retrying blindly or asking the human to take over. If the verified state has changed, retrying on stale authority risks exceeding verified bounds.

## Solution

ATLAS makes the worker responsible for getting the job to a verified outcome, within the authority it was given. The closed loop ensures: evidence → policy → capability → execution → state re-evaluation. If reality no longer supports the authority, the capability is revoked automatically.

## Key Features

- **8 security guarantees** enforced through the capability derivation pipeline
- **Cross-chain evidence** from Ethereum repayment history to Creditcoin credit authority
- **Temporary, bounded capabilities** that cannot be manufactured, only derived
- **Automatic revocation** when verified state changes (collateral drops, policy expiry, etc.)
- **8 attack-tested guarantees**: Over-Limit, Expired, Revoked State, Wrong Agent, Replay, Wrong Policy, Fake Evidence, Wrong Source

## Demo

2-minute demo script available at DEMO.md. The demo shows the full flow: from Ethereum repayment events, through USC proof submission, policy evaluation, capability derivation, $20K execution, and 8 attack vectors all blocked.

## Smart Contracts

20+ Solidity contracts implementing the capability derivation pipeline:
- EvidenceRegistry: Stores verified cross-chain facts
- PolicyRegistry: On-chain policy definitions
- CapabilityRegistry: Issues, tracks, and revokes capabilities
- CapabilityGuard: Validates execution requests
- AtlasUSC: Integration layer with Creditcoin Universal Smart Contracts

## Tests

37 tests passing across EvidenceRegistry, PolicyRegistry, CapabilityRegistry, CapabilityGuard, MockCreditMarket, AtlasUSC, Attack Lab, Full Lifecycle, Replay, and Expiry.

## Video

Demo video script: DEMO.md (2 minutes). Records the complete flow on Local Anvil with Sepolia/Creditcoin testnet integration.

## Devpost Fields

- **Title:** ATLAS: Cross-Chain Capability Derivation from Verified State
- **Category:** Smart Contracts / Blockchain Infrastructure
- **Submission Type:** Project Submission
- **URL:** https://github.com/atlas-protocol/atlas