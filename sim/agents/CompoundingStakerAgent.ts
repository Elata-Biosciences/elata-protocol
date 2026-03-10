/**
 * CompoundingStakerAgent - Auto-compounds all staking rewards
 *
 * Behavior:
 * - Claims rewards regularly
 * - Immediately reinvests claimed rewards
 * - Optimizes compound frequency for gas efficiency
 * - Tracks compound growth over time
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { lockVeElta, buyAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Compound position tracking
 */
interface CompoundPosition {
  type: 'veelta' | 'app_stake';
  appId?: string;
  principal: bigint;
  totalCompounded: bigint;
  lastCompoundTick: number;
}

/**
 * Parameters for CompoundingStakerAgent
 */
export interface CompoundingStakerAgentParams extends BaseProtocolAgentParams {
  /** Compound frequency in ticks (default 15) */
  compoundFrequency?: number;
  /** Minimum reward to compound (default 5 ELTA) */
  minCompoundAmount?: bigint;
  /** Primary staking strategy: 'veelta' | 'app_stake' (default 'veelta') */
  primaryStrategy?: 'veelta' | 'app_stake';
  /** Target app for app staking (if using app_stake strategy) */
  targetApp?: string;
  /** Initial stake amount (default 100 ELTA) */
  initialStake?: bigint;
}

/**
 * Auto-compounding staker
 */
export class CompoundingStakerAgent extends BaseProtocolAgent {
  /** Current positions */
  private positions: CompoundPosition[] = [];

  /** Phase: 'initial_stake' | 'compounding' */
  private phase: 'initial_stake' | 'compounding' = 'initial_stake';

  /** Total compounds executed */
  private compoundCount = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const compoundFreq = (this.params.compoundFrequency as number | undefined) ?? 15;
    const minCompound = (this.params.minCompoundAmount as bigint | undefined) ?? BigInt(5e18);
    const strategy = (this.params.primaryStrategy as 'veelta' | 'app_stake' | undefined) ?? 'veelta';
    const initialStake = (this.params.initialStake as bigint | undefined) ?? BigInt(100e18);

    // Phase 1: Create initial stake
    if (this.phase === 'initial_stake') {
      const stakeAction = this.createInitialStake(ctx, strategy, initialStake);
      if (stakeAction) return stakeAction;
    }

    // Phase 2: Compound rewards
    if (this.phase === 'compounding') {
      // Check if it's time to compound
      const shouldCompound = this.positions.some(p => 
        ctx.tick - p.lastCompoundTick >= compoundFreq
      );

      if (shouldCompound && this.shouldAct(ctx, 0.7)) {
        const compoundAction = this.executeCompound(ctx, strategy, minCompound);
        if (compoundAction) return compoundAction;
      }
    }

    return null;
  }

  /**
   * Create initial staking position
   */
  private createInitialStake(
    ctx: TickContext,
    strategy: 'veelta' | 'app_stake',
    amount: bigint
  ): Action | null {
    if (!this.hasEnoughElta(amount)) {
      // Try with what we have
      const balance = this.getEltaBalance();
      if (balance < BigInt(10e18)) {
        this.phase = 'compounding'; // Skip if not enough
        return null;
      }
      amount = balance / 2n;
    }

    if (strategy === 'veelta') {
      // Create veELTA lock
      this.positions.push({
        type: 'veelta',
        principal: amount,
        totalCompounded: 0n,
        lastCompoundTick: ctx.tick,
      });

      this.phase = 'compounding';

      ctx.logger.info(
        { agent: this.id, amount: this.formatElta(amount), strategy: 'veELTA' },
        'Compounder: Creating initial stake'
      );

      return this.createAction(
        'lock_veelta',
        lockVeElta(amount, 4 * 365 * 24 * 60 * 60),
        ctx.tick
      );
    } else {
      // App staking
      const targetAppId = this.params.targetApp as string | undefined;
      let app;

      if (targetAppId) {
        app = this.getAppState(targetAppId);
      } else {
        // Pick first available app
        const apps = Array.from(this.getAllApps().entries())
          .filter(([_, a]) => !a.graduated);
        if (apps.length > 0) {
          const [_id, a] = apps[0]!;
          app = a;
        }
      }

      if (!app) {
        this.phase = 'compounding';
        return null;
      }

      this.positions.push({
        type: 'app_stake',
        appId: String(app.id),
        principal: amount,
        totalCompounded: 0n,
        lastCompoundTick: ctx.tick,
      });

      this.phase = 'compounding';

      ctx.logger.info(
        { agent: this.id, amount: this.formatElta(amount), app: app.id },
        'Compounder: Creating initial app stake position'
      );

      return this.createAction(
        'buy_app_token',
        buyAppToken(String(app.id), app.tokenAddress, amount),
        ctx.tick
      );
    }
  }

  /**
   * Execute compound operation
   */
  private executeCompound(
    ctx: TickContext,
    strategy: 'veelta' | 'app_stake',
    minAmount: bigint
  ): Action | null {
    // Find position that needs compounding
    const position = this.positions.find(p => p.type === strategy);
    if (!position) return null;

    // Simulate claimed rewards (in reality would call claim then reinvest)
    // For simulation, estimate based on APY and time
    const ticksSinceLastCompound = ctx.tick - position.lastCompoundTick;
    const estimatedApy = strategy === 'veelta' ? 0.15 : 0.10;
    const ticksPerYear = 365 * 24 * 60 * 4; // ~4 ticks per minute
    const yieldRate = estimatedApy * (ticksSinceLastCompound / ticksPerYear);
    const estimatedReward = BigInt(Math.floor(Number(position.principal + position.totalCompounded) * yieldRate));

    if (estimatedReward < minAmount) {
      // Not enough to compound, wait more
      return null;
    }

    // Update position
    position.totalCompounded += estimatedReward;
    position.lastCompoundTick = ctx.tick;
    this.compoundCount++;

    // Calculate compound growth
    const growthPct = Number(position.totalCompounded) / Number(position.principal) * 100;

    ctx.logger.info(
      { 
        agent: this.id, 
        reward: this.formatElta(estimatedReward),
        totalCompounded: this.formatElta(position.totalCompounded),
        growthPct: growthPct.toFixed(2) + '%',
        compoundCount: this.compoundCount
      },
      'Compounder: Executing compound'
    );

    if (strategy === 'veelta') {
      // For veELTA, we'd increase lock amount
      // Simplified: just lock the reward amount
      return this.createAction(
        'lock_veelta',
        lockVeElta(estimatedReward, 4 * 365 * 24 * 60 * 60),
        ctx.tick
      );
    } else if (position.appId) {
      const app = this.getAppState(position.appId);
      if (!app) return null;

      // Buy more app tokens with the reward
      return this.createAction(
        'buy_app_token',
        buyAppToken(position.appId, app.tokenAddress, estimatedReward),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get compounding stats
   */
  getSimStats(): {
    positions: Array<{ type: string; principal: string; compounded: string; growth: string }>;
    compoundCount: number;
  } {
    return {
      positions: this.positions.map(p => {
        const growth = p.principal > 0n 
          ? (Number(p.totalCompounded) / Number(p.principal) * 100).toFixed(2) + '%'
          : '0%';
        return {
          type: p.type + (p.appId ? `(${p.appId})` : ''),
          principal: this.formatElta(p.principal),
          compounded: this.formatElta(p.totalCompounded),
          growth,
        };
      }),
      compoundCount: this.compoundCount,
    };
  }
}
