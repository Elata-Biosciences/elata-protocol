/**
 * YieldMaximizerAgent - Maximizes yield across all protocol opportunities
 *
 * Behavior:
 * - Analyzes all yield sources (staking, app staking, LPing)
 * - Allocates capital to highest yield opportunities
 * - Rebalances based on yield changes
 * - Claims and reinvests rewards
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { lockVeElta, buyAppToken, claimRewards } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Yield source tracking
 */
interface YieldSource {
  type: 'veelta' | 'app_stake' | 'bonding_curve';
  appId?: string;
  apy: number;
  allocation: bigint;
}

/**
 * Parameters for YieldMaximizerAgent
 */
export interface YieldMaximizerAgentParams extends BaseProtocolAgentParams {
  /** Target total yield allocation (default 0.7 = 70% of balance) */
  targetAllocation?: number;
  /** Minimum APY to consider (default 0.05 = 5%) */
  minApy?: number;
  /** Rebalance threshold (default 0.1 = 10% drift) */
  rebalanceThreshold?: number;
  /** Claim frequency in ticks (default 20) */
  claimFrequency?: number;
}

/**
 * Yield maximizer - finds and exploits best returns
 */
export class YieldMaximizerAgent extends BaseProtocolAgent {
  /** Current yield allocations */
  private allocations: YieldSource[] = [];

  /** Last claim tick */
  private lastClaimTick = 0;

  /** Total yield earned (estimated) */
  private totalYieldEarned = 0n;

  /** Whether initial allocation is done */
  private initialized = false;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetAlloc = (this.params.targetAllocation as number | undefined) ?? 0.7;
    const minApy = (this.params.minApy as number | undefined) ?? 0.05;
    const rebalanceThresh = (this.params.rebalanceThreshold as number | undefined) ?? 0.1;
    const claimFreq = (this.params.claimFrequency as number | undefined) ?? 20;

    // Priority 1: Claim rewards
    if (ctx.tick - this.lastClaimTick >= claimFreq && this.shouldAct(ctx, 0.6)) {
      const claimAction = this.claimAllRewards(ctx);
      if (claimAction) return claimAction;
    }

    // Priority 2: Initial allocation
    if (!this.initialized && this.shouldAct(ctx, 0.4)) {
      const allocAction = this.initialAllocation(ctx, targetAlloc, minApy);
      if (allocAction) return allocAction;
    }

    // Priority 3: Rebalance to higher yield
    if (this.shouldAct(ctx, 0.2)) {
      const rebalanceAction = this.rebalanceToHigherYield(ctx, minApy, rebalanceThresh);
      if (rebalanceAction) return rebalanceAction;
    }

