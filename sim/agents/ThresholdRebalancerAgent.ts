import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

export interface ThresholdRebalancerAgentParams extends BaseProtocolAgentParams {
  minEltaBuffer?: bigint;
  buyChunk?: bigint;
  sellFractionBps?: number;
}

/**
 * Deterministic portfolio rebalancer:
 * - buys when ELTA buffer is large
 * - trims app-token positions when they exceed thresholds
 */
export class ThresholdRebalancerAgent extends BaseProtocolAgent {
  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const minEltaBuffer = (this.params.minEltaBuffer as bigint | undefined) ?? BigInt(300e18);
    const buyChunk = (this.params.buyChunk as bigint | undefined) ?? BigInt(120e18);
    const sellFractionBps = (this.params.sellFractionBps as number | undefined) ?? 2500;

    for (const [appId, bal] of this.appTokenBalances) {
      if (bal > BigInt(400e18)) {
        const app = this.getAppState(appId);
        if (!app) continue;
        const sellAmount = (bal * BigInt(sellFractionBps)) / 10_000n;
        if (sellAmount > 0n) {
          return this.createAction(
            'sell_app_token',
            sellAppToken(appId, app.tokenAddress, sellAmount),
            ctx.tick
          );
        }
      }
    }

    if (this.getEltaBalance() > minEltaBuffer + buyChunk) {
      const target = this.chooseAppWithMomentum();
      if (target) {
        return this.createAction(
          'buy_app_token',
          buyAppToken(String(target.id), target.tokenAddress, buyChunk),
          ctx.tick
        );
      }
    }

    return null;
  }
}
