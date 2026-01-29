/**
 * ReferrerAgent - Builds referral network
 *
 * Behavior:
 * - Acts as a referrer for other agents' purchases
 * - Claims accumulated referral rewards
 * - Tracks referral statistics
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimReferralRewards } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for ReferrerAgent
 */
export interface ReferrerAgentParams extends BaseProtocolAgentParams {
  /** Probability of claiming rewards each tick */
  claimProbability?: number;
  /** Minimum rewards to trigger claim */
  minRewardsToClaim?: bigint;
}

/**
 * Agent that builds and manages a referral network
 */
export class ReferrerAgent extends BaseProtocolAgent {
  /** Track referral count */
  private referralCount = 0;

  /** Track claimed rewards */
  private claimedRewards = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const claimProb = (this.params.claimProbability as number | undefined) ?? 0.3;
    const minRewards = (this.params.minRewardsToClaim as bigint | undefined) ?? BigInt(10e18);

    // Priority 1: Claim accumulated rewards
    if (this.canClaimReferralRewards() && this.shouldAct(ctx, claimProb)) {
      if (this.referralRewardsAccrued >= minRewards) {
        const claimAction = this.claimRewards(ctx);
        if (claimAction) return claimAction;
      }
    }

    return null;
  }

  /**
   * Claim accumulated referral rewards
   */
  private claimRewards(ctx: TickContext): Action | null {
    const amount = this.referralRewardsAccrued;

    ctx.logger.info(
      { agent: this.id, amount: this.formatElta(amount), referrals: this.referralCount },
      'Claiming referral rewards'
    );

    // Reset accrued rewards (will be updated by actual claim)
    this.claimedRewards += amount;
    this.referralRewardsAccrued = 0n;

    return this.createAction('claim_referral_rewards', claimReferralRewards(), ctx.tick);
  }

  /**
   * Record a new referral
   */
  addReferral(rewardAmount: bigint): void {
    this.referralCount++;
    this.referralRewardsAccrued += rewardAmount;
  }

  /**
   * Get referral statistics
   */
  getReferralStats(): { count: number; accrued: bigint; claimed: bigint } {
    return {
      count: this.referralCount,
      accrued: this.referralRewardsAccrued,
      claimed: this.claimedRewards,
    };
  }

  /**
   * Get the referrer address for other agents to use
   */
  getReferrerAddress(): string {
    return this.getAddress();
  }
}
