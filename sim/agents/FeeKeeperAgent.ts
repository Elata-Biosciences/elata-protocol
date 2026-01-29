/**
 * FeeKeeperAgent - Maintains the fee pipeline
 *
 * Behavior:
 * - Sweeps accumulated fees from bonding curves to FeeCollector
 * - Sweeps ELTA from FeeCollector to FeeManager
 * - Closes fee epochs to trigger distribution (earns incentive)
 * - Closes epochs for both protocol fees (appId 0) and app-specific fees (appId 1+)
 * - Monitors fee accumulation and optimizes timing
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { closeFeeEpoch, sweepFees, sweepEltaToFeeManager } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for FeeKeeperAgent
 */
export interface FeeKeeperAgentParams extends BaseProtocolAgentParams {
  /** Probability of sweeping fees each tick */
  sweepProbability?: number;
  /** Probability of closing epoch each tick */
  closeEpochProbability?: number;
  /** Probability of sweeping ELTA from FeeCollector to FeeManager */
  sweepEltaProbability?: number;
  /** Minimum fees to trigger sweep (in ELTA wei) */
  minFeesToSweep?: bigint;
  /** Ticks between epoch close attempts */
  epochCloseCooldown?: number;
}

/**
 * Agent that maintains the fee pipeline by sweeping fees and closing epochs
 */
export class FeeKeeperAgent extends BaseProtocolAgent {
  /** Track last epoch close tick per appId */
  private lastEpochCloseByApp: Map<number, number> = new Map();

  /** Track curves we've swept recently */
  private recentlySweped: Set<string> = new Set();

  /** Track apps we've swept ELTA for recently */
  private recentlySweptElta: Set<number> = new Set();

  /** Track which appIds we've attempted to close recently */
  private recentlyClosedEpochs: Set<number> = new Set();

  async step(ctx: TickContext): Promise<Action | null> {
    const sweepProb = (this.params.sweepProbability as number | undefined) ?? 0.3;
    const sweepEltaProb = (this.params.sweepEltaProbability as number | undefined) ?? 0.4;
    const closeProb = (this.params.closeEpochProbability as number | undefined) ?? 0.2;
    const minFees = (this.params.minFeesToSweep as bigint | undefined) ?? BigInt(100e18);
    const cooldown = (this.params.epochCloseCooldown as number | undefined) ?? 5;

    // Priority 1: Close fee epoch if cooldown passed (for any appId that's ready)
    if (this.shouldAct(ctx, closeProb)) {
      const epochAction = this.considerClosingEpoch(ctx, cooldown);
      if (epochAction) {
        return epochAction;
      }
    }

    // Priority 2: Sweep ELTA from FeeCollector to FeeManager
    if (this.shouldAct(ctx, sweepEltaProb)) {
      const sweepEltaAction = this.considerSweepingEltaToFeeManager(ctx);
      if (sweepEltaAction) {
        return sweepEltaAction;
      }
    }

    // Priority 3: Sweep fees from curves to FeeCollector
    if (this.shouldAct(ctx, sweepProb)) {
      const sweepAction = this.considerSweepingFees(ctx, minFees);
      if (sweepAction) {
        return sweepAction;
      }
    }

    return null;
  }

  /**
   * Consider sweeping fees from bonding curves
   */
  private considerSweepingFees(ctx: TickContext, minFees: bigint): Action | null {
    const curves = this.getCurvesWithPendingFees();
    if (curves.length === 0) return null;

    // Find a curve we haven't swept recently
    const candidateCurves = curves.filter((addr) => !this.recentlySweped.has(addr));
    if (candidateCurves.length === 0) {
      // Clear the set and start fresh
      this.recentlySweped.clear();
      return null;
    }

    // Check if estimated fees are worth sweeping
    const estimatedFees = this.getEstimatedPendingFees();
    if (estimatedFees < minFees) {
      return null;
    }

    // Pick a random curve to sweep
    const curveAddress = ctx.rng.pickOne(candidateCurves);
    this.recentlySweped.add(curveAddress);

    ctx.logger.info(
      { agent: this.id, curve: curveAddress, estimatedFees: this.formatElta(estimatedFees) },
      'Sweeping fees from curve'
    );

    return this.createAction('sweep_fees', sweepFees(curveAddress), ctx.tick);
  }

  /**
   * Consider sweeping ELTA from FeeCollector to FeeManager
   * This is step 2 of the fee pipeline, after sweepFees from curves
   */
  private considerSweepingEltaToFeeManager(ctx: TickContext): Action | null {
    // Get all known app IDs from world state
    const worldState = this.pack?.getWorldState();
    if (!worldState) return null;

    // Get active app count
    const appCount = (worldState as { appCount?: number }).appCount ?? 0;
    if (appCount === 0) return null;

    // Try to sweep for each app ID, prioritizing ones we haven't swept recently
    const appIds: number[] = [];
    for (let i = 0; i < appCount; i++) {
      if (!this.recentlySweptElta.has(i)) {
        appIds.push(i);
      }
    }

    if (appIds.length === 0) {
      // Clear and start fresh
      this.recentlySweptElta.clear();
      return null;
    }

    // Pick a random app to sweep
    const appId = ctx.rng.pickOne(appIds);
    this.recentlySweptElta.add(appId);

    ctx.logger.info({ agent: this.id, appId }, 'Sweeping ELTA from FeeCollector to FeeManager');

    return this.createAction('sweep_elta_to_feemanager', sweepEltaToFeeManager(appId), ctx.tick);
  }

  /**
   * Consider closing the fee epoch for any eligible appId
   * Iterates through appId 0 (protocol fees) and all known app IDs (1+)
   */
  private considerClosingEpoch(ctx: TickContext, cooldown: number): Action | null {
    if (!this.canCloseFeeEpoch()) {
      return null;
    }

    // Get all known app IDs from world state
    const worldState = this.pack?.getWorldState();
    const appCount = (worldState as { appCount?: number })?.appCount ?? 0;

    // Build list of all appIds to consider: 0 (protocol fees) + all app IDs
    const appIdsToConsider: number[] = [0]; // Always include appId 0 for protocol fees
    for (let i = 1; i <= appCount; i++) {
      appIdsToConsider.push(i);
    }

    // Filter to appIds that haven't been closed recently
    const eligibleAppIds = appIdsToConsider.filter((appId) => {
      const lastClose = this.lastEpochCloseByApp.get(appId) ?? 0;
      return ctx.tick - lastClose >= cooldown && !this.recentlyClosedEpochs.has(appId);
    });

    if (eligibleAppIds.length === 0) {
      // Clear recent set and try again next time
      this.recentlyClosedEpochs.clear();
      return null;
    }

    // Pick a random appId to close
    const appIdToClose = ctx.rng.pickOne(eligibleAppIds);
    this.lastEpochCloseByApp.set(appIdToClose, ctx.tick);
    this.recentlyClosedEpochs.add(appIdToClose);

    ctx.logger.info(
      { agent: this.id, appId: appIdToClose },
      `Closing fee epoch for appId ${appIdToClose} to trigger distribution`
    );

    return this.createAction('close_fee_epoch', closeFeeEpoch(appIdToClose), ctx.tick);
  }
}
