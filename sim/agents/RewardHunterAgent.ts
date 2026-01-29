/**
 * RewardHunterAgent - Maximizes reward collection
 *
 * Behavior:
 * - Claims veELTA rewards every tick if eligible
 * - Claims app rewards from all staked positions
 * - Compounds rewards by restaking
 * - Aggressive about getting into reward-earning positions
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import {
  buyAppToken,
  claimAppRewards,
  claimRewards,
  lockVeElta,
  stakeAppToken,
} from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for RewardHunterAgent
 */
export interface RewardHunterAgentParams extends BaseProtocolAgentParams {
  /** How aggressively to claim (0-1, higher = claim more often) */
  claimAggressiveness?: number;
  /** Whether to compound rewards into more staking */
  compoundRewards?: boolean;
  /** Minimum amount to compound */
  minCompoundAmount?: bigint;
}

/**
 * Agent focused on maximizing reward collection from all sources
 */
export class RewardHunterAgent extends BaseProtocolAgent {
  /** Track last claim tick to avoid claiming too often */
  private lastVeEltaClaim = -1;
  /** Track last app claim per app */
  private lastAppClaims: Map<string, number> = new Map();
  /** Track if we've set up reward-earning positions */
  private hasSetupPositions = false;
  /** Track if we've already attempted to lock */
  private hasAttemptedLock = false;

  async step(ctx: TickContext): Promise<Action | null> {
    // Refresh balances at start of each step
    await this.updateBalances();

    const aggressiveness = (this.params.claimAggressiveness as number | undefined) ?? 0.8;
    const compound = (this.params.compoundRewards as boolean | undefined) ?? true;
    const minCompound = (this.params.minCompoundAmount as bigint | undefined) ?? BigInt(50e18);

    // Phase 1: Setup - Get into reward-earning positions first
    if (!this.hasSetupPositions) {
      const setupAction = this.setupRewardPositions(ctx);
      if (setupAction) return setupAction;
    }

    // Phase 2: Claim aggressively
    const claimAction = await this.claimAllRewards(ctx, aggressiveness);
    if (claimAction) return claimAction;

    // Phase 3: Compound if enabled
    if (compound) {
      const compoundAction = this.compoundRewards(ctx, minCompound);
      if (compoundAction) return compoundAction;
    }

    return null;
  }

  /**
   * Setup reward-earning positions (veELTA lock, app token stakes)
   * Note: EltaPack handles lock state - if lock exists, it auto-increases
   */
  private setupRewardPositions(ctx: TickContext): Action | null {
    const hasVeElta = this.getVeEltaBalance() > 0n;

    // If we already have veELTA, we're done with the veELTA setup phase
    if (hasVeElta) {
      this.hasSetupPositions = true;
      this.hasAttemptedLock = true;
      return null;
    }

    // First, lock ELTA for veELTA if we don't have any yet (only try once)
    if (!hasVeElta && !this.hasAttemptedLock && this.hasEnoughElta(BigInt(200e18))) {
      const lockAmount = this.getEltaBalance() / 3n; // Lock 33%
      const lockDays = 365; // 1 year for good boost
      this.hasAttemptedLock = true;

      ctx.logger.info(
        { agent: this.id, amount: this.formatElta(lockAmount) },
        'Setting up veELTA lock for rewards'
      );

      return this.createAction(
        'lock_veelta',
        lockVeElta(lockAmount, lockDays * 24 * 60 * 60),
        ctx.tick
      );
    }

    // If we've already tried to lock, move on to app tokens
    if (this.hasAttemptedLock) {
      // Try to buy and stake app tokens instead
      if (this.hasEnoughElta(BigInt(100e18))) {
        const apps = Array.from(this.getAllApps().values()).filter((a) => !a.graduated);
        if (apps.length > 0) {
          const app = ctx.rng.pickOne(apps);
          const buyAmount = BigInt(100e18);

          ctx.logger.info(
            { agent: this.id, app: app.id, amount: this.formatElta(buyAmount) },
            'Buying app tokens for staking rewards'
          );

          // Mark as setup to avoid repeated buy attempts
          this.hasSetupPositions = true;

          return this.createAction(
            'buy_app_token',
            buyAppToken(String(app.id), app.tokenAddress, buyAmount),
            ctx.tick
          );
        }
      }

      // Check if we have app tokens to stake
      for (const [appId, balance] of this.appTokenBalances) {
        if (balance > BigInt(50e18)) {
          const app = this.getAppState(appId);
          if (app) {
            ctx.logger.info(
              { agent: this.id, app: appId, amount: balance.toString() },
              'Staking app tokens for rewards'
            );

            return this.createAction(
              'stake_app_token',
              stakeAppToken(appId, app.tokenAddress, balance),
              ctx.tick
            );
          }
        }
      }
    }

    // If nothing to do, mark as set up anyway to move to claim phase
    this.hasSetupPositions = true;
    return null;
  }

