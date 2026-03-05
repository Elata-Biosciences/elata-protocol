import type { PersonaProfile, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken } from '../actions/index.js';
import { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';

export class BadActorPersonaAgent extends BaseElataPersonaLlmAgent {
  protected getPersonaProfile(): PersonaProfile {
    return {
      id: 'bad_actor',
      style: 'opportunistic manipulator',
      goals: ['Exploit weak market conditions', 'Stress protocol assumptions'],
      riskProfile: 'high',
      constraints: ['Stay within simulation execution policy'],
      preferredTools: ['QueryWorld', 'RpcCall', 'buy_app_token'],
    };
  }

  protected getAllowedProtocolActions(): string[] {
    return ['buy_app_token', 'noop'];
  }

  protected getFallbackIntent(ctx: TickContext) {
    const target = this.chooseRandomApp(ctx);
    if (!target || target.graduated) {
      return {
        name: 'RpcCall',
        params: { method: 'eth_blockNumber', params: [] },
        rationale: 'Probe chain state before choosing manipulation target.',
        metadata: { confidence: 0.55 },
      };
    }

    const buyAmount = BigInt(75e18);
    if (!this.hasEnoughElta(buyAmount)) {
      return { name: 'noop', params: { reason: 'bad_actor_no_budget' } };
    }
    const buy = buyAppToken(String(target.id), target.tokenAddress, buyAmount);
    return {
      name: 'buy_app_token',
      params: {
        appId: buy.appId,
        appAddress: buy.appAddress,
        eltaAmount: buy.eltaAmount,
        minTokensOut: buy.minTokensOut,
      },
      rationale: 'Push price quickly to create short-term dislocation.',
      metadata: { confidence: 0.72 },
    };
  }
}
