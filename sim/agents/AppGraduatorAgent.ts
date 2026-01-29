/**
 * AppGraduatorAgent - Helps apps reach graduation threshold
 *
 * Behavior:
 * - Identifies apps close to graduation
 * - Invests to push apps over threshold
 * - Earns rewards from graduation events
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Graduation target tracking
 */
interface GraduationTarget {
  appId: string;
  initialProgress: number;
  currentProgress: number;
  investedAmount: bigint;
  graduated: boolean;
}

/**
 * Parameters for AppGraduatorAgent
 */
export interface AppGraduatorAgentParams extends BaseProtocolAgentParams {
  /** Minimum progress to target (default 0.7 = 70%) */
  minProgressThreshold?: number;
  /** Maximum investment per app (default 200 ELTA) */
  maxInvestmentPerApp?: bigint;
  /** Investment frequency (default 0.2) */
  investmentFrequency?: number;
  /** Hold after graduation (default false) */
  holdAfterGraduation?: boolean;
}

/**
 * App graduation specialist
 */
export class AppGraduatorAgent extends BaseProtocolAgent {
  /** Target apps for graduation */
  private targets: Map<string, GraduationTarget> = new Map();

  /** Apps successfully graduated */
  private graduatedApps: string[] = [];

  /** Total invested */
  private totalInvested = 0n;

  /** Graduation bonuses earned (simulated) */
  private bonusesEarned = 0n;

  /** Graduation threshold in ELTA (e.g., 100k ELTA raised) */
  private readonly GRADUATION_THRESHOLD = BigInt(100_000e18);

  async step(ctx: TickContext): Promise<Action | null> {
    const minProgress = (this.params.minProgressThreshold as number | undefined) ?? 0.7;
    const maxPerApp = (this.params.maxInvestmentPerApp as bigint | undefined) ?? BigInt(200e18);
    const frequency = (this.params.investmentFrequency as number | undefined) ?? 0.2;
    const holdAfter = (this.params.holdAfterGraduation as boolean | undefined) ?? false;

    // Scout for graduation candidates
    if (this.shouldAct(ctx, 0.15)) {
      this.scoutCandidates(ctx, minProgress);
    }

    // Check for graduations
    this.checkGraduations(ctx);

    // Sell graduated positions if not holding
    if (!holdAfter && this.shouldAct(ctx, 0.3)) {
      const sellAction = this.sellGraduated(ctx);
      if (sellAction) return sellAction;
    }

    // Invest in targets
    if (this.shouldAct(ctx, frequency)) {
      return this.investInTarget(ctx, maxPerApp);
    }

    return null;
  }

