/**
 * DegenTraderAgent - High-frequency, high-risk trader
 *
 * Behavior:
 * - Trades 5-10x more frequently than BasicUserAgent
 * - Uses larger position sizes
 * - Chases pumps (FOMO buying)
 * - Panic sells on price drops
 * - Generates substantial fees through high activity
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for DegenTraderAgent
 */
export interface DegenTraderAgentParams extends BaseProtocolAgentParams {
  /** Trade frequency multiplier (default 5x normal) */
  tradeFrequency?: number;
  /** Risk multiplier for position sizing (default 2.0) */
  riskMultiplier?: number;
  /** FOMO threshold - buy when price up this % (default 0.05 = 5%) */
  fomoThreshold?: number;
  /** Panic sell threshold - sell when price down this % (default 0.03 = 3%) */
  panicSellThreshold?: number;
  /** Minimum trade size in ELTA */
  minTradeSize?: bigint;
  /** Maximum percentage of balance per trade (default 0.5 = 50%) */
  maxPositionPercent?: number;
}

/**
 * High-frequency degen trader that generates lots of fees
 */
export class DegenTraderAgent extends BaseProtocolAgent {
  /** Track last known prices for momentum detection */
  private lastPrices: Map<string, bigint> = new Map();

  /** Track positions for P&L */
  private positions: Map<string, { amount: bigint; avgCost: bigint }> = new Map();

  /** Consecutive loss counter for tilt detection */
  private consecutiveLosses = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const tradeFreq = (this.params.tradeFrequency as number | undefined) ?? 5;
    const riskMult = (this.params.riskMultiplier as number | undefined) ?? 2.0;
    const fomoThreshold = (this.params.fomoThreshold as number | undefined) ?? 0.05;
    const panicThreshold = (this.params.panicSellThreshold as number | undefined) ?? 0.03;
    const minTrade = (this.params.minTradeSize as bigint | undefined) ?? BigInt(50e18);
    const maxPosPct = (this.params.maxPositionPercent as number | undefined) ?? 0.5;

    // Degens trade very frequently
    const baseProb = 0.3 * tradeFreq;
    
    // Check for panic sell first (highest priority for degens)
    const panicAction = this.checkPanicSell(ctx, panicThreshold);
    if (panicAction) return panicAction;

    // Check for FOMO buy opportunities
    if (this.shouldAct(ctx, baseProb * 0.6)) {
      const fomoAction = this.checkFomoBuy(ctx, fomoThreshold, minTrade, maxPosPct, riskMult);
      if (fomoAction) return fomoAction;
    }

    // Regular aggressive buying
    if (this.shouldAct(ctx, baseProb * 0.4)) {
      const buyAction = this.aggressiveBuy(ctx, minTrade, maxPosPct, riskMult);
      if (buyAction) return buyAction;
    }

    // Take profits if significantly up
    if (this.shouldAct(ctx, baseProb * 0.3)) {
      const profitAction = this.takeProfits(ctx);
      if (profitAction) return profitAction;
    }

    // Update price tracking
    this.updatePriceTracking();