    return null;
  }

  /**
   * Analyze available yield sources
   */
  private analyzeYieldSources(minApy: number): YieldSource[] {
    const sources: YieldSource[] = [];

    // veELTA staking (simulated APY based on lock duration)
    // 4-year lock: ~15% APY, 1-year: ~5% APY
    sources.push({
      type: 'veelta',
      apy: 0.15, // Assume 4-year lock
      allocation: 0n,
    });

    // App staking opportunities
    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;

      // Simulate APY based on app activity (more volume = higher APY)
      const baseApy = 0.08;
      const volumeBonus = Math.random() * 0.07; // 0-7% bonus based on volume
      const apy = baseApy + volumeBonus;

      if (apy >= minApy) {
        sources.push({
          type: 'app_stake',
          appId,
          apy,
          allocation: 0n,
        });
      }
    }

    // Sort by APY descending
    sources.sort((a, b) => b.apy - a.apy);

    return sources;
  }

  /**
   * Initial capital allocation
   */
  private initialAllocation(
    ctx: TickContext,
    targetPct: number,
    minApy: number
  ): Action | null {
    const balance = this.getEltaBalance();
    const totalToAllocate = BigInt(Math.floor(Number(balance) * targetPct));

    if (totalToAllocate < BigInt(20e18)) {
      this.initialized = true;
      return null;
    }

    // Analyze yield sources
    const sources = this.analyzeYieldSources(minApy);
    if (sources.length === 0) {
      this.initialized = true;
      return null;
    }

    // Allocate to best source first
    const best = sources[0]!;
    const allocationAmount = totalToAllocate / BigInt(sources.length > 3 ? 3 : sources.length);

    if (!this.hasEnoughElta(allocationAmount)) return null;

    // Track allocation
    best.allocation = allocationAmount;
    this.allocations.push(best);

    if (best.type === 'veelta') {
      ctx.logger.info(
        { 
          agent: this.id, 
          type: 'veELTA',
          apy: (best.apy * 100).toFixed(1) + '%',
          amount: this.formatElta(allocationAmount)
        },
        'Yield maximizer: Allocating to veELTA'
      );

      // Check if more allocations needed
      if (this.allocations.length >= 3) {
        this.initialized = true;
      }

      return this.createAction(
        'lock_veelta',
        lockVeElta(allocationAmount, 4 * 365 * 24 * 60 * 60),
        ctx.tick
      );
    } else if (best.type === 'app_stake' && best.appId) {
      const app = this.getAppState(best.appId);
      if (!app) return null;

      ctx.logger.info(
        { 
          agent: this.id, 
          type: 'app_stake',
          app: best.appId,
          apy: (best.apy * 100).toFixed(1) + '%',
          amount: this.formatElta(allocationAmount)
        },
        'Yield maximizer: Allocating to app stake'
      );

      // First need to buy app tokens, then stake
      // For now, just buy the tokens
      if (this.allocations.length >= 3) {
        this.initialized = true;
      }

      return this.createAction(
        'buy_app_token',
        buyAppToken(best.appId, app.tokenAddress, allocationAmount),
        ctx.tick
      );
    }

    this.initialized = true;
    return null;
  }

  /**
   * Claim all available rewards
   */
  private claimAllRewards(ctx: TickContext): Action | null {
    // Check if we have any staked positions
    const hasStakes = this.allocations.some(a => a.type === 'app_stake' && a.allocation > 0n);

    if (!hasStakes) return null;

    this.lastClaimTick = ctx.tick;

    // Find first app stake to claim from
    const appStake = this.allocations.find(a => a.type === 'app_stake' && a.appId);
    if (!appStake || !appStake.appId) return null;

    ctx.logger.debug(
      { agent: this.id, app: appStake.appId },
      'Yield maximizer: Claiming rewards'
    );

    // Estimate yield earned
    const yieldRate = appStake.apy / (365 * 24 * 60 / 15); // Per tick at 15s/tick
    const estimated = BigInt(Math.floor(Number(appStake.allocation) * yieldRate));
    this.totalYieldEarned += estimated;

    return this.createAction(
      'claim_rewards',
      claimRewards(), // Claim all available rewards
      ctx.tick
    );
  }

  /**
   * Rebalance to higher yield opportunities
   */
  private rebalanceToHigherYield(
    ctx: TickContext,
    minApy: number,
    threshold: number
  ): Action | null {
    // Find new opportunities
    const newSources = this.analyzeYieldSources(minApy);
    if (newSources.length === 0) return null;

    // Check if any existing allocation has significantly lower APY
    for (const current of this.allocations) {
      const best = newSources[0]!;
      
      if (current.apy < best.apy - threshold && current.type !== best.type) {
        // Should rebalance - but for now just log
        ctx.logger.debug(
          { 
            agent: this.id, 
            from: current.type,
            fromApy: (current.apy * 100).toFixed(1) + '%',
            to: best.type,
            toApy: (best.apy * 100).toFixed(1) + '%'
          },
          'Yield maximizer: Found better yield opportunity'
        );
        // Rebalancing is complex - would need to unstake/sell and restake/buy
        // For now, just acknowledge the opportunity
      }
    }

    return null;
  }

  /**
   * Get yield maximizer stats
   */
  getSimStats(): {
    allocations: Array<{ type: string; apy: string; amount: string }>;
    totalYieldEarned: bigint;
  } {
    return {
      allocations: this.allocations.map(a => ({
        type: a.type + (a.appId ? `(${a.appId})` : ''),
        apy: (a.apy * 100).toFixed(1) + '%',
        amount: this.formatElta(a.allocation),
      })),
      totalYieldEarned: this.totalYieldEarned,
    };
  }
}
