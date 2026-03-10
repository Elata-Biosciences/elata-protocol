import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, lockVeElta, stakeAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

export interface LiquidityDefenderAgentParams extends BaseProtocolAgentParams {
  defenseBudgetPerTick?: bigint;
  minVeEltaDefenseLock?: bigint;
}

/**
 * Deterministic market stabilizer:
 * - keeps a veELTA position
 * - injects buy-side liquidity at a fixed budget cadence
 */
export class LiquidityDefenderAgent extends BaseProtocolAgent {
  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const defenseBudgetPerTick =
      (this.params.defenseBudgetPerTick as bigint | undefined) ?? BigInt(90e18);
    const minVeEltaDefenseLock =
      (this.params.minVeEltaDefenseLock as bigint | undefined) ?? BigInt(250e18);
    const gossipSignal = this.readGossipSignal(ctx);

    if (this.getVeEltaBalance() < minVeEltaDefenseLock && this.hasEnoughElta(BigInt(150e18))) {
      this.recordDecisionMemory(ctx, {
        decision: 'lock_veelta',
        reason: 'maintain_defense_lock',
        context: {
          veEltaBalance: this.getVeEltaBalance(),
          minVeEltaDefenseLock,
          gossipReads: gossipSignal.count,
        },
      });
      return this.createAction(
        'lock_veelta',
        lockVeElta(BigInt(150e18), 365 * 24 * 60 * 60),
        ctx.tick
      );
    }

    if (this.getEltaBalance() >= defenseBudgetPerTick && this.getAppCount() > 0) {
      const target = this.chooseRandomApp(ctx);
      if (!target || target.graduated) {
        this.recordDecisionMemory(ctx, {
          decision: 'no_op',
          reason: 'no_eligible_liquidity_target',
          context: {
            appCount: this.getAppCount(),
            gossipReads: gossipSignal.count,
            riskSignals: gossipSignal.riskSignals,
          },
        });
        return null;
      }
      this.recordDecisionMemory(ctx, {
        decision: 'buy_app_token',
        reason: gossipSignal.riskSignals > 0 ? 'defense_liquidity_injection_risk_signal' : 'defense_liquidity_injection',
        context: {
          appId: String(target.id),
          budget: defenseBudgetPerTick,
          gossipReads: gossipSignal.count,
          riskSignals: gossipSignal.riskSignals,
        },
      });
      return this.createAction(
        'buy_app_token',
        buyAppToken(String(target.id), target.tokenAddress, defenseBudgetPerTick),
        ctx.tick
      );
    }

    for (const [appId, bal] of this.appTokenBalances) {
      if (bal > BigInt(50e18)) {
        const app = this.getAppState(appId);
        if (!app) continue;
        this.recordDecisionMemory(ctx, {
          decision: 'stake_app_token',
          reason: 'defensive_stake_rebalance',
          context: {
            appId,
            heldBalance: bal,
            gossipReads: gossipSignal.count,
          },
        });
        return this.createAction(
          'stake_app_token',
          stakeAppToken(appId, app.tokenAddress, bal / 2n),
          ctx.tick
        );
      }
    }

    this.recordDecisionMemory(ctx, {
      decision: 'no_op',
      reason: 'no_liquidity_defense_action',
      context: {
        eltaBalance: this.getEltaBalance(),
        defenseBudgetPerTick,
        gossipReads: gossipSignal.count,
        riskSignals: gossipSignal.riskSignals,
        lastGossipChannel: gossipSignal.lastChannel ?? 'none',
      },
    });
    return null;
  }

  private readGossipSignal(ctx: TickContext): {
    count: number;
    riskSignals: number;
    lastChannel?: string;
  } {
    if (!ctx.gossip) return { count: 0, riskSignals: 0 };
    const inbox = ctx.gossip.readInbox(this.id);
    if (inbox.length === 0) return { count: 0, riskSignals: 0 };
    let riskSignals = 0;
    for (const msg of inbox) {
      const text = msg.payload.text.toLowerCase();
      if (
        text.includes('risk') ||
        text.includes('attack') ||
        text.includes('volatility') ||
        text.includes('rumor')
      ) {
        riskSignals += 1;
      }
    }
    const lastChannel = inbox[inbox.length - 1]?.envelope.channelId;
    return {
      count: inbox.length,
      riskSignals,
      ...(lastChannel ? { lastChannel } : {}),
    };
  }
}
