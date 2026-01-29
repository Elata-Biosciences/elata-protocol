/**
 * GovernorAgent - Active governance participant
 *
 * Behavior:
 * - Creates governance proposals for parameter changes
 * - Votes on all active proposals
 * - Queues and executes passed proposals
 * - Maintains veELTA position for voting power
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import {
  castVote,
  createProposal,
  executeProposal,
  lockVeElta,
  queueProposal,
} from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Proposal state tracking
 */
interface ProposalTracker {
  id: bigint;
  createdAt: number;
  state: 'pending' | 'active' | 'succeeded' | 'queued' | 'executed' | 'failed';
  votedOn: boolean;
}

/**
 * Parameters for GovernorAgent
 */
export interface GovernorAgentParams extends BaseProtocolAgentParams {
  /** Probability of creating a proposal each tick */
  proposeProbability?: number;
  /** Probability of voting each tick */
  voteProbability?: number;
  /** Minimum veELTA to hold for governance */
  minVotingPower?: bigint;
  /** Lock duration in days */
  lockDurationDays?: number;
  /** Ticks between proposal creation */
  proposalCooldown?: number;
}

/**
 * Agent that actively participates in governance
 */
export class GovernorAgent extends BaseProtocolAgent {
  /** Track proposals we've created or know about */
  private proposals: Map<bigint, ProposalTracker> = new Map();

  /** Last tick we created a proposal */
  private lastProposalTick = 0;

  /** Counter for proposal descriptions */
  private proposalCounter = 0;

  /** Track if we've already attempted to lock */
  private hasAttemptedLock = false;

