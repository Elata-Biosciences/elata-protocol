/**
 * XPFarmerAgent - Maximizes XP points accumulation
 *
 * Behavior:
 * - Completes all XP-earning activities
 * - Optimizes XP per action
 * - Claims XP regularly
 * - Tracks XP accumulation
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimXpPoints, buyAppToken, lockVeElta, enterTournament, purchaseContent } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * XP source tracking
 */
interface XpSource {
  type: 'trade' | 'stake' | 'tournament' | 'content' | 'daily';
  xpEarned: bigint;
  actionsCompleted: number;
}

/**
 * Parameters for XPFarmerAgent
 */
export interface XPFarmerAgentParams extends BaseProtocolAgentParams {
  /** Activity frequency (default 0.25) */
  activityRate?: number;
  /** Focus on highest XP activities (default true) */
  optimizeXp?: boolean;
  /** XP claim threshold (default 100 XP) */
  claimThreshold?: bigint;
  /** Daily activities completed */
  dailyActivities?: number;
}

/**
 * XP farmer maximizing points
 */
export class XPFarmerAgent extends BaseProtocolAgent {
  /** XP by source */
  private xpSources: Map<string, XpSource> = new Map();

  /** Total XP earned */
  private totalXp = 0n;

  /** Pending XP to claim */
  private pendingXp = 0n;

  /** Daily activities tracking */
  private lastDailyTick = 0;
  private dailyStreak = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const activityRate = (this.params.activityRate as number | undefined) ?? 0.25;
    const optimizeXp = (this.params.optimizeXp as boolean | undefined) ?? true;
    const claimThreshold = (this.params.claimThreshold as bigint | undefined) ?? BigInt(100e18);

    // Priority 1: Claim accumulated XP
    if (this.pendingXp >= claimThreshold) {
      return this.claimXp(ctx);
    }

    // Priority 2: Complete daily activities
    const dailyInterval = 20; // Ticks representing a "day"
    if (ctx.tick - this.lastDailyTick >= dailyInterval) {
      return this.completeDailyActivity(ctx);
    }

    // Priority 3: Farm XP through various activities
    if (this.shouldAct(ctx, activityRate)) {
      return this.farmXp(ctx, optimizeXp);
    }

    return null;
  }

  /**
   * Complete daily activity for streak bonus
   */
  private completeDailyActivity(ctx: TickContext): Action | null {
    this.lastDailyTick = ctx.tick;
    this.dailyStreak++;

    // Daily XP with streak multiplier
    const baseXp = BigInt(10e18);
    const streakMultiplier = Math.min(this.dailyStreak, 7); // Max 7x
    const dailyXp = baseXp * BigInt(streakMultiplier);

    this.recordXp('daily', dailyXp);

    ctx.logger.debug(
      { 
        agent: this.id, 
        dailyStreak: this.dailyStreak,
        xpEarned: this.formatElta(dailyXp)
      },
      'Daily activity completed'
    );

    // Do a small trade as daily activity
    const balance = this.getEltaBalance();
    if (balance < BigInt(5e18)) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);
    const tradeAmount = BigInt(5e18); // Small trade for daily

    return this.createAction(
      'buy_app_token',
      buyAppToken(appId, app.tokenAddress, tradeAmount),
      ctx.tick
    );
  }

  /**
   * Farm XP through various activities
   */
  private farmXp(ctx: TickContext, optimizeXp: boolean): Action | null {
    const balance = this.getEltaBalance();
    if (balance < BigInt(10e18)) return null;

    // XP rewards per activity type (simulated)
    const activities = [
      { type: 'trade' as const, xpRate: 5, minAmount: BigInt(10e18) },
      { type: 'stake' as const, xpRate: 10, minAmount: BigInt(50e18) },
      { type: 'tournament' as const, xpRate: 20, minAmount: BigInt(20e18) },
      { type: 'content' as const, xpRate: 8, minAmount: BigInt(15e18) },
    ];

    // Sort by XP rate if optimizing
    if (optimizeXp) {
      activities.sort((a, b) => b.xpRate - a.xpRate);
    }

    // Find affordable activity
    for (const activity of activities) {
      if (balance < activity.minAmount) continue;

      return this.executeActivity(ctx, activity);
    }

    return null;
  }

  /**
   * Execute XP-earning activity
   */
  private executeActivity(
    ctx: TickContext,
    activity: { type: 'trade' | 'stake' | 'tournament' | 'content'; xpRate: number; minAmount: bigint }
  ): Action | null {
    // Record XP
    const xpEarned = BigInt(activity.xpRate) * BigInt(1e18);
    this.recordXp(activity.type, xpEarned);

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);

    ctx.logger.debug(
      { 
        agent: this.id, 
        activity: activity.type,
        xpEarned: this.formatElta(xpEarned),
        totalXp: this.formatElta(this.totalXp)
      },
      'XP farming activity'
    );

    switch (activity.type) {
      case 'trade':
        return this.createAction(
          'buy_app_token',
          buyAppToken(appId, app.tokenAddress, activity.minAmount),
          ctx.tick
        );

      case 'stake':
        return this.createAction(
          'lock_veelta',
          lockVeElta(activity.minAmount, 365 * 24 * 60 * 60), // 1 year
          ctx.tick
        );

      case 'tournament':
        const tournamentAddr = `0x${Array(40).fill(0).map(() => 
          Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;
        return this.createAction(
          'enter_tournament',
          enterTournament(tournamentAddr, app.tokenAddress, activity.minAmount),
          ctx.tick
        );

      case 'content':
        return this.createAction(
          'purchase_content',
          purchaseContent(app.tokenAddress as Address, 1n, this.getWorldState().elta as Address, activity.minAmount),
          ctx.tick
        );

      default:
        return null;
    }
  }

  /**
   * Record XP earned
   */
  private recordXp(type: string, amount: bigint): void {
    let source = this.xpSources.get(type);
    if (!source) {
      source = {
        type: type as XpSource['type'],
        xpEarned: 0n,
        actionsCompleted: 0,
      };
      this.xpSources.set(type, source);
    }

    source.xpEarned += amount;
    source.actionsCompleted++;
    this.totalXp += amount;
    this.pendingXp += amount;
  }

  /**
   * Claim accumulated XP
   */
  private claimXp(ctx: TickContext): Action | null {
    const claimAmount = this.pendingXp;
    this.pendingXp = 0n;

    ctx.logger.info(
      { 
        agent: this.id, 
        claiming: this.formatElta(claimAmount),
        totalXp: this.formatElta(this.totalXp),
        dailyStreak: this.dailyStreak
      },
      'Claiming XP points'
    );

    const mockProof: `0x${string}`[] = [
      '0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`,
    ];

    return this.createAction(
      'claim_xp_points',
      claimXpPoints(mockProof, claimAmount),
      ctx.tick
    );
  }

  /**
   * Get XP statistics
   */
  getSimStats(): {
    totalXp: bigint;
    pendingXp: bigint;
    dailyStreak: number;
    sourceBreakdown: Array<{ type: string; xp: string; actions: number }>;
  } {
    const sourceBreakdown = Array.from(this.xpSources.values()).map(s => ({
      type: s.type,
      xp: this.formatElta(s.xpEarned),
      actions: s.actionsCompleted,
    }));

    return {
      totalXp: this.totalXp,
      pendingXp: this.pendingXp,
      dailyStreak: this.dailyStreak,
      sourceBreakdown,
    };
  }
}
