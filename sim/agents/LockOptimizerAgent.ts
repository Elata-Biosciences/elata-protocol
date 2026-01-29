/**
 * LockOptimizerAgent - Optimizes lock durations for maximum benefit
 *
 * Behavior:
 * - Analyzes optimal lock periods based on rewards
 * - Creates tiered lock positions
 * - Rebalances between lock tiers
 * - Maximizes yield/voting power ratio
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { lockVeElta, extendVeEltaLock } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Lock tier configuration
 */
interface LockTier {
  durationYears: number;
  durationSeconds: number;
  allocationPercent: number;
  amount: bigint;
}

/**
 * Parameters for LockOptimizerAgent
 */
export interface LockOptimizerAgentParams extends BaseProtocolAgentParams {
  /** Whether to use tiered locking strategy (default true) */
  useTieredStrategy?: boolean;
  /** Maximum percentage of ELTA to lock (default 0.8 = 80%) */
  maxLockPercent?: number;
  /** Minimum amount per lock tier (default 20 ELTA) */
  minTierAmount?: bigint;
  /** Custom tier allocations (default: 40% 4yr, 30% 2yr, 20% 1yr, 10% 6mo) */
  tierAllocations?: number[];
}

/**
 * Lock optimizer - maximizes returns from staking
 */
export class LockOptimizerAgent extends BaseProtocolAgent {
  /** Lock tiers */
  private lockTiers: LockTier[] = [];

  /** Whether initial setup is complete */
  private initialized = false;

  /** Current tier being built */
  private currentTierIndex = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const useTiered = (this.params.useTieredStrategy as boolean | undefined) ?? true;
    const maxLockPct = (this.params.maxLockPercent as number | undefined) ?? 0.8;
    const minTier = (this.params.minTierAmount as bigint | undefined) ?? BigInt(20e18);
    const tierAllocs = (this.params.tierAllocations as number[] | undefined) ?? [0.4, 0.3, 0.2, 0.1];

    // Initialize tiers on first run
    if (!this.initialized) {
      this.initializeTiers(tierAllocs);
      this.initialized = true;
    }

    // Build tiered positions
    if (useTiered && this.shouldAct(ctx, 0.3)) {
      const lockAction = this.buildTieredPosition(ctx, maxLockPct, minTier);
      if (lockAction) return lockAction;
    }

    // Optimize existing positions
    if (this.shouldAct(ctx, 0.1)) {
      const optimizeAction = this.optimizePositions(ctx);
      if (optimizeAction) return optimizeAction;
    }

    return null;
  }

  /**
   * Initialize lock tiers
   */
  private initializeTiers(allocations: number[]): void {
    const durations = [
      { years: 4, seconds: 4 * 365 * 24 * 60 * 60 },
      { years: 2, seconds: 2 * 365 * 24 * 60 * 60 },
      { years: 1, seconds: 365 * 24 * 60 * 60 },
      { years: 0.5, seconds: 183 * 24 * 60 * 60 },
    ];

    this.lockTiers = durations.map((d, i) => ({
      durationYears: d.years,
      durationSeconds: d.seconds,
      allocationPercent: allocations[i] ?? 0.25,
      amount: 0n,
    }));
  }

  /**
   * Build tiered lock positions
   */
  private buildTieredPosition(
    ctx: TickContext,
    maxLockPct: number,
    minAmount: bigint
  ): Action | null {
    const balance = this.getEltaBalance();
    if (balance < minAmount) return null;

    // Find the next tier that needs funding
    const totalLockable = BigInt(Math.floor(Number(balance) * maxLockPct));
    
    for (let i = this.currentTierIndex; i < this.lockTiers.length; i++) {
      const tier = this.lockTiers[i]!;
      const targetAmount = BigInt(Math.floor(Number(totalLockable) * tier.allocationPercent));

      if (tier.amount < targetAmount) {
        const needed = targetAmount - tier.amount;
        const lockAmount = needed > balance ? balance : needed;

        if (lockAmount < minAmount) continue;

        // Update tier tracking
        tier.amount += lockAmount;
        this.currentTierIndex = i;

        ctx.logger.info(
          { 
            agent: this.id, 
            tier: tier.durationYears + 'yr',
            amount: this.formatElta(lockAmount),
            tierTotal: this.formatElta(tier.amount)
          },
          'Lock optimizer: Building tier position'
        );

        return this.createAction(
          'lock_veelta',
          lockVeElta(lockAmount, tier.durationSeconds),
          ctx.tick
        );
      }
    }

    // All tiers funded, reset for next round
    this.currentTierIndex = 0;
    return null;
  }

  /**
   * Optimize existing positions
   */
  private optimizePositions(ctx: TickContext): Action | null {
    // Could extend short-term locks to longer terms for better returns
    // For now, just extend 1-year and 6-month locks to longer terms occasionally

    const shortTier = this.lockTiers.find(t => t.durationYears <= 1 && t.amount > 0n);
    if (!shortTier) return null;

    // Probabilistically extend to longer term
    if (ctx.rng.nextFloat() < 0.2) {
      const newDuration = 4 * 365 * 24 * 60 * 60; // Extend to 4 years

      ctx.logger.debug(
        { 
          agent: this.id, 
          from: shortTier.durationYears + 'yr',
          to: '4yr'
        },
        'Lock optimizer: Extending lock duration'
      );

      return this.createAction(
        'extend_veelta_lock',
        extendVeEltaLock(newDuration),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get optimizer statistics
   */
  getSimStats(): {
    tiers: Array<{ duration: string; amount: string }>;
    totalLocked: bigint;
  } {
    let total = 0n;
    const tierStats = this.lockTiers.map(t => {
      total += t.amount;
      return {
        duration: t.durationYears + 'yr',
        amount: this.formatElta(t.amount),
      };
    });

    return {
      tiers: tierStats,
      totalLocked: total,
    };
  }
}
