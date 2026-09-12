export enum CapabilityStatus {
  NONE = 0,
  ACTIVE = 1,
  CONSUMED = 2,
  EXPIRED = 3,
  REVOKED = 4
}

export interface AtlasConfig {
  rpcUrl: string;
  contracts: {
    evidenceRegistry: `0x${string}`;
    policyRegistry: `0x${string}`;
    capabilityRegistry: `0x${string}`;
    capabilityGuard: `0x${string}`;
  };
}

export interface Evidence {
  id: `0x${string}`;
  sourceContract: `0x${string}`;
  eventSig: `0x${string}`;
  subject: `0x${string}`;
  value: bigint;
  blockNumber: number;
  txHash: `0x${string}`;
  valid: boolean;
}

export interface Policy {
  id: `0x${string}`;
  name: string;
  minRepayments: number;
  minRepaymentVolume: bigint;
  minCollateralRatioBps: number;
  maxCapability: bigint;
  capabilityTTL: number;
  version: number;
  active: boolean;
}

export interface Capability {
  id: `0x${string}`;
  subject: `0x${string}`;
  action: `0x${string}`;
  maxAmount: bigint;
  consumedAmount: bigint;
  evidenceRoot: `0x${string}`;
  policyId: `0x${string}`;
  policyVersion: number;
  issuedAt: number;
  expiresAt: number;
  nonce: bigint;
  status: CapabilityStatus;
}

export interface CapabilityRequest {
  action: string;
  amount: number;
}

export interface ExecutionResult {
  success: boolean;
  capabilityId: `0x${string}`;
  amount: bigint;
  txHash?: `0x${string}`;
  error?: string;
}
