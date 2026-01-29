/**
 * DollarCostAveragerAgent - Systematic periodic investor
 *
 * Behavior:
 * - Invests fixed amounts at regular intervals
 * - Ignores price movements
 * - Builds positions over time
 * - Generates steady buy pressure
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for DollarCostAveragerAgent
 */
export interface DollarCostAveragerAgentParams extends BaseProtocolAgentParams {
  /** Investment interval in ticks (default 10) */
  investmentInterval?: number;
  /** Fixed investment amount in ELTA (default 50 ELTA) */
  investmentAmount?: bigint;
  /** Target apps to DCA into (empty = random) */
  targetApps?: string[];
  /** Percentage to allocate to veELTA staking (default 0.2 = 20%) */
  stakingAllocation?: number;
  /** Whether to diversify across apps (default true) */
  diversify?: boolean;
}

/**
 * DCA investor - systematic and consistent
 */
export class DollarCostAveragerAgent extends BaseProtocolAgent {
  /** Last investment tick */
  private lastInvestTick = 0;

  /** Investment count */
  private investmentCount = 0;

  /** Total invested per app */
  private investedByApp: Map<string, bigint> = new Map();

  /** Apps we're DCA-ing into */
  private dcaApps: string[] = [];

  /** Current index in rotation */
  private rotationIndex = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const interval = (this.params.investmentInterval as number | undefined) ?? 10;
    const amount = (this.params.investmentAmount as bigint | undefined) ?? BigInt(50e18);
    const stakingPct = (this.params.stakingAllocation as number | undefined) ?? 0.2;
    const diversify = (this.params.diversify as boolean | undefined) ?? true;

    // Check if it's time to invest
    if (ctx.tick - this.lastInvestTick < interval) {
      return null;
    }

    // Initialize DCA apps if not done
    if (this.dcaApps.length === 0) {
      this.initializeDcaApps();
    }

    // Decide: invest in app tokens or stake in veELTA
    const rand = ctx.rng.nextFloat();
    
    if (rand < stakingPct && this.hasEnoughElta(amount)) {
      // Allocate to staking
      return this.stakeAllocation(ctx, amount);
    } else {
      // Regular DCA into apps
      return this.dcaInvest(ctx, amount, diversify);
    }
  }

  /**
   * Initialize apps to DCA into
   */
  private initializeDcaApps(): void {
    const targetApps = this.params.targetApps as string[] | undefined;
    
    if (targetApps && targetApps.length > 0) {
      this.dcaApps = [...targetApps];
    } else {
      // Pick first 3 non-graduated apps
      const apps = Array.from(this.getAllApps().entries())
        .filter(([_, app]) => !app.graduated)
        .slice(0, 3);
      this.dcaApps = apps.map(([id, _]) => id);
    }
  }

  /**
   * DCA invest into app tokens
   */
  private dcaInvest(ctx: TickContext, amount: bigint, diversify: boolean): Action | null {
    if (!this.hasEnoughElta(amount)) {
      ctx.logger.debug({ agent: this.id }, 'DCA: Insufficient balance, skipping');
      return null;
    }

    // Get current target app
    if (this.dcaApps.length === 0) return null;

    let targetAppId: string;
    if (diversify) {
      // Rotate through apps
      targetAppId = this.dcaApps[this.rotationIndex % this.dcaApps.length]!;
      this.rotationIndex++;
    } else {
      // Pick random from targets
      targetAppId = ctx.rng.pickOne(this.dcaApps);
    }

    const app = this.getAppState(targetAppId);
    if (!app || app.graduated) {
      // Remove graduated app and retry
      this.dcaApps = this.dcaApps.filter(id => id !== targetAppId);
      return null;
    }

    // Update tracking
    this.lastInvestTick = ctx.tick;
    this.investmentCount++;
    const current = this.investedByApp.get(targetAppId) ?? 0n;
    this.investedByApp.set(targetAppId, current + amount);

    ctx.logger.debug(
      { 
        agent: this.id, 
        app: targetAppId, 
        amount: this.formatElta(amount),
        totalInvestments: this.investmentCount,
        totalInvestedInApp: this.formatElta(current + amount)
      },
      'DCA investment'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(targetAppId, app.tokenAddress, amount),
      ctx.tick
    );
  }

  /**
   * Allocate to veELTA staking
   */
  private stakeAllocation(ctx: TickContext, amount: bigint): Action | null {
    if (!this.hasEnoughElta(amount)) return null;

    // Update last invest tick
    this.lastInvestTick = ctx.tick;
    this.investmentCount++;

    // Lock for random duration (1-4 years in seconds)
    const lockDurations = [
      365 * 24 * 60 * 60,     // 1 year
      2 * 365 * 24 * 60 * 60, // 2 years
      3 * 365 * 24 * 60 * 60, // 3 years
      4 * 365 * 24 * 60 * 60, // 4 years
    ];
    const lockDuration = ctx.rng.pickOne(lockDurations);

    ctx.logger.debug(
      { 
        agent: this.id, 
        amount: this.formatElta(amount),
        lockYears: lockDuration / (365 * 24 * 60 * 60)
      },
      'DCA staking allocation'
    );

    return this.createAction(
      'lock_veelta',
      lockVeElta(amount, lockDuration),
      ctx.tick
    );
  }

  /**
   * Get DCA statistics
   */
  getSimStats(): { 
    investmentCount: number; 
    totalInvested: bigint; 
    appsInvested: string[];
  } {
    let totalInvested = 0n;
    for (const amount of this.investedByApp.values()) {
      totalInvested += amount;
    }

    return {
      investmentCount: this.investmentCount,
      totalInvested,
      appsInvested: [...this.investedByApp.keys()],
    };
  }
}
