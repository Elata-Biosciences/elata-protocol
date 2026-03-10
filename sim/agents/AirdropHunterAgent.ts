/**
 * AirdropHunterAgent - Claims airdrops
 *
 * Behavior:
 * - Monitors airdrop campaigns
 * - Claims eligible airdrops using Merkle proofs
 * - Manages airdrop tokens
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimAirdrop } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for AirdropHunterAgent
 */
export interface AirdropHunterAgentParams extends BaseProtocolAgentParams {
  /** Probability of claiming airdrops each tick */
  claimProbability?: number;
  /** Minimum amount to bother claiming */
  minClaimAmount?: bigint;
}

/**
 * Agent that hunts for and claims airdrops
 */
export class AirdropHunterAgent extends BaseProtocolAgent {
  /** Track total claimed */
  private totalClaimed = 0n;

  /** Track campaigns claimed */
  private claimedCampaigns = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const claimProb = (this.params.claimProbability as number | undefined) ?? 0.8;
    const minAmount = (this.params.minClaimAmount as bigint | undefined) ?? BigInt(1e18);

    // Check for unclaimed airdrops
    if (!this.hasUnclaimedAirdrops()) return null;

    // Claim with probability
    if (this.shouldAct(ctx, claimProb)) {
      const claimAction = this.considerClaimingAirdrop(ctx, minAmount);
      if (claimAction) return claimAction;
    }

    return null;
  }

  /**
   * Consider claiming an airdrop
   */
  private considerClaimingAirdrop(ctx: TickContext, minAmount: bigint): Action | null {
    const airdrop = this.getNextClaimableAirdrop();
    if (!airdrop) return null;

    // Skip small amounts
    if (airdrop.amount < minAmount) {
      this.markAirdropClaimed(airdrop.campaignId);
      return null;
    }

    ctx.logger.info(
      {
        agent: this.id,
        campaignId: airdrop.campaignId.toString(),
        amount: this.formatElta(airdrop.amount),
      },
      'Claiming airdrop'
    );

    return this.createAction(
      'claim_airdrop',
      claimAirdrop(airdrop.campaignId, airdrop.proof, airdrop.amount),
      ctx.tick
    );
  }

  /**
   * Record successful airdrop claim
   */
  recordClaim(campaignId: bigint, amount: bigint): void {
    this.markAirdropClaimed(campaignId);
    this.totalClaimed += amount;
    this.claimedCampaigns++;
  }

  /**
   * Register eligible airdrop (typically called by simulation setup)
   */
  registerEligibleAirdrop(campaignId: bigint, proof: `0x${string}`[], amount: bigint): void {
    this.eligibleAirdrops.set(campaignId, { proof, amount });
  }

  /**
   * Get airdrop statistics
   */
  getAirdropStats(): { totalClaimed: bigint; campaignsClaimed: number; pending: number } {
    return {
      totalClaimed: this.totalClaimed,
      campaignsClaimed: this.claimedCampaigns,
      pending: this.eligibleAirdrops.size,
    };
  }
}
