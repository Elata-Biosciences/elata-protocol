/**
 * ArbitragerAgent - Trades based on price movements
 *
 * Behavior:
 * - Tracks price changes across apps
 * - Buys apps that have dropped significantly (oversold)
 * - Sells apps that have spiked (take profit)
 * - Quick in/out trades for short-term gains
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for ArbitragerAgent
 */
export interface ArbitragerAgentParams extends BaseProtocolAgentParams {
  /** Threshold for price drop to trigger buy (e.g., 0.1 = 10% drop) */
  buyDipThreshold?: number;
  /** Threshold for price spike to trigger sell (e.g., 0.2 = 20% gain) */
  takeProfitThreshold?: number;
  /** Probability of executing a trade each tick */
  tradeProbability?: number;
  /** Maximum percentage of balance to use per trade */
  maxTradePercent?: number;
}

/**
 * Agent that trades based on price movements for short-term gains
 */
export class ArbitragerAgent extends BaseProtocolAgent {
  /** Track prices from previous tick */
  private lastPrices: Map<string, bigint> = new Map();
  /** Track our entry prices for positions */
  private entryPrices: Map<string, bigint> = new Map();

  async step(ctx: TickContext): Promise<Action | null> {
    const buyDip = (this.params.buyDipThreshold as number | undefined) ?? 0.15; // 15% drop
    const takeProfit = (this.params.takeProfitThreshold as number | undefined) ?? 0.25; // 25% gain
    const tradeProb = (this.params.tradeProbability as number | undefined) ?? 0.5;
    const maxTrade = (this.params.maxTradePercent as number | undefined) ?? 0.2; // 20% of balance

    // Update price tracking
    const currentPrices = this.getCurrentPrices();

    // Priority 1: Take profit on positions that have gained
    const profitAction = this.checkTakeProfit(ctx, takeProfit);
    if (profitAction) {
      this.updateLastPrices(currentPrices);
      return profitAction;
    }

    // Priority 2: Buy dips if we should act this tick
    if (this.shouldAct(ctx, tradeProb)) {
      const dipAction = this.checkBuyDip(ctx, buyDip, maxTrade);
      if (dipAction) {
        this.updateLastPrices(currentPrices);
        return dipAction;
      }
    }

    // Update last prices for next tick comparison
    this.updateLastPrices(currentPrices);

    return null;
  }

  /**
   * Get current prices for all apps
   */
  private getCurrentPrices(): Map<string, bigint> {
    const prices = new Map<string, bigint>();
    for (const [id, app] of this.getAllApps()) {
      if (!app.graduated) {
        prices.set(id, app.tokenPrice);
      }
    }
    return prices;
  }

  /**
   * Update last prices for next tick
   */
  private updateLastPrices(prices: Map<string, bigint>): void {
    this.lastPrices = new Map(prices);
  }

  /**
   * Calculate price change percentage
   */
  private getPriceChange(appId: string, currentPrice: bigint): number {
    const lastPrice = this.lastPrices.get(appId);
    if (!lastPrice || lastPrice === 0n) return 0;

    // Calculate percentage change: (current - last) / last
    const change = Number(currentPrice - lastPrice) / Number(lastPrice);
    return change;
  }

  /**
   * Check if we should take profit on any positions
   */
  private checkTakeProfit(ctx: TickContext, threshold: number): Action | null {
    for (const [appId, balance] of this.appTokenBalances) {
      if (balance <= 0n) continue;

      const app = this.getAppState(appId);
      if (!app || app.graduated) continue;

      const entryPrice = this.entryPrices.get(appId);
      if (!entryPrice || entryPrice === 0n) continue;

      // Calculate gain from entry
      const gain = Number(app.tokenPrice - entryPrice) / Number(entryPrice);

      if (gain >= threshold) {
        // Take profit - sell all tokens
        ctx.logger.info(
          { agent: this.id, app: appId, gain: `${(gain * 100).toFixed(1)}%` },
          'Taking profit on position'
        );

        // Clear entry price
        this.entryPrices.delete(appId);

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
   * Check if any apps have dipped enough to buy
   */
  private checkBuyDip(ctx: TickContext, threshold: number, maxTrade: number): Action | null {
    const apps = Array.from(this.getAllApps().entries());

    // Find apps with significant price drops
    const dippedApps: { app: AppState; id: string; drop: number }[] = [];

    for (const [id, app] of apps) {
      if (app.graduated) continue;

      const priceChange = this.getPriceChange(id, app.tokenPrice);

      // Negative change means price dropped
      if (priceChange < -threshold) {
        dippedApps.push({ app, id, drop: Math.abs(priceChange) });
      }
    }

    if (dippedApps.length === 0) return null;

    // Sort by biggest drop
    dippedApps.sort((a, b) => b.drop - a.drop);

    // Buy the biggest dip if we have ELTA
    const biggest = dippedApps[0]!; // Non-null assertion after length check
    const eltaBalance = this.getEltaBalance();
    const tradeAmount = (eltaBalance * BigInt(Math.floor(maxTrade * 100))) / 100n;

    if (tradeAmount < BigInt(10e18)) return null; // Min 10 ELTA

    ctx.logger.info(
      {
        agent: this.id,
        app: biggest.id,
        drop: `${(biggest.drop * 100).toFixed(1)}%`,
        amount: this.formatElta(tradeAmount),
      },
      'Buying the dip'
    );

    // Record entry price
    this.entryPrices.set(biggest.id, biggest.app.tokenPrice);

    return this.createAction(
      'buy_app_token',
      buyAppToken(biggest.id, biggest.app.tokenAddress, tradeAmount),
      ctx.tick
    );
  }
}
