/**
 * VeELTAManagerAgent - Advanced veELTA position manager
 *
 * Behavior:
 * - Strategically manages lock durations
 * - Maximizes voting power
 * - Extends locks at optimal times
 * - Delegates voting power strategically
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { lockVeElta, extendVeEltaLock, delegateVotes } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for VeELTAManagerAgent
 */
export interface VeELTAManagerAgentParams extends BaseProtocolAgentParams {
  /** Target veELTA percentage of total balance (default 0.5 = 50%) */
  targetStakePercent?: number;
  /** Preferred lock duration in seconds (default 4 years) */
  preferredLockDuration?: number;
  /** Minimum lock to create (default 50 ELTA) */
  minLockAmount?: bigint;
  /** Whether to auto-extend expiring locks (default true) */
  autoExtend?: boolean;
  /** Days before expiry to extend lock (default 30 days in seconds) */
  extendThreshold?: number;
}

/**
 * Lock position tracking
 */
interface LockPosition {
  amount: bigint;
  lockEnd: number;
  votingPower: bigint;
}

/**
 * Strategic veELTA manager
 */
export class VeELTAManagerAgent extends BaseProtocolAgent {
  /** Current lock positions */
  private locks: LockPosition[] = [];

  /** Total locked */
  private totalLocked = 0n;

  /** Delegation target (if any) */
  private delegatedTo: string | null = null;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetPct = (this.params.targetStakePercent as number | undefined) ?? 0.5;
    const lockDuration = (this.params.preferredLockDuration as number | undefined) ?? 4 * 365 * 24 * 60 * 60;
    const minLock = (this.params.minLockAmount as bigint | undefined) ?? BigInt(50e18);
    const autoExtend = (this.params.autoExtend as boolean | undefined) ?? true;
    const extendThreshold = (this.params.extendThreshold as number | undefined) ?? 30 * 24 * 60 * 60;

    // Priority 1: Extend expiring locks
    if (autoExtend && this.shouldAct(ctx, 0.7)) {
      const extendAction = this.checkExtendLocks(ctx, extendThreshold, lockDuration);
      if (extendAction) return extendAction;
    }

    // Priority 2: Create new locks to reach target
    if (this.shouldAct(ctx, 0.3)) {
      const lockAction = this.createNewLock(ctx, targetPct, lockDuration, minLock);
      if (lockAction) return lockAction;
    }

    // Priority 3: Delegate if not delegated
    if (this.shouldAct(ctx, 0.1) && this.totalLocked > 0n && !this.delegatedTo) {
      const delegateAction = this.delegateVotingPower(ctx);
      if (delegateAction) return delegateAction;
    }

    return null;
  }

  /**
   * Check if any locks need extending
   */
  private checkExtendLocks(
    ctx: TickContext,
    threshold: number,
    newDuration: number
  ): Action | null {
    // Simulate checking lock expiry
    // In reality, this would query the veELTA contract
    const simulatedCurrentTime = Date.now() / 1000 + ctx.tick * 15; // 15 sec per tick

    for (const lock of this.locks) {
      const timeToExpiry = lock.lockEnd - simulatedCurrentTime;
      
      if (timeToExpiry > 0 && timeToExpiry < threshold) {
        ctx.logger.info(
          { 
            agent: this.id, 
            daysToExpiry: Math.floor(timeToExpiry / (24 * 60 * 60)),
            newDurationYears: newDuration / (365 * 24 * 60 * 60)
          },
          'Extending veELTA lock before expiry'
        );

        // Update lock tracking
        lock.lockEnd = simulatedCurrentTime + newDuration;

        return this.createAction(
          'extend_veelta_lock',
          extendVeEltaLock(newDuration),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Create a new lock to reach target stake percentage
   */
  private createNewLock(
    ctx: TickContext,
    targetPct: number,
    duration: number,
    minAmount: bigint
  ): Action | null {
    const balance = this.getEltaBalance();
    const totalHoldings = balance + this.totalLocked;

    if (totalHoldings === 0n) return null;

    // Calculate target
    const targetLocked = BigInt(Math.floor(Number(totalHoldings) * targetPct));
    
    if (this.totalLocked >= targetLocked) return null;

    // Calculate deficit
    const deficit = targetLocked - this.totalLocked;
    const lockAmount = deficit > balance ? balance : deficit;

    if (lockAmount < minAmount) return null;

    // Track lock
    const simulatedCurrentTime = Date.now() / 1000 + ctx.tick * 15;
    this.locks.push({
      amount: lockAmount,
      lockEnd: simulatedCurrentTime + duration,
      votingPower: lockAmount, // Simplified - real calculation is more complex
    });
    this.totalLocked += lockAmount;

    ctx.logger.info(
      { 
        agent: this.id, 
        amount: this.formatElta(lockAmount),
        durationYears: duration / (365 * 24 * 60 * 60),
        totalLocked: this.formatElta(this.totalLocked)
      },
      'Creating veELTA lock'
    );

    return this.createAction(
      'lock_veelta',
      lockVeElta(lockAmount, duration),
      ctx.tick
    );
  }

  /**
   * Delegate voting power
   */
  private delegateVotingPower(ctx: TickContext): Action | null {
    // Delegate to self for now (could be more strategic)
    const delegateTo = this.getAddress();
    
    ctx.logger.debug(
      { agent: this.id, delegateTo },
      'Delegating veELTA voting power'
    );

    this.delegatedTo = delegateTo;

    return this.createAction(
      'delegate_votes',
      delegateVotes(delegateTo),
      ctx.tick
    );
  }

  /**
   * Get veELTA manager stats
   */
  getSimStats(): {
    totalLocked: bigint;
    lockCount: number;
    isDelegated: boolean;
  } {
    return {
      totalLocked: this.totalLocked,
      lockCount: this.locks.length,
      isDelegated: this.delegatedTo !== null,
    };
  }
}
