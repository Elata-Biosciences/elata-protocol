/**
 * VestingManagerAgent - Manages vesting schedules
 *
 * Behavior:
 * - Claims vested tokens on schedule
 * - Tracks vesting progress
 * - Reinvests claimed tokens
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { releaseVestedTokens, lockVeElta, buyAppToken } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Vesting schedule tracking
 */
interface VestingSchedule {
  vestingWalletAddress: Address;
  totalAmount: bigint;
  vestedAmount: bigint;
  claimedAmount: bigint;
  startTick: number;
  durationTicks: number;
  cliffTicks: number;
}

/**
 * Parameters for VestingManagerAgent
 */
export interface VestingManagerAgentParams extends BaseProtocolAgentParams {
  /** Vesting wallet addresses */
  vestingWallets?: Address[];
  /** Claim frequency in ticks (default 10) */
  claimFrequency?: number;
  /** Reinvestment strategy: 'stake' | 'trade' | 'hold' (default 'stake') */
  reinvestStrategy?: 'stake' | 'trade' | 'hold';
  /** Percentage to reinvest (default 0.5 = 50%) */
  reinvestPercent?: number;
}

/**
 * Vesting schedule manager
 */
export class VestingManagerAgent extends BaseProtocolAgent {
  /** Active vesting schedules */
  private schedules: VestingSchedule[] = [];

  /** Total vested and claimed */
  private totalVested = 0n;
  private totalClaimed = 0n;
  private totalReinvested = 0n;

  /** Last claim tick */
  private lastClaimTick = 0;

  /** Initialized flag */
  private initialized = false;

  async step(ctx: TickContext): Promise<Action | null> {
    const claimFreq = (this.params.claimFrequency as number | undefined) ?? 10;
    const strategy = (this.params.reinvestStrategy as 'stake' | 'trade' | 'hold' | undefined) ?? 'stake';
    const reinvestPct = (this.params.reinvestPercent as number | undefined) ?? 0.5;

    // Initialize vesting schedules
    if (!this.initialized) {
      this.initializeSchedules(ctx);
      this.initialized = true;
    }

    // Update vested amounts
    this.updateVestedAmounts(ctx);

    // Priority 1: Claim vested tokens
    if (ctx.tick - this.lastClaimTick >= claimFreq) {
      const claimAction = this.claimVested(ctx);
      if (claimAction) return claimAction;
    }

    // Priority 2: Reinvest claimed tokens
    if (strategy !== 'hold' && this.shouldAct(ctx, 0.2)) {
      return this.reinvest(ctx, strategy, reinvestPct);
    }

    return null;
  }

  /**
   * Initialize vesting schedules
   */
  private initializeSchedules(ctx: TickContext): void {
    const wallets = this.params.vestingWallets as Address[] | undefined;

    if (wallets && wallets.length > 0) {
      for (const wallet of wallets) {
        this.schedules.push({
          vestingWalletAddress: wallet,
          totalAmount: BigInt(1000e18), // Default 1000 ELTA
          vestedAmount: 0n,
          claimedAmount: 0n,
          startTick: ctx.tick,
          durationTicks: 100, // ~25 minutes at 15s/tick
          cliffTicks: 10,
        });
      }
    } else {
      // Create simulated vesting schedule
      const vestingAddr = `0x${Array(40).fill(0).map(() => 
        Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

      this.schedules.push({
        vestingWalletAddress: vestingAddr,
        totalAmount: BigInt(500e18),
        vestedAmount: 0n,
        claimedAmount: 0n,
        startTick: ctx.tick,
        durationTicks: 80,
        cliffTicks: 8,
      });
    }

    ctx.logger.info(
      { agent: this.id, schedules: this.schedules.length },
      'Initialized vesting schedules'
    );
  }

  /**
   * Update vested amounts based on time
   */
  private updateVestedAmounts(ctx: TickContext): void {
    for (const schedule of this.schedules) {
      const elapsed = ctx.tick - schedule.startTick;

      // Check cliff
      if (elapsed < schedule.cliffTicks) {
        schedule.vestedAmount = 0n;
        continue;
      }

      // Calculate vested amount (linear vesting)
      const vestingElapsed = elapsed - schedule.cliffTicks;
      const vestingDuration = schedule.durationTicks - schedule.cliffTicks;

      if (vestingElapsed >= vestingDuration) {
        schedule.vestedAmount = schedule.totalAmount;
      } else {
        schedule.vestedAmount = schedule.totalAmount * BigInt(vestingElapsed) / BigInt(vestingDuration);
      }
    }

    // Update total vested
    this.totalVested = this.schedules.reduce((sum, s) => sum + s.vestedAmount, 0n);
  }

  /**
   * Claim vested tokens
   */
  private claimVested(ctx: TickContext): Action | null {
    for (const schedule of this.schedules) {
      const claimable = schedule.vestedAmount - schedule.claimedAmount;

      if (claimable > BigInt(1e18)) {
        schedule.claimedAmount += claimable;
        this.totalClaimed += claimable;
        this.lastClaimTick = ctx.tick;

        const progress = Number(schedule.claimedAmount * 100n / schedule.totalAmount);

        ctx.logger.info(
          { 
            agent: this.id, 
            claimed: this.formatElta(claimable),
            progress: progress + '%',
            totalClaimed: this.formatElta(this.totalClaimed)
          },
          'Claiming vested tokens'
        );

        return this.createAction(
          'release_vested_tokens',
          releaseVestedTokens(schedule.vestingWalletAddress),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Reinvest claimed tokens
   */
  private reinvest(
    ctx: TickContext,
    strategy: 'stake' | 'trade',
    reinvestPct: number
  ): Action | null {
    const balance = this.getEltaBalance();
    const reinvestAmount = BigInt(Math.floor(Number(balance) * reinvestPct));

    if (reinvestAmount < BigInt(10e18)) return null;

    this.totalReinvested += reinvestAmount;

    if (strategy === 'stake') {
      ctx.logger.debug(
        { agent: this.id, amount: this.formatElta(reinvestAmount) },
        'Reinvesting vested tokens into veELTA'
      );

      return this.createAction(
        'lock_veelta',
        lockVeElta(reinvestAmount, 2 * 365 * 24 * 60 * 60), // 2 years
        ctx.tick
      );
    } else {
      // Trade strategy - buy app tokens
      const apps = Array.from(this.getAllApps().entries())
        .filter(([_, app]) => !app.graduated);

      if (apps.length === 0) return null;

      const [appId, app] = ctx.rng.pickOne(apps);

      ctx.logger.debug(
        { agent: this.id, app: appId, amount: this.formatElta(reinvestAmount) },
        'Reinvesting vested tokens into app'
      );

      return this.createAction(
        'buy_app_token',
        buyAppToken(appId, app.tokenAddress, reinvestAmount),
        ctx.tick
      );
    }
  }

  /**
   * Get vesting statistics
   */
  getSimStats(): {
    schedulesCount: number;
    totalVested: bigint;
    totalClaimed: bigint;
    totalReinvested: bigint;
    progressPercent: string;
  } {
    const totalTotal = this.schedules.reduce((sum, s) => sum + s.totalAmount, 0n);
    const progress = totalTotal > 0n 
      ? (Number(this.totalClaimed * 100n / totalTotal)).toFixed(1) + '%'
      : '0%';

    return {
      schedulesCount: this.schedules.length,
      totalVested: this.totalVested,
      totalClaimed: this.totalClaimed,
      totalReinvested: this.totalReinvested,
      progressPercent: progress,
    };
  }
}
