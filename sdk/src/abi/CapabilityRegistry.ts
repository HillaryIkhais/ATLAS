export const CapabilityRegistryABI = [
  {
    "inputs": [
      { "internalType": "address", "name": "subject", "type": "address" },
      { "internalType": "bytes32", "name": "action", "type": "bytes32" },
      { "internalType": "uint256", "name": "maxAmount", "type": "uint256" },
      { "internalType": "bytes32", "name": "evidenceRoot", "type": "bytes32" },
      { "internalType": "bytes32", "name": "policyId", "type": "bytes32" },
      { "internalType": "uint64", "name": "ttl", "type": "uint64" }
    ],
    "name": "createCapability",
    "outputs": [
      { "internalType": "bytes32", "name": "", "type": "bytes32" }
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "bytes32", "name": "capId", "type": "bytes32" },
      { "internalType": "address", "name": "subject", "type": "address" },
      { "internalType": "bytes32", "name": "action", "type": "bytes32" },
      { "internalType": "uint256", "name": "amount", "type": "uint256" }
    ],
    "name": "consumeCapability",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "bytes32", "name": "capId", "type": "bytes32" },
      { "internalType": "string", "name": "reason", "type": "string" }
    ],
    "name": "revokeCapability",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "bytes32", "name": "capId", "type": "bytes32" }
    ],
    "name": "getCapability",
    "outputs": [
      {
        "components": [
          { "internalType": "bytes32", "name": "id", "type": "bytes32" },
          { "internalType": "address", "name": "subject", "type": "address" },
          { "internalType": "bytes32", "name": "action", "type": "bytes32" },
          { "internalType": "uint256", "name": "maxAmount", "type": "uint256" },
          { "internalType": "uint256", "name": "consumedAmount", "type": "uint256" },
          { "internalType": "bytes32", "name": "evidenceRoot", "type": "bytes32" },
          { "internalType": "bytes32", "name": "policyId", "type": "bytes32" },
          { "internalType": "uint64", "name": "policyVersion", "type": "uint64" },
          { "internalType": "uint64", "name": "issuedAt", "type": "uint64" },
          { "internalType": "uint64", "name": "expiresAt", "type": "uint64" },
          { "internalType": "uint256", "name": "nonce", "type": "uint256" },
          { "internalType": "uint8", "name": "status", "type": "uint8" }
        ],
        "internalType": "struct ICapabilityRegistry.Capability",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "bytes32", "name": "capId", "type": "bytes32" }
    ],
    "name": "isCapabilityValid",
    "outputs": [
      { "internalType": "bool", "name": "", "type": "bool" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "bytes32", "name": "capId", "type": "bytes32" }
    ],
    "name": "getRemainingAuthority",
    "outputs": [
      { "internalType": "uint256", "name": "", "type": "uint256" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCapabilityCount",
    "outputs": [
      { "internalType": "uint256", "name": "", "type": "uint256" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "address", "name": "agent", "type": "address" }
    ],
    "name": "getAgentCapabilities",
    "outputs": [
      { "internalType": "bytes32[]", "name": "", "type": "bytes32[]" }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "bytes32", "name": "capId", "type": "bytes32" },
      { "indexed": true, "internalType": "address", "name": "subject", "type": "address" },
      { "indexed": false, "internalType": "bytes32", "name": "action", "type": "bytes32" },
      { "indexed": false, "internalType": "uint256", "name": "maxAmount", "type": "uint256" },
      { "indexed": false, "internalType": "uint64", "name": "expiresAt", "type": "uint64" }
    ],
    "name": "CapabilityCreated",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "bytes32", "name": "capId", "type": "bytes32" },
      { "indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "remaining", "type": "uint256" }
    ],
    "name": "CapabilityConsumed",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "bytes32", "name": "capId", "type": "bytes32" },
      { "indexed": false, "internalType": "string", "name": "reason", "type": "string" }
    ],
    "name": "CapabilityRevoked",
    "type": "event"
  }
] as const;
