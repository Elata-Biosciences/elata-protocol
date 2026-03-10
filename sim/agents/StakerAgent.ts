/**
 * StakerAgent - Focuses on veELTA staking
 *
 * Behavior:
 * - Locks ELTA for maximum duration (2 years) to get highest boost
 * - Increases lock amounts to compound voting power
 * - Claims rewards regularly
 *
 * Note: The EltaPack now handles lock state intelligently:
 * - If lock exists and agent tries to lock again, it auto-increases amount
 * - Operations validate on-chain state before executing
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { claimRewards, lockVeElta } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for StakerAgent
 */
export interface StakerAgentParams extends BaseProtocolAgentParams {
  /** Minimum ELTA to lock (default: 500 ELTA) */
  minLockAmount?: bigint;
  /** Lock duration in days (default: 730 = 2 years for max boost) */
  lockDurationDays?: number;
  /** Probability of claiming rewards each tick */
  claimProbability?: number;
  /** Probability of adding more to lock */
  compoundProbability?: number;
}

/**
 * Agent focused on veELTA staking for maximum voting power and rewards
 */
export class StakerAgent extends BaseProtocolAgent {
  /** Track if we've already attempted to lock this session */
  private hasAttemptedLock = false;

  async step(ctx: TickContext): Promise<Action | null> {
    // Refresh balances at start of each step
    await this.updateBalances();

    const minLock = (this.params.minLockAmount as bigint | undefined) ?? BigInt(500e18);
    const lockDays = (this.params.lockDurationDays as number | undefined) ?? 730; // 2 years max
    const claimProb = (this.params.claimProbability as number | undefined) ?? 0.2;
    const compoundProb = (this.params.compoundProbability as number | undefined) ?? 0.1;

    const hasVeElta = this.getVeEltaBalance() > 0n;
    const durationSeconds = lockDays * 24 * 60 * 60;

    // Priority 1: Lock ELTA if we don't have veELTA yet (only attempt once per session)
    // Note: EltaPack will auto-increase if lock already exists
    if (!hasVeElta && !this.hasAttemptedLock && this.hasEnoughElta(minLock)) {
      const lockAmount = this.getEltaBalance() / 2n; // 50% of balance
      this.hasAttemptedLock = true;

      ctx.logger.info(
        { agent: this.id, amount: this.formatElta(lockAmount), days: lockDays },
        'Creating veELTA lock'
      );

      return this.createAction('lock_veelta', lockVeElta(lockAmount, durationSeconds), ctx.tick);
    }

    // If we have veELTA, mark as having a lock
    if (hasVeElta) {
      this.hasAttemptedLock = true;
    }

    // Priority 2: Claim rewards if we have veELTA and there are claimable epochs
    // Only claim every 5 ticks to avoid excessive claim attempts
    if (hasVeElta && ctx.tick % 5 === 0 && this.shouldAct(ctx, claimProb)) {
      const hasClaimable = await this.hasClaimableVeEltaRewards();
      if (hasClaimable) {
        ctx.logger.debug({ agent: this.id }, 'Claiming veELTA rewards');
        return this.createAction('claim_rewards', claimRewards(), ctx.tick);
      }
    }

    // Priority 3: Add more to lock if we have spare ELTA (less frequent)
    // Using lock_veelta action - EltaPack will auto-convert to increaseAmount
    if (hasVeElta && ctx.tick % 10 === 0 && this.shouldAct(ctx, compoundProb)) {
      const spareElta = this.getEltaBalance();
      const minIncrease = BigInt(100e18);

      if (spareElta >= minIncrease) {
        ctx.logger.info(
          { agent: this.id, amount: this.formatElta(spareElta) },
          'Adding more ELTA to veELTA lock'
        );

        return this.createAction('lock_veelta', lockVeElta(spareElta, durationSeconds), ctx.tick);
      }
    }

    return null;
  }
}
