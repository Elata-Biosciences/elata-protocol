/**
 * LiquidityProviderAgent - Provides liquidity to pools
 *
 * Behavior:
 * - Adds liquidity to bonding curves
 * - Monitors pool health
 * - Rebalances positions
 * - Earns fees from swaps
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, sellAppToken } from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * LP position tracking
 */
interface LpPosition {
  appId: string;
  initialElta: bigint;
  currentElta: bigint;
  lastRebalanceTick: number;
}

/**
 * Parameters for LiquidityProviderAgent
 */
export interface LiquidityProviderAgentParams extends BaseProtocolAgentParams {
  /** Target number of pools to provide liquidity to (default 3) */
  targetPools?: number;
  /** Initial liquidity amount per pool (default 100 ELTA) */
  initialLiquidity?: bigint;
  /** Rebalance threshold as percentage drift (default 0.15 = 15%) */
  rebalanceThreshold?: number;
  /** Minimum ticks between rebalances (default 20) */
  rebalanceCooldown?: number;
  /** Percentage of profits to compound (default 0.5 = 50%) */
  compoundRate?: number;
}

/**
 * Liquidity provider - earns fees from pool activity
 */
export class LiquidityProviderAgent extends BaseProtocolAgent {
  /** LP positions */
  private positions: Map<string, LpPosition> = new Map();

  /** Target allocation per pool */
  private targetAllocations: Map<string, bigint> = new Map();

  /** Total fees earned (estimated) */
  private estimatedFeesEarned = 0n;

  /** Whether initial deployment is done */
  private deployed = false;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetPools = (this.params.targetPools as number | undefined) ?? 3;
    const initialLiquidity = (this.params.initialLiquidity as bigint | undefined) ?? BigInt(100e18);
    const rebalanceThreshold = (this.params.rebalanceThreshold as number | undefined) ?? 0.15;
    const rebalanceCooldown = (this.params.rebalanceCooldown as number | undefined) ?? 20;

    // Priority 1: Deploy initial liquidity
    if (!this.deployed) {
      const deployAction = this.deployLiquidity(ctx, targetPools, initialLiquidity);
      if (deployAction) return deployAction;
    }

    // Priority 2: Rebalance positions
    if (this.shouldAct(ctx, 0.3)) {
      const rebalanceAction = this.checkRebalance(ctx, rebalanceThreshold, rebalanceCooldown);
      if (rebalanceAction) return rebalanceAction;
    }

    // Priority 3: Monitor and adjust
    if (this.shouldAct(ctx, 0.1)) {
      return this.monitorPositions(ctx);
    }

    return null;
  }

  /**
   * Deploy initial liquidity across pools
   */
  private deployLiquidity(
    ctx: TickContext, 
    targetPools: number,
    liquidityPerPool: bigint
  ): Action | null {
    // Find pools to provide liquidity to
    const eligibleApps = Array.from(this.getAllApps().entries())
      .filter(([id, app]) => !app.graduated && !this.positions.has(id))
      .slice(0, targetPools);

    if (eligibleApps.length === 0) {
      this.deployed = true;
      return null;
    }

    const [appId, app] = eligibleApps[0]!;

    if (!this.hasEnoughElta(liquidityPerPool)) {
      // If we've deployed at least one, consider deployed
      if (this.positions.size > 0) {
        this.deployed = true;
      }
      return null;
    }

    // Create position
    this.positions.set(appId, {
      appId,
      initialElta: liquidityPerPool,
      currentElta: liquidityPerPool,
      lastRebalanceTick: ctx.tick,
    });

    this.targetAllocations.set(appId, liquidityPerPool);

    ctx.logger.info(
      { 
        agent: this.id, 
        app: appId, 
        amount: this.formatElta(liquidityPerPool),
        poolCount: this.positions.size
      },
      'LP deploying liquidity'
    );

    // Mark as deployed if we've reached target
    if (this.positions.size >= targetPools) {
      this.deployed = true;
    }

    return this.createAction(
      'buy_app_token',
      buyAppToken(appId, app.tokenAddress, liquidityPerPool),
      ctx.tick
    );
  }

  /**
   * Check if any positions need rebalancing
   */
  private checkRebalance(
    ctx: TickContext,
    threshold: number,
    cooldown: number
  ): Action | null {
    for (const [appId, position] of this.positions) {
      // Check cooldown
      if (ctx.tick - position.lastRebalanceTick < cooldown) continue;

      const app = this.getAppState(appId);
      if (!app) continue;

      const currentBalance = this.appTokenBalances.get(appId) ?? 0n;
      const target = this.targetAllocations.get(appId) ?? 0n;

      if (target === 0n) continue;

      // Calculate value drift
      // For simplicity, we track ELTA equivalent value
      const currentValue = currentBalance; // Simplified: token amount as proxy for value
      const drift = Math.abs(Number(currentValue - target)) / Number(target);

      if (drift > threshold) {
        return this.rebalancePosition(ctx, appId, app, currentBalance, target);
      }
    }

    return null;
  }

  /**
   * Rebalance a single position
   */
  private rebalancePosition(
    ctx: TickContext,
    appId: string,
    app: AppState,
    current: bigint,
    target: bigint
  ): Action | null {
    const position = this.positions.get(appId);
    if (!position) return null;

    // Update rebalance tick
    position.lastRebalanceTick = ctx.tick;

    if (current > target) {
      // Oversized - sell some
      const excess = current - target;
      const sellAmount = excess / 2n; // Sell half the excess

      if (sellAmount > 0n) {
        ctx.logger.debug(
          { agent: this.id, app: appId, amount: this.formatElta(sellAmount) },
          'LP rebalancing - reducing position'
        );

        return this.createAction(
          'sell_app_token',
          sellAppToken(appId, app.tokenAddress, sellAmount),
          ctx.tick
        );
      }
    } else {
      // Undersized - buy more
      const deficit = target - current;
      const buyAmount = deficit / 2n; // Buy half the deficit

      if (buyAmount > 0n && this.hasEnoughElta(buyAmount)) {
        ctx.logger.debug(
          { agent: this.id, app: appId, amount: this.formatElta(buyAmount) },
          'LP rebalancing - increasing position'
        );

        return this.createAction(
          'buy_app_token',
          buyAppToken(appId, app.tokenAddress, buyAmount),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Monitor positions and track metrics
   */
  private monitorPositions(ctx: TickContext): Action | null {
    // Update position tracking
    for (const [appId, position] of this.positions) {
      const balance = this.appTokenBalances.get(appId) ?? 0n;
      position.currentElta = balance;
    }

    // Check if any positions need attention (app graduated, etc.)
    for (const [appId, _position] of this.positions) {
      const app = this.getAppState(appId);
      if (!app) continue;

      // If app graduated, exit position
      if (app.graduated) {
        const balance = this.appTokenBalances.get(appId) ?? 0n;
        if (balance > 0n) {
          ctx.logger.info(
            { agent: this.id, app: appId },
            'LP exiting graduated app'
          );

          this.positions.delete(appId);
          this.targetAllocations.delete(appId);
          this.deployed = false; // Re-deploy to another pool

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
   * Get LP statistics
   */
  getSimStats(): {
    positionCount: number;
    totalDeployed: bigint;
    estimatedFeesEarned: bigint;
  } {
    let totalDeployed = 0n;
    for (const allocation of this.targetAllocations.values()) {
      totalDeployed += allocation;
    }

    return {
      positionCount: this.positions.size,
      totalDeployed,
      estimatedFeesEarned: this.estimatedFeesEarned,
    };
  }
}
