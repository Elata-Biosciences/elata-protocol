/**
 * ContrarianTraderAgent - Buys dips, sells rallies
 *
 * Behavior:
 * - Counter-trades market sentiment
 * - Buys when prices drop significantly (others panic)
 * - Sells when prices spike (others FOMO)
 * - Profits from mean reversion
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for ContrarianTraderAgent
 */
export interface ContrarianTraderAgentParams extends BaseProtocolAgentParams {
  /** Dip percentage to trigger buy (default 0.08 = 8%) */
  dipThreshold?: number;
  /** Rally percentage to trigger sell (default 0.1 = 10%) */
  rallyThreshold?: number;
  /** Position size as percentage of balance (default 0.25 = 25%) */
  positionSize?: number;
  /** Maximum positions to hold (default 4) */
  maxPositions?: number;
  /** Lookback period in ticks for price analysis (default 10) */
  lookbackPeriod?: number;
}

/**
 * Price tracking for contrarian analysis
 */
interface PriceTracking {
  highWaterMark: bigint;
  lowWaterMark: bigint;
  recentHigh: bigint;
  recentLow: bigint;
}

/**
 * Contrarian trader - counter-trades the crowd
 */
export class ContrarianTraderAgent extends BaseProtocolAgent {
  /** Price tracking per app */
  private priceTracking: Map<string, PriceTracking> = new Map();

  /** Positions with entry info */
  private positions: Map<string, { entryPrice: bigint; dipBought: boolean }> = new Map();

  /** Price history for recent high/low */
  private priceHistory: Map<string, bigint[]> = new Map();

  async step(ctx: TickContext): Promise<Action | null> {
    const dipThreshold = (this.params.dipThreshold as number | undefined) ?? 0.08;
    const rallyThreshold = (this.params.rallyThreshold as number | undefined) ?? 0.1;
    const positionSize = (this.params.positionSize as number | undefined) ?? 0.25;
    const maxPositions = (this.params.maxPositions as number | undefined) ?? 4;
    const lookback = (this.params.lookbackPeriod as number | undefined) ?? 10;

    // Update price tracking
    this.updatePriceTracking(lookback);

    // Priority 1: Sell on rallies (existing positions)
    if (this.shouldAct(ctx, 0.5)) {
      const sellAction = this.sellRally(ctx, rallyThreshold);
      if (sellAction) return sellAction;
    }

    // Priority 2: Buy on dips
    if (this.positions.size < maxPositions && this.shouldAct(ctx, 0.4)) {
      const buyAction = this.buyDip(ctx, dipThreshold, positionSize);
      if (buyAction) return buyAction;
    }

    return null;
  }

  /**
   * Update price tracking for all apps
   */
  private updatePriceTracking(lookback: number): void {
    for (const [appId, app] of this.getAllApps()) {
      // Update history
      let history = this.priceHistory.get(appId);
      if (!history) {
        history = [];
        this.priceHistory.set(appId, history);
      }
      history.push(app.tokenPrice);
      if (history.length > lookback) history.shift();

      // Get or create tracking
      let tracking = this.priceTracking.get(appId);
      if (!tracking) {
        tracking = {
          highWaterMark: app.tokenPrice,
          lowWaterMark: app.tokenPrice,
          recentHigh: app.tokenPrice,
          recentLow: app.tokenPrice,
        };
        this.priceTracking.set(appId, tracking);
      }

      // Update all-time marks
      if (app.tokenPrice > tracking.highWaterMark) {
        tracking.highWaterMark = app.tokenPrice;
      }
      if (app.tokenPrice < tracking.lowWaterMark || tracking.lowWaterMark === 0n) {
        tracking.lowWaterMark = app.tokenPrice;
      }

      // Update recent high/low from history
      if (history.length > 0) {
        tracking.recentHigh = history.reduce((max, p) => p > max ? p : max, 0n);
        tracking.recentLow = history.reduce((min, p) => p < min ? p : min, history[0]!);
      }
    }
  }

  /**
   * Buy when price has dipped significantly from recent high
   */
  private buyDip(ctx: TickContext, threshold: number, positionSizePct: number): Action | null {
    const minTrade = BigInt(20e18);
    if (!this.hasEnoughElta(minTrade)) return null;

    // Find dipped apps
    const dippedApps: Array<{ appId: string; dipPct: number }> = [];

    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;
      if (this.positions.has(appId)) continue;

      const tracking = this.priceTracking.get(appId);
      if (!tracking || tracking.recentHigh === 0n) continue;

      // Calculate dip from recent high
      const dipPct = Number(tracking.recentHigh - app.tokenPrice) / Number(tracking.recentHigh);

      if (dipPct >= threshold) {
        dippedApps.push({ appId, dipPct });
      }
    }

    if (dippedApps.length === 0) return null;

    // Buy the biggest dip (most contrarian)
    dippedApps.sort((a, b) => b.dipPct - a.dipPct);
    const target = dippedApps[0]!;
    const app = this.getAppState(target.appId);
    if (!app) return null;

    // Position sizing - bigger dip = bigger position
    const balance = this.getEltaBalance();
    const dipMultiplier = 1 + target.dipPct; // More dip = more conviction
    const amount = BigInt(Math.floor(Number(balance) * positionSizePct * dipMultiplier));
    const finalAmount = amount < minTrade ? minTrade : amount;

    if (!this.hasEnoughElta(finalAmount)) return null;

    // Track position
    this.positions.set(target.appId, {
      entryPrice: app.tokenPrice,
      dipBought: true,
    });

    ctx.logger.info(
      { 
        agent: this.id, 
        app: target.appId, 
        dipPct: (target.dipPct * 100).toFixed(2) + '%',
        amount: this.formatElta(finalAmount)
      },
      'Contrarian buying the dip'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(target.appId, app.tokenAddress, finalAmount),
      ctx.tick
    );
  }

  /**
   * Sell when price has rallied significantly
   */
  private sellRally(ctx: TickContext, threshold: number): Action | null {
    for (const [appId, position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) {
        this.positions.delete(appId);
        continue;
      }

      // Calculate rally from entry
      const rallyPct = Number(app.tokenPrice - position.entryPrice) / Number(position.entryPrice);

      if (rallyPct >= threshold) {
        ctx.logger.info(
          { 
            agent: this.id, 
            app: appId, 
            rallyPct: (rallyPct * 100).toFixed(2) + '%'
          },
          'Contrarian selling the rally'
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
}
