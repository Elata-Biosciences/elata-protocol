/**
 * VoterAgent - Passive governance participant
 *
 * Behavior:
 * - Acquires veELTA for voting power
 * - Votes on proposals based on configurable sentiment
 * - Never creates proposals (passive participant)
 * - May abstain based on probability
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { castVote, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for VoterAgent
 */
export interface VoterAgentParams extends BaseProtocolAgentParams {
  /** Probability of voting each tick */
  voteProbability?: number;
  /** Probability of voting FOR (vs AGAINST) */
  forBias?: number;
  /** Probability of abstaining */
  abstainProbability?: number;
  /** Minimum veELTA to hold */
  minVotingPower?: bigint;
  /** Lock duration in days */
  lockDurationDays?: number;
}

/**
 * Agent that passively participates in governance voting
 */
export class VoterAgent extends BaseProtocolAgent {
  /** Track proposals we've voted on */
  private votedProposals: Set<bigint> = new Set();

  /** Known active proposals */
  private activeProposals: Set<bigint> = new Set();

  /** Track if we've already attempted to lock */
  private hasAttemptedLock = false;

  async step(ctx: TickContext): Promise<Action | null> {
    // Refresh balances at start of each step
    await this.updateBalances();

    const voteProb = (this.params.voteProbability as number | undefined) ?? 0.6;
    const forBias = (this.params.forBias as number | undefined) ?? 0.7;
    const abstainProb = (this.params.abstainProbability as number | undefined) ?? 0.1;
    const minPower = (this.params.minVotingPower as bigint | undefined) ?? BigInt(500e18);
    const lockDays = (this.params.lockDurationDays as number | undefined) ?? 180;

    // Update lock status based on current balance
    if (this.veEltaBalance > 0n) {
      this.hasAttemptedLock = true;
    }

    // Priority 0: Ensure we have voting power (only attempt lock once)
    if (!this.hasAttemptedLock && !this.hasVotingPower(minPower)) {
      const lockAction = this.considerLockingForVotingPower(ctx, minPower, lockDays);
      if (lockAction) {
        this.hasAttemptedLock = true;
        return lockAction;
      }
    }

    // Priority 1: Vote on active proposals
    if (this.shouldAct(ctx, voteProb)) {
      const voteAction = this.considerVoting(ctx, forBias, abstainProb);
      if (voteAction) return voteAction;
    }

    return null;
  }

  /**
   * Lock ELTA for voting power if needed
   */
  private considerLockingForVotingPower(
    ctx: TickContext,
    minPower: bigint,
    lockDays: number
  ): Action | null {
    const lockAmount = minPower;
    if (!this.hasEnoughElta(lockAmount)) return null;

    const durationSeconds = lockDays * 24 * 60 * 60;

    ctx.logger.info(
      { agent: this.id, amount: this.formatElta(lockAmount), days: lockDays },
      'Locking ELTA for voting power'
    );

    return this.createAction('lock_veelta', lockVeElta(lockAmount, durationSeconds), ctx.tick);
  }

  /**
   * Consider voting on active proposals
   */
  private considerVoting(ctx: TickContext, forBias: number, abstainProb: number): Action | null {
    // Get proposals we haven't voted on
    const activeProposals = this.getActiveProposals();
    const unvoted = activeProposals.filter((id) => !this.votedProposals.has(id));

    if (unvoted.length === 0) return null;

    const proposalId = ctx.rng.pickOne(unvoted);
    this.votedProposals.add(proposalId);

    // Decide vote: abstain, for, or against
    let support: 0 | 1 | 2;
    let voteType: string;

    if (ctx.rng.chance(abstainProb)) {
      support = 2; // Abstain
      voteType = 'ABSTAIN';
    } else if (ctx.rng.chance(forBias)) {
      support = 1; // For
      voteType = 'FOR';
    } else {
      support = 0; // Against
      voteType = 'AGAINST';
    }

    ctx.logger.info(
      { agent: this.id, proposalId: proposalId.toString(), vote: voteType },
      'Casting vote on proposal'
    );

    return this.createAction('cast_vote', castVote(proposalId, support), ctx.tick);
  }

  /**
   * Register an active proposal to track
   */
  registerActiveProposal(id: bigint): void {
    this.activeProposals.add(id);
  }

  /**
   * Mark a proposal as no longer active
   */
  deactivateProposal(id: bigint): void {
    this.activeProposals.delete(id);
  }
}
