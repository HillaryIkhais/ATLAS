# ATLAS Live Integration Run

## Claim Summary

### MockUSC Baseline (code-level verification)

> v1 → prove → v2 → prove → replay v1 → `StaleVersion` ✅

The full supersession lifecycle works correctly through the complete ATLAS code path: proof decoding, event extraction, version enforcement, and stale-version rejection. All on-chain, all real transactions.

### RealUSC (precompile-level verification)

> Sepolia proof → RealUSCProver → live BlockProver precompile → cryptographic rejection of stale continuity chain ✅

The real Creditcoin USC precompile at `0x0...FD2` was invoked and performed cryptographic verification. It correctly rejected a proof whose continuity chain does not connect to the current CC3 attestation state. A fresh successful RealUSC proof has **not** been demonstrated yet — this is an infrastructure constraint (proof-gen service returns cached proofs), not a code correctness issue.

---

## Bugs Fixed During This Run

### 1. Wrong `AUTHORITY_UPDATED_SIG` constant

**File:** `contracts/usc/AbstractUSCProver.sol:25-26`

The hardcoded event signature hash was wrong. The contract had `0x9e9f7c6a...` but the correct keccak256 of `"AuthorityUpdated(uint256,address,bytes32,uint256,uint256,uint64,uint8)"` is `0x151846dc546d791bbd3724826e32bca4c9ff60d27aa50fad111e95ccd8dcd6bf`. This caused `_decodeAuthorityUpdated` to never find the AuthorityUpdated log in the receipt, reverting with `NoAuthorityUpdatedLog`.

### 2. Wrong proof packing format for inner `inclusionProof.data`

**File:** `integration/pack-proof.js:12-18`, `integration/index.ts:38-48`

The inner data was encoded as a flat tuple `coder.encode(["bytes", "bytes32", "bool", ...], ...)` instead of the correct nested format `coder.encode(["bytes", "tuple(bytes32,bool)[]"], ...)`. Solidity's `abi.decode(data, (bytes, MerkleProofEntry[]))` expects the array to have a length prefix and properly encoded tuple elements. The flat encoding caused an immediate revert during proof decoding.

---

## Deployed Contracts

### Sepolia (source chain — Ethereum testnet)

| Contract | Address |
|---|---|
| AtlasAuthorityController | `0xd584BC8bd63711990264f04D4359DBAbA2b88247` |
| Deployer | `0x1B3F6b55B2c0b97a5d0A62Ec3c7f26C8CEc8140F` |

### CC3 Testnet — MockUSCProver (code-level verification)

| Contract | Address |
|---|---|
| MockUSCProver | `0xe1436d9A81Db7A128F7f2e982D179Ca116F7b0B6` |
| AtlasAuthorityRegistry | `0x19a3268C2d141BDd76Cb451A69a3EeeA3ee649d1` |

### CC3 Testnet — RealUSCProver (precompile-level verification)

| Contract | Address |
|---|---|
| RealUSCProver | `0xB73AF4F069833d035ba7737628B4d7B787fc510D` |
| AtlasAuthorityRegistry | `0xE150680bbE2917448E13193F0aCA728217cB6B89` |

### Shared

- **Deployer:** `0x1B3F6b55B2c0b97a5d0A62Ec3c7f26C8CEc8140F`
- **CC3 RPC:** `https://rpc.cc3-testnet.creditcoin.network`
- **CC3 Chain ID:** `102031` (whitelisted in `NativeQueryVerifierLib.hasPrecompile()`)
- **BlockProver precompile:** `0x0000000000000000000000000000000000000FD2`

---

## MockUSC Flow — Full Supersession Lifecycle

### Step 1: Create Authority v1 on Sepolia

- **Action:** `createAuthority(1, BORROW, $25,000, expiry)`
- **TX:** `0x01b3b77c0449e43a413f79a4a7c96499a2ace956de43341a39710e090057cfb1`
- **Block:** 11,696,022
- **AuthorityId:** 1
- **maxAmount:** 25,000
- **status:** ACTIVE (1)
- **version:** 1

### Step 2: Generate + Submit v1 Proof

- **Proof file:** `integration/proof-v1-alt.json`
- **headerNumber:** 11,696,022
- **CC3 TX:** `0x46e49dc70eaf6a5fa8a29897f0a96bdc0f56d83d012de39884309d92a0ba6f7e`
- **Status:** 1 (success)
- **Event:** `AuthorityProven(authorityId=1, version=1, maxAmount=25000, status=ACTIVE)`

### Step 3: Narrow Authority to v2 on Sepolia

