import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

type TraderRegime = 'risk_on' | 'neutral' | 'risk_off';

export interface RegimeNoiseTraderAgentParams extends BaseProtocolAgentParams {
  regimeSwitchProbability?: number;
  minTrade?: bigint;
  maxTrade?: bigint;
}

/**
 * Stochastic noise trader with volatility regimes.
 */
export class RegimeNoiseTraderAgent extends BaseProtocolAgent {
  private regime: TraderRegime = 'neutral';

  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const regimeSwitchProbability =
      (this.params.regimeSwitchProbability as number | undefined) ?? 0.18;
    const minTrade = (this.params.minTrade as bigint | undefined) ?? BigInt(20e18);
    const maxTrade = (this.params.maxTrade as bigint | undefined) ?? BigInt(180e18);
    const gossipSignal = this.readGossipSignal(ctx);

    if (this.shouldAct(ctx, regimeSwitchProbability)) {
      this.regime = ctx.rng.pickOne(['risk_on', 'neutral', 'risk_off']);
    }

    const target = this.chooseRandomApp(ctx);
    if (!target || target.graduated) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'no_trade_target',
        context: {
          regime: this.regime,
          appCount: this.getAppCount(),
          gossipReads: gossipSignal.count,
          bullishSignals: gossipSignal.bullishSignals,
          bearishSignals: gossipSignal.bearishSignals,
        },
      });
      return null;
    }

    const tradeAmount = this.randomAmount(minTrade, maxTrade, ctx);
    if (tradeAmount <= 0n) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'invalid_trade_amount',
        context: {
          regime: this.regime,
          minTrade,
          maxTrade,
          gossipReads: gossipSignal.count,
        },
      });
      return null;
    }

    if (
      this.regime === 'risk_on' &&
      this.hasEnoughElta(tradeAmount) &&
      this.shouldAct(ctx, gossipSignal.bullishSignals > 0 ? 0.82 : 0.72)
    ) {
      this.recordDecisionMemory(ctx, {
        decision: 'buy_app_token',
        reason: 'regime_risk_on_buy',
        context: {
          regime: this.regime,
          appId: String(target.id),
          tradeAmount,
          gossipReads: gossipSignal.count,
          bullishSignals: gossipSignal.bullishSignals,
        },
      });
      return this.createAction(
        'buy_app_token',
        buyAppToken(String(target.id), target.tokenAddress, tradeAmount),
        ctx.tick
      );
    }

    const held = this.getAppTokenBalance(String(target.id));
    if (
      this.regime === 'risk_off' &&
      held > 0n &&
      this.shouldAct(ctx, gossipSignal.bearishSignals > 0 ? 0.78 : 0.68)
    ) {
      this.recordDecisionMemory(ctx, {
        decision: 'sell_app_token',
        reason: 'regime_risk_off_sell',
        context: {
          regime: this.regime,
          appId: String(target.id),
          held,
          gossipReads: gossipSignal.count,
          bearishSignals: gossipSignal.bearishSignals,
        },
      });
      return this.createAction(
        'sell_app_token',
        sellAppToken(String(target.id), target.tokenAddress, held / 2n || held),
        ctx.tick
      );
    }

    if (this.regime === 'neutral' && this.shouldAct(ctx, 0.45)) {
      if (held > BigInt(40e18) && this.shouldAct(ctx, 0.5)) {
        this.recordDecisionMemory(ctx, {
          decision: 'sell_app_token',
          reason: 'regime_neutral_trim',
          context: {
            regime: this.regime,
            appId: String(target.id),
            held,
            gossipReads: gossipSignal.count,
          },
        });
        return this.createAction(
          'sell_app_token',
          sellAppToken(String(target.id), target.tokenAddress, held / 3n || held),
          ctx.tick
        );
      }
      if (this.hasEnoughElta(minTrade)) {
        this.recordDecisionMemory(ctx, {
          decision: 'buy_app_token',
          reason: 'regime_neutral_probe_buy',
          context: {
            regime: this.regime,
            appId: String(target.id),
            minTrade,
            gossipReads: gossipSignal.count,
            bullishSignals: gossipSignal.bullishSignals,
          },
        });
        return this.createAction(
          'buy_app_token',
          buyAppToken(String(target.id), target.tokenAddress, minTrade),
          ctx.tick
        );
      }
    }

    this.recordDecisionMemory(ctx, {
      decision: 'no_op',
      reason: 'regime_condition_not_met',
      context: {
        regime: this.regime,
        appId: String(target.id),
        held,
        gossipReads: gossipSignal.count,
        bullishSignals: gossipSignal.bullishSignals,
        bearishSignals: gossipSignal.bearishSignals,
        lastGossipChannel: gossipSignal.lastChannel ?? 'none',
      },
    });
    return null;
  }

  private readGossipSignal(ctx: TickContext): {
    count: number;
    bullishSignals: number;
    bearishSignals: number;
    lastChannel?: string;
  } {
    if (!ctx.gossip) return { count: 0, bullishSignals: 0, bearishSignals: 0 };
    const inbox = ctx.gossip.readInbox(this.id);
    if (inbox.length === 0) return { count: 0, bullishSignals: 0, bearishSignals: 0 };
    let bullishSignals = 0;
    let bearishSignals = 0;
    for (const msg of inbox) {
      const text = msg.payload.text.toLowerCase();
      if (text.includes('buy') || text.includes('bull') || text.includes('accumulate')) {
        bullishSignals += 1;
      }
      if (
        text.includes('sell') ||
        text.includes('risk') ||
        text.includes('bear') ||
        text.includes('dump')
      ) {
        bearishSignals += 1;
      }
    }
    const lastChannel = inbox[inbox.length - 1]?.envelope.channelId;
    return {
      count: inbox.length,
      bullishSignals,
      bearishSignals,
      ...(lastChannel ? { lastChannel } : {}),
    };
  }
}
