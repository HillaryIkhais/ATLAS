# ATLAS

## Cross-Chain Capability Derivation from Verified State

> **Authority cannot exceed verified state.**

ATLAS is a protocol that derives, enforces, and revokes machine capabilities from cryptographically verified cross-chain state. It bridges Ethereum repayment history to Creditcoin credit authority through a deterministic, auditable pipeline.

---

## The Thesis

The primitive is not "cross-chain credit scoring."

The primitive is:

```
VERIFIED CROSS-CHAIN STATE → TEMPORARY CAPABILITY → ENFORCED EXECUTION
```

The key insight:

**Cross-chain evidence should not merely inform an agent's decision. It should be able to deterministically create, constrain, and revoke the agent's authority.**

The agent is deliberately outside the trust boundary.

---

## Architecture

```
Ethereum
   │
   │ actual repayment event
   ▼
USC proof
   │
   │ cryptographic verification
   ▼
ATLAS Evidence
   │
   │ policy evaluation
   ▼
Capability
   │
   │ execution guard
   ▼
Creditcoin action
```

### The Closed Loop

```
SOURCE STATE
     ↓
PROOF
     ↓
VERIFICATION
     ↓
EVIDENCE
     ↓
POLICY
     ↓
CAPABILITY
     ↓
EXECUTION
     ↓
STATE CHANGE
     ↓
STATE RE-EVALUATION
     ↓
REVOKE / CONTINUE
```

The loop closes: the action changes reality. Reality can then invalidate the authority that permitted the action.

---

## Core Contracts

### EvidenceRegistry
Stores verified cross-chain facts. Each evidence entry links to a specific Ethereum event, verified through USC proof.

### PolicyRegistry
On-chain policy definitions. Policies define eligibility criteria, maximum authority, and time-to-live for capabilities.

### CapabilityRegistry
The hero contract. Issues, tracks, and revokes capabilities. Each capability is a time-bound, amount-constrained, subject-specific authority derived from verified evidence.

### CapabilityGuard
Validates execution requests. Checks subject, action, amount, expiry, and remaining authority before allowing state transitions.

### AtlasUSC
Integration layer with Creditcoin Universal Smart Contracts. Accepts verified cross-chain facts and issues capabilities.

---

## The Invariant

```
capability.scope ≤ policy(scope)
capability.amount ≤ policy(max)
capability.lifetime ≤ policy(TTL)
capability.validity ≤ current verified state
```

**An agent can request authority. It cannot manufacture authority.**

---

## Non-Widening Capability Derivation

Suppose verified state → maximum authority = $25K.

The agent asks: "Give me $100K authority."

ATLAS cannot.

Even if the LLM is extremely persuasive.
Even if the frontend says $100K.
Even if the worker requests it.

The contract mathematically constrains:

```
requested authority ≤ policy authority ≤ verified state
```

This is the ATLAS equivalent of: **Derived capability ≤ verified authority.**

---

## Attack Lab

ATLAS enforces 8 security guarantees:

### Attack 1: Over-Limit
Agent has $25K capability, requests $40K → **REVERT**

### Attack 2: Expired
Capability expires after TTL → **REVERT**

### Attack 3: Revoked State
Collateral drops from 181% to 138% → **CAPABILITY REVOKED**

### Attack 4: Wrong Agent
Capability belongs to Agent_07, Agent_08 tries it → **REVERT**

### Attack 5: Replay
Already consumed capability → **REVERT**

### Attack 6: Wrong Policy Version
Capability issued under V3, current is V4 → **REVOKED**

### Attack 7: Fake Cross-Chain Evidence
Invalid proof → **USC VERIFICATION FAILED**

### Attack 8: Wrong Source
Valid-looking event from wrong source contract → **REJECT**

---

## Usage

### TypeScript SDK

```typescript
import { connect } from '@atlas/sdk';

const atlas = connect({
  rpcUrl: 'https://rpc.sepolia.org',
  contracts: {
    evidenceRegistry: '0x...',
    policyRegistry: '0x...',
    capabilityRegistry: '0x...',
    capabilityGuard: '0x...',
  }
});

// Get a capability
const cap = await atlas.getCapability(capabilityId);

// Format for display
console.log(atlas.formatCapability(cap));

// Execute
const result = await atlas.execute({
  action: 'increase_credit',
  amount: 20000
});
```

### Solidity Integration

```solidity
import {ICapabilityGuard} from "./interfaces/ICapabilityGuard.sol";

contract MyContract {
    ICapabilityGuard public guard;
    
    function executeWithCapability(
        bytes32 capId,
        uint256 amount
    ) external {
        guard.executeWithCapability(
            capId,
            msg.sender,
            keccak256("MY_ACTION"),
            amount
        );
        // State transition happens here
    }
}
```

---

## Test Results

```
37 tests passing
  - EvidenceRegistry: 3
  - PolicyRegistry: 3
  - CapabilityRegistry: 8
  - CapabilityGuard: 4
  - MockCreditMarket: 2
  - AtlasUSC: 5
  - Attack Lab: 9
  - Full Lifecycle: 1
  - Replay: 1
  - Expiry: 1
```

---

## Demo

See [DEMO.md](./DEMO.md) for the 2-minute demo script.

### Demo Flow

```
0:00  Show Ethereum repayment events
0:10  Submit USC proof
0:25  Show verified evidence
0:35  Policy evaluation
0:45  Derive capability
0:55  Happy path execution ($20K)
1:10  Attack: Over-limit ($40K)
1:20  Attack: Wrong agent
1:30  State deterioration
1:40  Attack: Revoked capability
1:50  Show evidence → policy → capability → execution lineage
1:55  Closing statement
```

---

## Project Structure

```
ATLAS/
├── contracts/
│   ├── EvidenceRegistry.sol
│   ├── PolicyRegistry.sol
│   ├── CapabilityRegistry.sol
│   ├── CapabilityGuard.sol
│   ├── MockCreditMarket.sol
│   ├── AgentHistory.sol
│   ├── AtlasUSC.sol
│   └── interfaces/
├── test/
│   ├── ATLASTest.t.sol
│   └── ATLASAttackLab.t.sol
├── script/
│   ├── DeployATLAS.s.sol
│   └── RunScenario.s.sol
├── sdk/
│   ├── src/
│   │   ├── index.ts
│   │   ├── client.ts
│   │   ├── types.ts
│   │   └── abi/
│   └── package.json
├── ui/
│   └── index.html
├── foundry.toml
├── .env
├── DEMO.md
└── README.md
```

---

## License

MIT
