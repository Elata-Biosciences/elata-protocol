import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimRewards, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

type StakeState = 'accumulate' | 'lock_bias' | 'claim_bias';

export interface ProbabilisticStakerAgentParams extends BaseProtocolAgentParams {
  stateSwitchProbability?: number;
  minLockAmount?: bigint;
}

/**
 * Stochastic veELTA participant with state-dependent transitions.
 */
export class ProbabilisticStakerAgent extends BaseProtocolAgent {
  private state: StakeState = 'accumulate';

  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const stateSwitchProbability =
      (this.params.stateSwitchProbability as number | undefined) ?? 0.2;
    const minLockAmount = (this.params.minLockAmount as bigint | undefined) ?? BigInt(120e18);

    if (this.shouldAct(ctx, stateSwitchProbability)) {
      this.state = ctx.rng.pickOne(['accumulate', 'lock_bias', 'claim_bias']);
    }

    if (this.state === 'accumulate') {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'state_accumulate',
        context: {
          state: this.state,
        },
      });
      return null;
    }

    if (
      this.state === 'lock_bias' &&
      this.hasEnoughElta(minLockAmount) &&
      this.shouldAct(ctx, 0.7)
    ) {
      const lockAmount = this.randomAmount(minLockAmount, minLockAmount * 3n, ctx);
      this.recordDecisionMemory(ctx, {
        decision: 'lock_veelta',
        reason: 'state_lock_bias',
        context: {
          state: this.state,
          lockAmount,
          minLockAmount,
        },
      });
      return this.createAction('lock_veelta', lockVeElta(lockAmount, 365 * 24 * 60 * 60), ctx.tick);
    }

    if (this.state === 'claim_bias' && this.getVeEltaBalance() > 0n && this.shouldAct(ctx, 0.65)) {
      const hasClaimable = await this.hasClaimableVeEltaRewards();
      if (hasClaimable) {
        this.recordDecisionMemory(ctx, {
          decision: 'claim_rewards',
          reason: 'state_claim_bias',
          context: {
            state: this.state,
            veEltaBalance: this.getVeEltaBalance(),
          },
        });
        return this.createAction('claim_rewards', claimRewards(), ctx.tick);
      }
    }

    this.recordDecisionMemory(ctx, {
      decision: 'no_op',
      reason: 'state_condition_not_met',
      context: {
        state: this.state,
        minLockAmount,
      },
    });
    return null;
  }
}
