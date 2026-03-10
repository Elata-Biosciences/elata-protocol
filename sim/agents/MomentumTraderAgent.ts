/**
 * MomentumTraderAgent - Trend-following trader
 *
 * Behavior:
 * - Analyzes price history to detect trends
 * - Buys when momentum is positive
 * - Sells when momentum turns negative
 * - Rides trends for maximum profit
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Price history entry
 */
interface PricePoint {
  tick: number;
  price: bigint;
}

/**
 * Parameters for MomentumTraderAgent
 */
export interface MomentumTraderAgentParams extends BaseProtocolAgentParams {
  /** Number of ticks to look back for trend analysis (default 5) */
  trendLookback?: number;
  /** Minimum momentum score to trigger buy (default 0.02 = 2%) */
  momentumThreshold?: number;
  /** Minimum trend strength to act (default 0.6 = 60% of lookback positive) */
  trendStrength?: number;
  /** Position size as percentage of balance (default 0.2 = 20%) */
  positionSize?: number;
  /** Stop loss percentage (default 0.05 = 5%) */
  stopLoss?: number;
}

/**
 * Momentum-based trend follower
 */
export class MomentumTraderAgent extends BaseProtocolAgent {
  /** Price history per app */
  private priceHistory: Map<string, PricePoint[]> = new Map();

  /** Current positions with entry info */
  private positions: Map<string, { entryPrice: bigint; amount: bigint }> = new Map();

  /** Maximum history length */
  private readonly MAX_HISTORY = 20;

  async step(ctx: TickContext): Promise<Action | null> {
    const lookback = (this.params.trendLookback as number | undefined) ?? 5;
    const momentumThreshold = (this.params.momentumThreshold as number | undefined) ?? 0.02;
    const trendStrength = (this.params.trendStrength as number | undefined) ?? 0.6;
    const positionSize = (this.params.positionSize as number | undefined) ?? 0.2;
    const stopLoss = (this.params.stopLoss as number | undefined) ?? 0.05;

    // Update price history
    this.updatePriceHistory(ctx);

    // Priority 1: Check stop losses
    const stopAction = this.checkStopLoss(ctx, stopLoss);
    if (stopAction) return stopAction;

    // Priority 2: Exit positions with negative momentum
    if (this.shouldAct(ctx, 0.5)) {
      const exitAction = this.checkMomentumExit(ctx, lookback);
      if (exitAction) return exitAction;
    }

    // Priority 3: Enter positions with positive momentum
    if (this.shouldAct(ctx, 0.4)) {
      const entryAction = this.checkMomentumEntry(ctx, lookback, momentumThreshold, trendStrength, positionSize);
      if (entryAction) return entryAction;
    }

    return null;
  }

  /**
   * Update price history for all apps
   */
  private updatePriceHistory(ctx: TickContext): void {
    for (const [appId, app] of this.getAllApps()) {
      let history = this.priceHistory.get(appId);
      if (!history) {
        history = [];
        this.priceHistory.set(appId, history);
      }

      history.push({ tick: ctx.tick, price: app.tokenPrice });

      // Trim to max length
      if (history.length > this.MAX_HISTORY) {
        history.shift();
      }
    }
  }

  /**
   * Calculate momentum score for an app
   * Returns percentage change over lookback period
   */
  private calculateMomentum(appId: string, lookback: number): { momentum: number; strength: number } {
    const history = this.priceHistory.get(appId);
    if (!history || history.length < lookback + 1) {
      return { momentum: 0, strength: 0 };
    }

    const recent = history.slice(-lookback - 1);
    const oldPrice = recent[0]!.price;
    const newPrice = recent[recent.length - 1]!.price;

    if (oldPrice === 0n) return { momentum: 0, strength: 0 };

    // Calculate overall momentum
    const momentum = Number(newPrice - oldPrice) / Number(oldPrice);

    // Calculate trend strength (% of periods that were positive)
    let positiveCount = 0;
    for (let i = 1; i < recent.length; i++) {
      if (recent[i]!.price > recent[i - 1]!.price) {
        positiveCount++;
      }
    }
    const strength = positiveCount / (recent.length - 1);

    return { momentum, strength };
  }

  /**
   * Check for stop loss triggers
   */
  private checkStopLoss(ctx: TickContext, stopLossPct: number): Action | null {
    for (const [appId, position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) {
        this.positions.delete(appId);
        continue;
      }

      // Check loss percentage
      const lossPct = Number(position.entryPrice - app.tokenPrice) / Number(position.entryPrice);
      
      if (lossPct > stopLossPct) {
        ctx.logger.info(
          { agent: this.id, app: appId, lossPct: (lossPct * 100).toFixed(2) + '%' },
          'Momentum stop loss triggered'
        );

        this.positions.delete(appId);

        return this.createAction(
          'sell_app_token',
          sellAppToken(appId, app.tokenAddress, balance),
          ctx.tick
        );
      }
    }
    return null;
  }

  /**
   * Check for momentum-based exits
   */
  private checkMomentumExit(ctx: TickContext, lookback: number): Action | null {
    for (const [appId, _position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) continue;

      const { momentum, strength } = this.calculateMomentum(appId, lookback);

      // Exit if momentum turns negative with strong trend
      if (momentum < -0.01 && strength < 0.4) {
        ctx.logger.debug(
          { agent: this.id, app: appId, momentum: (momentum * 100).toFixed(2) + '%', strength },
          'Momentum exit - trend reversing'
        );

        this.positions.delete(appId);

        return this.createAction(
          'sell_app_token',
          sellAppToken(appId, app.tokenAddress, balance),
          ctx.tick
        );
      }
    }
    return null;
  }

  /**
   * Check for momentum-based entries
   */
  private checkMomentumEntry(
    ctx: TickContext,
    lookback: number,
    momentumThreshold: number,
    trendStrengthThreshold: number,
    positionSizePct: number
  ): Action | null {
    const minTrade = BigInt(20e18);
    if (!this.hasEnoughElta(minTrade)) return null;

    // Find apps with strong positive momentum
    const candidates: Array<{ appId: string; momentum: number; strength: number }> = [];

    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;
      if (this.positions.has(appId)) continue;

      const { momentum, strength } = this.calculateMomentum(appId, lookback);

      if (momentum >= momentumThreshold && strength >= trendStrengthThreshold) {
        candidates.push({ appId, momentum, strength });
      }
    }

    if (candidates.length === 0) return null;

    // Pick the strongest momentum
    candidates.sort((a, b) => b.momentum - a.momentum);
    const target = candidates[0]!;
    const app = this.getAppState(target.appId);
    if (!app) return null;

    // Calculate position size
    const balance = this.getEltaBalance();
    const amount = BigInt(Math.floor(Number(balance) * positionSizePct));
    const finalAmount = amount < minTrade ? minTrade : amount;

    if (!this.hasEnoughElta(finalAmount)) return null;

    // Track position
    this.positions.set(target.appId, {
      entryPrice: app.tokenPrice,
      amount: finalAmount,
    });

    ctx.logger.info(
      { 
        agent: this.id, 
        app: target.appId, 
        momentum: (target.momentum * 100).toFixed(2) + '%',
        strength: target.strength.toFixed(2),
        amount: this.formatElta(finalAmount)
      },
      'Momentum entry - riding trend'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(target.appId, app.tokenAddress, finalAmount),
      ctx.tick
    );
  }
}