  /**
   * Claim all available rewards
   */
  private async claimAllRewards(ctx: TickContext, aggressiveness: number): Promise<Action | null> {
    // Claim veELTA rewards if we have veELTA and there are claimable epochs
    if (this.getVeEltaBalance() > 0n) {
      const ticksSinceLastClaim = ctx.tick - this.lastVeEltaClaim;
      // Use a minimum interval of 5 ticks to avoid excessive claims
      const claimInterval = Math.max(5, Math.floor(10 / aggressiveness));

      if (ticksSinceLastClaim >= claimInterval) {
        const hasClaimable = await this.hasClaimableVeEltaRewards();
        if (hasClaimable) {
          this.lastVeEltaClaim = ctx.tick;
          ctx.logger.debug({ agent: this.id, tick: ctx.tick }, 'Claiming veELTA rewards');
          return this.createAction('claim_rewards', claimRewards(), ctx.tick);
        }
      }
    }

    // Claim app rewards from staked positions only (check staked balance)
    for (const [appId] of this.appTokenBalances) {
      const lastClaim = this.lastAppClaims.get(appId) ?? -1;
      const ticksSinceClaim = ctx.tick - lastClaim;
      // Use a minimum interval of 5 ticks
      const claimInterval = Math.max(5, Math.floor(8 / aggressiveness));

      if (ticksSinceClaim >= claimInterval) {
        // Check if we actually have staked balance and claimable rewards
        const stakedBalance = await this.getStakedBalance(appId);
        if (stakedBalance > BigInt(10e18)) {
          const hasClaimable = await this.hasClaimableAppRewards(appId);
          if (hasClaimable) {
            const app = this.getAppState(appId);
            if (app) {
              this.lastAppClaims.set(appId, ctx.tick);
              ctx.logger.debug({ agent: this.id, app: appId }, 'Claiming app rewards');
              return this.createAction(
                'claim_app_rewards',
                claimAppRewards(appId, app.tokenAddress),
                ctx.tick
              );
            }
          }
        }
      }
    }

    return null;
  }

  /**
   * Compound rewards by restaking
   */
  private compoundRewards(ctx: TickContext, minAmount: bigint): Action | null {
    // If we have spare ELTA from rewards, stake more app tokens
    if (this.hasEnoughElta(minAmount)) {
      const apps = Array.from(this.getAllApps().values()).filter((a) => !a.graduated);
      if (apps.length > 0) {
        const app = ctx.rng.pickOne(apps);
        const buyAmount = minAmount;

        ctx.logger.info(
          { agent: this.id, amount: this.formatElta(buyAmount) },
          'Compounding rewards into more app tokens'
        );

        return this.createAction(
          'buy_app_token',
          buyAppToken(String(app.id), app.tokenAddress, buyAmount),
          ctx.tick
        );
      }
    }

    return null;
  }
}
