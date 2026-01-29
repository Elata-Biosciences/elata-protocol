/**
 * AirdropSniperAgent - Hunts and claims airdrops
 *
 * Behavior:
 * - Identifies airdrop opportunities
 * - Qualifies for airdrops through activity
 * - Claims airdrops efficiently
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimAirdrop, buyAppToken, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Airdrop campaign tracking
 */
interface AirdropCampaign {
  campaignId: bigint;
  appId: string;
  totalAllocation: bigint;
  eligibleAmount: bigint;
  requirements: {
    minHolding?: bigint;
    minActivity?: number;
    veEltaRequired?: boolean;
  };
  discovered: number;
  claimed: boolean;
  qualified: boolean;
}

/**
 * Parameters for AirdropSniperAgent
 */
export interface AirdropSniperAgentParams extends BaseProtocolAgentParams {
  /** Scout frequency (default 0.15) */
  scoutFrequency?: number;
  /** Qualification aggressiveness (default 0.3) */
  qualificationRate?: number;
  /** Minimum airdrop value to pursue (default 20 ELTA) */
  minAirdropValue?: bigint;
}

/**
 * Airdrop sniper
 */
export class AirdropSniperAgent extends BaseProtocolAgent {
  /** Known campaigns */
  private campaigns: AirdropCampaign[] = [];

  /** Total airdrops claimed */
  private totalClaimed = 0n;

  /** Activity score for qualification */
  private activityScore = 0;

  /** VeELTA locked for qualification */
  private veEltaLocked = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const scoutFreq = (this.params.scoutFrequency as number | undefined) ?? 0.15;
    const qualRate = (this.params.qualificationRate as number | undefined) ?? 0.3;
    const minValue = (this.params.minAirdropValue as bigint | undefined) ?? BigInt(20e18);

    // Priority 1: Claim qualified airdrops
    const claimAction = this.claimAirdrops(ctx);
    if (claimAction) return claimAction;

    // Priority 2: Scout for new airdrops
    if (this.shouldAct(ctx, scoutFreq)) {
      this.scoutAirdrops(ctx, minValue);
    }

    // Priority 3: Qualify for discovered airdrops
    if (this.shouldAct(ctx, qualRate)) {
      return this.qualifyForAirdrops(ctx);
    }

