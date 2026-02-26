import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

type AttackMode = 'probe' | 'burst_buy' | 'burst_sell';

export interface OpportunisticAttackerAgentParams extends BaseProtocolAgentParams {
  attackWindowProbability?: number;
  attackBudget?: bigint;
}

/**
 * Stochastic adversarial agent:
 * randomizes attack windows and direction within a risk budget.
 */
export class OpportunisticAttackerAgent extends BaseProtocolAgent {
  private mode: AttackMode = 'probe';

  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const attackWindowProbability =
      (this.params.attackWindowProbability as number | undefined) ?? 0.2;
    const attackBudget = (this.params.attackBudget as bigint | undefined) ?? BigInt(220e18);

    if (!this.shouldAct(ctx, attackWindowProbability)) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'attack_window_closed',
        context: {
          attackWindowProbability,
        },
      });
      return null;
    }

    this.mode = ctx.rng.pickOne(['probe', 'burst_buy', 'burst_sell']);
    const target = this.chooseRandomApp(ctx);
    if (!target || target.graduated) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'no_attack_target',
        context: {
          mode: this.mode,
          appCount: this.getAppCount(),
        },
      });
      return null;
    }

    if (this.mode === 'probe') {
      if (this.hasEnoughElta(BigInt(30e18))) {
        this.recordDecisionMemory(ctx, {
          decision: 'buy_app_token',
          reason: 'probe_buy',
          context: {
            mode: this.mode,
            appId: String(target.id),
            amount: BigInt(30e18),
          },
        });
        return this.createAction(
          'buy_app_token',
          buyAppToken(String(target.id), target.tokenAddress, BigInt(30e18)),
          ctx.tick
        );
      }
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'probe_insufficient_elta',
        context: {
          mode: this.mode,
          appId: String(target.id),
        },
      });
      return null;
    }

    if (this.mode === 'burst_buy') {
      if (!this.hasEnoughElta(attackBudget)) {
        this.recordDecisionMemory(ctx, {
          decision: 'no_op',
          reason: 'burst_buy_insufficient_elta',
          context: {
            mode: this.mode,
            appId: String(target.id),
            attackBudget,
          },
        });
        return null;
      }
      this.recordDecisionMemory(ctx, {
        decision: 'buy_app_token',
        reason: 'burst_buy_execute',
        context: {
          mode: this.mode,
          appId: String(target.id),
          attackBudget,
        },
      });
      return this.createAction(
        'buy_app_token',
        buyAppToken(String(target.id), target.tokenAddress, attackBudget),
        ctx.tick
      );
    }

    const held = this.getAppTokenBalance(String(target.id));
    if (held > 0n) {
      this.recordDecisionMemory(ctx, {
        decision: 'sell_app_token',
        reason: 'burst_sell_execute',
        context: {
          mode: this.mode,
          appId: String(target.id),
          held,
        },
      });
      return this.createAction(
        'sell_app_token',
        sellAppToken(String(target.id), target.tokenAddress, held),
        ctx.tick
      );
    }

    this.recordDecisionMemory(ctx, {
      decision: 'no_op',
      reason: 'burst_sell_no_inventory',
      context: {
        mode: this.mode,
        appId: String(target.id),
      },
    });
    return null;
  }
}
