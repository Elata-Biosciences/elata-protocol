/**
 * AppStakerAgent - Focuses on app token staking
 *
 * Behavior:
 * - Buys app tokens specifically to stake them
 * - Stakes tokens in app vaults to earn rewards
 * - Claims app-specific rewards regularly
 * - May unstake and compound (sell rewards, buy more tokens)
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { buyAppToken, claimAppRewards, stakeAppToken, unstakeAppToken } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for AppStakerAgent
 */
export interface AppStakerAgentParams extends BaseProtocolAgentParams {
  /** Probability of buying tokens to stake */
  buyToStakeProbability?: number;
  /** Probability of staking held tokens */
  stakeProbability?: number;
  /** Probability of claiming app rewards */
  claimProbability?: number;
  /** Probability of unstaking to rebalance */
  unstakeProbability?: number;
  /** Minimum tokens to stake */
  minStakeAmount?: bigint;
  /** Target number of apps to stake in */
  targetApps?: number;
}

/**
 * Agent focused on app token staking and app-specific rewards
 */
export class AppStakerAgent extends BaseProtocolAgent {
  /** Track staked amounts per app */
  private stakedAmounts: Map<string, bigint> = new Map();
  /** Track apps we're targeting */
  private targetedApps: Set<string> = new Set();

  async step(ctx: TickContext): Promise<Action | null> {
    const buyProb = (this.params.buyToStakeProbability as number | undefined) ?? 0.3;
    const stakeProb = (this.params.stakeProbability as number | undefined) ?? 0.4;
    const claimProb = (this.params.claimProbability as number | undefined) ?? 0.2;
    const unstakeProb = (this.params.unstakeProbability as number | undefined) ?? 0.05;
    const minStake = (this.params.minStakeAmount as bigint | undefined) ?? BigInt(50e18);
    const targetApps = (this.params.targetApps as number | undefined) ?? 3;

    // Priority 1: Buy tokens to stake if we don't have enough positions
    if (this.targetedApps.size < targetApps && this.shouldAct(ctx, buyProb)) {
      const buyAction = this.considerBuyingToStake(ctx, minStake);
      if (buyAction) return buyAction;
    }

    // Priority 2: Stake any unstaked tokens we're holding
    if (this.shouldAct(ctx, stakeProb)) {
      const stakeAction = this.considerStaking(ctx, minStake);
      if (stakeAction) return stakeAction;
    }

    // Priority 3: Claim rewards from staked positions
    if (this.shouldAct(ctx, claimProb)) {
      const claimAction = this.considerClaimingAppRewards(ctx);
      if (claimAction) return claimAction;
    }

    // Priority 4: Occasionally unstake to rebalance
    if (this.shouldAct(ctx, unstakeProb)) {
      const unstakeAction = this.considerUnstaking(ctx);
      if (unstakeAction) return unstakeAction;
    }

    return null;
  }

  /**
   * Buy app tokens with the intention of staking them
   */
  private considerBuyingToStake(ctx: TickContext, minAmount: bigint): Action | null {
    const buyAmount = minAmount * 2n; // Buy enough to stake

    if (!this.hasEnoughElta(buyAmount)) {
      return null;
    }

    // Find an app we haven't targeted yet
    const apps = Array.from(this.getAllApps().values());
    const untargetedApps = apps.filter(
      (app) => !app.graduated && !this.targetedApps.has(String(app.id))
    );

    if (untargetedApps.length === 0) {
      return null;
    }

    // Pick a random untargeted app
    const app = ctx.rng.pickOne(untargetedApps);
    this.targetedApps.add(String(app.id));

    ctx.logger.info(
      { agent: this.id, app: app.id, amount: this.formatElta(buyAmount) },
      'Buying tokens to stake'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(String(app.id), app.tokenAddress, buyAmount),
      ctx.tick
    );
  }

  /**
   * Stake any held app tokens
   */
  private considerStaking(ctx: TickContext, minStake: bigint): Action | null {
    for (const [appId, balance] of this.appTokenBalances) {
      const stakedAmount = this.stakedAmounts.get(appId) ?? 0n;
      const unstaked = balance - stakedAmount;

      if (unstaked >= minStake) {
        const app = this.getAppState(appId);
        if (app) {
          // Stake all unstaked tokens
          this.stakedAmounts.set(appId, stakedAmount + unstaked);

          ctx.logger.info(
            { agent: this.id, app: appId, amount: unstaked.toString() },
            'Staking app tokens in vault'
          );

          return this.createAction(
            'stake_app_token',
            stakeAppToken(appId, app.tokenAddress, unstaked),
            ctx.tick
          );
        }
      }
    }

    return null;
  }

  /**
   * Claim app rewards from staked positions
   */
  private considerClaimingAppRewards(ctx: TickContext): Action | null {
    for (const [appId, stakedAmount] of this.stakedAmounts) {
      if (stakedAmount > 0n) {
        const app = this.getAppState(appId);
        if (app) {
          ctx.logger.debug({ agent: this.id, app: appId }, 'Claiming app staking rewards');

          return this.createAction(
            'claim_app_rewards',
            claimAppRewards(appId, app.tokenAddress),
            ctx.tick
          );
        }
      }
    }

    return null;
  }

  /**
   * Occasionally unstake to rebalance or take profits
   */
  private considerUnstaking(ctx: TickContext): Action | null {
    for (const [appId, stakedAmount] of this.stakedAmounts) {
      if (stakedAmount > BigInt(100e18)) {
        const app = this.getAppState(appId);
        if (app) {
          // Unstake half to rebalance
          const unstakeAmount = stakedAmount / 2n;
          this.stakedAmounts.set(appId, stakedAmount - unstakeAmount);

          ctx.logger.info(
            { agent: this.id, app: appId, amount: unstakeAmount.toString() },
            'Unstaking app tokens'
          );

          return this.createAction(
            'unstake_app_token',
            unstakeAppToken(appId, app.tokenAddress, unstakeAmount),
            ctx.tick
          );
        }
      }
    }

    return null;
  }
}
