/**
 * ManipulatorAgent - Tests economic attack vectors
 *
 * Behavior:
 * - Attempts price manipulation via large trades
 * - Tests sandwich attack patterns (front/back-running)
 * - Probes for arbitrage opportunities
 * - Tests market stability under adversarial conditions
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, noop, sellAppToken } from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Attack strategy type
 */
type AttackStrategy = 'pump_dump' | 'whale_splash' | 'arbitrage' | 'sandwich';

/**
 * Parameters for ManipulatorAgent
 */
export interface ManipulatorAgentParams extends BaseProtocolAgentParams {
  /** Attack aggressiveness (0-1) */
  aggressiveness?: number;
  /** Preferred attack strategy */
  preferredStrategy?: AttackStrategy;
  /** Minimum profit threshold for arbitrage */
  minProfitThreshold?: number;
  /** Maximum position size (as % of balance) */
  maxPositionPercent?: number;
}

/**
 * Agent that attempts market manipulation for testing
 */
export class ManipulatorAgent extends BaseProtocolAgent {
  /** Track manipulation attempts */
  private attempts = {
    pumpDump: 0,
    whaleSplash: 0,
    arbitrage: 0,
    sandwich: 0,
  };

  /** Track success/failure */
  private results = {
    succeeded: 0,
    failed: 0,
    profitLoss: 0n,
  };

  /** Current strategy in progress */
  private currentStrategy: AttackStrategy | null = null;
  private strategyPhase = 0;
  private targetAppId: string | null = null;
  private positionSize = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const aggressiveness = (this.params.aggressiveness as number | undefined) ?? 0.7;
    const strategy = (this.params.preferredStrategy as AttackStrategy | undefined) ?? 'pump_dump';
    const maxPosition = (this.params.maxPositionPercent as number | undefined) ?? 0.5;

    // Continue current strategy if in progress
    if (this.currentStrategy && this.targetAppId) {
      const continueAction = this.continueStrategy(ctx);
      if (continueAction) return continueAction;
    }

    // Start new manipulation attempt
    if (this.shouldAct(ctx, aggressiveness * 0.3)) {
      const newStrategy = this.selectStrategy(ctx, strategy);
      const startAction = this.startStrategy(ctx, newStrategy, maxPosition);
      if (startAction) return startAction;
    }

