/**
 * ReferralNetworkBuilderAgent - Builds referral networks for commission
 *
 * Behavior:
 * - Recruits new users with referral codes
 * - Maximizes referral commission
 * - Tracks network growth
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { setReferrer, claimReferralRewards, buyAppToken } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Referral tracking
 */
interface Referral {
  address: Address;
  recruitedTick: number;
  purchaseVolume: bigint;
  commissionEarned: bigint;
  active: boolean;
}

/**
 * Parameters for ReferralNetworkBuilderAgent
 */
export interface ReferralNetworkBuilderAgentParams extends BaseProtocolAgentParams {
  /** Target network size (default 50) */
  targetNetworkSize?: number;
  /** Commission rate (default 0.02 = 2%) */
  commissionRate?: number;
  /** Recruitment intensity (default 0.15) */
  recruitmentRate?: number;
  /** Claim frequency in ticks (default 25) */
  claimFrequency?: number;
}

/**
 * Referral network builder
 */
export class ReferralNetworkBuilderAgent extends BaseProtocolAgent {
  /** Network members */
  private network: Referral[] = [];

  /** Total commission earned */
  private totalCommission = 0n;

  /** Pending commission */
  private pendingCommission = 0n;

  /** Last claim tick */
  private lastClaimTick = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetSize = (this.params.targetNetworkSize as number | undefined) ?? 50;
    const commissionRate = (this.params.commissionRate as number | undefined) ?? 0.02;
    const recruitRate = (this.params.recruitmentRate as number | undefined) ?? 0.15;
    const claimFreq = (this.params.claimFrequency as number | undefined) ?? 25;

    // Simulate network activity
    this.simulateNetworkActivity(ctx, commissionRate);

    // Priority 1: Claim accumulated rewards
    if (ctx.tick - this.lastClaimTick >= claimFreq && this.pendingCommission > BigInt(1e18)) {
      return this.claimCommission(ctx);
    }

    // Priority 2: Recruit new members
    if (this.network.length < targetSize && this.shouldAct(ctx, recruitRate)) {
      return this.recruitMember(ctx);
    }

    // Priority 3: Buy tokens to demonstrate protocol (leads by example)
    if (this.shouldAct(ctx, 0.1)) {
      return this.leadByExample(ctx);
    }

    return null;
  }

  /**
   * Recruit a new network member
   */
  private recruitMember(ctx: TickContext): Action | null {
    // Simulate recruiting a new member
    const newMember = `0x${Array(40).fill(0).map(() => 
      Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

    this.network.push({
      address: newMember,
      recruitedTick: ctx.tick,
      purchaseVolume: 0n,
      commissionEarned: 0n,
      active: true,
    });

    ctx.logger.debug(
      { 
        agent: this.id, 
        networkSize: this.network.length
      },
      'Recruited new referral'
    );

    // Set ourselves as referrer for this new member
    return this.createAction(
      'set_referrer',
      setReferrer(this.getAddress() as Address),
      ctx.tick
    );
  }

  /**
   * Simulate network members making purchases
   */
  private simulateNetworkActivity(ctx: TickContext, commissionRate: number): void {
    for (const member of this.network) {
      if (!member.active) continue;

      // Each member has a chance to make a purchase each tick
      if (ctx.rng.nextFloat() < 0.15) {
        // Random purchase volume
        const volume = BigInt(Math.floor(Math.random() * 100e18)) + BigInt(10e18);
        member.purchaseVolume += volume;

        // Calculate commission
        const commission = BigInt(Math.floor(Number(volume) * commissionRate));
        member.commissionEarned += commission;
        this.pendingCommission += commission;
      }

      // Members might become inactive
      if (ctx.rng.nextFloat() < 0.02) {
        member.active = false;
      }
    }
  }

  /**
   * Claim accumulated commission
   */
  private claimCommission(ctx: TickContext): Action | null {
    const claimAmount = this.pendingCommission;
    this.totalCommission += claimAmount;
    this.pendingCommission = 0n;
    this.lastClaimTick = ctx.tick;

    ctx.logger.info(
      { 
        agent: this.id, 
        claimAmount: this.formatElta(claimAmount),
        totalCommission: this.formatElta(this.totalCommission),
        networkSize: this.network.length
      },
      'Claiming referral commission'
    );

    return this.createAction(
      'claim_referral_rewards',
      claimReferralRewards(),
      ctx.tick
    );
  }

  /**
   * Buy tokens to demonstrate value to network
   */
  private leadByExample(ctx: TickContext): Action | null {
    const balance = this.getEltaBalance();
    const buyAmount = balance / 20n; // 5% of balance

    if (buyAmount < BigInt(5e18)) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);

    ctx.logger.debug(
      { agent: this.id, app: appId, amount: this.formatElta(buyAmount) },
      'Leading by example - buying tokens'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(appId, app.tokenAddress, buyAmount),
      ctx.tick
    );
  }

  /**
   * Get network statistics
   */
  getSimStats(): {
    networkSize: number;
    activeMembers: number;
    totalVolume: bigint;
    totalCommission: bigint;
    pendingCommission: bigint;
  } {
    const activeMembers = this.network.filter(m => m.active).length;
    const totalVolume = this.network.reduce((sum, m) => sum + m.purchaseVolume, 0n);

    return {
      networkSize: this.network.length,
      activeMembers,
      totalVolume,
      totalCommission: this.totalCommission,
      pendingCommission: this.pendingCommission,
    };
  }
}
