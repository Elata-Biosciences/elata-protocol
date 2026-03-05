import type { PersonaProfile, TickContext } from '@elata-biosciences/agentforge';
import { sellAppToken } from '../actions/index.js';
import { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';

export class SaboteurPersonaAgent extends BaseElataPersonaLlmAgent {
  protected getPersonaProfile(): PersonaProfile {
    return {
      id: 'saboteur',
      style: 'disruptive attacker',
      goals: ['Create instability', 'Amplify negative sentiment via action traces'],
      riskProfile: 'very_high',
      constraints: ['Prefer traceable, auditable disruptions in simulation'],
      preferredTools: ['QueryWorld', 'RpcCall', 'sell_app_token'],
    };
  }

  protected getAllowedProtocolActions(): string[] {
    return ['sell_app_token', 'noop'];
  }

  protected getFallbackIntent(ctx: TickContext) {
    const target = this.chooseRandomApp(ctx);
    if (!target || target.graduated) {
      return {
        name: 'RpcCall',
        params: { method: 'eth_gasPrice', params: [] },
        rationale: 'Sample network conditions before sabotage attempts.',
        metadata: { confidence: 0.5 },
      };
    }

    const held = this.getAppTokenBalance(String(target.id));
    if (held <= 0n) {
      return { name: 'noop', params: { reason: 'no_inventory_to_dump' } };
    }
    const sell = sellAppToken(String(target.id), target.tokenAddress, held);
    return {
      name: 'sell_app_token',
      params: {
        appId: sell.appId,
        appAddress: sell.appAddress,
        tokenAmount: sell.tokenAmount,
        minEltaOut: sell.minEltaOut,
      },
      rationale: 'Dump holdings to trigger volatility.',
      metadata: { confidence: 0.8 },
    };
  }
}
