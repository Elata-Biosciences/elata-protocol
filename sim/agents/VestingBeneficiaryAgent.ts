/**
 * VestingBeneficiaryAgent - App team member with vesting
 *
 * Behavior:
 * - Releases vested tokens on schedule
 * - May sell or stake released tokens
 * - Tracks vesting progress
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { releaseVestedTokens, sellAppToken, stakeAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for VestingBeneficiaryAgent
 */
export interface VestingBeneficiaryAgentParams extends BaseProtocolAgentParams {
  /** Probability of releasing tokens each tick */
  releaseProbability?: number;
  /** Probability of selling after release (vs staking) */
  sellProbability?: number;
  /** Probability of staking released tokens */
  stakeProbability?: number;
}

/**
 * Agent that manages vesting positions and released tokens
 */
export class VestingBeneficiaryAgent extends BaseProtocolAgent {
  /** Track released tokens per app */
  private releasedTokens: Map<string, bigint> = new Map();

  /** Total released across all vesting */
  private totalReleased = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const releaseProb = (this.params.releaseProbability as number | undefined) ?? 0.5;
    const sellProb = (this.params.sellProbability as number | undefined) ?? 0.2;
    const stakeProb = (this.params.stakeProbability as number | undefined) ?? 0.5;

    // Priority 1: Release vested tokens
    if (this.hasVestingPositions() && this.shouldAct(ctx, releaseProb)) {
      const releaseAction = this.considerReleasingTokens(ctx);
      if (releaseAction) return releaseAction;
    }

    // Priority 2: Do something with released tokens
    for (const [appId, amount] of this.releasedTokens) {
      if (amount <= 0n) continue;

      const app = this.getAppState(appId);
      if (!app) continue;

      // Decide: sell or stake
      if (this.shouldAct(ctx, sellProb)) {
        return this.sellTokens(ctx, appId, app.tokenAddress, amount);
      } else if (this.shouldAct(ctx, stakeProb)) {
        return this.stakeTokens(ctx, appId, app.tokenAddress, amount);
      }
    }

    return null;
  }

  /**
   * Consider releasing vested tokens
   */
  private considerReleasingTokens(ctx: TickContext): Action | null {
    const releasable = this.getReleasableVestingWallets();
    if (releasable.length === 0) return null;

    const walletAddress = ctx.rng.pickOne(releasable);
    const vestingData = this.vestingWallets.get(walletAddress);

    if (!vestingData) return null;

    ctx.logger.info(
      { agent: this.id, wallet: walletAddress, app: vestingData.appId },
      'Releasing vested tokens'
    );

    return this.createAction('release_vested_tokens', releaseVestedTokens(walletAddress), ctx.tick);
  }

  /**
   * Sell released tokens
   */
  private sellTokens(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address,
    amount: bigint
  ): Action {
    ctx.logger.info(
      { agent: this.id, app: appId, amount: this.formatElta(amount) },
      'Selling released vested tokens'
    );

    // Clear released tokens
    this.releasedTokens.set(appId, 0n);

    return this.createAction('sell_app_token', sellAppToken(appId, tokenAddress, amount), ctx.tick);
  }

  /**
   * Stake released tokens
   */
  private stakeTokens(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address,
    amount: bigint
  ): Action {
    ctx.logger.info(
      { agent: this.id, app: appId, amount: this.formatElta(amount) },
      'Staking released vested tokens'
    );

    // Clear released tokens
    this.releasedTokens.set(appId, 0n);

    return this.createAction(
      'stake_app_token',
      stakeAppToken(appId, tokenAddress, amount),
      ctx.tick
    );
  }

  /**
   * Register a vesting wallet this agent is beneficiary of
   */
  registerVestingWallet(walletAddress: Address, appId: string, totalAmount: bigint): void {
    this.vestingWallets.set(walletAddress, {
      appId,
      totalAmount,
      releasedAmount: 0n,
    });
  }

  /**
   * Record token release
   */
  recordRelease(walletAddress: Address, amount: bigint): void {
    const data = this.vestingWallets.get(walletAddress);
    if (data) {
      data.releasedAmount += amount;
      this.totalReleased += amount;

      // Add to available released tokens
      const current = this.releasedTokens.get(data.appId) ?? 0n;
      this.releasedTokens.set(data.appId, current + amount);
    }

    this.recordVestingRelease(walletAddress, amount);
  }

  /**
   * Get vesting statistics
   */
  getVestingStats(): { totalReleased: bigint; vestingPositions: number } {
    return {
      totalReleased: this.totalReleased,
      vestingPositions: this.vestingWallets.size,
    };
  }
}
