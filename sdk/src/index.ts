import { AtlasClient } from './client';
import { AtlasConfig, Capability, Evidence, Policy } from './types';

export { AtlasClient } from './client';
export { AtlasConfig, Capability, Evidence, Policy, CapabilityStatus } from './types';

export function connect(config: AtlasConfig): AtlasClient {
  return new AtlasClient(config);
}