    return null;
  }

  /**
   * Scout for airdrop opportunities
   */
  private scoutAirdrops(ctx: TickContext, minValue: bigint): void {
    for (const [appId, _app] of this.getAllApps()) {
      // Check if we already know about this app's airdrop
      if (this.campaigns.some(c => c.appId === appId && !c.claimed)) continue;

      // Simulate discovering an airdrop (20% chance per app)
      if (ctx.rng.nextFloat() > 0.2) continue;

      // Generate airdrop details
      const totalAllocation = BigInt(Math.floor(Math.random() * 1000e18)) + minValue;
      const eligibleAmount = totalAllocation / BigInt(10 + Math.floor(Math.random() * 40));

      if (eligibleAmount < minValue) continue;

      // Build requirements object conditionally to satisfy exactOptionalPropertyTypes
      const requirements: AirdropCampaign['requirements'] = {
        veEltaRequired: ctx.rng.nextFloat() < 0.4,
      };
      if (ctx.rng.nextFloat() < 0.5) {
        requirements.minHolding = BigInt(10e18);
      }
      if (ctx.rng.nextFloat() < 0.3) {
        requirements.minActivity = 5;
      }

      const campaign: AirdropCampaign = {
        campaignId: BigInt(this.campaigns.length + 1),
        appId,
        totalAllocation,
        eligibleAmount,
        requirements,
        discovered: ctx.tick,
        claimed: false,
        qualified: false,
      };

      this.campaigns.push(campaign);

      ctx.logger.info(
        { 
          agent: this.id, 
          app: appId,
          eligibleAmount: this.formatElta(eligibleAmount),
          requirements: campaign.requirements
        },
        'Discovered airdrop opportunity'
      );
    }
  }

  /**
   * Take actions to qualify for airdrops
   */
  private qualifyForAirdrops(ctx: TickContext): Action | null {
    const balance = this.getEltaBalance();

    for (const campaign of this.campaigns) {
      if (campaign.claimed || campaign.qualified) continue;

      const app = this.getAppState(campaign.appId);
      if (!app) continue;

      // Check and fulfill requirements
      const reqs = campaign.requirements;

      // Requirement: Minimum holding
      if (reqs.minHolding) {
        const holding = this.appTokenBalances.get(campaign.appId) ?? 0n;
        if (holding < reqs.minHolding && balance >= reqs.minHolding) {
          ctx.logger.debug(
            { agent: this.id, app: campaign.appId, amount: this.formatElta(reqs.minHolding) },
            'Buying tokens to qualify for airdrop'
          );

          this.activityScore++;

          return this.createAction(
            'buy_app_token',
            buyAppToken(campaign.appId, app.tokenAddress, reqs.minHolding),
            ctx.tick
          );
        }
      }

      // Requirement: veELTA
      if (reqs.veEltaRequired && this.veEltaLocked === 0n) {
        const lockAmount = BigInt(20e18);
        if (balance >= lockAmount) {
          ctx.logger.debug(
            { agent: this.id, amount: this.formatElta(lockAmount) },
            'Locking veELTA to qualify for airdrop'
          );

          this.veEltaLocked = lockAmount;
          this.activityScore++;

          return this.createAction(
            'lock_veelta',
            lockVeElta(lockAmount, 365 * 24 * 60 * 60),
            ctx.tick
          );
        }
      }

      // Requirement: Activity
      if (reqs.minActivity && this.activityScore < reqs.minActivity) {
        // Do an activity to increase score
        const activityAmount = BigInt(5e18);
        if (balance >= activityAmount) {
          this.activityScore++;

          return this.createAction(
            'buy_app_token',
            buyAppToken(campaign.appId, app.tokenAddress, activityAmount),
            ctx.tick
          );
        }
      }

      // Check if all requirements met
      const holdingMet = !reqs.minHolding || 
        (this.appTokenBalances.get(campaign.appId) ?? 0n) >= reqs.minHolding;
      const veEltaMet = !reqs.veEltaRequired || this.veEltaLocked > 0n;
      const activityMet = !reqs.minActivity || this.activityScore >= reqs.minActivity;

      if (holdingMet && veEltaMet && activityMet) {
        campaign.qualified = true;
        ctx.logger.info(
          { agent: this.id, app: campaign.appId, eligibleAmount: this.formatElta(campaign.eligibleAmount) },
          'Qualified for airdrop'
        );
      }
    }

    return null;
  }

  /**
   * Claim qualified airdrops
   */
  private claimAirdrops(ctx: TickContext): Action | null {
    for (const campaign of this.campaigns) {
      if (campaign.claimed || !campaign.qualified) continue;

      campaign.claimed = true;
      this.totalClaimed += campaign.eligibleAmount;

      ctx.logger.info(
        { 
          agent: this.id, 
          app: campaign.appId,
          amount: this.formatElta(campaign.eligibleAmount),
          totalClaimed: this.formatElta(this.totalClaimed)
        },
        'Claiming airdrop'
      );

      const mockProof: `0x${string}`[] = [
        '0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`,
      ];

      return this.createAction(
        'claim_airdrop',
        claimAirdrop(campaign.campaignId, mockProof, campaign.eligibleAmount),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get sniper statistics
   */
  getSimStats(): {
    campaignsDiscovered: number;
    campaignsQualified: number;
    campaignsClaimed: number;
    totalClaimed: bigint;
    activityScore: number;
  } {
    return {
      campaignsDiscovered: this.campaigns.length,
      campaignsQualified: this.campaigns.filter(c => c.qualified).length,
      campaignsClaimed: this.campaigns.filter(c => c.claimed).length,
      totalClaimed: this.totalClaimed,
      activityScore: this.activityScore,
    };
  }
}