    return null;
  }

  /**
   * Select strategy to execute
   */
  private selectStrategy(ctx: TickContext, preferred: AttackStrategy): AttackStrategy {
    const strategies: AttackStrategy[] = ['pump_dump', 'whale_splash', 'arbitrage'];

    // Weight towards preferred strategy
    if (ctx.rng.chance(0.6)) {
      return preferred;
    }
    return ctx.rng.pickOne(strategies);
  }

  /**
   * Start a new manipulation strategy
   */
  private startStrategy(
    ctx: TickContext,
    strategy: AttackStrategy,
    maxPosition: number
  ): Action | null {
    // Find target app
    const apps = Array.from(this.getAllApps().values()).filter((a) => !a.graduated);
    if (apps.length === 0) return null;

    // Pick target (prefer smaller apps for easier manipulation)
    const sortedApps = [...apps].sort((a, b) => Number(a.totalRaised - b.totalRaised));
    const target = sortedApps[0]!;

    const appIdStr = String(target.id);
    this.currentStrategy = strategy;
    this.targetAppId = appIdStr;
    this.strategyPhase = 1;

    const eltaBalance = this.getEltaBalance();
    this.positionSize = (eltaBalance * BigInt(Math.floor(maxPosition * 100))) / 100n;

    ctx.logger.info(
      { agent: this.id, strategy, target: appIdStr, position: this.formatElta(this.positionSize) },
      'Starting manipulation strategy'
    );

    // Phase 1: Buy to accumulate position
    this.attempts[
      strategy === 'pump_dump'
        ? 'pumpDump'
        : strategy === 'whale_splash'
          ? 'whaleSplash'
          : 'arbitrage'
    ]++;

    return this.createAction(
      'buy_app_token',
      buyAppToken(appIdStr, target.tokenAddress, this.positionSize),
      ctx.tick
    );
  }

  /**
   * Continue executing current strategy
   */
  private continueStrategy(ctx: TickContext): Action | null {
    if (!this.currentStrategy || !this.targetAppId) return null;

    const app = this.getAppState(this.targetAppId);
    if (!app) {
      this.resetStrategy();
      return null;
    }

    switch (this.currentStrategy) {
      case 'pump_dump':
        return this.executePumpDump(ctx, app);
      case 'whale_splash':
        return this.executeWhaleSplash(ctx, app);
      case 'arbitrage':
        return this.executeArbitrage(ctx, app);
      default:
        this.resetStrategy();
        return null;
    }
  }

  /**
   * Execute pump and dump strategy
   * Phase 1: Buy (done in startStrategy)
   * Phase 2: Wait for price to rise
   * Phase 3: Dump tokens
   */
  private executePumpDump(ctx: TickContext, app: AppState): Action | null {
    const appIdStr = String(app.id);
    this.strategyPhase++;

    // Phase 2: Wait a tick
    if (this.strategyPhase === 2) {
      ctx.logger.debug({ agent: this.id, strategy: 'pump_dump' }, 'Waiting for price movement');
      return this.createAction('noop', noop('Waiting for price movement'), ctx.tick);
    }

    // Phase 3: Dump
    if (this.strategyPhase === 3) {
      const tokenBalance = this.getAppTokenBalance(appIdStr);
      if (tokenBalance > 0n) {
        ctx.logger.info(
          { agent: this.id, strategy: 'pump_dump', tokens: tokenBalance.toString() },
          'Dumping tokens'
        );
        this.resetStrategy();
        return this.createAction(
          'sell_app_token',
          sellAppToken(appIdStr, app.tokenAddress, tokenBalance),
          ctx.tick
        );
      }
    }

    this.resetStrategy();
    return null;
  }

  /**
   * Execute whale splash (large sudden buy/sell)
   */
  private executeWhaleSplash(ctx: TickContext, app: AppState): Action | null {
    const appIdStr = String(app.id);
    this.strategyPhase++;

    // Phase 2: Immediate large sell
    if (this.strategyPhase === 2) {
      const tokenBalance = this.getAppTokenBalance(appIdStr);
      if (tokenBalance > 0n) {
        ctx.logger.info(
          { agent: this.id, strategy: 'whale_splash', tokens: tokenBalance.toString() },
          'Whale splash sell'
        );
        this.resetStrategy();
        return this.createAction(
          'sell_app_token',
          sellAppToken(appIdStr, app.tokenAddress, tokenBalance),
          ctx.tick
        );
      }
    }

    this.resetStrategy();
    return null;
  }

  /**
   * Execute arbitrage strategy
   */
  private executeArbitrage(ctx: TickContext, app: AppState): Action | null {
    const appIdStr = String(app.id);
    // Simple arbitrage: check if we can profit from price difference
    // In bonding curve context, look for apps where buy price < sell value

    this.strategyPhase++;

    // Phase 2: Evaluate and sell if profitable
    if (this.strategyPhase === 2) {
      const tokenBalance = this.getAppTokenBalance(appIdStr);
      if (tokenBalance > 0n) {
        // For now, just sell - real arb would check other DEXs
        ctx.logger.info({ agent: this.id, strategy: 'arbitrage' }, 'Closing arbitrage position');
        this.resetStrategy();
        return this.createAction(
          'sell_app_token',
          sellAppToken(appIdStr, app.tokenAddress, tokenBalance),
          ctx.tick
        );
      }
    }

    this.resetStrategy();
    return null;
  }

  /**
   * Reset current strategy
   */
  private resetStrategy(): void {
    this.currentStrategy = null;
    this.targetAppId = null;
    this.strategyPhase = 0;
    this.positionSize = 0n;
  }

  /**
   * Record strategy result
   */
  recordResult(success: boolean, profitLoss: bigint): void {
    if (success) {
      this.results.succeeded++;
    } else {
      this.results.failed++;
    }
    this.results.profitLoss += profitLoss;
  }

  /**
   * Get manipulation statistics
   */
  getManipulationStats(): typeof this.attempts & typeof this.results {
    return {
      ...this.attempts,
      ...this.results,
    };
  }
}