- **Action:** `narrowAuthority(1, $10,000)` — version increments to 2
- **TX:** `0xe7cd8dfcc30e2fc9d965a3220bfcb62d4829f3528b26249c941fe8454f782d65`
- **Block:** 11,696,578
- **maxAmount:** 10,000 (narrowed)
- **status:** NARROWED (2)
- **version:** 2

### Step 4: Generate + Submit v2 Proof

- **Proof file:** `integration/proof-v2-alt.json`
- **headerNumber:** 11,696,578
- **CC3 TX:** `0x574150961c274a9e81a99c8a9239adacad32f25602e8b4975a0b534c9015a095`
- **Status:** 1 (success)
- **Event:** `AuthorityProven(authorityId=1, version=2, maxAmount=10000, status=NARROWED)`

### Step 5: Replay v1 — Supersession Enforced

- **CC3 TX:** `0x27054f1f6b15462dca6e949c577c490bcf0124399cd94b1a73067e299dca5bfe`
- **Status:** 0 (failed — reverted)
- **Revert reason:** `StaleVersion()` — version 1 is not strictly greater than stored version 2
- **Result:** The old authority is permanently rejected. Supersession enforced on-chain.

### Final Registry State

```
authorityId: 1
version: 2
maxAmount: 10,000
expiresAt: 1,893,452,400 (2030-01-01)
status: NARROWED (2)
sourceTxHash: 0xd618a2be...
sourceBlock: 11,696,578
action: BORROW
agent: 0x1B3F6b55B2c0b97a5d0A62Ec3c7f26C8CEc8140F
proven: true
```

---

## RealUSC Flow — Precompile Verification

### What was tested

The same Sepolia v1 proof was submitted through the `RealUSCProver` → `AtlasAuthorityRegistry` pipeline. This path invokes the live Creditcoin BlockProver precompile at `0x0...FD2`.

### Result

- **Registry TX:** `0x4d029fb4c545c3cebe305082d2ab63f6e5a2934d2ddbc85eea30375860c8ea16`
- **Status:** 0 (reverted)
- **Revert reason from precompile:** `"Continuity proof does not match attestation or checkpoint"`
- **This is a real cryptographic rejection** — not a code-level error.

### Interpretation

The BlockProver precompile performs three checks:
1. **Inclusion proof** — verifies the transaction is in the source chain block
2. **Continuity proof** — verifies the block header chains from a known CC3 attestation checkpoint
3. **Attestation head** — verifies the chain reaches the current CC3 attestation state

The cached proof's continuity chain (79 roots) terminates at an older CC3 attestation state. The precompile correctly identifies this and rejects the proof.

### Why the proof was stale

The proof-gen service (`prover.cc3-testnet.creditcoin.network`) returns cached proofs. The cached v1 proof was generated against an older CC3 attestation state. Between generation and submission, the CC3 attestation advanced, making the continuity chain stale. The proof-gen service did not regenerate a fresh proof.

### What has NOT been demonstrated

A **fresh successful RealUSC proof submission** has not been demonstrated. The full RealUSC end-to-end cycle (proof generated against current CC3 attestation → accepted by precompile) requires a proof-gen service that generates fresh proofs chaining to the current attestation head.

---

## How Supersession Works

1. Authority v1 (version=1, $25k) is proven on CC3 via Attestcoin proof
2. Authority is narrowed on Sepolia — version increments to 2, maxAmount reduced to $10k
3. Authority v2 (version=2, $10k) is proven on CC3 via new Attestcoin proof
4. Registry enforces `action.version > current.version` — any attempt to prove v1 again fails with `StaleVersion`
5. The old authority is permanently superseded; the narrower v2 is the only valid authority

## Proof Generation

The proof-gen service endpoint is:
```
GET https://prover.cc3-testnet.creditcoin.network/api/v1/proof-by-tx/{chainKey}/{txHash}
```

- `chainKey`: 1 (Sepolia mapped to chainKey=1)
- `txHash`: the Sepolia transaction hash

## Proof Packing (pack-proof.js)

```javascript
// Correct encoding for inclusionProof.data
const data = coder.encode(
    ['bytes', 'tuple(bytes32,bool)[]'],
    [txBytes, siblings.map(s => [s.hash, s.isLeft])]
);

// Correct encoding for outer proof
const proofBytes = coder.encode(
    ['uint64', 'tuple(uint8,bytes32,bytes)', 'tuple(bytes32,bytes32[])'],
    [headerNumber, [0, root, data], [lowerEndpointDigest, roots]]
);
```