    return null;
  }

  /**
   * Check if any position needs panic selling
   */
  private checkPanicSell(ctx: TickContext, threshold: number): Action | null {
    for (const [appId, position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) continue;

      // Calculate loss percentage
      const currentValue = app.tokenPrice;
      const costBasis = position.avgCost;
      
      if (costBasis > 0n) {
        const lossPct = Number(costBasis - currentValue) / Number(costBasis);
        
        if (lossPct > threshold) {
          // PANIC SELL EVERYTHING
          ctx.logger.info(
            { agent: this.id, app: appId, lossPct: (lossPct * 100).toFixed(2) + '%' },
            'PANIC SELLING - Price dropped!'
          );

          this.consecutiveLosses++;
          
          return this.createAction(
            'sell_app_token',
            sellAppToken(appId, app.tokenAddress, balance),
            ctx.tick
          );
        }
      }
    }
    return null;
  }

  /**
   * FOMO buy when price is pumping
   */
  private checkFomoBuy(
    ctx: TickContext,
    threshold: number,
    minTrade: bigint,
    maxPosPct: number,
    riskMult: number
  ): Action | null {
    if (!this.hasEnoughElta(minTrade)) return null;

    // Find pumping apps
    const pumpingApps: Array<{ app: AppState; gainPct: number }> = [];
    
    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;
      
      const lastPrice = this.lastPrices.get(appId);
      if (lastPrice && lastPrice > 0n) {
        const gainPct = Number(app.tokenPrice - lastPrice) / Number(lastPrice);
        if (gainPct > threshold) {
          pumpingApps.push({ app, gainPct });
        }
      }
    }

    if (pumpingApps.length === 0) return null;

    // Sort by gain and pick the hottest
    pumpingApps.sort((a, b) => b.gainPct - a.gainPct);
    const target = pumpingApps[0]!;

    // FOMO in with aggressive sizing
    const available = this.getEltaBalance();
    const baseAmount = BigInt(Math.floor(Number(available) * maxPosPct * riskMult));
    const amount = baseAmount < minTrade ? minTrade : baseAmount;

    if (!this.hasEnoughElta(amount)) return null;

    ctx.logger.info(
      { 
        agent: this.id, 
        app: target.app.id, 
        gainPct: (target.gainPct * 100).toFixed(2) + '%',
        amount: this.formatElta(amount)
      },
      'FOMO BUYING - Price pumping!'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(String(target.app.id), target.app.tokenAddress, amount),
      ctx.tick
    );
  }

  /**
   * Aggressive regular buying
   */
  private aggressiveBuy(
    ctx: TickContext,
    minTrade: bigint,
    maxPosPct: number,
    riskMult: number
  ): Action | null {
    if (!this.hasEnoughElta(minTrade)) return null;

    // Pick any active app
    const app = this.chooseRandomApp(ctx);
    if (!app || app.graduated) return null;

    // Aggressive position sizing
    const available = this.getEltaBalance();
    const randomFactor = 0.3 + ctx.rng.nextFloat() * 0.7; // 0.3 to 1.0
    const amount = BigInt(Math.floor(Number(available) * maxPosPct * riskMult * randomFactor));

    const finalAmount = amount < minTrade ? minTrade : amount;
    if (!this.hasEnoughElta(finalAmount)) return null;

    // Tilt mode: bet even bigger after losses
    const tiltMultiplier = this.consecutiveLosses > 0 ? 1 + (this.consecutiveLosses * 0.2) : 1;
    const tiltAmount = BigInt(Math.floor(Number(finalAmount) * tiltMultiplier));

    const actualAmount = this.hasEnoughElta(tiltAmount) ? tiltAmount : finalAmount;

    ctx.logger.debug(
      { agent: this.id, app: app.id, amount: this.formatElta(actualAmount) },
      'Degen buying'
    );

    // Track position
    const existing = this.positions.get(String(app.id));
    if (existing) {
      this.positions.set(String(app.id), {
        amount: existing.amount + actualAmount,
        avgCost: (existing.avgCost * existing.amount + app.tokenPrice * actualAmount) / 
                 (existing.amount + actualAmount),
      });
    } else {
      this.positions.set(String(app.id), { amount: actualAmount, avgCost: app.tokenPrice });
    }

    return this.createAction(
      'buy_app_token',
      buyAppToken(String(app.id), app.tokenAddress, actualAmount),
      ctx.tick
    );
  }

  /**
   * Take profits on winning positions
   */
  private takeProfits(ctx: TickContext): Action | null {
    for (const [appId, position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const balance = this.appTokenBalances.get(appId) ?? 0n;
      if (balance === 0n) continue;

      // Check for profit
      const gainPct = Number(app.tokenPrice - position.avgCost) / Number(position.avgCost);
      
      // Take profits at 10%+ gain
      if (gainPct > 0.1) {
        // Sell half to lock in profits
        const sellAmount = balance / 2n;

        ctx.logger.info(
          { agent: this.id, app: appId, gainPct: (gainPct * 100).toFixed(2) + '%' },
          'Taking profits'
        );

        this.consecutiveLosses = 0; // Reset tilt

        return this.createAction(
          'sell_app_token',
          sellAppToken(appId, app.tokenAddress, sellAmount),
          ctx.tick
        );
      }
    }
    return null;
  }

  /**
   * Update price tracking for momentum detection
   */
  private updatePriceTracking(): void {
    for (const [appId, app] of this.getAllApps()) {
      this.lastPrices.set(appId, app.tokenPrice);
    }
  }
}
