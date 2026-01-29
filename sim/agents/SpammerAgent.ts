/**
 * SpammerAgent - Tests system limits
 *
 * Behavior:
 * - Creates many low-value transactions
 * - Tests rate limiting and gas efficiency
 * - Probes system stability under load
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, createApp, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Spam action type
 */
type SpamType = 'micro_trades' | 'app_spam' | 'lock_spam';

/**
 * Parameters for SpammerAgent
 */
export interface SpammerAgentParams extends BaseProtocolAgentParams {
  /** Number of actions to attempt per tick */
  actionsPerTick?: number;
  /** Preferred spam type */
  spamType?: SpamType;
  /** Minimum trade size (very small for spam) */
  minTradeSize?: bigint;
}

/**
 * Agent that generates high volumes of transactions
 */
export class SpammerAgent extends BaseProtocolAgent {
  /** Track spam statistics */
  private stats = {
    microTrades: 0,
    appCreations: 0,
    lockOperations: 0,
    totalGasUsed: 0n,
    failedAttempts: 0,
  };

  /** Counter for app naming */
  private appCounter = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    // Note: actionsPerTick can be used by external orchestrators for batch operations
    const spamType = (this.params.spamType as SpamType | undefined) ?? 'micro_trades';
    const minTrade = (this.params.minTradeSize as bigint | undefined) ?? BigInt(1e15); // 0.001 ELTA

    // Execute spam based on type
    switch (spamType) {
      case 'micro_trades':
        return this.executeMicroTrade(ctx, minTrade);
      case 'app_spam':
        return this.executeAppSpam(ctx);
      case 'lock_spam':
        return this.executeLockSpam(ctx);
      default:
        return this.executeMicroTrade(ctx, minTrade);
    }
  }

  /**
   * Execute micro trades (many small buys)
   */
  private executeMicroTrade(ctx: TickContext, minSize: bigint): Action | null {
    const apps = Array.from(this.getAllApps().values()).filter((a) => !a.graduated);
    if (apps.length === 0) return null;

    const app = ctx.rng.pickOne(apps);
    const appIdStr = String(app.id);

    // Very small trade
    const tradeSize = minSize + BigInt(Math.floor(ctx.rng.nextFloat() * Number(minSize)));

    if (!this.hasEnoughElta(tradeSize)) {
      this.stats.failedAttempts++;
      return null;
    }

    this.stats.microTrades++;

    ctx.logger.debug(
      { agent: this.id, type: 'micro_trade', size: this.formatElta(tradeSize) },
      'Executing spam micro trade'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(appIdStr, app.tokenAddress, tradeSize),
      ctx.tick
    );
  }

  /**
   * Execute app creation spam
   */
  private executeAppSpam(ctx: TickContext): Action | null {
    this.appCounter++;

    // Random short names to vary
    const name = `Spam${this.appCounter}_${ctx.rng.nextInt(0, 9999)}`;
    const symbol = `SP${this.appCounter}`;

    this.stats.appCreations++;

    ctx.logger.debug({ agent: this.id, type: 'app_spam', name }, 'Creating spam app');

    return this.createAction('create_app', createApp(name, symbol), ctx.tick);
  }

  /**
   * Execute lock operation spam (many small locks)
   */
  private executeLockSpam(ctx: TickContext): Action | null {
    // Very small lock amount
    const lockAmount = BigInt(1e17); // 0.1 ELTA
    const minDuration = 7 * 24 * 60 * 60; // 1 week minimum

    if (!this.hasEnoughElta(lockAmount)) {
      this.stats.failedAttempts++;
      return null;
    }

    // If already has veELTA, skip (can't create multiple locks)
    if (this.getVeEltaBalance() > 0n) {
      return this.executeMicroTrade(ctx, BigInt(1e15)); // Fallback to micro trades
    }

    this.stats.lockOperations++;

    ctx.logger.debug(
      { agent: this.id, type: 'lock_spam', amount: this.formatElta(lockAmount) },
      'Executing spam lock'
    );

    return this.createAction('lock_veelta', lockVeElta(lockAmount, minDuration), ctx.tick);
  }

  /**
   * Record gas used
   */
  recordGasUsed(gas: bigint): void {
    this.stats.totalGasUsed += gas;
  }

  /**
   * Get spam statistics
   */
  getSpamStats(): typeof this.stats {
    return { ...this.stats };
  }

  /**
   * Get average gas per operation
   */
  getAverageGas(): bigint {
    const totalOps = BigInt(
      this.stats.microTrades + this.stats.appCreations + this.stats.lockOperations
    );
    if (totalOps === 0n) return 0n;
    return this.stats.totalGasUsed / totalOps;
  }
}
