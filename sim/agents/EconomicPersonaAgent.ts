import type { PersonaProfile, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';

export class EconomicPersonaAgent extends BaseElataPersonaLlmAgent {
  protected getPersonaProfile(): PersonaProfile {
    return {
      id: 'economic',
      style: 'risk-adjusted allocator',
      goals: ['Accumulate yield opportunities', 'Protect downside with inventory management'],
      riskProfile: 'balanced',
      constraints: ['Avoid over-concentration in one app'],
      preferredTools: ['QueryWorld', 'buy_app_token', 'sell_app_token'],
    };
  }

  protected getAllowedProtocolActions(): string[] {
    return ['buy_app_token', 'sell_app_token', 'noop'];
  }

  protected getFallbackIntent(ctx: TickContext) {
    const target = this.chooseRandomApp(ctx);
    if (!target || target.graduated) {
      return {
        name: 'QueryWorld',
        params: { endpoint: this.getQueryEndpointHint(), params: {} },
        metadata: { confidence: 0.6 },
      };
    }

    if (ctx.tick % 3 === 0 && this.getAppTokenBalance(String(target.id)) > 0n) {
      const held = this.getAppTokenBalance(String(target.id));
      const sell = sellAppToken(String(target.id), target.tokenAddress, held);
      return {
        name: 'sell_app_token',
        params: {
          appId: sell.appId,
          appAddress: sell.appAddress,
          tokenAmount: sell.tokenAmount,
          minEltaOut: sell.minEltaOut,
        },
        rationale: 'Realize gains and rebalance exposure.',
        metadata: { confidence: 0.65 },
      };
    }

    const buyAmount = BigInt(40e18);
    if (!this.hasEnoughElta(buyAmount)) {
      return { name: 'noop', params: { reason: 'reserve_preservation' } };
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
      rationale: 'Allocate ELTA into active app market.',
      metadata: { confidence: 0.7 },
    };
  }
}
