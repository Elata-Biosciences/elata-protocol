import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { closeFeeEpoch, sweepEltaToFeeManager, sweepFees } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

export interface EpochFeeClaimerAgentParams extends BaseProtocolAgentParams {
  closeEveryTicks?: number;
  sweepEveryTicks?: number;
  appIdForFeeManagerSweep?: number;
}

/**
 * Deterministic fee pipeline keeper:
 * - sweeps fees on a fixed cadence
 * - closes epochs on a fixed cadence
 */
export class EpochFeeClaimerAgent extends BaseProtocolAgent {
  async step(ctx: TickContext): Promise<Action | null> {
    const closeEveryTicks = (this.params.closeEveryTicks as number | undefined) ?? 8;
    const sweepEveryTicks = (this.params.sweepEveryTicks as number | undefined) ?? 4;
    const appIdForFeeManagerSweep =
      (this.params.appIdForFeeManagerSweep as number | undefined) ?? 0;

    if (this.isScheduledTick(sweepEveryTicks, ctx)) {
      const curves = this.getCurvesWithPendingFees();
      if (curves.length > 0) {
        return this.createAction('sweep_fees', sweepFees(curves[0]!), ctx.tick);
      }
      return this.createAction(
        'sweep_elta_to_feemanager',
        sweepEltaToFeeManager(appIdForFeeManagerSweep),
        ctx.tick
      );
    }

    if (this.isScheduledTick(closeEveryTicks, ctx)) {
      return this.createAction('close_fee_epoch', closeFeeEpoch(appIdForFeeManagerSweep), ctx.tick);
    }

    return null;
  }
}