  /**
   * Scout for apps close to graduation
   */
  private scoutCandidates(ctx: TickContext, minProgress: number): void {
    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;
      if (this.targets.has(appId)) continue;

      // Calculate progress toward graduation
      // Using total supply as proxy for funds raised
      const progress = this.calculateProgress(app);

      if (progress >= minProgress && progress < 1.0) {
        this.targets.set(appId, {
          appId,
          initialProgress: progress,
          currentProgress: progress,
          investedAmount: 0n,
          graduated: false,
        });

        ctx.logger.info(
          { 
            agent: this.id, 
            app: appId,
            progress: (progress * 100).toFixed(1) + '%'
          },
          'Targeting app for graduation'
        );
      }
    }
  }

  /**
   * Calculate graduation progress
   */
  private calculateProgress(app: AppState): number {
    // Simplified: use tokenPrice as proxy for market cap/funds raised
    // In reality, would check actual funds raised in bonding curve
    const estimatedRaised = app.tokenPrice * app.tokenSupply / BigInt(1e18);
    return Math.min(Number(estimatedRaised) / Number(this.GRADUATION_THRESHOLD), 1.0);
  }

  /**
   * Invest in target app to push toward graduation
   */
  private investInTarget(ctx: TickContext, maxPerApp: bigint): Action | null {
    const balance = this.getEltaBalance();
    if (balance < BigInt(20e18)) return null;

    // Find best target (closest to graduation, under investment cap)
    let bestTarget: GraduationTarget | null = null;
    let bestProgress = 0;

    for (const target of this.targets.values()) {
      if (target.graduated) continue;
      if (target.investedAmount >= maxPerApp) continue;

      const app = this.getAppState(target.appId);
      if (!app || app.graduated) {
        target.graduated = true;
        continue;
      }

      // Update progress
      target.currentProgress = this.calculateProgress(app);

      if (target.currentProgress > bestProgress && target.currentProgress < 1.0) {
        bestProgress = target.currentProgress;
        bestTarget = target;
      }
    }

    if (!bestTarget) return null;

    const app = this.getAppState(bestTarget.appId);
    if (!app) return null;

    // Calculate investment amount
    // More aggressive as we get closer to graduation
    const progressMultiplier = 1 + bestTarget.currentProgress;
    const baseAmount = balance / 10n;
    const investAmount = BigInt(Math.floor(Number(baseAmount) * progressMultiplier));
    
    const maxInvest = maxPerApp - bestTarget.investedAmount;
    const finalAmount = investAmount > maxInvest ? maxInvest : investAmount;

    if (finalAmount < BigInt(10e18)) return null;

    bestTarget.investedAmount += finalAmount;
    this.totalInvested += finalAmount;

    ctx.logger.debug(
      { 
        agent: this.id, 
        app: bestTarget.appId,
        investment: this.formatElta(finalAmount),
        progress: (bestTarget.currentProgress * 100).toFixed(1) + '%',
        totalInvested: this.formatElta(bestTarget.investedAmount)
      },
      'Investing to push graduation'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(bestTarget.appId, app.tokenAddress, finalAmount),
      ctx.tick
    );
  }

  /**
   * Check for graduated apps
   */
  private checkGraduations(ctx: TickContext): void {
    for (const target of this.targets.values()) {
      if (target.graduated) continue;

      const app = this.getAppState(target.appId);
      if (!app) continue;

      if (app.graduated) {
        target.graduated = true;
        this.graduatedApps.push(target.appId);

        // Simulate graduation bonus (1% of investment)
        const bonus = target.investedAmount / 100n;
        this.bonusesEarned += bonus;

        ctx.logger.info(
          { 
            agent: this.id, 
            app: target.appId,
            invested: this.formatElta(target.investedAmount),
            bonus: this.formatElta(bonus),
            totalGraduated: this.graduatedApps.length
          },
          'App graduated!'
        );
      }
    }
  }

  /**
   * Sell positions in graduated apps
   */
  private sellGraduated(ctx: TickContext): Action | null {
    for (const appId of this.graduatedApps) {
      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) continue;

      const app = this.getAppState(appId);
      if (!app) continue;

      ctx.logger.debug(
        { agent: this.id, app: appId, amount: this.formatElta(balance) },
        'Selling graduated app position'
      );

      return this.createAction(
        'sell_app_token',
        sellAppToken(appId, app.tokenAddress, balance),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get graduator statistics
   */
  getSimStats(): {
    targetsCount: number;
    graduatedCount: number;
    totalInvested: bigint;
    bonusesEarned: bigint;
    activeTargets: Array<{ appId: string; progress: string; invested: string }>;
  } {
    const activeTargets = Array.from(this.targets.values())
      .filter(t => !t.graduated)
      .map(t => ({
        appId: t.appId,
        progress: (t.currentProgress * 100).toFixed(1) + '%',
        invested: this.formatElta(t.investedAmount),
      }));

    return {
      targetsCount: this.targets.size,
      graduatedCount: this.graduatedApps.length,
      totalInvested: this.totalInvested,
      bonusesEarned: this.bonusesEarned,
      activeTargets,
    };
  }
}
