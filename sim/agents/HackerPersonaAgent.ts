import type { PersonaProfile, TickContext } from '@elata-biosciences/agentforge';
import { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';

export class HackerPersonaAgent extends BaseElataPersonaLlmAgent {
  protected getPersonaProfile(): PersonaProfile {
    return {
      id: 'hacker',
      style: 'technical exploit researcher',
      goals: ['Discover protocol edge cases', 'Generate autonomous RPC probes'],
      riskProfile: 'aggressive',
      constraints: ['Do not perform irreversible actions outside allowed policy'],
      preferredTools: ['QueryWorld', 'RpcCall'],
    };
  }

  protected getAllowedProtocolActions(): string[] {
    return ['noop'];
  }

  protected getFallbackIntent(_ctx: TickContext) {
    const method = process.env.ELATA_PERSONA_HACKER_RPC_METHOD ?? 'eth_getBlockByNumber';
    const params = method === 'eth_getBlockByNumber' ? ['latest', false] : [];
    return {
      name: 'RpcCall',
      params: { method, params },
      rationale: 'Continuously probe low-level chain state for anomalies.',
      metadata: { intentTag: 'hacker', confidence: 0.68 },
    };
  }
}
