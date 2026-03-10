/**
 * GovernanceDelegateAgent - Professional governance participant
 *
 * Behavior:
 * - Accumulates voting power
 * - Votes on all proposals
 * - May delegate or receive delegation
 * - Tracks governance participation
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { lockVeElta, delegateVotes, castVote, createProposal, queueProposal, executeProposal } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Proposal tracking
 */
interface TrackedProposal {
  proposalId: bigint;
  description: string;
  votedOn: boolean;
  vote: 0 | 1 | 2 | null; // Against, For, Abstain
  createdTick: number;
  state: 'active' | 'succeeded' | 'defeated' | 'queued' | 'executed';
}

/**
 * Parameters for GovernanceDelegateAgent
 */
export interface GovernanceDelegateAgentParams extends BaseProtocolAgentParams {
  /** Target voting power (default 100 ELTA) */
  targetVotingPower?: bigint;
  /** Voting frequency (default 0.3) */
  voteFrequency?: number;
  /** Vote tendency (0=against, 0.5=neutral, 1=for) (default 0.7) */
  voteTendency?: number;
  /** Create proposals (default false) */
  createProposals?: boolean;
  /** Delegate to address (if set) */
  delegateTo?: Address;
}

/**
 * Governance delegate agent
 */
export class GovernanceDelegateAgent extends BaseProtocolAgent {
  /** Known proposals */
  private proposals: TrackedProposal[] = [];

  /** Voting power accumulated */
  private votingPower = 0n;

  /** Votes cast */
  private votesCast = 0;

  /** Proposals created */
  private proposalsCreated = 0;

  /** Delegated flag */
  private hasDelegated = false;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetPower = (this.params.targetVotingPower as bigint | undefined) ?? BigInt(100e18);
    const voteFreq = (this.params.voteFrequency as number | undefined) ?? 0.3;
    const tendency = (this.params.voteTendency as number | undefined) ?? 0.7;
    const canCreate = (this.params.createProposals as boolean | undefined) ?? false;
    const delegateTo = this.params.delegateTo as Address | undefined;

    // Discover new proposals
    if (this.shouldAct(ctx, 0.2)) {
      this.discoverProposals(ctx);
    }

    // Priority 1: Accumulate voting power
    if (this.votingPower < targetPower && this.shouldAct(ctx, 0.2)) {
      const lockAction = this.accumulateVotingPower(ctx, targetPower);
      if (lockAction) return lockAction;
    }

    // Priority 2: Delegate if configured
    if (!this.hasDelegated && delegateTo) {
      return this.delegateVotingPower(ctx, delegateTo);
    }

    // Priority 3: Vote on proposals
    if (this.shouldAct(ctx, voteFreq)) {
      const voteAction = this.voteOnProposals(ctx, tendency);
      if (voteAction) return voteAction;
    }

    // Priority 4: Create proposals if enabled
    if (canCreate && this.votingPower >= targetPower && this.shouldAct(ctx, 0.05)) {
      return this.createNewProposal(ctx);
    }

    // Priority 5: Process proposal lifecycle
    if (this.shouldAct(ctx, 0.1)) {
      return this.processProposalLifecycle(ctx);
    }

