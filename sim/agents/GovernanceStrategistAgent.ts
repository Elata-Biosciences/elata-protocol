import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { castVote, claimRewards, delegateVotes, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

export interface GovernanceStrategistAgentParams extends BaseProtocolAgentParams {
  targetVeEltaLock?: bigint;
  voteSupport?: 0 | 1 | 2;
  claimEveryTicks?: number;
}

/**
 * Deterministic governance participant:
 * - acquires and maintains veELTA voting power
 * - self-delegates and votes with a fixed policy
 */
export class GovernanceStrategistAgent extends BaseProtocolAgent {
  private delegated = false;

  async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);

    const targetVeEltaLock = (this.params.targetVeEltaLock as bigint | undefined) ?? BigInt(500e18);
    const voteSupport = (this.params.voteSupport as 0 | 1 | 2 | undefined) ?? 1;
    const claimEveryTicks = (this.params.claimEveryTicks as number | undefined) ?? 10;
    const gossipSignal = this.readGossipSignal(ctx);

    if (this.getVeEltaBalance() < targetVeEltaLock && this.hasEnoughElta(BigInt(120e18))) {
      this.recordDecisionMemory(ctx, {
        decision: 'lock_veelta',
        reason: 'increase_voting_power',
        context: {
          currentVeElta: this.getVeEltaBalance(),
          targetVeElta: targetVeEltaLock,
          gossipReads: gossipSignal.count,
        },
      });
      return this.createAction(
        'lock_veelta',
        lockVeElta(BigInt(120e18), 365 * 24 * 60 * 60),
        ctx.tick
      );
    }

    if (!this.delegated && this.getVeEltaBalance() > 0n) {
      this.delegated = true;
      this.recordDecisionMemory(ctx, {
        decision: 'delegate_votes',
        reason: 'self_delegate_bootstrap',
        context: {
          veEltaBalance: this.getVeEltaBalance(),
          gossipReads: gossipSignal.count,
        },
      });
      return this.createAction('delegate_votes', delegateVotes(this.getAddress()), ctx.tick);
    }

    if (this.isScheduledTick(claimEveryTicks, ctx)) {
      const hasClaimable = await this.hasClaimableVeEltaRewards();
      if (hasClaimable) {
        this.recordDecisionMemory(ctx, {
          decision: 'claim_rewards',
          reason: 'scheduled_reward_claim',
          context: {
            claimEveryTicks,
            gossipReads: gossipSignal.count,
            claimSignals: gossipSignal.claimSignals,
          },
        });
        return this.createAction('claim_rewards', claimRewards(), ctx.tick);
      }
    }

    const proposals = this.getActiveProposals();
    for (const proposalId of proposals) {
      const hasVoted = await this.hasVotedOnProposal(proposalId);
      if (!hasVoted) {
        this.recordDecisionMemory(ctx, {
          decision: 'cast_vote',
          reason: 'active_proposal_unvoted',
          context: {
            proposalId: proposalId.toString(),
            voteSupport,
            gossipReads: gossipSignal.count,
            governanceSignals: gossipSignal.governanceSignals,
          },
        });
        return this.createAction('cast_vote', castVote(proposalId, voteSupport), ctx.tick);
      }
    }

    this.recordDecisionMemory(ctx, {
      decision: 'no_op',
      reason: 'no_governance_action_available',
      context: {
        delegated: this.delegated,
        activeProposals: proposals.length,
        gossipReads: gossipSignal.count,
        governanceSignals: gossipSignal.governanceSignals,
        lastGossipChannel: gossipSignal.lastChannel ?? 'none',
      },
    });
    return null;
  }

  private readGossipSignal(ctx: TickContext): {
    count: number;
    claimSignals: number;
    governanceSignals: number;
    lastChannel?: string;
  } {
    if (!ctx.gossip) return { count: 0, claimSignals: 0, governanceSignals: 0 };
    const inbox = ctx.gossip.readInbox(this.id);
    if (inbox.length === 0) return { count: 0, claimSignals: 0, governanceSignals: 0 };

    let claimSignals = 0;
    let governanceSignals = 0;
    for (const msg of inbox) {
      const text = msg.payload.text.toLowerCase();
      if (text.includes('claim') || text.includes('reward')) claimSignals += 1;
      if (text.includes('governance') || text.includes('proposal') || text.includes('vote')) {
        governanceSignals += 1;
      }
    }
    const lastChannel = inbox[inbox.length - 1]?.envelope.channelId;
    return {
      count: inbox.length,
      claimSignals,
      governanceSignals,
      ...(lastChannel ? { lastChannel } : {}),
    };
  }
}
