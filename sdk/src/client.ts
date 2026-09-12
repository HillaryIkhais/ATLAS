import { createPublicClient, createWalletClient, http, getContract, PublicClient, WalletClient } from 'viem';
import { mainnet, sepolia } from 'viem/chains';
import { AtlasConfig, Capability, CapabilityRequest, ExecutionResult, CapabilityStatus } from './types';
import { CapabilityRegistryABI } from './abi/CapabilityRegistry';

export class AtlasClient {
  private config: AtlasConfig;
  private publicClient: PublicClient;
  private walletClient?: WalletClient;
  private capabilityRegistry: any;

  constructor(config: AtlasConfig) {
    this.config = config;
    
    this.publicClient = createPublicClient({
      chain: sepolia,
      transport: http(config.rpcUrl),
    });

    this.capabilityRegistry = getContract({
      address: config.contracts.capabilityRegistry,
      abi: CapabilityRegistryABI,
      client: this.publicClient,
    });
  }

  setWallet(walletClient: WalletClient) {
    this.walletClient = walletClient;
  }

  async getCapability(capabilityId: `0x${string}`): Promise<Capability> {
    const cap = await this.capabilityRegistry.read.getCapability([capabilityId]);
    return {
      id: cap.id,
      subject: cap.subject,
      action: cap.action,
      maxAmount: cap.maxAmount,
      consumedAmount: cap.consumedAmount,
      evidenceRoot: cap.evidenceRoot,
      policyId: cap.policyId,
      policyVersion: cap.policyVersion,
      issuedAt: Number(cap.issuedAt),
      expiresAt: Number(cap.expiresAt),
      nonce: cap.nonce,
      status: cap.status as CapabilityStatus,
    };
  }

  async isCapabilityValid(capabilityId: `0x${string}`): Promise<boolean> {
    return this.capabilityRegistry.read.isCapabilityValid([capabilityId]);
  }

  async getRemainingAuthority(capabilityId: `0x${string}`): Promise<bigint> {
    return this.capabilityRegistry.read.getRemainingAuthority([capabilityId]);
  }

  async getCapabilityCount(): Promise<bigint> {
    return this.capabilityRegistry.read.getCapabilityCount();
  }

  async getAgentCapabilities(agent: `0x${string}`): Promise<`0x${string}`[]> {
    return this.capabilityRegistry.read.getAgentCapabilities([agent]);
  }

  async execute(request: CapabilityRequest): Promise<ExecutionResult> {
    if (!this.walletClient) {
      return {
        success: false,
        capabilityId: '0x0000000000000000000000000000000000000000000000000000000000000000',
        amount: BigInt(request.amount),
        error: 'Wallet not connected',
      };
    }

    // For now, return a mock result
    // In production, this would call the CapabilityGuard contract
    return {
      success: true,
      capabilityId: '0x0000000000000000000000000000000000000000000000000000000000000000',
      amount: BigInt(request.amount),
    };
  }

  formatCapability(cap: Capability): string {
    const statusMap: Record<CapabilityStatus, string> = {
      [CapabilityStatus.NONE]: 'NONE',
      [CapabilityStatus.ACTIVE]: 'ACTIVE',
      [CapabilityStatus.CONSUMED]: 'CONSUMED',
      [CapabilityStatus.EXPIRED]: 'EXPIRED',
      [CapabilityStatus.REVOKED]: 'REVOKED',
    };

    const remaining = cap.maxAmount - cap.consumedAmount;
    const expiresIn = Math.max(0, cap.expiresAt - Math.floor(Date.now() / 1000));

    return `
CAPABILITY ${cap.id.slice(0, 10)}...

Subject:    ${cap.subject}
Action:     ${cap.action}
Maximum:    $${cap.maxAmount}
Consumed:   $${cap.consumedAmount}
Remaining:  $${remaining}

Evidence:   ${cap.evidenceRoot.slice(0, 10)}...
Policy:     ${cap.policyId.slice(0, 10)}... v${cap.policyVersion}

Issued:     ${new Date(cap.issuedAt * 1000).toISOString()}
Expires:    ${new Date(cap.expiresAt * 1000).toISOString()}
TTL Left:   ${expiresIn}s

Status:     ${statusMap[cap.status]}
    `.trim();
  }
}