    return null;
  }

  /**
   * Accumulate voting power through veELTA
   */
  private accumulateVotingPower(ctx: TickContext, target: bigint): Action | null {
    const balance = this.getEltaBalance();
    const needed = target - this.votingPower;
    const lockAmount = needed > balance ? balance : needed;

    if (lockAmount < BigInt(10e18)) return null;

    this.votingPower += lockAmount;

    ctx.logger.debug(
      { 
        agent: this.id, 
        amount: this.formatElta(lockAmount),
        totalPower: this.formatElta(this.votingPower)
      },
      'Accumulating voting power'
    );

    return this.createAction(
      'lock_veelta',
      lockVeElta(lockAmount, 4 * 365 * 24 * 60 * 60), // 4 years for max power
      ctx.tick
    );
  }

  /**
   * Delegate voting power
   */
  private delegateVotingPower(ctx: TickContext, delegatee: Address): Action | null {
    this.hasDelegated = true;

    ctx.logger.info(
      { agent: this.id, delegatee },
      'Delegating voting power'
    );

    return this.createAction(
      'delegate_votes',
      delegateVotes(delegatee),
      ctx.tick
    );
  }

  /**
   * Discover new proposals
   */
  private discoverProposals(ctx: TickContext): void {
    // Simulate discovering proposals
    if (ctx.rng.nextFloat() < 0.3) {
      const proposalId = BigInt(this.proposals.length + 1);
      
      this.proposals.push({
        proposalId,
        description: `Proposal ${proposalId}: Protocol improvement`,
        votedOn: false,
        vote: null,
        createdTick: ctx.tick,
        state: 'active',
      });

      ctx.logger.debug(
        { agent: this.id, proposalId: proposalId.toString() },
        'Discovered new proposal'
      );
    }
  }

  /**
   * Vote on active proposals
   */
  private voteOnProposals(ctx: TickContext, tendency: number): Action | null {
    if (this.votingPower === 0n) return null;

    for (const proposal of this.proposals) {
      if (proposal.votedOn || proposal.state !== 'active') continue;

      // Determine vote based on tendency
      let vote: 0 | 1 | 2;
      const roll = ctx.rng.nextFloat();
      
      if (roll < tendency * 0.8) {
        vote = 1; // For
      } else if (roll < tendency * 0.8 + 0.1) {
        vote = 2; // Abstain
      } else {
        vote = 0; // Against
      }

      proposal.votedOn = true;
      proposal.vote = vote;
      this.votesCast++;

      ctx.logger.info(
        { 
          agent: this.id, 
          proposalId: proposal.proposalId.toString(),
          vote: vote === 1 ? 'For' : vote === 0 ? 'Against' : 'Abstain',
          totalVotes: this.votesCast
        },
        'Casting governance vote'
      );

      return this.createAction(
        'cast_vote',
        castVote(proposal.proposalId, vote, 'Governance delegate vote'),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Create a new proposal
   */
  private createNewProposal(ctx: TickContext): Action | null {
    this.proposalsCreated++;

    // Create a simple proposal (e.g., parameter change)
    const targets: Address[] = [this.getWorldState().elta as Address];
    const values: bigint[] = [0n];
    const calldatas: `0x${string}`[] = ['0x' as `0x${string}`];
    const description = `Governance delegate proposal #${this.proposalsCreated}`;

    ctx.logger.info(
      { agent: this.id, proposalNumber: this.proposalsCreated },
      'Creating governance proposal'
    );

    return this.createAction(
      'create_proposal',
      createProposal(targets, values, calldatas, description),
      ctx.tick
    );
  }

  /**
   * Process proposal lifecycle (queue/execute)
   */
  private processProposalLifecycle(ctx: TickContext): Action | null {
    const votingPeriod = 10; // Ticks

    for (const proposal of this.proposals) {
      const age = ctx.tick - proposal.createdTick;

      // Check if voting period ended
      if (proposal.state === 'active' && age >= votingPeriod) {
        // Simulate success/defeat (70% success rate)
        proposal.state = ctx.rng.nextFloat() < 0.7 ? 'succeeded' : 'defeated';
      }

      // Queue succeeded proposals
      if (proposal.state === 'succeeded') {
        proposal.state = 'queued';

        ctx.logger.debug(
          { agent: this.id, proposalId: proposal.proposalId.toString() },
          'Queueing proposal'
        );

        return this.createAction(
          'queue_proposal',
          queueProposal(proposal.proposalId),
          ctx.tick
        );
      }

      // Execute queued proposals after timelock
      if (proposal.state === 'queued' && age >= votingPeriod + 5) {
        proposal.state = 'executed';

        ctx.logger.info(
          { agent: this.id, proposalId: proposal.proposalId.toString() },
          'Executing proposal'
        );

        return this.createAction(
          'execute_proposal',
          executeProposal(proposal.proposalId),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Get delegate statistics
   */
  getSimStats(): {
    votingPower: bigint;
    votesCast: number;
    proposalsCreated: number;
    proposalsTracked: number;
    hasDelegated: boolean;
  } {
    return {
      votingPower: this.votingPower,
      votesCast: this.votesCast,
      proposalsCreated: this.proposalsCreated,
      proposalsTracked: this.proposals.length,
      hasDelegated: this.hasDelegated,
    };
  }
}