  async step(ctx: TickContext): Promise<Action | null> {
    // Refresh balances at start of each step
    await this.updateBalances();

    const proposeProb = (this.params.proposeProbability as number | undefined) ?? 0.1;
    const voteProb = (this.params.voteProbability as number | undefined) ?? 0.8;
    const minPower = (this.params.minVotingPower as bigint | undefined) ?? BigInt(1000e18);
    const lockDays = (this.params.lockDurationDays as number | undefined) ?? 365;
    const cooldown = (this.params.proposalCooldown as number | undefined) ?? 20;

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

    // Priority 1: Execute queued proposals
    const execAction = await this.considerExecutingProposals(ctx);
    if (execAction) return execAction;

    // Priority 2: Queue succeeded proposals
    const queueAction = await this.considerQueueingProposals(ctx);
    if (queueAction) return queueAction;

    // Priority 3: Vote on active proposals
    if (this.shouldAct(ctx, voteProb)) {
      const voteAction = await this.considerVoting(ctx);
      if (voteAction) return voteAction;
    }

    // Priority 4: Create new proposals (with cooldown)
    if (ctx.tick - this.lastProposalTick >= cooldown && this.shouldAct(ctx, proposeProb)) {
      const propAction = this.considerCreatingProposal(ctx);
      if (propAction) {
        this.lastProposalTick = ctx.tick;
        return propAction;
      }
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
    const lockAmount = minPower * 2n; // Lock more than minimum
    if (!this.hasEnoughElta(lockAmount)) return null;

    const durationSeconds = lockDays * 24 * 60 * 60;

    ctx.logger.info(
      { agent: this.id, amount: this.formatElta(lockAmount), days: lockDays },
      'Locking ELTA for governance voting power'
    );

    return this.createAction('lock_veelta', lockVeElta(lockAmount, durationSeconds), ctx.tick);
  }

  /**
   * Consider voting on active proposals
   */
  private async considerVoting(ctx: TickContext): Promise<Action | null> {
    // Find proposals we haven't voted on
    for (const [proposalId, tracker] of this.proposals) {
      if (tracker.state === 'active' && !tracker.votedOn) {
        // Double-check on-chain state before voting
        const onChainState = await this.getProposalState(proposalId);
        // State 1 = Active
        if (onChainState !== 1) {
          // Update local state to reflect on-chain state
          if (onChainState !== null) {
            tracker.state = this.mapOnChainStateToLocal(onChainState);
          }
          continue;
        }

        // Check if we've already voted on-chain
        const alreadyVoted = await this.hasVotedOnProposal(proposalId);
        if (alreadyVoted) {
          tracker.votedOn = true;
          continue;
        }

        // Vote FOR (support = 1) for simplicity
        tracker.votedOn = true;

        ctx.logger.info(
          { agent: this.id, proposalId: proposalId.toString() },
          'Casting vote on proposal'
        );

        return this.createAction(
          'cast_vote',
          castVote(proposalId, 1, 'Supporting protocol improvement'),
          ctx.tick
        );
      }
    }
    return null;
  }

  /**
   * Map on-chain proposal state to local tracker state
   */
  private mapOnChainStateToLocal(onChainState: number): ProposalTracker['state'] {
    switch (onChainState) {
      case 0:
        return 'pending';
      case 1:
        return 'active';
      case 4:
        return 'succeeded';
      case 5:
        return 'queued';
      case 7:
        return 'executed';
      default:
        return 'failed'; // 2=Canceled, 3=Defeated, 6=Expired
    }
  }

  /**
   * Consider creating a new proposal
   */
  private considerCreatingProposal(ctx: TickContext): Action | null {
    // Check if we meet proposal threshold
    const threshold = this.getProposalThreshold();
    if (this.veEltaBalance < threshold) {
      return null;
    }

    this.proposalCounter++;
    const description = `Governance Proposal #${this.proposalCounter} from ${this.id}`;

    // Create a simple no-op proposal (targets empty for simulation)
    // In reality, would target real parameter changes
    const state = this.getWorldState();
    const targets: Address[] = [state.elta]; // Target ELTA contract as placeholder
    const values: bigint[] = [0n];
    const calldatas: `0x${string}`[] = ['0x']; // Empty calldata

    ctx.logger.info(
      { agent: this.id, proposalNumber: this.proposalCounter },
      'Creating governance proposal'
    );

    return this.createAction(
      'create_proposal',
      createProposal(targets, values, calldatas, description),
      ctx.tick
    );
  }

  /**
   * Consider queueing succeeded proposals
   */
  private async considerQueueingProposals(ctx: TickContext): Promise<Action | null> {
    for (const [proposalId, tracker] of this.proposals) {
      if (tracker.state === 'succeeded') {
        // Check on-chain state first
        const onChainState = await this.getProposalState(proposalId);
        // State 4 = Succeeded
        if (onChainState !== 4) {
          if (onChainState !== null) {
            tracker.state = this.mapOnChainStateToLocal(onChainState);
          }
          continue;
        }

        tracker.state = 'queued';

        ctx.logger.info(
          { agent: this.id, proposalId: proposalId.toString() },
          'Queueing succeeded proposal'
        );

        return this.createAction('queue_proposal', queueProposal(proposalId), ctx.tick);
      }
    }
    return null;
  }

  /**
   * Consider executing queued proposals
   */
  private async considerExecutingProposals(ctx: TickContext): Promise<Action | null> {
    for (const [proposalId, tracker] of this.proposals) {
      if (tracker.state === 'queued') {
        // Check on-chain state first
        const onChainState = await this.getProposalState(proposalId);
        // State 5 = Queued
        if (onChainState !== 5) {
          if (onChainState !== null) {
            tracker.state = this.mapOnChainStateToLocal(onChainState);
          }
          continue;
        }

        tracker.state = 'executed';

        ctx.logger.info(
          { agent: this.id, proposalId: proposalId.toString() },
          'Executing queued proposal'
        );

        return this.createAction('execute_proposal', executeProposal(proposalId), ctx.tick);
      }
    }
    return null;
  }

  /**
   * Register a proposal we created or learned about
   */
  registerProposal(id: bigint, tick: number): void {
    this.proposals.set(id, {
      id,
      createdAt: tick,
      state: 'pending',
      votedOn: false,
    });
  }

  /**
   * Update proposal state (called externally or from events)
   */
  updateProposalState(id: bigint, state: ProposalTracker['state']): void {
    const tracker = this.proposals.get(id);
    if (tracker) {
      tracker.state = state;
    }
  }
}
