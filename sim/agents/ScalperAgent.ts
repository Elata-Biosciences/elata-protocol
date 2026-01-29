/**
 * ScalperAgent - Micro-profit trader with high transaction volume
 *
 * Behavior:
 * - Makes small frequent trades
 * - Targets tight profit margins (0.5-2%)
 * - Quick entries and exits (1-3 ticks)
 * - Generates high transaction volume and fees
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Position tracking for scalping
 */
interface ScalpPosition {
  appId: string;
  entryPrice: bigint;
  amount: bigint;
  entryTick: number;
}

/**
 * Parameters for ScalperAgent
 */
export interface ScalperAgentParams extends BaseProtocolAgentParams {
  /** Target profit in basis points (default 50 = 0.5%) */
  profitTargetBps?: number;
  /** Maximum ticks to hold a position (default 3) */
  maxHoldTicks?: number;
  /** Trade size as percentage of balance (default 0.1 = 10%) */
  tradeSizePercent?: number;
  /** Maximum concurrent positions (default 5) */
  maxPositions?: number;
  /** Minimum spread to enter (default 0.002 = 0.2%) */
  minSpread?: number;
}

/**
 * High-frequency scalper targeting micro-profits
 */
export class ScalperAgent extends BaseProtocolAgent {
  /** Active scalp positions */
  private positions: Map<string, ScalpPosition> = new Map();

  /** Total trades for tracking */
  private totalTrades = 0;

  /** Total profit/loss */
  private totalPnL = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const profitTarget = (this.params.profitTargetBps as number | undefined) ?? 50;
    const maxHold = (this.params.maxHoldTicks as number | undefined) ?? 3;
    const tradeSize = (this.params.tradeSizePercent as number | undefined) ?? 0.1;
    const maxPositions = (this.params.maxPositions as number | undefined) ?? 5;

    // Priority 1: Check for exits (profit target or max hold time)
    const exitAction = this.checkExits(ctx, profitTarget, maxHold);
    if (exitAction) return exitAction;

    // Priority 2: Enter new positions if under limit
    if (this.positions.size < maxPositions && this.shouldAct(ctx, 0.6)) {
      const entryAction = this.enterPosition(ctx, tradeSize);
      if (entryAction) return entryAction;
    }

    return null;
  }

  /**
   * Check all positions for exit conditions
   */
  private checkExits(ctx: TickContext, profitTargetBps: number, maxHoldTicks: number): Action | null {
    for (const [appId, position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      const currentPrice = app.tokenPrice;
      const holdTime = ctx.tick - position.entryTick;

      // Calculate profit in basis points
      const priceDiff = currentPrice - position.entryPrice;
      const profitBps = position.entryPrice > 0n 
        ? Number(priceDiff * 10000n / position.entryPrice)
        : 0;

      // Exit if profit target hit
      if (profitBps >= profitTargetBps) {
        ctx.logger.debug(
          { agent: this.id, app: appId, profitBps, holdTicks: holdTime },
          'Scalp profit target hit'
        );
        return this.exitPosition(ctx, appId, position, 'profit');
      }

      // Exit if max hold time reached (cut losses)
      if (holdTime >= maxHoldTicks) {
        ctx.logger.debug(
          { agent: this.id, app: appId, profitBps, holdTicks: holdTime },
          'Scalp max hold time - exiting'
        );
        return this.exitPosition(ctx, appId, position, 'timeout');
      }
    }

    return null;
  }

  /**
   * Enter a new scalp position
   */
  private enterPosition(ctx: TickContext, tradeSizePercent: number): Action | null {
    const minTrade = BigInt(10e18); // 10 ELTA minimum
    const balance = this.getEltaBalance();
    
    if (balance < minTrade) return null;

    // Calculate trade size
    const tradeAmount = BigInt(Math.floor(Number(balance) * tradeSizePercent));
    const finalAmount = tradeAmount < minTrade ? minTrade : tradeAmount;

    if (!this.hasEnoughElta(finalAmount)) return null;

    // Find an app to scalp
    const apps = Array.from(this.getAllApps().values())
      .filter(app => !app.graduated && !this.positions.has(String(app.id)));

    if (apps.length === 0) return null;

    // Pick randomly (scalpers don't care about fundamentals)
    const app = ctx.rng.pickOne(apps);

    // Create position
    const position: ScalpPosition = {
      appId: String(app.id),
      entryPrice: app.tokenPrice,
      amount: finalAmount,
      entryTick: ctx.tick,
    };

    this.positions.set(String(app.id), position);
    this.totalTrades++;

    ctx.logger.debug(
      { agent: this.id, app: app.id, amount: this.formatElta(finalAmount), trade: this.totalTrades },
      'Scalp entry'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(String(app.id), app.tokenAddress, finalAmount),
      ctx.tick
    );
  }

  /**
   * Exit a scalp position
   */
  private exitPosition(
    ctx: TickContext, 
    appId: string, 
    position: ScalpPosition,
    reason: 'profit' | 'timeout'
  ): Action | null {
    const app = this.getAppState(appId);
    if (!app) {
      this.positions.delete(appId);
      return null;
    }

    const balance = this.appTokenBalances.get(appId) ?? 0n;
    if (balance === 0n) {
      this.positions.delete(appId);
      return null;
    }

    // Calculate P&L
    const pnl = app.tokenPrice - position.entryPrice;
    this.totalPnL += pnl * balance / BigInt(1e18);

    // Remove position
    this.positions.delete(appId);
    this.totalTrades++;

    ctx.logger.debug(
      { 
        agent: this.id, 
        app: appId, 
        reason,
        totalTrades: this.totalTrades,
        runningPnL: this.formatElta(this.totalPnL)
      },
      'Scalp exit'
    );

    return this.createAction(
      'sell_app_token',
      sellAppToken(appId, app.tokenAddress, balance),
      ctx.tick
    );
  }

  /**
   * Get scalping statistics
   */
  getSimStats(): { totalTrades: number; totalPnL: bigint; openPositions: number } {
    return {
      totalTrades: this.totalTrades,
      totalPnL: this.totalPnL,
      openPositions: this.positions.size,
    };
  }
}
