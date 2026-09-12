# ATLAS Demo Script (2 Minutes)

## Setup
- Local Anvil running on port 8545
- All ATLAS contracts deployed
- UI open in browser

## 0:00 - Show Ethereum Source
**Narrator:** "We start on Ethereum Sepolia. Agent_07 has 4 verified repayment events."

**Action:** Show `cast call` to AgentHistory contract showing repayment events.

```
$ cast call 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707 "getRepaymentCount(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://127.0.0.1:8545

4
```

## 0:10 - Submit USC Proof
**Narrator:** "We submit a USC proof. Creditcoin verifies the cryptographic proof."

**Action:** Submit proof via AtlasUSC contract.

```
$ cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
  "processUSCQuery(address,bytes32,address,uint256,bytes32)" \
  0x5FC8d32690cc91D4c39d9d3abcBD16989F875707 \
  $(cast keccak "RepaymentRecorded") \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  30000 \
  $(cast keccak "CREDIT_V3") \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://127.0.0.1:8545
```

## 0:25 - Show Verified Evidence
**Narrator:** "ATLAS now has 4 verified cross-chain facts. Total volume: $30,000."

**Action:** Open UI, show Screen 1 (Evidence).

```
$ open ui/index.html
```

**Show in UI:**
```
VERIFIED CROSS-CHAIN STATE

Repayment #1     $5,000    ✓
Repayment #2     $8,000    ✓
Repayment #3     $7,000    ✓
Repayment #4    $10,000    ✓

Total Verified Volume: $30,000
```

## 0:35 - Policy Evaluation
**Narrator:** "The policy evaluates: 3 repayments minimum, $20K volume minimum. Agent_07 qualifies."

**Action:** Show policy check.

```
$ cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 "isPolicyActive(bytes32)(bool)" $(cast keccak "CREDIT_V3") --rpc-url http://127.0.0.1:8545

true
```

## 0:45 - Derive Capability
**Narrator:** "ATLAS derives a $25,000 capability. Valid for 10 minutes."

**Action:** Show Screen 2 (Capability) in UI.

```
CAPABILITY #1842...

Subject:    Agent_07
Action:     INCREASE_CREDIT
Maximum:    $25,000
Remaining:  $25,000

Policy:     CREDIT_V3 v1
Issued:     09:31:42
Expires:    09:41:42
Status:     ACTIVE
```

## 0:55 - Happy Path Execution
**Narrator:** "Agent_07 requests $20,000. ATLAS validates. Credit limit increases."

**Action:** Show Screen 3 (Execution), execute $20K.

```
$ cast send 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9 \
  "increaseCredit(address,uint256,bytes32)" \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  20000 \
  <capability-id> \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://127.0.0.1:8545
```

**Show in UI:**
```
✓ EXECUTION SUCCESSFUL

Amount: $20,000
Remaining Authority: $5,000
Credit limit: $10,000 → $30,000
```

## 1:10 - Attack: Over-Limit
**Narrator:** "Agent_08 tries to use $40,000. Blocked."

**Action:** Click "SIMULATE ATTACK: $40,000" in UI.

**Show in UI:**
```
✗ EXECUTION BLOCKED

Requested: $40,000
Maximum Authority: $25,000
Error: AMOUNT EXCEEDS CAPABILITY
```

## 1:20 - Attack: Wrong Agent
**Narrator:** "Agent_08 tries to use Agent_07's capability. Blocked."

**Action:** Click "Attack 4: Wrong Agent" in UI.

**Show in UI:**
```
✗ ATTACK BLOCKED: WRONG AGENT

Capability Subject: Agent_07
Requester: Agent_08
Capabilities are non-transferable
```

## 1:30 - State Deterioration
**Narrator:** "Collateral drops from 181% to 138%. Capability revoked."

**Action:** Revoke capability.

```
$ cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 \
  "revokeCapability(bytes32,string)" \
  <capability-id> \
  "collateral dropped to 138%" \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://127.0.0.1:8545
```

## 1:40 - Attack: Revoked State
**Narrator:** "Agent tries to use revoked capability. Blocked."

**Action:** Click "Attack 3: Revoked" in UI.

**Show in UI:**
```
✗ ATTACK BLOCKED: REVOKED

Reason: Collateral dropped to 138%
Status: REVOKED
CapabilityGuard.revert()
```

## 1:50 - Show Lineage
**Narrator:** "Evidence → Policy → Capability → Execution. The loop closes."

**Action:** Show the full flow diagram in UI.

```
SOURCE STATE (Ethereum)
     ↓
PROOF (USC)
     ↓
VERIFICATION (Precompile)
     ↓
EVIDENCE (EvidenceRegistry)
     ↓
POLICY (PolicyRegistry)
     ↓
CAPABILITY (CapabilityRegistry)
     ↓
EXECUTION (CapabilityGuard)
     ↓
STATE CHANGE (CreditMarket)
     ↓
STATE RE-EVALUATION
     ↓
REVOKE / CONTINUE
```

## 1:55 - Closing Statement
**Narrator:** "ATLAS doesn't give agents permissions. It derives permissions from verified reality, bounds them, and kills them when reality no longer supports them."

**Show on screen:**
```
AUTHORITY CANNOT EXCEED VERIFIED STATE

capability.scope ≤ policy(scope)
capability.amount ≤ policy(max)
capability.lifetime ≤ policy(TTL)
capability.validity ≤ current verified state

An agent can request authority.
It cannot manufacture authority.
```

## 2:00 - End
**Show:** "ATLAS - Cross-Chain Capability Derivation from Verified State"

---

## Key Metrics to Display

### Contract Addresses (Local Anvil)
```
EvidenceRegistry:    0x5FbDB2315678afecb367f032d93F642f64180aa3
PolicyRegistry:      0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
CapabilityRegistry:  0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
CapabilityGuard:     0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
MockCreditMarket:    0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
AgentHistory:        0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
AtlasUSC:            0x... (deployed separately)
```

### Test Results
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

### Attack Lab Results
```
Attack 1: Over-Limit        ✓ BLOCKED
Attack 2: Expired           ✓ BLOCKED
Attack 3: Revoked State     ✓ BLOCKED
Attack 4: Wrong Agent       ✓ BLOCKED
Attack 5: Replay            ✓ BLOCKED
Attack 6: Wrong Policy      ✓ BLOCKED
Attack 7: Fake Evidence     ✓ BLOCKED
Attack 8: Wrong Source       ✓ BLOCKED
```
