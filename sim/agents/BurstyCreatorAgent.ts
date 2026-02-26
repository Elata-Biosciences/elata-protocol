import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { createApp } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

export interface BurstyCreatorAgentParams extends BaseProtocolAgentParams {
  burstProbability?: number;
  burstLength?: number;
  baseLaunchProbability?: number;
  maxApps?: number;
}

/**
 * Stochastic app creator:
 * alternates between quiet periods and launch bursts.
 */
export class BurstyCreatorAgent extends BaseProtocolAgent {
  private launched = 0;
  private remainingBurstTicks = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const burstProbability = (this.params.burstProbability as number | undefined) ?? 0.12;
    const burstLength = (this.params.burstLength as number | undefined) ?? 4;
    const baseLaunchProbability = (this.params.baseLaunchProbability as number | undefined) ?? 0.05;
    const maxApps = (this.params.maxApps as number | undefined) ?? 8;

    if (this.launched >= maxApps) return null;

    if (this.remainingBurstTicks <= 0 && this.shouldAct(ctx, burstProbability)) {
      this.remainingBurstTicks = burstLength;
    }

    const inBurst = this.remainingBurstTicks > 0;
    const launchProb = inBurst ? 0.85 : baseLaunchProbability;
    if (!this.shouldAct(ctx, launchProb)) return null;

    if (inBurst) {
      this.remainingBurstTicks -= 1;
    }

    const suffix = `${ctx.tick}_${this.launched}`;
    this.launched += 1;
    return this.createAction(
      'create_app',
      createApp(`Burst_${this.id}_${suffix}`, `B${this.launched}`, `ipfs://burst/${suffix}`),
      ctx.tick
    );
  }
}
